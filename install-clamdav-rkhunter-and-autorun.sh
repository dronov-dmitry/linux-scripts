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

printf '[1/6] Установка ClamAV + rkhunter + chkrootkit (менеджер пакетов: %s)...\n' "$pm"
case "$pm" in
  apt)
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon rkhunter chkrootkit libnotify-bin zenity
    ;;
  dnf)
    dnf install -y epel-release 2>/dev/null || true
    dnf install -y clamav clamav-update rkhunter chkrootkit libnotify zenity
    ;;
  yum)
    yum install -y epel-release 2>/dev/null || true
    yum install -y clamav clamav-update rkhunter chkrootkit libnotify zenity
    ;;
  pacman)
    pacman -S --noconfirm --needed clamav rkhunter chkrootkit libnotify zenity
    ;;
  zypper)
    zypper --non-interactive install clamav rkhunter chkrootkit libnotify-tools zenity
    ;;
esac

printf '%s\n' "[2/6] Обновление баз ClamAV и rkhunter (chkrootkit обновляется только через менеджер пакетов)..."
case "$pm" in
  apt|pacman)
    systemctl stop clamav-freshclam 2>/dev/null || true
    timeout 120 freshclam --no-dns || true
    systemctl start clamav-freshclam 2>/dev/null || true
    ;;
  *)
    timeout 120 freshclam --no-dns || true
    ;;
esac

chown -R clamav:clamav /var/lib/clamav 2>/dev/null || true

printf '%s\n' "[3/6] Настройка rkhunter: whitelist известных ложных срабатываний..."
if [ -f /etc/rkhunter.conf ]; then
  mkdir -p /etc/rkhunter 2>/dev/null || true
  cat > /etc/rkhunter.conf.local <<'EOF'
SCRIPTWHITELIST=/usr/bin/lwp-request
ALLOWHIDDENDIR=/etc/.java
ALLOWHIDDENFILE=/etc/.resolv.conf.systemd-resolved.bak
ALLOWHIDDENFILE=/etc/.updated
ALLOWIPCPROC=/usr/libexec/mutter-x11-frames
ALLOWIPCPROC=/usr/libexec/gnome-terminal-server
ALLOWIPCPROC=/usr/bin/python3.12
EOF

  # Баг Debian/Ubuntu: WEB_CMD="/bin/false" в кавычках валится на --config-check.
  # rkhunter намеренно НЕ срезает кавычки у *_CMD-опций, дублируем в .local без кавычек.
  if grep -q '^WEB_CMD="/bin/false"' /etc/rkhunter.conf; then
    printf '%s\n' 'WEB_CMD=/bin/false' >> /etc/rkhunter.conf.local
    printf '%s\n' "       (исправлен WEB_CMD)"
  fi
else
  printf '%s\n' "       /etc/rkhunter.conf не найден — пропуск"
fi

printf '%s\n' "       Убираем ложные срабатывания chkrootkit (ежедневный chkrootkit-daily)..."
if [ -f /etc/chkrootkit/chkrootkit.ignore ]; then
  if ! grep -qE '^RTNETLINK answers' /etc/chkrootkit/chkrootkit.ignore; then
    cat >> /etc/chkrootkit/chkrootkit.ignore <<'EOF'
^RTNETLINK answers: Invalid argument$
^Potential bindshell installed: infected ports:\s*114\s*$
^/usr/lib/debug/.build-id$
^/usr/lib/llvm-18/build/utils/lit/tests/.coveragerc$
^/usr/lib/libreoffice/share/.registry$
^/usr/lib/ruby/vendor_ruby/rubygems/optparse/.document$
^/usr/lib/ruby/vendor_ruby/rubygems/tsort/.document$
^/usr/lib/ruby/vendor_ruby/rubygems/ssl_certs/.document$
^/usr/lib/jvm/.java-1.17.0-openjdk-amd64.jinfo$
^/usr/lib/jvm/.java-1.21.0-openjdk-amd64.jinfo$
^/usr/lib/modules/.*/vdso/.build-id$
^/usr/lib/python3/dist-packages/tldextract/.tld_set_snapshot$
^/usr/lib/python3/dist-packages/fail2ban/tests/files/config/apache-auth/.*/\..*$
^/usr/lib/python3/dist-packages/numpy/f2py/tests/src/.*/.f2py_f2cmap$
EOF
  fi
else
  printf '%s\n' "       chkrootkit.ignore не найден — пропуск (версия без wrapper'а)"
fi

printf '%s\n' "[4/6] Установка сценариев сканирования..."
install -d /opt/avscan /var/log/avscan

cat > /opt/avscan/scan-key-modules.sh <<'SCANEOF'
#!/usr/bin/env bash
set -u

LOGDIR="/var/log/avscan"
mkdir -p "$LOGDIR"
TS="$(date +%Y%m%d-%H%M%S)"
CLAMLOG="$LOGDIR/clamav-$TS.log"
RKLOG="$LOGDIR/rkhunter-$TS.log"
CHKLOG="$LOGDIR/chkrootkit-$TS.log"

