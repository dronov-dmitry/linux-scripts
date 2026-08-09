sudo bash -c '
# 1. Настройка сканирования при доступе в конфигурации ClamAV
CONFIG="/etc/clamav/clamd.conf"
if [ -f "$CONFIG" ]; then
    grep -q "^OnAccessIncludePath" "$CONFIG" || echo "OnAccessIncludePath /home" >> "$CONFIG"
    grep -q "^OnAccessPrevention" "$CONFIG" || echo "OnAccessPrevention yes" >> "$CONFIG"
    grep -q "^OnAccessExcludeUname" "$CONFIG" || echo "OnAccessExcludeUname clamav" >> "$CONFIG"
fi

# 2. Перезапуск основного демона
systemctl restart clamav-daemon

# 3. Создание скрипта фонового монитора
cat << "EOF" > /usr/local/bin/clam-shield.sh
#!/usr/bin/env bash

LOG_FILE="/var/log/clamav/clamav.log"
USER_NAME="${SUDO_USER:-$USER}"
USER_ID=$(id -u "$USER_NAME")

notify_user() {
    local message="$1"
    if [ -n "$USER_ID" ]; then
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
        sudo -u "$USER_NAME" notify-send -u critical "ClamAV Shield" "$message" 2>/dev/null || true
    fi
}

tail -Fn0 "$LOG_FILE" 2>/dev/null | while read -r line; do
    if echo "$line" | grep -q "FOUND"; then
        FILE_PATH=$(echo "$line" | awk -F ":" "{print \$1}")
        notify_user "ОБНАРУЖЕН ВИРУС!\nФайл: $FILE_PATH"
    fi
done
EOF

chmod +x /usr/local/bin/clam-shield.sh

# 4. Регистрация и запуск фонового сервиса systemd
cat << "EOF" > /etc/systemd/system/clam-shield.service
[Unit]
Description=ClamAV Real-Time Notification Shield
After=clamav-daemon.service

[Service]
Type=simple
ExecStart=/usr/local/bin/clam-shield.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now clam-shield.service
'