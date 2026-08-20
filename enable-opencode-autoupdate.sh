#!/bin/bash

# Включает автобновление opencode.
#
# ВАЖНО: эта версия НИКОГДА не меняет владельца системных каталогов.
# Предыдущая версия ломала sudo: при npm prefix=/usr строка
#   chown -R "$USER" "$NPM_PREFIX/bin"
# выполняла `chown -R <пользователь> /usr/bin`, из-за чего sudo (и другие
# setuid-бинарники) теряли владельца root и setuid-бит.
# Теперь никаких chown вне домашней директории пользователя.

set -uo pipefail

# Определяем реального пользователя (если запущен через sudo)
if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$SUDO_USER")
else
    REAL_USER="${USER:-$(id -un)}"
    REAL_HOME="$HOME"
fi

# Защита: вне домашней директории ничего не трогаем
if [[ "$REAL_HOME" != /* || "$REAL_HOME" == "/" ]]; then
    echo "Ошибка: не удалось определить домашнюю директорию пользователя." >&2
    exit 1
fi

CONFIG_DIR="$REAL_HOME/.config/opencode"
CONFIG_PATH="$CONFIG_DIR/opencode.jsonc"

# 1. Включаем встроенное автобновление opencode (autoupdate в конфиге)
mkdir -p "$CONFIG_DIR"

set_autoupdate() {
    if command -v jq &> /dev/null; then
        tmp=$(mktemp)
        if jq '.autoupdate = false' "$CONFIG_PATH" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$CONFIG_PATH"
            return 0
        fi
        rm -f "$tmp"
    fi
    # jsonc с комментариями — jq не справился, правим sed-ом
    if grep -q '"autoupdate"' "$CONFIG_PATH"; then
        sed -i 's/"autoupdate":.*/"autoupdate": false,/' "$CONFIG_PATH"
    else
        sed -i '/^{/a \  "autoupdate": false,' "$CONFIG_PATH"
    fi
}

if [ ! -f "$CONFIG_PATH" ]; then
    echo '{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false
}' > "$CONFIG_PATH"
else
    set_autoupdate
fi

# Восстанавливаем владельца только в пределах домашней директории
chown -R "$REAL_USER:$REAL_USER" "$CONFIG_DIR"

# 2. Определяем способ обновления — БЕЗ изменения владельца системных файлов
OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
OPENCODE_REAL=""
[ -n "$OPENCODE_BIN" ] && OPENCODE_REAL=$(readlink -f "$OPENCODE_BIN")

# Запрос пользователю: обновить opencode перед запуском (по умолчанию — нет).
UPDATE_PROMPT='read -r -p "Обновить opencode? (y/N): " _op_ans; if [[ "$_op_ans" == [yY] ]]; then'

if [[ "$OPENCODE_BIN" == *"/snap/"* ]]; then
    # Snap-версия
    ALIAS_CMD="alias opencode='$UPDATE_PROMPT sudo snap refresh opencode >/dev/null 2>&1; fi; command opencode'"
    echo "Обнаружена Snap-версия opencode. Алиас настроен на snap refresh по запросу (y/N)."

elif [[ -n "$OPENCODE_REAL" && "$OPENCODE_REAL" == "$REAL_HOME"/* ]]; then
    # Установка в домашней директории (например ~/.opencode/bin/opencode).
    # opencode обновляет себя сам через встроенную команду upgrade — по запросу (y/N).
    ALIAS_CMD="alias opencode='$UPDATE_PROMPT command opencode upgrade >/dev/null 2>&1; fi; command opencode'"
    echo "opencode установлен локально ($OPENCODE_REAL): обновление через upgrade по запросу (y/N)."

else
    # Глобальная npm-установка. Обновляем через npm, но владельца каталогов НЕ трогаем.
    NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "/usr/local")
    if [[ -w "$NPM_PREFIX" ]]; then
        ALIAS_CMD="alias opencode='$UPDATE_PROMPT npm install -g opencode@latest --silent 2>/dev/null; fi; command opencode'"
        echo "npm prefix доступен на запись ($NPM_PREFIX): обновление без sudo по запросу (y/N)."
    else
        ALIAS_CMD="alias opencode='$UPDATE_PROMPT sudo npm install -g opencode@latest --silent 2>/dev/null; fi; command opencode'"
        echo "npm prefix только для чтения ($NPM_PREFIX): обновление через sudo по запросу (y/N)."
    fi
fi

# 3. Добавляем алиас в .bashrc и .zshrc (удаляем старый, если был)
for RC_FILE in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
    if [ -f "$RC_FILE" ]; then
        sed -i '/alias opencode=/d' "$RC_FILE"
        sed -i '/Auto-update opencode on launch/d' "$RC_FILE"

        echo "" >> "$RC_FILE"
        echo "# Auto-update opencode on launch" >> "$RC_FILE"
        echo "$ALIAS_CMD" >> "$RC_FILE"
        echo "Алиас добавлен в $RC_FILE"
    fi
done

echo ""
echo "Готово! Чтобы изменения вступили в силу прямо сейчас, выполните:"
echo "source ~/.bashrc"
