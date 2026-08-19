#!/bin/bash

# Определяем реального пользователя (если запущен через sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(eval echo "~$SUDO_USER")
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

CONFIG_DIR="$REAL_HOME/.config/opencode"
CONFIG_PATH="$CONFIG_DIR/opencode.jsonc"

# 1. Настройка autoupdate в конфиге
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_PATH" ]; then
    echo '{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": true
}' > "$CONFIG_PATH"
else
    if command -v jq &> /dev/null; then
        tmp=$(mktemp)
        jq '.autoupdate = true' "$CONFIG_PATH" > "$tmp" && mv "$tmp" "$CONFIG_PATH"
    else
        if grep -q '"autoupdate"' "$CONFIG_PATH"; then
            sed -i 's/"autoupdate":.*/"autoupdate": true,/' "$CONFIG_PATH"
        else
            sed -i '/^{/a \  "autoupdate": true,' "$CONFIG_PATH"
        fi
    fi
fi

# 2. Формируем команду обновления в зависимости от того, установлен Snap или NPM
OPENCODE_BIN=$(which opencode 2>/dev/null)

if [[ "$OPENCODE_BIN" == *"/snap/bin"* ]]; then
    # Если это Snap, обновляем через snap refresh в фоновом режиме перед запуском
    ALIAS_CMD='alias opencode="sudo snap refresh opencode >/dev/null 2>&1; command opencode"'
    echo "Обнаружена Snap-версия opencode. Алиас настроен на snap refresh."
else
    # Если это NPM или бинарник, обновляем через npm
    NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "/usr/local")
    if [ -d "$NPM_PREFIX" ]; then
        chown -R "$REAL_USER:$REAL_USER" "$NPM_PREFIX/lib/node_modules" "$NPM_PREFIX/bin" 2>/dev/null
    fi
    ALIAS_CMD='alias opencode="npm install -g opencode@latest --silent 2>/dev/null; command opencode"'
    echo "Настроен алиас обновления через npm."
fi

# 3. Добавляем алиас в .bashrc и .zshrc
for RC_FILE in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc"; do
    if [ -f "$RC_FILE" ]; then
        # Удаляем старый алиас opencode, если он был
        sed -i '/alias opencode=/d' "$RC_FILE"
        sed -i '/Auto-update opencode on launch/d' "$RC_FILE"
        
        # Записываем актуальный алиас
        echo "" >> "$RC_FILE"
        echo "# Auto-update opencode on launch" >> "$RC_FILE"
        echo "$ALIAS_CMD" >> "$RC_FILE"
        echo "Алиас добавлен в $RC_FILE"
    fi
done

# 4. Восстанавливаем права на конфиги
chown -R "$REAL_USER:$REAL_USER" "$CONFIG_DIR"

echo ""
echo "Готово! Чтобы изменения вступили в силу прямо сейчас, выполните:"
echo "source ~/.bashrc"
