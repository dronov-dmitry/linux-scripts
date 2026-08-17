#!/usr/bin/env bash
#
# security_audit.sh — аудит безопасности локальной системы (Debian/Ubuntu/Zorin)
# Режим: только чтение/диагностика. Ничего не меняет.
# Использование: sudo ./security_audit.sh
#
# Критерии: UFW должен быть ВКЛЮЧЁН, sshd должен быть ВЫКЛЮЧЕН.
# Это аудит соответствия (PASS/FAIL) + дополнительные предупреждения (WARN).

set -u

# Принудительно английская локаль, чтобы тесты грепали "Status: active", "active" и т.п.
# без зависимости от локали системы (ru_RU.UTF-8 переводит вывод ufw/apt/… на русский).
# Важно: в glibc переменная LANGUAGE приоритетнее LC_ALL, поэтому сбрасываем её тоже.
export LC_ALL=C LANGUAGE=C LANG=C

if [[ $EUID -ne 0 ]]; then
  echo "Запустите с правами root: sudo $0" >&2
  exit 1
fi

PASS=0
FAIL=0
WARN=0
declare -a failed_items=()
declare -a warn_items=()

header() { echo; echo "=== $1 ==="; }

ok()   { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad()  { FAIL=$((FAIL+1)); failed_items+=("$1"); echo "  [FAIL] $1"; }
warn() { WARN=$((WARN+1)); warn_items+=("$1"); echo "  [WARN] $1"; }

verdict() {
  echo
  echo "==============================="
  if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo " ВЕРДИКТ: СИСТЕМА БЕЗОПАСНА (в рамках проверки)"
  elif [[ $FAIL -eq 0 ]]; then
    echo " ВЕРДИКТ: В ОСНОВНОМ БЕЗОПАСНА, но есть замечания"
  else
    echo " ВЕРДИКТ: ЕСТЬ ПРОБЛЕМЫ БЕЗОПАСНОСТИ ($FAIL серьёзных)"
  fi
  echo " PASS=$PASS FAIL=$FAIL WARN=$WARN"
  echo "==============================="
  if [[ ${#failed_items[@]} -gt 0 ]]; then
    echo; echo "КРИТИЧНЫЕ ИСПРАВЛЕНИЯ:"
    for i in "${failed_items[@]}"; do echo "  - $i"; done
  fi
  if [[ ${#warn_items[@]} -gt 0 ]]; then
    echo; echo "РЕКОМЕНДАЦИИ:"
    for i in "${warn_items[@]}"; do echo "  - $i"; done
  fi
}

docker_status() {
  if command -v systemctl >/dev/null && systemctl is-active docker 2>/dev/null | grep -qx "active"; then
    warn "Docker активен — проверьте контейнеры на уязвимости и права."
  fi
}

# ---------------- Фаервол UFW ----------------
header "Фаервол UFW (должен быть включён)"
if command -v ufw >/dev/null; then
  if ufw status | grep -q "Status: active"; then
    ok "UFW ВКЛЮЧЁН"
    RULES=$(ufw status numbered | grep -cE "^\[" )
    if [[ "$RULES" -gt 0 ]]; then
      ok "Правил UFW: $RULES"
    else
      warn "UFW включён, но нет ни одного правила (политика по умолчанию)."
    fi
    if ufw status | grep -qi "anywhere.*ALLOW.*22"; then
      warn "Порт 22 (SSH) явно разрешён в UFW."
    fi
  else
    bad "UFW ВЫКЛЮЧЕН. Включите: sudo ufw enable"
  fi
else
  bad "UFW не установлен (ufw отсутствует)."
fi

# Другие фаерволы/nftables
header "Альтернативные фаерволы"
if command -v nft >/dev/null; then
  if nft list ruleset 2>/dev/null | grep -q . && ! ufw status 2>/dev/null | grep -q active; then
    ok "nftables активен как резерв"
  elif ! ufw status 2>/dev/null | grep -q active; then
    warn "nftables установлен, но правила не найдены."
  fi
fi
if command -v iptables >/dev/null && ! ufw status 2>/dev/null | grep -q active; then
  if iptables -L -n 2>/dev/null | grep -qE "(Chain (INPUT|FORWARD)|DROP)"; then
    ok "iptables содержит правила"
  else
    warn "iptables пуст."
  fi
fi

# ---------------- SSH (должен быть выключен) ----------------
header "SSH / удалённый доступ (должен быть ВЫКЛЮЧЕН)"
RUNNING=0
if command -v sshd >/dev/null; then
  RUNNING=1
else
  for p in /usr/sbin/sshd /usr/lib/openssh/sftp-server; do
    [[ -x "$p" ]] && RUNNING=1
  done
fi
if systemctl is-active ssh 2>/dev/null | grep -qx "active"; then RUNNING=1; fi
if systemctl is-active sshd 2>/dev/null | grep -qx "active"; then RUNNING=1; fi
if command -v systemctl >/dev/null; then
  for s in ssh.socket sshd.socket ssh-listener.service; do
    systemctl is-active "$s" 2>/dev/null | grep -qx "active" && RUNNING=1
  done
fi

if [[ "$RUNNING" -eq 1 ]]; then
  bad "ssh/sshd активен. Отключите: sudo systemctl disable --now ssh sshd"
  if [[ -f /etc/ssh/sshd_config ]]; then
    PERMIT=$(grep -E '^\s*PermitRootLogin' /etc/ssh/sshd_config | awk '{print $2}')
    if [[ "$PERMIT" =~ (yes|prohibit-password) ]]; then
      bad "Разрешён вход root через SSH (PermitRootLogin=$PERMIT)."
    fi
    PW=$(grep -E '^\s*PasswordAuthentication' /etc/ssh/sshd_config | awk '{print $2}')
    if [[ "$PW" == "yes" ]]; then
      warn "В SSH разрешена парольная аутентификация."
    fi
  fi
else
  ok "SSH выключен (sshd не запущен / не установлен)"
fi
# Прослушивание порта 22 в принципе
if ss -ltn 2>/dev/null | grep -q ":22 "; then
  bad "Порт 22 реально прослушивается."
else
  ok "Порт 22 не прослушивается"
fi

# Другие удалённые сервисы
header "Прочие сетевые сервисы"
for srv in telnetd vsftpd proftpd smbd rdp xrdp; do
  if systemctl is-active "$srv" 2>/dev/null | grep -qx "active"; then
    warn "Работает удалённый/ненужный сервис: $srv"
  fi
done
if ss -ltnu 2>/dev/null | grep -q ":23 "; then warn "Открыт порт 23 (telnet)."; fi
if ss -ltnu 2>/dev/null | grep -q ":21 "; then warn "Открыт порт 21 (FTP, пароли открыто)."; fi

# Прослушиваемые порты (кратко)
header "Открытые прослушиваемые порты"
PORTS=$(ss -ltnH 2>/dev/null | awk '{print $4}' | sed 's/\[::\]/0.0.0.0/; s/\*//' | sort -u)
if [[ -z "$PORTS" ]]; then
  ok "Нет прослушиваемых TCP-портов"
else
  echo "  $PORTS"
  if echo "$PORTS" | grep -qE '0\.0\.0\.0:|\[::\]:|:::'; then
    warn "Есть порты, доступные всем из сети (0.0.0.0/:::). Проверьте необходимость."
  else
    ok "Все порты слушают только localhost."
  fi
fi

# ---------------- Обновления ----------------
header "Системные обновления"
if command -v apt >/dev/null; then
  UPD=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / {n++} END {print n+0}')
  if [[ "$UPD" -eq 0 ]]; then
    ok "Обновления установлены"
  else
    bad "Доступно обновлений для установки: $UPD. Выполните sudo apt update && sudo apt full-upgrade"
  fi
  if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && grep -qE "2|1" /etc/apt/apt.conf.d/20auto-upgrades; then
    ok "Автообновления безопасности настроены"
  else
    warn "Автообновления безопасности не настроены (unattended-upgrades)."
  fi
fi
if command -v snap >/dev/null; then
  HOLD=$(snap refresh --list 2>/dev/null | grep -c "held\|refreshed")
  if [[ "$HOLD" -eq 0 ]]; then
    ok "Snap-пакеты актуальны"
  else
    warn "Есть snap-обновления: sudo snap refresh"
  fi
fi

# ---------------- Пользователи и пароли ----------------
header "Пользователи и пароли"
USERS=$(awk -F: '($3>=1000)&&($3<65534){print $1":uid"$3":shell:"$7}' /etc/passwd)
if [[ -z "$USERS" ]]; then
  ok "Нет интерактивных пользователей"
else
  echo "  $USERS"
  echo "$USERS" | while IFS=: read -r u ud sh; do
    if [[ "$sh" == "/bin/bash" || "$sh" == "/bin/zsh" ]] && ! grep -qE "^$u:" /etc/shadow; then
      bad "Пользователь '$u' не имеет записи в /etc/shadow."
    fi
  done
  if command -v passwd >/dev/null; then
    while IFS=: read -r u ud sh; do
      [[ "$sh" =~ /(nologin|false)$ ]] && continue
      STATE=$(passwd -S "$u" 2>/dev/null | awk '{print $2}')
      if [[ "$STATE" != "P" ]]; then
        bad "У пользователя '$u' нет пароля (passwd -S = $STATE)."
      fi
    done <<< "$USERS"
  fi
fi

# root без пароля / с пустым
RLOCKED=$(passwd -S root 2>/dev/null | awk '{print $2}')
if [[ "$RLOCKED" != "L" ]]; then
  warn "Root-пароль активен или не заблокирован (state=$RLOCKED). Для Ubuntu так и должно быть."
else
  ok "Root заблокирован (соответствует дистрибутиву)"
fi

# uid 0 аккаунты
header "Дубли root (uid=0)"
NUL=$(awk -F: '($3==0){print $1}' /etc/passwd | wc -l)
if [[ "$NUL" -gt 1 ]]; then
  bad "Несколько аккаунтов uid=0: $(awk -F: '($3==0){print $1}' /etc/passwd | tr '\n' ' ')"
else
  ok "Единственный uid=0 — root"
fi

# ---------------- Sudo ----------------
header "Конфигурация sudo"
if ! grep -qE "NOPASSWD|!authenticate" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
  ok "Нет правил NOPASSWD"
else
  bad "Найдены правила NOPASSWD/!authenticate в sudo — пароль не требуется."
fi
NOPATH=$(awk '/secure_path/{print $2}' /etc/sudoers 2>/dev/null | head -1)
if [[ -z "$NOPATH" ]]; then
  warn "secure_path не настроен в sudoers."
fi

if command -v journalctl >/dev/null; then
  echo "Последние неудачные попытки sudo (/var/log/auth.log или journal):"
  journalctl -q _COMM=sudo 2>/dev/null | grep -i "incorrect password" | tail -3 || \
    grep -i "incorrect password" /var/log/auth.log 2>/dev/null | tail -3
  echo "  (пусто — это хорошо)"
fi

# ---------------- Инциденты / атаки ----------------
header "Признаки взлома/атак"
AUTHL=""
[[ -r /var/log/auth.log ]] && AUTHL=/var/log/auth.log
if [[ -n "$AUTHL" ]]; then
  NOK=$(grep -c "Failed password" "$AUTHL" 2>/dev/null)
  if [[ "${NOK:-0}" -gt 0 ]]; then
    warn "Попыток входа с неверным паролем в логах: $NOK"
    echo "  Последниеsource IP:"
    grep "Failed password" "$AUTHL" 2>/dev/null | grep -oE "from [0-9.]+" | awk '{print $2}' | sort | uniq -c | sort -rn | head -5
  else
    ok "Нет неудачных SSH-подключений в логах"
  fi
else
  warn "Лог auth.log недоступен."
fi
if [[ -n "$AUTHL" ]] && grep -q "Accepted password" "$AUTHL"; then
  warn "В логах есть успешные входы по паролю (возможно, SSH)."
fi

# ---------------- СКАН троянов/руткитов ----------------
header "Антируткит / антивирус"
if command -v rkhunter >/dev/null; then
  ok "rkhunter установлен"
  if [[ -f /var/lib/rkhunter/rkhunter.dat ]]; then
    echo "  Последний прогон rkhunter:"
    grep -A1 "Last run" /var/lib/rkhunter/rkhunter.dat 2>/dev/null
  fi
else
  warn "rkhunter не установлен (sudo apt install rkhunter)"
fi
if command -v chkrootkit >/dev/null; then
  ok "chkrootkit установлен"
else
  warn "chkrootkit не установлен (sudo apt install chkrootkit)"
fi
if command -v clamscan >/dev/null; then
  ok "ClamAV установлен"
else
  warn "ClamAV не установлен (sudo apt install clamav clamav-daemon)"
fi

# ---------------- SUID/SGID ----------------
header "SUID/SGID бинарники (потенциально опасные)"
SUIDD=$(find / -xdev -type f -perm /6000 2>/dev/null)
N=$(echo "$SUIDD" | grep -c . )
echo "  Кол-во SUID/SGID файлов: $N"
if echo "$SUIDD" | grep -qE "(/bin/(mount|umount|su)|/usr/bin/(sudo|passwd|su))"; then
  ok "Стандартные SUID утилиты на месте"
fi
# Стандартный набор Ubuntu: /usr/*, /bin/*, /snap, /opt, /lib; chroot-сборки pmbootstrap — вне хоста.
PMB=$(echo "$SUIDD" | grep -cE 'pmbootstrap|/chroot' || true)
[[ -n "$PMB" && "$PMB" -gt 0 ]] && echo "  INFO: $PMB SUID-файлов во chroot pmbootstrap (нормально для сборки Android-ROM, на хост не влияют)."
UNW=$(echo "$SUIDD" | grep -vE '^(/usr|/bin|/snap|/opt|/lib|/etc)' | grep -vE 'pmbootstrap|/chroot')
if [[ -n "$UNW" ]]; then
  warn "SUID-файлы вне стандартных путей (/usr, /bin, /snap, /opt, /lib):"
  echo "$UNW" | sed 's/^/    /'
else
  ok "Все SUID/SGID файлы в стандартных путях"
fi

# ---------------- Мир-записываемые файлы ----------------
header "Записываемые для всех файлы"
NET=$(find / ! -path /proc ! -path /sys ! -path /dev ! -path /run -xdev -type f -perm -0002 2>/dev/null | grep -v "/home/\|/tmp/\|/var/tmp\|/snap/\|/var/cache")
if [[ -n "$NET" ]]; then
  warn "Мир-записываемые файлы вне настраиваемых зон:"
  echo "$NET" | sed 's/^/    /'
else
  ok "Не найдены подозрительные мир-записываемые файлы"
fi

# ---------------- Kernel hardening (sysctl) ----------------
header "Hаstraивание ядра (sysctl)"
for kv in net.ipv4.ip_forward net.ipv4.conf.all.accept_redirects net.ipv4.conf.default.accept_redirects net.ipv4.conf.all.rp_filter kernel.suid_dumpable; do
  V=$(sysctl -n "$kv" 2>/dev/null)
  [[ -z "$V" ]] && continue
  case "$kv" in
    net.ipv4.ip_forward)
      [[ "$V" == "1" ]] && warn "IP forward включён ($kv=1) — см. /etc/sysctl.d/*.conf."
      ;;
    kernel.suid_dumpable)
      [[ "$V" != "0" ]] && warn "Дампы ядра разрешены ($kv=$V)."
      ;;
    *)
      [[ "$V" == "1" ]] && warn "$kv=1 — следует выставить 0."
      ;;
  esac
done
ip -br addr show 2>/dev/null | grep -v "127.0.0.1\|::1" | head -4 >/dev/null && ok "Сетевые интерфейсы: $(ip -br addr show 2>/dev/null | grep -v "lo" | awk '{print $1}' | tr '\n' ' ')"

# ---------------- Автоматический вход / пароли в открытом виде ----------------
header "Автовход и локальные пароли"
if grep -rE "autologin|AutoLogin" /etc/gdm3* /etc/lightdm /etc/gdm /etc/lightdm/lightdm.conf 2>/dev/null | grep -v "#"; then
  warn "Найден автовход в графическую систему."
else
  ok "Автовхода в графическую оболочку не найдено"
fi
TECH=$(find /var/run /tmp /home -xdev -name ".Xauthority" -o -name "*.ovpn" 2>/dev/null)
echo "  (Xauthority/ovpn файлы: $(echo "$TECH" | grep -c .))"

# ---------------- Bluetooth / USB ----------------
header "Bluetooth и USB"
if command -v bluetoothctl >/dev/null; then
  if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    warn "Bluetooth включён. Отключите, если не нужен: sudo systemctl disable bluetooth"
  else
    ok "Bluetooth выключен"
  fi
fi
if ! lsmod 2>/dev/null | grep -q u3_driver; then
  :
fi
MODS=$(lsmod 2>/dev/null | awk '{print $1}' | grep -E "usb_storage|u3" | head -1)
if [[ -n "$MODS" ]]; then
  warn "USB-накопители разрешены (модуль $MODS в ядре). При высокой паранойе — блокируйте."
else
  ok "USB-накопители не подгружены"
fi

# ---------------- Журнал (аудит) ----------------
header "Аудит и журналирование"
if systemctl is-active auditd 2>/dev/null | grep -q active; then
  ok "auditd работает"
else
  warn "auditd не активен."
fi
if systemctl is-active rsyslog 2>/dev/null | grep -q active || systemctl is-active syslog 2>/dev/null | grep -q active; then
  ok "Журналирование активно"
else
  warn "rsyslog/syslog не активен — логи могут не писаться."
fi

# ---------------- Экранирование диска ----------------
header "Шифрование диска"
CRYPT=$(lsblk -o FSTYPE 2>/dev/null | grep -iE "crypto_LUKS" | head -1)
SWAPFT=$(findmnt -no FSTYPE / 2>/dev/null)
if [[ -n "$CRYPT" ]]; then
  ok "Диск/раздел шифруется (LUKS): $CRYPT"
else
  warn "Раздел / использует $SWAPFT без LUKS — данные без шифрования."
fi

# ---------------- Докер (отдельно) ----------------
docker_status

verdict
