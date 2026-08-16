#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "Ошибка: запустите скрипт от root (например: sudo $0)"
  exit 1
fi

pm=""
if command -v apt-get >/dev/null 2>&1; then
  pm=apt
elif command -v dnf >/dev/null 2>&1; then
  pm=dnf
elif command -v yum >/dev/null 2>&1; then
  pm=yum
elif command -v pacman >/dev/null 2>&1; then
  pm=pacman
elif command -v zypper >/dev/null 2>&1; then
  pm=zypper
fi

if [ -z "$pm" ]; then
  printf '%s\n' "Ошибка: не удалось определить пакетный менеджер (поддерживаются apt, dnf, yum, pacman, zypper)."
  exit 1
fi

printf '[1/5] Установка ClamAV + rkhunter (менеджер пакетов: %s)...\n' "$pm"
case "$pm" in
  apt)
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon rkhunter libnotify-bin zenity
    ;;
  dnf)
    dnf install -y clamav clamav-update rkhunter libnotify zenity
    ;;
  yum)
    yum install -y clamav clamav-update rkhunter libnotify zenity
    ;;
  pacman)
    pacman -S --noconfirm --needed clamav rkhunter libnotify zenity
    ;;
  zypper)
    zypper --non-interactive install clamav rkhunter libnotify-tools zenity
    ;;
esac

printf '%s\n' "[2/5] Обновление баз ClamAV и rkhunter..."
case "$pm" in
  apt|pacman)
    systemctl stop clamav-freshclam 2>/dev/null || true
    freshclam --no-dns || true
    systemctl start clamav-freshclam 2>/dev/null || true
    ;;
  *)
    freshclam --no-dns || true
    ;;
esac

chown -R clamav:clamav /var/lib/clamav 2>/dev/null || true

printf '%s\n' "[3/5] Установка сценариев сканирования..."
install -d /opt/avscan /var/log/avscan

cat > /opt/avscan/scan-key-modules.sh <<'SCANEOF'
#!/usr/bin/env bash
set -u

LOGDIR="/var/log/avscan"
mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
CLAMLOG="$LOGDIR/clamav-$TS.log"
RKLOG="$LOGDIR/rkhunter-$TS.log"

echo "[avscan] Updating ClamAV virus definitions..."
freshclam --quiet >/dev/null 2>&1 || echo "[avscan] freshclam: update failed (offline?), continuing"

echo "[avscan] Updating rkhunter database..."
rkhunter --update --nocolors >/dev/null 2>&1 || echo "[avscan] rkhunter update failed, continuing"

echo "[avscan] ClamAV: scanning key modules (/boot /lib/modules /bin /sbin /usr/bin /usr/sbin)..."
clamscan --recursive --infected --quiet \
    /boot \
    /lib/modules \
    /bin /sbin /usr/bin /usr/sbin \
    > "$CLAMLOG" 2>&1

echo "[avscan] rkhunter: checking system..."
rkhunter --check --skip-keypress --nocolors --rwo > "$RKLOG" 2>&1

INFECTED=$(grep -c 'FOUND' "$CLAMLOG" 2>/dev/null) || INFECTED=0
WARNINGS=$(grep -cE 'Warning|Please inspect' "$RKLOG" 2>/dev/null) || WARNINGS=0

echo "[avscan] DONE: clamscan infected=$INFECTED, rkhunter warnings=$WARNINGS"
echo "[avscan] Logs: $CLAMLOG $RKLOG"

if [ "${INFECTED:-0}" -gt 0 ] || [ "${WARNINGS:-0}" -gt 0 ]; then
    echo "[avscan] RESULT: PROBLEMS FOUND - inspect logs"
    /opt/avscan/notify-report.sh "$INFECTED" "$WARNINGS" "$CLAMLOG" "$RKLOG" || \
        echo "[avscan] desktop notification failed"
    exit 1
fi
echo "[avscan] RESULT: clean"
exit 0
SCANEOF
chmod 755 /opt/avscan/scan-key-modules.sh

