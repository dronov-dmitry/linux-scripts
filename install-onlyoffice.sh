#!/usr/bin/env bash
# Установка ONLYOFFICE Desktop Editors и установка русского языка интерфейса.
# Подходит для Ubuntu, Debian и производных: Zorin OS, Linux Mint, Pop!_OS и др.
set -euo pipefail

LANG_ID="ru-RU"
KEYRING="/usr/share/keyrings/onlyoffice.gpg"
REPO_FILE="/etc/apt/sources.list.d/onlyoffice.list"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Проверки -------------------------------------------------------------
[[ $EUID -eq 0 ]] && err "Запустите скрипт от обычного пользователя: sudo не нужен, скрипт сам его вызовет."

if ! command -v apt-get >/dev/null 2>&1; then
    err "apt-get не найден. Скрипт предназначен для Ubuntu/Debian и производных."
fi

sudo -v

# --- 1. Зависимости -------------------------------------------------------
info "Устанавливаю зависимости (wget, gnupg, ca-certificates)..."
sudo apt-get update
sudo apt-get install -y wget gnupg ca-certificates

# --- 2. GPG-ключ ONLYOFFICE ----------------------------------------------
if [[ ! -f "$KEYRING" ]]; then
    info "Добавляю GPG-ключ ONLYOFFICE..."
    gpg --no-default-keyring \
        --keyring gnupg-ring:/tmp/onlyoffice.gpg \
        --keyserver hkp://keyserver.ubuntu.com:80 \
        --recv-keys CB2DE8E5
    chmod 644 /tmp/onlyoffice.gpg
    sudo mv /tmp/onlyoffice.gpg "$KEYRING"
fi

# --- 3. Репозиторий ------------------------------------------------------
info "Добавляю репозиторий ONLYOFFICE..."
echo "deb [signed-by=$KEYRING] https://download.onlyoffice.com/repo/debian squeeze main" \
    | sudo tee "$REPO_FILE" >/dev/null

# --- 4. Установка --------------------------------------------------------
info "Устанавливаю ONLYOFFICE Desktop Editors (может занять несколько минут)..."
sudo apt-get update
sudo apt-get install -y onlyoffice-desktopeditors

ok "ONLYOFFICE Desktop Editors установлен."

# --- 5. Русский язык интерфейса -----------------------------------------
info "Настраиваю русский язык интерфейса..."

CFG="$HOME/.config/onlyoffice/DesktopEditors.conf"
mkdir -p "$(dirname "$CFG")"

# Закрываем ONLYOFFICE, если запущен: иначе он перезапишет конфиг при выходе
if pgrep -x desktopeditors >/dev/null 2>&1 || pgrep -f 'desktopeditors/DesktopEditors' >/dev/null 2>&1; then
    warn "ONLYOFFICE запущен - закрываю его, чтобы применить настройки..."
    pkill -f 'desktopeditors/DesktopEditors' 2>/dev/null
    pkill -x desktopeditors 2>/dev/null
    sleep 2
fi

if command -v python3 >/dev/null 2>&1; then
    python3 - "$CFG" "$LANG_ID" <<'PY'
import base64, json, os, sys
from collections import OrderedDict

path, lang = sys.argv[1], sys.argv[2]
sections = OrderedDict()
cur = None

if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith(";"):
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                cur = stripped[1:-1]
                sections.setdefault(cur, OrderedDict())
            elif "=" in line:
                k, v = line.split("=", 1)
                v = v.strip()
                if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                    v = v[1:-1]
                if cur is None:
                    cur = "General"
                    sections[cur] = OrderedDict()
                sections[cur][k.strip()] = v

sec = sections.setdefault("General", OrderedDict())

# Главный ключ: язык Qt-оболочки (читается CLangater при старте)
sec["locale"] = lang

updated = False
if "appdata" in sec:
    v = sec["appdata"]
    if v.startswith("@ByteArray(") and v.endswith(")"):
        try:
            data = json.loads(base64.b64decode(v[len("@ByteArray("):-1]).decode("utf-8"))
            data["langid"] = lang
            sec["appdata"] = "@ByteArray(" + base64.b64encode(
                json.dumps(data, ensure_ascii=False).encode("utf-8")).decode("ascii") + ")"
            updated = True
        except Exception:
            pass

if not updated:
    data = {
        "username": os.environ.get("USER", "User"),
        "docopenmode": "edit",
        "langid": lang,
        "uiscaling": "0",
        "uitheme": "theme-classic-light",
        "editorwindowmode": False,
    }
    sec["appdata"] = "@ByteArray(" + base64.b64encode(
        json.dumps(data, ensure_ascii=False).encode("utf-8")).decode("ascii") + ")"

with open(path, "w", encoding="utf-8") as f:
    for name, kv in sections.items():
        f.write("[" + name + "]\n")
        for k, v in kv.items():
            f.write(k + "=" + v + "\n")
        f.write("\n")
PY
else
    # Запасной вариант без python3
    if [[ -f "$CFG" ]] && grep -q 'appdata=@ByteArray(' "$CFG"; then
        b64=$(sed -n 's/^appdata=@ByteArray(\(.*\))$/\1/p' "$CFG" | head -n1 | tr -d '"')
        dec=$(printf '%s' "$b64" | base64 -d 2>/dev/null || true)
        new=$(printf '%s' "$dec" | sed 's/"langid":"[^"]*"/"langid":"ru-RU"/')
        enc=$(printf '%s' "$new" | base64 -w0)
        sed -i "s|^appdata=@ByteArray(.*)$|appdata=@ByteArray($enc)|" "$CFG"
    else
        json="{\"username\":\"$USER\",\"docopenmode\":\"edit\",\"langid\":\"ru-RU\",\"uiscaling\":\"0\",\"uitheme\":\"theme-classic-light\",\"editorwindowmode\":false}"
        app=$(printf '%s' "$json" | base64 -w0)
        printf '[General]\nappdata=@ByteArray(%s)\n' "$app" > "$CFG"
    fi
    # добавляем ключ locale (основной для языка интерфейса)
    if ! grep -q '^locale=' "$CFG"; then
        sed -i "1i locale=ru-RU" "$CFG"
    fi
fi

ok "Русский язык интерфейса задан ($LANG_ID)."

# --- 6. Итог -------------------------------------------------------------
info "Установка завершена."
if command -v desktopeditors >/dev/null 2>&1; then
    info "Запуск: desktopeditors"
else
    warn "Команда desktopeditors не найдена в PATH - возможно, нужно перезайти в систему."
fi
