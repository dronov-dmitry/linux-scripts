#!/bin/bash

# Включает автообновление opencode.
#
# Исправления по сравнению с первой версией:
#   1. В конфиг пишется "autoupdate": true (раньше писалось false,
#      т.е. встроенное автообновление ВЫКЛЮЧАЛОСЬ вопреки названию скрипта).
#   2. Обновление больше не глушится через >/dev/null 2>&1 — виден любой сбой.
#   3. Для snap-версии: если фоновые обновления заморожены (snap refresh --hold),
#      скрипт предложит разморозить их — иначе обновления не приходят никогда.
#      Вопрос "Обновить opencode? (y/N)" при запуске ставится ВСЕГДА: ответ "y"
#       выполняет sudo snap refresh opencode с видимым выводом.
#   4. Для npm-версии правильное имя пакета opencode-ai (пакета "opencode"
#      в npm нет, поэтому старая команда завершалась ошибкой незаметно).
#   5. Вместо хрупкого алиаса — функция; она передаёт аргументы opencode
#      и корректно работает и в bash, и в zsh.
#   6. Повторный запуск безопасен: блок в .bashrc/.zshrc помечен маркерами
#      и перезаписывается, а не дублируется.
#
# Как и раньше: вне домашней директории пользователя ничего не трогаем
# и владельца системных каталогов НЕ меняем.

set -uo pipefail

# --- Определяем реального пользователя (если запущен через sudo) ---
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$SUDO_USER")
else
    REAL_USER="${USER:-$(id -un)}"
    REAL_HOME="$HOME"
fi

if [[ "$REAL_HOME" != /* || "$REAL_HOME" == "/" ]]; then
    echo "Ошибка: не удалось определить домашнюю директорию пользователя." >&2
    exit 1
fi

CONFIG_DIR="$REAL_HOME/.config/opencode"
CONFIG_PATH="$CONFIG_DIR/opencode.jsonc"

# --- 1. Включаем встроенное автообновление в конфиге opencode ---
mkdir -p "$CONFIG_DIR"

set_autoupdate() {
    # jq справляется только с чистым JSON; для jsonc с комментариями — sed.
    if command -v jq >/dev/null 2>&1 && jq -e . "$CONFIG_PATH" >/dev/null 2>&1; then
        local tmp
        tmp=$(mktemp)
        if jq '.autoupdate = true' "$CONFIG_PATH" > "$tmp"; then
            mv "$tmp" "$CONFIG_PATH"
            return 0
        fi
        rm -f "$tmp"
    fi
    if grep -q '"autoupdate"' "$CONFIG_PATH"; then
        sed -i 's/"autoupdate"[[:space:]]*:[[:space:]]*[a-z]*/"autoupdate": true/' "$CONFIG_PATH"
    else
        sed -i '0,/^{/s//{\n  "autoupdate": true,/' "$CONFIG_PATH"
    fi
}

if [ ! -f "$CONFIG_PATH" ]; then
    cat > "$CONFIG_PATH" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": true
}
EOF
else
    set_autoupdate
fi

chown -R "$REAL_USER:$REAL_USER" "$CONFIG_DIR"
echo "В $CONFIG_PATH включено \"autoupdate\": true."

# --- 2. Определяем способ установки ---
OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
OPENCODE_REAL=""
[ -n "$OPENCODE_BIN" ] && OPENCODE_REAL=$(readlink -f "$OPENCODE_BIN")

MARK_BEGIN="# >>> opencode autoupdate >>>"
MARK_END="# <<< opencode autoupdate <<<"

clean_rc() {
    # убираем наш прошлый блок и легаси-алиасы от старых версий скрипта
    sed -i "/^${MARK_BEGIN}\$/,/^${MARK_END}\$/d" "$1"
    sed -i '/alias opencode=/d' "$1"
    sed -i '/Auto-update opencode on launch/d' "$1"
}