cat > /opt/avscan/notify-report.sh <<'NOTIFYEOF'
#!/usr/bin/env bash
set -u

INFECTED="${1:-0}"
WARNINGS="${2:-0}"
CLAMLOG="${3:-}"
RKLOG="${4:-}"

find_active_user() {
    local s a u
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
        a=$(loginctl show-session "$s" -p Active --value 2>/dev/null)
        [ "$a" = "yes" ] || continue
        u=$(loginctl show-session "$s" -p Name --value 2>/dev/null)
        if [ -n "$u" ] && [ "$u" != "gdm" ] && [ "$u" != "lightdm" ]; then
            echo "$u"
            return 0
        fi
    done
    return 1
}

ACTIVE_USER="$(find_active_user)" || { echo "[avscan] No active user session; desktop notification skipped"; exit 0; }
USER_UID="$(id -u "$ACTIVE_USER" 2>/dev/null)" || { echo "[avscan] No uid for $ACTIVE_USER"; exit 0; }

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="$(getent passwd "$ACTIVE_USER" | cut -d: -f6)/.Xauthority"
export XDG_RUNTIME_DIR="/run/user/$USER_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"

REPORT_TMP="$(mktemp /tmp/avscan-report-XXXXXX.txt)"
trap 'rm -f "$REPORT_TMP"' EXIT

cat > "$REPORT_TMP" <<EOF
=========================================
  avscan: обнаружены угрозы при загрузке
=========================================

ClamAV:   $INFECTED заражённых файлов
rkhunter: $WARNINGS предупреждений

Лог ClamAV:   $CLAMLOG
Лог rkhunter: $RKLOG

EOF

if [ -f "$RKLOG" ] && [ -s "$RKLOG" ]; then
    {
        echo "========== rkhunter log =========="
        cat "$RKLOG"
        echo ""
    } >> "$REPORT_TMP"
fi

if [ -f "$CLAMLOG" ] && [ -s "$CLAMLOG" ]; then
    {
        echo "========== ClamAV log ============"
        cat "$CLAMLOG"
        echo ""
    } >> "$REPORT_TMP"
fi

chmod 644 "$REPORT_TMP"

if command -v zenity >/dev/null 2>&1; then
    timeout 600 runuser -u "$ACTIVE_USER" -- env DISPLAY="$DISPLAY" \
        zenity --text-info \
            --title "avscan: отчёт (выделите текст → Ctrl+C для копирования)" \
            --filename="$REPORT_TMP" \
            --width=850 --height=600 2>/dev/null || true
else
    runuser -u "$ACTIVE_USER" -- notify-send \
        -u critical -a "avscan" -i dialog-error \
        "avscan: обнаружены угрозы" \
        "$(cat "$REPORT_TMP")" 2>/dev/null || echo "[avscan] no notification available"
fi

echo "[avscan] Desktop notification sent to $ACTIVE_USER"
exit 0
NOTIFYEOF
chmod 755 /opt/avscan/notify-report.sh

printf '%s\n' "[4/5] Настройка rkhunter..."
rkhunter --propupd --nocolors >/dev/null 2>&1 || true

printf '%s\n' "[5/5] Создание systemd-сервиса..."
cat > /etc/systemd/system/avscan.service <<'SERVICEEOF'
[Unit]
Description=Antivirus and rootkit scan of key system modules
Documentation=man:rkhunter(8) man:clamscan(1)
After=local-fs.target
ConditionPathExists=/opt/avscan/scan-key-modules.sh

[Service]
Type=oneshot
ExecStart=/opt/avscan/scan-key-modules.sh
Nice=5
IOSchedulingClass=idle
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable avscan.service

printf '%s\n' "Готово."
printf '%s\n' "Сканирование запускается при каждой загрузке (avscan.service)."
printf '%s\n' "Журналы: /var/log/avscan/"
printf '%s\n' "Просмотр логов: journalctl -u avscan.service -f"
printf '%s\n' "Ручной запуск: sudo systemctl start avscan.service"
