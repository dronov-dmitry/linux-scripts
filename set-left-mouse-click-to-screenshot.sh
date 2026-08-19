#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
REAL_UID=$(id -u "$REAL_USER")
REAL_HOME=$(eval echo "~$REAL_USER")
DBUS="unix:path=/run/user/${REAL_UID}/bus"

run_user() {
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS" "$@"
}

echo "=========================================="
echo " Настройка мыши для скриншотов (Wayland)"
echo " Пользователь: $REAL_USER (uid=$REAL_UID)"
echo "=========================================="

# ── [1] Установка пакетов ──
echo ""
echo "=== [1/4] Установка пакетов ==="
apt update -qq
apt install -y -qq gnome-screenshot wl-clipboard input-remapper dconf-cli

# ── [2] Горячая клавиша Ctrl+Alt+S ──
echo ""
echo "=== [2/4] Настройка Ctrl+Alt+S ==="
SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
CUSTOM_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom-screenshot/"

CURRENT_BINDINGS=$(run_user gsettings get "$SCHEMA" custom-keybindings)

if [[ "$CURRENT_BINDINGS" == "@as []" ]]; then
    NEW_BINDINGS="['$CUSTOM_PATH']"
elif [[ "$CURRENT_BINDINGS" != *"$CUSTOM_PATH"* ]]; then
    NEW_BINDINGS=$(echo "$CURRENT_BINDINGS" | sed "s|]|, '$CUSTOM_PATH']|")
else
    NEW_BINDINGS="$CURRENT_BINDINGS"
fi

run_user gsettings set "$SCHEMA" custom-keybindings "$NEW_BINDINGS"
run_user dconf write "${CUSTOM_PATH}name" "'Mouse Screenshot Wayland'"
run_user dconf write "${CUSTOM_PATH}command" "'bash -c \"gnome-screenshot -a -f /tmp/shot.png && wl-copy < /tmp/shot.png\"'"
run_user dconf write "${CUSTOM_PATH}binding" "'<Control><Alt>s'"
echo "  ✔ Горячая клавиша Ctrl+Alt+S настроена"

# ── [3] Поиск мыши ──
echo ""
echo "=== [3/4] Поиск USB-мыши ==="

MOUSE_NAME=""
while IFS= read -r line; do
    if [[ "$line" == N:\ Name=* ]]; then
        CURRENT_NAME=$(echo "$line" | sed 's/.*Name="\(.*\)"/\1/')
    fi
    if [[ "$line" == H:\ Handlers=*mouse* && "$CURRENT_NAME" == *"MOUSE"* ]]; then
        MOUSE_NAME="$CURRENT_NAME"
        break
    fi
done < /proc/bus/input/devices

if [ -n "$MOUSE_NAME" ]; then
    echo "  ✔ Найдена мышь: $MOUSE_NAME"
else
    echo "  ✘ Мышь не найдена. Настройте вручную через Input Remapper."
    exit 1
fi

# ── [4] Настройка input-remapper ──
echo ""
echo "=== [4/4] Настройка input-remapper ==="

CONFIG_DIR="$REAL_HOME/.config/input-remapper-2"
PRESET_DIR="$CONFIG_DIR/presets/${MOUSE_NAME}"
mkdir -p "$PRESET_DIR"

# config.json обязателен — без него daemon не принимает injection-запросы
if [ ! -f "$CONFIG_DIR/config.json" ]; then
    echo '{}' > "$CONFIG_DIR/config.json"
    chown "$REAL_USER":"$REAL_USER" "$CONFIG_DIR/config.json"
    echo "  ✔ Создан config.json"
fi

# Новый формат пресета input-remapper 2.0 (список объектов, НЕ старый dict)
cat > "$PRESET_DIR/screenshot.json" << 'PRESET'
[
    {
        "input_combination": [
            {"type": 1, "code": 275, "value": 1}
        ],
        "target_uinput": "keyboard",
        "output_symbol": "Control_L + Alt_L + s",
        "mapping_type": "key_macro"
    }
]
PRESET

chown -R "$REAL_USER":"$REAL_USER" "$CONFIG_DIR"
echo "  ✔ Пресет записан"

systemctl enable input-remapper 2>/dev/null || true
systemctl restart input-remapper 2>/dev/null || true
sleep 1
echo "  ✔ Сервис перезапущен"

input-remapper-control --command stop-all 2>/dev/null || true
input-remapper-control --command start \
    --device "$MOUSE_NAME" \
    --preset screenshot 2>/dev/null || true
echo "  ✔ Пресет применён"

echo ""
echo "=========================================="
echo " ✅ ГОТОВО!"
echo ""
echo " Нажмите боковую кнопку мыши (BTN_SIDE)"
echo " для скриншота."
echo ""
echo " Горячая клавиша: Ctrl+Alt+S"
echo " (тоже работает для скриншота)"
echo "=========================================="