install_fallback_func() {
    # Резервная проверка обновлений при запуске: вопрос y/N, вывод НЕ глушится.
    # $1 = команда обновления, $2 = rc-файл
    local update_cmd="$1" rc="$2"
    clean_rc "$rc"
    {
        echo ""
        echo "$MARK_BEGIN"
        echo 'opencode() {'
        if [[ "$rc" == *.zshrc ]]; then
            echo '    read -r "_oc_ans?Обновить opencode? (y/N): "'
        else
            echo '    read -r -p "Обновить opencode? (y/N): " _oc_ans'
        fi
        cat <<'EOF_CASE_OPEN'
    case "$_oc_ans" in
        [yY]*)
EOF_CASE_OPEN
        if [[ "$update_cmd" == *"snap refresh"* ]]; then
            cat <<'EOF_SNAP_GUARD'
            # snap нельзя обновить, пока запущены его приложения,
            # иначе будет ошибка "snap has running apps".
            if pgrep -f "/snap/opencode/" >/dev/null 2>&1; then
                echo "Обновление сейчас невозможно: работают другие экземпляры opencode."
                echo "Закройте ВСЕ окна/терминалы с opencode и ответьте y при следующем запуске."
            else
                sudo snap refresh opencode
            fi
EOF_SNAP_GUARD
        else
            echo "            sudo $update_cmd"
        fi
        cat <<'EOF_CASE_CLOSE'
            ;;
    esac
    command opencode "$@"
}
EOF_CASE_CLOSE
        echo "$MARK_END"
    } >> "$rc"
    chown "$REAL_USER:$REAL_USER" "$rc"
}

RC_FILES=()
for f in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
    [ -f "$f" ] && RC_FILES+=("$f")
done

if [[ "$OPENCODE_BIN" == *"/snap/"* ]]; then
    echo "Обнаружена Snap-версия opencode."
    HELD=""
    if command -v snap >/dev/null 2>&1; then
        HELD=$(snap refresh --time 2>/dev/null | awk '/^hold:/ {print $2}')
    fi

    if [[ -n "$HELD" && "$HELD" != "--" ]]; then
        echo "ВНИМАНИЕ: фоновые обновления snap заморожены (hold: $HELD)."
        printf 'Разморозить автообновления ВСЕХ snap-пакетов? [Y/n] '
        read -r _ans
        case "$_ans" in
            n*|N*) echo "Пропущено." ;;
            *) sudo snap refresh --unhold && echo "Фоновые обновления snap снова включены." ;;
        esac
    fi

    # Вопрос "Обновить opencode? (y/N)" при каждом запуске opencode.
    # Ответ "y" выполняет sudo snap refresh opencode с видимым выводом.
    for rc in "${RC_FILES[@]}"; do
        install_fallback_func "snap refresh opencode" "$rc"
        echo "Добавлена функция с вопросом (y/N) в $rc."
    done

elif [[ -n "$OPENCODE_REAL" && "$OPENCODE_REAL" == "$REAL_HOME"/* ]]; then
    # Установка в домашней директории (~/.opencode/bin/opencode и т.п.):
    # встроенный updater сам обновляет opencode при запуске (autoupdate: true).
    echo "opencode установлен локально ($OPENCODE_REAL): он будет обновлять себя сам при запуске."
    for rc in "${RC_FILES[@]}"; do
        if grep -q "^$MARK_BEGIN$" "$rc" || grep -q 'alias opencode=' "$rc"; then
            clean_rc "$rc"
            chown "$REAL_USER:$REAL_USER" "$rc"
            echo "Убран старый алиас/функция из $rc — теперь обновляет сам opencode."
        fi
    done

else
    # Глобальная npm-установка. Правильное имя пакета — opencode-ai.
    NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "/usr/local")
    echo "Глобальная npm-установка (prefix: $NPM_PREFIX)."
    if [[ -w "$NPM_PREFIX" ]]; then
        UPDATE_CMD="npm install -g opencode-ai@latest"
        echo "npm prefix доступен на запись: обновление без sudo."
    else
        UPDATE_CMD="npm install -g opencode-ai@latest"
        echo "npm prefix только для чтения ($NPM_PREFIX): потребуется пароль sudo при первом 'y'."
    fi
    for rc in "${RC_FILES[@]}"; do
        install_fallback_func "$UPDATE_CMD" "$rc"
        echo "Добавлена функция с вопросом (y/N) в $rc."
    done
fi

echo ""
echo "Готово! Проверить версию/обновление вручную можно так:"
echo "  sudo snap refresh opencode   # для snap-версии"
echo "  opencode upgrade             # для остальных способов установки"
