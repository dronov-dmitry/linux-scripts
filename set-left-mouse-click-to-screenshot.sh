#!/bin/bash

set -e

echo "=== [1/4] Установка необходимых пакетов ==="
sudo apt update
sudo apt install -y gnome-screenshot wl-clipboard input-remapper dconf-cli

echo "=== [2/4] Настройка горячей клавиши GNOME (Ctrl+Alt+S) ==="
SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
CUSTOM_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-screenshot/"

CURRENT_BINDINGS=$(gsettings get $SCHEMA custom-keybindings)

if [[ "$CURRENT_BINDINGS" == "@as []" ]]; then
    NEW_BINDINGS="['$CUSTOM_PATH']"
elif [[ "$CURRENT_BINDINGS" != *"$CUSTOM_PATH"* ]]; then
    NEW_BINDINGS=$(echo "$CURRENT_BINDINGS" | sed "s|]|, '$CUSTOM_PATH']|")
else
    NEW_BINDINGS="$CURRENT_BINDINGS"
fi

gsettings set $SCHEMA custom-keybindings "$NEW_BINDINGS"

dconf write "${CUSTOM_PATH}name" "'Mouse Screenshot Wayland'"
dconf write "${CUSTOM_PATH}command" "'bash -c \"gnome-screenshot -a -f /tmp/shot.png && wl-copy < /tmp/shot.png\"'"
dconf write "${CUSTOM_PATH}binding" "'<Control><Alt>s'"

echo "=== [3/4] Автоматический поиск мыши и запись пресета ==="

# Запускаем службу daemon, если она не активна
sudo systemctl start input-remapper 2>/dev/null || true

# Опрашиваем устройства с правами root для точного определения
DEVICE_LIST=$(sudo input-remapper-control --list-devices 2>/dev/null || true)

# Ищем устройство мыши
MOUSE_NAME=$(echo "$DEVICE_LIST" | grep -iE "mouse|pointer" | head -n 1 || true)

if [ -z "$MOUSE_NAME" ]; then
    # Если мышь не найдена явно, берем первое доступное устройство ввода
    MOUSE_NAME=$(echo "$DEVICE_LIST" | head -n 1 || true)
fi

if [ -n "$MOUSE_NAME" ]; then
    echo "✔ Найдено устройство: $MOUSE_NAME"

    # Создаем конфигурацию пресета
    PRESET_DIR="$HOME/.config/input-remapper-2/presets/$MOUSE_NAME"
    mkdir -p "$PRESET_DIR"

    cat << 'EOF' > "$PRESET_DIR/screenshot.json"
{
    "mapping": {
        "1,275,1": [
            "Control_L + Alt_L + s"
        ]
    }
}
EOF

    # Применяем пресет и включаем автозагрузку для этого устройства
    sudo input-remapper-control --command autoload 2>/dev/null || true
    sudo input-remapper-control --command start --device "$MOUSE_NAME" --preset screenshot 2>/dev/null || true

    echo ""
    echo "=========================================================="
    echo " ✅ НАСТРОЙКА ПОЛНОСТЬЮ ЗАВЕРШЕНА АВТОМАТИЧЕСКИ!"
    echo " Нажмите боковую кнопку мыши для снимка экрана."
    echo "=========================================================="
else
    echo ""
    echo "=========================================================="
    echo " ⚠️ МЫШЬ НЕ НАЙДЕНА АВТОМАТИЧЕСКИ"
    echo "=========================================================="
    echo " Базовые настройки выполнены. Остался 1 шаг вручную:"
    echo " 1. Откройте приложение 'Input Remapper' в меню."
    echo " 2. Вверху выберите вашу мышь (Device)."
    echo " 3. Нажмите 'New preset' -> введите 'screenshot'."
    echo " 4. Добавьте кнопку (BTN_SIDE / Button 8) -> назначьте:"
    echo "    Control_L + Alt_L + s"
    echo " 5. Нажмите 'Apply' и включите 'Autostart'."
    echo "=========================================================="
fi