STAMP="$LOGDIR/.lastupdates"

# Базы обновляем не чаще раза в 12 ч (не на каждый прогон), сеть ограничена таймаутом
if [ ! -f "$STAMP" ] || [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -gt 43200 ]; then
  echo "[avscan] Updating ClamAV virus definitions..."
  timeout 120 freshclam --quiet >/dev/null 2>&1 || echo "[avscan] freshclam: update failed (offline?), continuing"

  echo "[avscan] Updating rkhunter database..."
  timeout 120 rkhunter --update --nocolors >/dev/null 2>&1 || echo "[avscan] rkhunter update failed, continuing"

  touch "$STAMP" 2>/dev/null || true
else
  echo "[avscan] Базы обновлены <12ч назад, пропускаю обновления"
fi

echo "[avscan] ClamAV: scanning key modules (/boot /lib/modules /bin /sbin /usr/bin /usr/sbin)..."
timeout 1800 clamscan --recursive --infected --quiet \
    /boot \
    /lib/modules \
    /bin /sbin /usr/bin /usr/sbin \
    > "$CLAMLOG" 2>&1 || true

echo "[avscan] rkhunter: checking system..."
rkhunter --check --skip-keypress --nocolors --rwo > "$RKLOG" 2>&1 || true

echo "[avscan] chkrootkit: checking system..."
chkrootkit -q > "$CHKLOG" 2>&1 || true

INFECTED=$(grep -c 'FOUND' "$CLAMLOG" 2>/dev/null) || INFECTED=0
WARNINGS=$(grep -cE 'Warning|Please inspect' "$RKLOG" 2>/dev/null) || WARNINGS=0
CHK=$(grep -cE 'INFECTED|FOUND|Possible' "$CHKLOG" 2>/dev/null) || CHK=0

echo "[avscan] DONE: clamscan infected=$INFECTED, rkhunter warnings=$WARNINGS, chkrootkit hits=$CHK"
echo "[avscan] Logs: $CLAMLOG $RKLOG $CHKLOG"

if [ "${INFECTED:-0}" -gt 0 ] || [ "${WARNINGS:-0}" -gt 0 ] || [ "${CHK:-0}" -gt 0 ]; then
    echo "[avscan] RESULT: PROBLEMS FOUND - inspect logs"
    /opt/avscan/notify-report.sh "$INFECTED" "$WARNINGS" "$CHK" "$CLAMLOG" "$RKLOG" "$CHKLOG" || \
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
CHK="${3:-0}"
CLAMLOG="${4:-}"
RKLOG="${5:-}"
CHKLOG="${6:-}"

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
  avscan: обнаружены угрозы
=========================================

ClamAV:      $INFECTED заражённых файлов
rkhunter:    $WARNINGS предупреждений
chkrootkit:  $CHK срабатываний

Лог ClamAV:    $CLAMLOG
Лог rkhunter:  $RKLOG
Лог chkrootkit: $CHKLOG

EOF

if [ -f "$RKLOG" ] && [ -s "$RKLOG" ]; then
    {
        echo "========== rkhunter log =========="
        cat "$RKLOG"
        echo ""
    } >> "$REPORT_TMP"
fi

if [ -f "$CHKLOG" ] && [ -s "$CHKLOG" ]; then
    {
        echo "========== chkrootkit log =========="
        cat "$CHKLOG"
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

bash -n /opt/avscan/scan-key-modules.sh
bash -n /opt/avscan/notify-report.sh

printf '%s\n' "[5/6] Базовая линия rkhunter (после whitelist)..."
rkhunter --propupd --nocolors >/dev/null 2>&1 || true

printf '%s\n' "[6/6] systemd: сервис + НЕ-блокирующий таймер..."
systemctl stop avscan.service 2>/dev/null || true
systemctl disable avscan.service 2>/dev/null || true

cat > /etc/systemd/system/avscan.service <<'SERVICEEOF'
[Unit]
Description=Antivirus and rootkit scan of key system modules
Documentation=man:rkhunter(8) man:chkrootkit(8) man:clamscan(1)
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

cat > /etc/systemd/system/avscan.timer <<'TIMEREOF'
[Unit]
Description=Antivirus/rootkit scan 10 minutes after boot, then daily
After=network-online.target

[Timer]
OnBootSec=10min
OnUnitActiveSec=1d
Unit=avscan.service

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable avscan.timer >/dev/null 2>&1

printf '%s\n' "Готово."
printf '%s\n' "Скан идёт в фоне: +10 мин после загрузки и далее раз в сутки (avscan.timer) — вход НЕ блокируется."
printf '%s\n' "Журналы: /var/log/avscan/"
printf '%s\n' "Просмотр сервиса: journalctl -u avscan.service -f"
printf '%s\n' "Ручной запуск: sudo systemctl start avscan.service"
printf '%s\n' "Ручной запуск таймера сейчас: sudo systemctl start avscan.timer"
