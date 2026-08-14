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

printf '[1/4] Установка ClamAV (менеджер пакетов: %s)...\n' "$pm"
case "$pm" in
  apt)
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon
    ;;
  dnf)
    dnf install -y clamav clamav-update
    ;;
  yum)
    yum install -y clamav clamav-update
    ;;
  pacman)
    pacman -S --noconfirm --needed clamav
    ;;
  zypper)
    zypper --non-interactive install clamav
    ;;
esac

printf '%s\n' "[2/4] Обновление базы сигнатур (freshclam)..."
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

# freshclam под root ломает владельца базы -> вернуть clamav
chown -R clamav:clamav /var/lib/clamav 2>/dev/null || true

printf '%s\n' "[3/4] Установка сценариев и сервиса автозапуска..."
install -d /usr/local/sbin /var/log/clamav /etc/issue.d

cat > /usr/local/sbin/clamav-bootscan.sh <<'EOF'
#!/usr/bin/env bash
REPORT=/var/log/clamav/boot-report.txt
MSG=/var/log/clamav/boot-message.txt
LOG=/var/log/clamav/bootscan.log
/usr/bin/clamscan -r -i -q --no-summary \
  --exclude-dir='^/proc' --exclude-dir='^/sys' --exclude-dir='^/dev' \
  --exclude-dir='^/run' --exclude-dir='^/mnt' --exclude-dir='^/media' \
  --exclude-dir='^/var/cache' --exclude-dir='\.cache$' \
  / 2>>"$LOG" > "$REPORT" || true
if [ -s "$REPORT" ] && grep -q "FOUND" "$REPORT"; then
  {
    printf '\n===================== CLAMAV: ОБНАРУЖЕНЫ ВИРУСЫ =====================\n'
    cat "$REPORT"
    printf '========================================================================\n\n'
  } > "$MSG"
  cp "$MSG" /etc/issue.d/clamav-report
  for tty in /dev/console /dev/tty1 /dev/tty2 /dev/tty3 /dev/tty4 /dev/tty5 /dev/tty6; do
    cat "$MSG" > "$tty" 2>/dev/null || true
  done
  wall -n < "$MSG" 2>/dev/null || true
else
  rm -f /etc/issue.d/clamav-report "$MSG"
fi
EOF
chmod 755 /usr/local/sbin/clamav-bootscan.sh

cat > /usr/local/sbin/clamav-bootscan-start.sh <<'EOF'
#!/usr/bin/env bash
setsid nice -n 19 ionice -c 3 /usr/local/sbin/clamav-bootscan.sh >/dev/null 2>&1 &
exit 0
EOF
chmod 755 /usr/local/sbin/clamav-bootscan-start.sh

if [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/clamav-bootscan.service <<'EOF'
[Unit]
Description=ClamAV full system scan
After=local-fs.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/clamav-bootscan-start.sh
TimeoutSec=0
EOF

  cat > /etc/systemd/system/clamav-bootscan.timer <<'EOF'
[Unit]
Description=ClamAV daily system scan timer

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=15min
OnActiveSec=1min
Unit=clamav-bootscan.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable clamav-bootscan.timer
  printf '%s\n' "[4/4] Таймер clamav-bootscan добавлен в автозагрузку."
  printf '%s\n' "Скан идёт раз в сутки; если комп был выключен в это время — выполнится при следующей загрузке."
  printf '%s\n' "Запуск первой проверки (в фоне)..."
  systemctl start clamav-bootscan.timer
else
  if ! grep -q "clamav-bootscan" /etc/rc.local 2>/dev/null; then
    printf '%s\n' "/usr/local/sbin/clamav-bootscan-start.sh" >> /etc/rc.local
    chmod 755 /etc/rc.local 2>/dev/null || true
  fi
  printf '%s\n' "[4/4] Автозапуск добавлен в /etc/rc.local."
fi

printf '%s\n' "Готово. Система будет проверяться на вирусы раз в сутки."
printf '%s\n' "Пропущенное сканирование выполнится при следующей загрузке (Persistent=true)."
printf '%s\n' "Журнал сканирования: /var/log/clamav/bootscan.log"
printf '%s\n' "Отчёт об обнаружениях: /var/log/clamav/boot-report.txt"
