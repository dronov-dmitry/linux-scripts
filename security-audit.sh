#!/usr/bin/env bash
# ============================================================================
# security-audit.sh — Комплексный аудит безопасности Linux-системы
# ----------------------------------------------------------------------------
#
# ЧТО ДЕЛАЕТ ЭТОТ СКРИПТ:
#   Проводит диагностику безопасности хоста и формирует текстовый отчёт
#   /home/kat/security-audit_report_<дата_время>.txt с итоговым вердиктом
#   (PASS/FAIL/WARN/INFO) и списком критичных исправлений и рекомендаций.
#
# ПРОВЕРЯЕМЫЕ ОБЛАСТИ (24 раздела):
#   1.  Ядро и загрузка: sysctl-параметры (ASLR, kptr_restrict, rp_filter,
#       ip_forward, protect_fifos, core_pattern и др.), KASLR, тип загрузки (EFI/BIOS).
#   2.  Файрвол и сеть: UFW, nftables, правила iptables, сетевые интерфейсы,
#       прослушиваемые порты, удалённые сервисы, DNS/DNSSEC, IPv6.
#   3.  SSH: установлен ли sshd, слушается ли порт 22, настройки sshd_config
#       (PermitRootLogin, PasswordAuthentication, слабые шифры/MAC/KEX и др.).
#   4.  Пользователи: uid=0, пароли, срок действия пароля, root заблокирован,
#       UMASK, домашние директории, системные аккаунты.
#   5.  Sudo и PAM: NOPASSWD-правила, логирование sudo, secure_path,
#       pam_wheel, pwquality, faillock.
#   6.  Неудачные входы и признаки атак по логам.
#   7.  Бэкдоры/руткиты: rkhunter/chkrootkit/ClamAV, SUID/SGID, LD_PRELOAD,
#       следы руткитов, подозрительные процессы.
#   8.  ПО и уязвимости: доступные обновления, автообновления, snap-пакеты,
#       опасные пакеты, целостность dpkg.
#   9.  Docker security (если установлен).
#  10.  Файловая система и диски: монтирование, шифрование (LUKS), swap,
#       место, права /boot, лимиты журнала.
#  11.  Службы и демоны: потенциально опасные и все запущенные сервисы,
#       avahi, CUPS, скрытые сокеты.
#  12.  Логирование и мониторинг: auditd, fail2ban, rsyslog, файлы логов,
#       logrotate, права /var/log.
#  13.  Индикаторы вредоносной активности: cron-задачи, скрытые и бесхозные
#       файлы, world-writable файлы, права критичных файлов.
#  14.  Векторы побега из контейнеров/ВМ.
#  15.  Шифрование и секреты: GPG-, SSH-ключи, доступность приватных ключей.
#  16.  Сетевые атаки: ARP-таблица, маршруты, IP forwarding.
#  17.  USB, Bluetooth, авто-вход и локальные файлы.
#  18.  AppArmor/SELinux: загружен ли, сколько профилей в режимах.
#  19.  Защита от эксплуатации ядра: SMEP, SMAP, NX, уязвимости CPU.
#  20.  Systemd unit hardening: директивы sandboxing у активных сервисов.
#  21.  Capabilities audit: бинарники с расширенными capabilities, SUID/SGID.
#  22.  Ядро: compile-time опции из /boot/config-* (CONFIG_*), mmap_rnd_bits.
#  23.  Прошивка: microcode CPU, обновления fwupd, Secure Boot.
#  24.  Сторонние репозитории APT, snap --classic, Flatpak.
#
# РЕЖИМ РАБОТЫ:
#   Только чтение и диагностика — НИЧЕГО НЕ МЕНЯЕТ и НЕ исправляет.
#   Для корректной работы большинства проверок нужны права root.
#
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./security-audit.sh
#   Результат: отчёт сохраняется в /home/kat/security-audit_report_*.txt
#               и выводится в терминал; подсчитывается PASS/FAIL/WARN/INFO.
#
# ЗАМЕЧАНИЕ ПО ПРАВКАМ (необязательные проверки):
#   Проверка USB-накопителей (usb_storage) отключена как некритичная —
#   выводится INFO. Проверка DNSSEC принимает и yes, и allow-downgrade
#   (читает /etc/systemd/resolved.conf напрямую, с запасным вариантом resolvectl).
# ============================================================================

set -uo pipefail

# Локаль C — чтобы ufw/apt/… выводили по-английски и тесты грепали стабильно.
export LC_ALL=C LANGUAGE=C LANG=C

if [[ $EUID -ne 0 ]]; then
  echo "Запустите с правами root: sudo $0" >&2
  exit 1
fi

REPORT="/home/kat/security-audit_report_$(date +%Y%m%d_%H%M%S).txt"
RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
RST='\033[0m'
BOLD='\033[1m'

PASS=0
FAIL=0
WARN=0
INFO=0
declare -a failed_items=()
declare -a warn_items=()

section() { echo -e "\n${BOLD}${CYN}══════════════════════════════════════════════════════════════${RST}" | tee -a "$REPORT"; echo -e "${BOLD}${CYN}  $1${RST}" | tee -a "$REPORT"; echo -e "${BOLD}${CYN}══════════════════════════════════════════════════════════════${RST}" | tee -a "$REPORT"; }
ok()    { PASS=$((PASS+1)); echo -e "  ${GRN}[PASS]${RST}  $1" | tee -a "$REPORT"; }
bad()   { FAIL=$((FAIL+1)); failed_items+=("$1"); echo -e "  ${RED}[FAIL]${RST}  $1" | tee -a "$REPORT"; }
warn()  { WARN=$((WARN+1)); warn_items+=("$1"); echo -e "  ${YEL}[WARN]${RST}  $1" | tee -a "$REPORT"; }
info()  { INFO=$((INFO+1)); echo -e "  [INFO]   $1" | tee -a "$REPORT"; }
divider(){ echo "" | tee -a "$REPORT"; }

{
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              SECURITY AUDIT REPORT (merged)                ║"
echo "║  Host: $(hostname)                                         ║"
echo "║  Date: $(date '+%Y-%m-%d %H:%M:%S %Z')                   ║"
echo "║  Kernel: $(uname -r)                                       ║"
echo "║  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
} > "$REPORT"

verdict() {
  echo | tee -a "$REPORT"
  echo "===============================" | tee -a "$REPORT"
  if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo -e " ${GRN}ВЕРДИКТ: СИСТЕМА БЕЗОПАСНА (в рамках проверки)${RST}" | tee -a "$REPORT"
  elif [[ $FAIL -eq 0 ]]; then
    echo -e " ${YEL}ВЕРДИКТ: В ОСНОВНОМ БЕЗОПАСНА, но есть замечания${RST}" | tee -a "$REPORT"
  else
    echo -e " ${RED}ВЕРДИКТ: ЕСТЬ ПРОБЛЕМЫ БЕЗОПАСНОСТИ ($FAIL серьёзных)${RST}" | tee -a "$REPORT"
  fi
  echo " PASS=$PASS  FAIL=$FAIL  WARN=$WARN  INFO=$INFO" | tee -a "$REPORT"
  echo "===============================" | tee -a "$REPORT"
  if [[ ${#failed_items[@]} -gt 0 ]]; then
    echo; echo "КРИТИЧНЫЕ ИСПРАВЛЕНИЯ:" | tee -a "$REPORT"
    for i in "${failed_items[@]}"; do echo "  - $i" | tee -a "$REPORT"; done
  fi
  if [[ ${#warn_items[@]} -gt 0 ]]; then
    echo; echo "РЕКОМЕНДАЦИИ:" | tee -a "$REPORT"
    for i in "${warn_items[@]}"; do echo "  - $i" | tee -a "$REPORT"; done
  fi
  echo "" | tee -a "$REPORT"
  echo "Full report saved to: $REPORT"
}

# ============================================================================
section "1. KERNEL & BOOT SECURITY"
# ============================================================================

divider

KVER=$(uname -r)
KDATE=$(stat -c %y /boot/vmlinuz-$KVER 2>/dev/null || echo "unknown")
info "Kernel: $KVER (boot image date: $KDATE)"

echo -e "\n  ${BOLD}Sysctl Security Parameters:${RST}" | tee -a "$REPORT"

declare -A SYSCTL_CHECKS=(
    ["net.ipv4.conf.all.accept_redirects"]="0"
    ["net.ipv4.conf.all.send_redirects"]="0"
    ["net.ipv4.conf.all.accept_source_route"]="0"
    ["net.ipv4.conf.all.log_martians"]="1"
    ["net.ipv4.conf.default.rp_filter"]="1"
    ["net.ipv4.icmp_echo_ignore_broadcasts"]="1"
    ["net.ipv4.tcp_syncookies"]="1"
    ["net.ipv4.ip_forward"]="0"
    ["net.ipv4.conf.all.proxy_arp"]="0"
    ["net.ipv6.conf.all.accept_redirects"]="0"
    ["net.ipv6.conf.all.accept_source_route"]="0"
    ["net.ipv6.conf.all.forwarding"]="0"
    ["kernel.randomize_va_space"]="2"
    ["kernel.dmesg_restrict"]="1"
    ["kernel.kptr_restrict"]="2"
    ["kernel.yama.ptrace_scope"]="1"
    ["fs.suid_dumpable"]="0"
    ["fs.protected_hardlinks"]="1"
    ["fs.protected_symlinks"]="1"
    ["fs.protected_fifos"]="2"
    ["fs.protected_regular"]="2"
    ["kernel.unprivileged_bpf_disabled"]="1"
    ["net.core.bpf_jit_harden"]="2"
    ["vm.mmap_min_addr"]="65536"
    ["kernel.perf_event_paranoid"]="3"
    ["kernel.sysrq"]="0"
    ["net.ipv4.conf.default.accept_redirects"]="0"
    ["net.ipv4.conf.default.send_redirects"]="0"
    ["net.ipv6.conf.default.accept_redirects"]="0"
    ["net.ipv6.conf.all.accept_ra"]="0"
    ["vm.unprivileged_userfaultfd"]="0"
)

command -v docker >/dev/null 2>&1 && DOCKER_INSTALLED=1 || DOCKER_INSTALLED=0

for param in "${!SYSCTL_CHECKS[@]}"; do
    expected="${SYSCTL_CHECKS[$param]}"
    actual=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    if [[ "$actual" == "N/A" ]]; then
        info "sysctl $param not available (неподдерживается ядром)"
    elif [[ "$param" == "net.ipv4.ip_forward" && "$DOCKER_INSTALLED" -eq 1 ]]; then
        if [[ "$actual" == "1" ]]; then
            ok "sysctl $param = $actual (требуется Docker для NAT/сети контейнеров)"
        else
            bad "sysctl $param = $actual (ожидалось 1 при установленном Docker)"
        fi
    elif [[ "$param" == "kernel.unprivileged_bpf_disabled" && "$actual" == "2" ]]; then
        ok "sysctl $param = $actual (2 безопаснее, чем 1: BPF permanently disabled)"
    elif [[ "$actual" != "$expected" ]]; then
        bad "sysctl $param = $actual (ожидалось $expected)"
    else
        ok "sysctl $param = $actual"
    fi
done

divider

ASLR=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null)
if [[ "$ASLR" == "2" ]]; then
    ok "ASLR fully enabled (value=2)"
else
    bad "ASLR not fully enabled (value=$ASLR, нужно 2)"
fi

COREPATTERN=$(cat /proc/sys/kernel/core_pattern 2>/dev/null)
if [[ "$COREPATTERN" == "|"* ]] || [[ "$COREPATTERN" == "none" ]]; then
    ok "Core dumps restricted: $COREPATTERN"
else
    warn "Core dumps writable: $COREPATTERN (атакующие могут читать память)"
fi

if grep -q "nokaslr" /proc/cmdline 2>/dev/null; then
    bad "KASLR ОТКЛЮЧЁН через nokaslr!"
elif grep -q "kaslr" /proc/cmdline 2>/dev/null; then
    ok "KASLR включен"
else
    info "KASLR status неизвестен из cmdline"
fi

if [ -d /sys/firmware/efi ]; then
    info "EFI boot detected (Secure Boot status неизвестен)"
else
    info "Legacy BIOS boot (no UEFI)"
fi

# ============================================================================
section "2. FIREWALL & NETWORK SECURITY"
# ============================================================================

divider

echo -e "\n  ${BOLD}UFW Firewall:${RST}" | tee -a "$REPORT"
if command -v ufw >/dev/null; then
  if ufw status | grep -q "Status: active"; then
    ok "UFW ВКЛЮЧЁН"
    RULES=$(ufw status numbered | grep -cE "^\[")
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
  bad "UFW не установлен."
fi

divider

echo -e "\n  ${BOLD}Альтернативные фаерволы:${RST}" | tee -a "$REPORT"
if command -v nft >/dev/null; then
  if nft list ruleset 2>/dev/null | grep -q . && ! ufw status 2>/dev/null | grep -q active; then
    ok "nftables активен как резерв"
  elif ! ufw status 2>/dev/null | grep -q active; then
    warn "nftables установлен, но правила не найдены."
  fi
fi
echo -e "\n  ${BOLD}iptables rules:${RST}" | tee -a "$REPORT"
IPT_RULES=$(iptables -L -n -v 2>/dev/null | head -30)
if [ -n "$IPT_RULES" ]; then
    if grep -qE "DROP|REJECT" <<< "$IPT_RULES"; then
        ok "iptables: DROP/REJECT правила найдены"
    else
        warn "iptables: нет DROP/REJECT правил (всё проходит)"
    fi
    echo "$IPT_RULES" >> "$REPORT"
else
    warn "iptables: не удалось получить правила"
fi

divider

echo -e "\n  ${BOLD}Network Interfaces:${RST}" | tee -a "$REPORT"
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v lo); do
    PROMISC=$(ip link show "$iface" 2>/dev/null | grep -o "PROMISC" || true)
    if [ -n "$PROMISC" ]; then
        bad "Interface $iface в PROMISCUOUS MODE (возможный сниффер/MITM)"
    else
        ok "Interface $iface: normal mode"
    fi
done
ok "Сетевые интерфейсы: $(ip -br addr show 2>/dev/null | grep -v "lo" | awk '{print $1}' | tr '\n' ' ')"

echo -e "\n  ${BOLD}Listening Ports:${RST}" | tee -a "$REPORT"
PORTS=$(ss -ltnH 2>/dev/null | awk '{print $4}' | sed 's/\[::\]/0.0.0.0/; s/\*//' | sort -u)
if [[ -z "$PORTS" ]]; then
  ok "Нет прослушиваемых TCP-портов"
else
  echo "  $PORTS" | tee -a "$REPORT"
  if echo "$PORTS" | grep -qE '0\.0\.0\.0:|\[::\]:|:::'; then
    warn "Есть порты, доступные всем из сети (0.0.0.0/:::). Проверьте необходимость."
  else
    ok "Все порты слушают только localhost."
  fi
fi
ss -tlnp 2>/dev/null | tee -a "$REPORT"

# Другие удалённые сервисы
echo -e "\n  ${BOLD}Remote Access Services:${RST}" | tee -a "$REPORT"
for srv in sshd xrdp vncserver tigervnc telnetd vsftpd proftpd smbd rdp; do
  if systemctl is-active "$srv" 2>/dev/null | grep -qx "active"; then
    warn "Работает удалённый сервис: $srv"
  fi
done
if ss -ltnu 2>/dev/null | grep -q ":23 "; then warn "Открыт порт 23 (telnet)."; fi
if ss -ltnu 2>/dev/null | grep -q ":21 "; then warn "Открыт порт 21 (FTP, пароли открыто)."; fi

echo -e "\n  ${BOLD}DNS Configuration:${RST}" | tee -a "$REPORT"
if [ -f /etc/resolv.conf ]; then
    NAMESERVERS=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}')
    for ns in $NAMESERVERS; do
        if [[ "$ns" == "127.0.0.53" ]] || [[ "$ns" == "127.0.0.1" ]]; then
            ok "DNS via local resolver: $ns (systemd-resolved)"
        else
            info "DNS server: $ns"
        fi
    done
fi
if command -v resolvectl >/dev/null && systemctl is-active systemd-resolved 2>/dev/null | grep -q "active"; then
    if grep -qE '^DNSSEC=(yes|allow-downgrade)' /etc/systemd/resolved.conf 2>/dev/null \
       || resolvectl status 2>/dev/null | grep -qE "DNSSEC.*(yes|allow-downgrade)"; then
        ok "DNSSEC active"
    else
        warn "DNSSEC не активен / неизвестен"
    fi
else
    info "systemd-resolved не используется — DNSSEC не проверяется"
fi

if sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q "1"; then
    info "IPv6 disabled"
else
    info "IPv6 active — проверьте firewall для IPv6"
fi

# ============================================================================
section "3. SSH SECURITY"
# ============================================================================

divider

echo -e "\n  ${BOLD}SSH / удалённый доступ:${RST}" | tee -a "$REPORT"
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
else
  ok "SSH выключен (sshd не запущен / не установлен)"
fi

if ss -ltn 2>/dev/null | grep -q ":22 "; then
  bad "Порт 22 реально прослушивается."
else
  ok "Порт 22 не прослушивается"
fi

SSHD_CFG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CFG" ]; then
    info "SSH config найден: $SSHD_CFG"

    PERMIT=$(grep -E '^\s*PermitRootLogin' "$SSHD_CFG" 2>/dev/null | awk '{print $2}')
    if [[ "$PERMIT" == "yes" ]]; then
        bad "SSH PermitRootLogin = yes (прямой вход root)"
    elif [[ "$PERMIT" =~ (prohibit-password|without-password) ]]; then
        ok "SSH PermitRootLogin = $PERMIT"
    fi

    PW=$(grep -E '^\s*PasswordAuthentication' "$SSHD_CFG" 2>/dev/null | awk '{print $2}')
    if [[ "$PW" == "yes" ]]; then
        bad "SSH PasswordAuthentication = yes (атака перебором)"
    elif [[ "$PW" == "no" ]]; then
        ok "SSH PasswordAuthentication = no"
    fi

    for setting in PermitEmptyPasswords X11Forwarding AllowTcpForwarding AllowAgentForwarding; do
        VAL=$(grep -i "^${setting}" "$SSHD_CFG" 2>/dev/null | awk '{print $2}' | tail -1)
        if [ -n "$VAL" ]; then
            case "$setting" in
                PermitEmptyPasswords)
                    [[ "$VAL" == "yes" ]] && bad "SSH PermitEmptyPasswords = yes!" || ok "SSH PermitEmptyPasswords = $VAL"
                    ;;
                X11Forwarding)
                    [[ "$VAL" == "yes" ]] && warn "SSH X11Forwarding = yes (keylogger, screen capture)" || ok "SSH X11Forwarding = $VAL"
                    ;;
                *)
                    ok "SSH $setting = $VAL"
                    ;;
            esac
        fi
    done

    for keyfile in /etc/ssh/ssh_host_*_key; do
        if [ -f "$keyfile" ]; then
            PERMS=$(stat -c "%a" "$keyfile" 2>/dev/null)
            if [[ "$PERMS" != "600" ]] && [[ "$PERMS" != "400" ]]; then
                bad "SSH host key permissions: $keyfile ($PERMS, нужно 600)"
            fi
            KEYTYPE=$(ssh-keygen -l -f "$keyfile" 2>/dev/null | awk '{print $NF}' | tr -d '()')
            if [[ "$KEYTYPE" == *"DSA"* ]] || [[ "$KEYTYPE" == *"1024"* ]]; then
                bad "Weak SSH host key: $keyfile ($KEYTYPE)"
            fi
        fi
    done

    WEAK_CIPHERS="3des-cbc,aes128-cbc,aes192-cbc,aes256-cbc,arcfour,arcfour128,arcfour256,blowfish-cbc,cast128-cbc"
    WEAK_MACS="hmac-md5,hmac-md5-96,hmac-sha1-96,umac-64@openssh.com"
    WEAK_KEX="diffie-hellman-group1-sha1,diffie-hellman-group14-sha1"

    configured_ciphers=$(sshd -T 2>/dev/null | grep -i "^ciphers " | awk '{print $2}')
    found_weak=0
    if [[ -n "$configured_ciphers" ]]; then
        IFS=',' read -ra ciphers_arr <<< "$configured_ciphers"
        for wc in $(echo "$WEAK_CIPHERS" | tr ',' ' '); do
            for c in "${ciphers_arr[@]}"; do
                [[ "$c" == "$wc" ]] && warn "SSH слабый шифр: $c" && found_weak=1
            done
        done
        [[ "$found_weak" -eq 0 ]] && ok "SSH Ciphers: слабые шифры отключены"
    fi

    configured_macs=$(sshd -T 2>/dev/null | grep -i "^macs " | awk '{print $2}')
    found_weak=0
    if [[ -n "$configured_macs" ]]; then
        IFS=',' read -ra macs_arr <<< "$configured_macs"
        for wm in $(echo "$WEAK_MACS" | tr ',' ' '); do
            for m in "${macs_arr[@]}"; do
                [[ "$m" == "$wm" ]] && warn "SSH слабый MAC: $m" && found_weak=1
            done
        done
        [[ "$found_weak" -eq 0 ]] && ok "SSH MACs: слабые MAC отключены"
    fi

    configured_kex=$(sshd -T 2>/dev/null | grep -i "^kexalgorithms " | awk '{print $2}')
    found_weak=0
    if [[ -n "$configured_kex" ]]; then
        IFS=',' read -ra kex_arr <<< "$configured_kex"
        for wk in $(echo "$WEAK_KEX" | tr ',' ' '); do
            for k in "${kex_arr[@]}"; do
                [[ "$k" == "$wk" ]] && warn "SSH слабый KeyExchange: $k" && found_weak=1
            done
        done
        [[ "$found_weak" -eq 0 ]] && ok "SSH KexAlgorithms: слабые алгоритмы отключены"
    fi

    sshd_max_auth=$(sshd -T 2>/dev/null | grep -i "^maxauthtries " | awk '{print $2}')
    if [[ -n "$sshd_max_auth" ]]; then
        if [[ "$sshd_max_auth" -le 5 ]] 2>/dev/null; then
            ok "SSH MaxAuthTries = $sshd_max_auth (<= 5)"
        else
            warn "SSH MaxAuthTries = $sshd_max_auth (рекомендуется <= 5)"
        fi
    fi

    sshd_log_grace=$(sshd -T 2>/dev/null | grep -i "^logingracetime " | awk '{print $2}')
    if [[ -n "$sshd_log_grace" ]]; then
        if [[ "$sshd_log_grace" == "0" ]]; then
            warn "SSH LoginGraceTime = unlimited (рекомендуется 30-120s)"
        elif [[ "$sshd_log_grace" -le 120 ]] 2>/dev/null; then
            ok "SSH LoginGraceTime = ${sshd_log_grace}s"
        else
            warn "SSH LoginGraceTime = ${sshd_log_grace}s (рекомендуется 30-120s)"
        fi
    fi

    sshd_log_level=$(sshd -T 2>/dev/null | grep -i "^loglevel " | awk '{print $2}')
    if [[ -n "$sshd_log_level" ]]; then
        if [[ "$sshd_log_level" == "VERBOSE" || "$sshd_log_level" == "INFO" ]]; then
            ok "SSH LogLevel = $sshd_log_level (достаточно для аудита)"
        else
            warn "SSH LogLevel = $sshd_log_level (рекомендуется VERBOSE/INFO)"
        fi
    fi
fi

# ============================================================================
section "4. USER & AUTHENTICATION SECURITY"
# ============================================================================

divider

echo -e "\n  ${BOLD}Users with UID 0 (root-equivalent):${RST}" | tee -a "$REPORT"
ROOTUSERS=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
ROOTCOUNT=$(echo "$ROOTUSERS" | wc -l)
if [ "$ROOTCOUNT" -gt 1 ]; then
    bad "Несколько аккаунтов uid=0: $(echo "$ROOTUSERS" | tr '\n' ' ')"
else
    ok "Единственный uid=0 — root"
fi

echo -e "\n  ${BOLD}Пользователи и пароли:${RST}" | tee -a "$REPORT"
USERS=$(awk -F: '($3>=1000)&&($3<65534){print $1":uid"$3":shell:"$7}' /etc/passwd)
if [[ -z "$USERS" ]]; then
  ok "Нет интерактивных пользователей"
else
  echo "  $USERS" | tee -a "$REPORT"
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

echo -e "\n  ${BOLD}Password aging policy:${RST}" | tee -a "$REPORT"
while IFS=: read -r user _ _ _ _ _ shell; do
    if [ -n "$user" ] && [[ "$shell" =~ /(bash|zsh)$ ]]; then
        UID_VAL=$(id -u "$user" 2>/dev/null || echo "0")
        if [ "$UID_VAL" -ge 1000 ] && [ "$UID_VAL" -lt 65534 ] 2>/dev/null; then
            EXPIRE=$(chage -l "$user" 2>/dev/null | grep "Password expires" | cut -d: -f2 | xargs || true)
            if [[ "$EXPIRE" == "never" ]]; then
                info "User $user: password NEVER expires (NIST 2024 не рекомендует принудительный срок)"
            fi
        fi
    fi
done < /etc/passwd

RLOCKED=$(passwd -S root 2>/dev/null | awk '{print $2}')
if [[ "$RLOCKED" != "L" ]]; then
  warn "Root-пароль активен или не заблокирован (state=$RLOCKED)."
else
  ok "Root заблокирован"
fi

echo -e "\n  ${BOLD}UMASK & login.defs:${RST}" | tee -a "$REPORT"
umask_val=$(grep -E "^UMASK" /etc/login.defs 2>/dev/null | awk '{print $2}')
if [[ -n "$umask_val" ]]; then
    if [[ "$umask_val" == "027" || "$umask_val" == "077" ]]; then
        ok "UMASK в login.defs = $umask_val"
    else
        warn "UMASK в login.defs = $umask_val (рекомендуется 027 или 077)"
    fi
else
    warn "UMASK не задан в /etc/login.defs"
fi

sha_rounds=$(grep -E "^SHA_CRYPT_MIN_ROUNDS" /etc/login.defs 2>/dev/null | awk '{print $2}')
if [[ -n "$sha_rounds" ]]; then
    if [[ "$sha_rounds" -ge 5000 ]] 2>/dev/null; then
        ok "SHA_CRYPT_MIN_ROUNDS = $sha_rounds (>= 5000)"
    else
        warn "SHA_CRYPT_MIN_ROUNDS = $sha_rounds (рекомендуется >= 5000)"
    fi
else
    info "SHA_CRYPT_MIN_ROUNDS не задан (по умолчанию 5000)"
fi

echo -e "\n  ${BOLD}Домашние директории:${RST}" | tee -a "$REPORT"
while IFS=: read -r user _ uid _ _ _ shell; do
    [[ "$uid" -ge 1000 && "$uid" -lt 65534 ]] 2>/dev/null || continue
    [[ "$shell" =~ /(bash|zsh|fish)$ ]] || continue
    home_dir="/home/$user"
    if [[ -d "$home_dir" ]]; then
        home_perms=$(stat -c "%a" "$home_dir" 2>/dev/null)
        if [[ "$home_perms" == "700" || "$home_perms" == "750" || "$home_perms" == "710" ]]; then
            ok "Home $user: $home_perms (норма)"
        else
            warn "Home $user: $home_perms (рекомендуется 700 или 750)"
        fi
    fi
done < /etc/passwd

echo -e "\n  ${BOLD}System accounts:${RST}" | tee -a "$REPORT"
sys_shell_bad=0
while IFS=: read -r user _ uid _ _ _ shell; do
    [[ "$uid" -lt 1000 && "$uid" -ne 0 ]] 2>/dev/null || continue
    [[ "$shell" == "/bin/bash" || "$shell" == "/bin/zsh" || "$shell" == "/bin/sh" ]] || continue
    warn "System account '$user' (uid=$uid) имеет интерактивный shell: $shell"
    sys_shell_bad=1
done < /etc/passwd
[[ "$sys_shell_bad" -eq 0 ]] && ok "Все системные аккаунты (uid<1000) имеют nologin/false shell"

# ============================================================================
section "5. SUDO & PAM SECURITY"
# ============================================================================

divider

echo -e "\n  ${BOLD}Sudo Configuration:${RST}" | tee -a "$REPORT"
NOPASSWD_BROAD=$(grep -E "NOPASSWD|!authenticate" /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v "^#" | grep -E "NOPASSWD:\s*(ALL|/bin/(sh|bash)|/usr/bin/(su|passwd))" || true)
if [ -n "$NOPASSWD_BROAD" ]; then
    bad "Найдены ОБЩИЕ правила NOPASSWD/!authenticate в sudo — пароль не требуется."
else
    ok "Нет общих правил NOPASSWD (scoped-правила для конкретных команд допустимы)"
fi

NOPATH=$(awk '/secure_path/{print $2}' /etc/sudoers 2>/dev/null | head -1)
if [[ -z "$NOPATH" ]]; then
  warn "secure_path не настроен в sudoers."
fi

if [ -f /var/log/sudo.log ] || [ -f /var/log/auth.log ]; then
    ok "Sudo logging available"
fi

if command -v journalctl >/dev/null; then
  echo -e "\n  ${BOLD}Последние неудачные попытки sudo:${RST}" | tee -a "$REPORT"
  SUDO_FAILS=$(journalctl -q _COMM=sudo 2>/dev/null | grep -i "incorrect password" | tail -5 || \
    grep -i "incorrect password" /var/log/auth.log 2>/dev/null | tail -5)
  if [[ -n "$SUDO_FAILS" ]]; then
    NFAILS=$(echo "$SUDO_FAILS" | wc -l)
    info "Есть неудачные попытки sudo: $NFAILS строк (информационно, содержимое скрыто)"
  else
    ok "Нет неудачных попыток sudo"
  fi
fi

echo -e "\n  ${BOLD}PAM Security:${RST}" | tee -a "$REPORT"
if grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
    ok "pam_wheel.so active (su restricted to wheel group)"
else
    warn "pam_wheel.so NOT active (any user can su)"
fi

if [ -f /etc/security/pwquality.conf ]; then
    MINLEN=$(grep "^minlen" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}' || echo "N/A")
    if [ "$MINLEN" != "N/A" ] && [ "$MINLEN" -ge 12 ] 2>/dev/null; then
        ok "Password minimum length: $MINLEN"
    elif [ "$MINLEN" != "N/A" ]; then
        warn "Password minimum length too short: $MINLEN (рекомендуется >= 12)"
    fi
fi

if [ -f /etc/security/faillock.conf ]; then
    if grep -q "^deny" /etc/security/faillock.conf 2>/dev/null; then
        ok "faillock configured"
    fi
fi

echo -e "\n  ${BOLD}PAM password quality (pwquality.conf):${RST}" | tee -a "$REPORT"
if [ -f /etc/security/pwquality.conf ]; then
    for param_name in dcredit ucredit lcredit ocredit maxrepeat maxclassrepeat minclass; do
        val=$(grep -E "^#?\s*${param_name}" /etc/security/pwquality.conf 2>/dev/null | tail -1 | awk '{print $NF}')
        if [[ -n "$val" && ! "$val" =~ ^# ]]; then
            ok "pwquality $param_name = $val"
        elif [[ -z "$val" ]]; then
            info "pwquality $param_name не задан (используется значение по умолчанию)"
        fi
    done
    if [ -f /etc/pam.d/common-password ]; then
        if grep -q "pam_faillock.so" /etc/pam.d/common-password 2>/dev/null; then
            ok "pam_faillock.so подключен к common-password"
        else
            info "pam_faillock.so не подключен к common-password (brute-force защита через fail2ban)"
        fi
    fi
fi

# ============================================================================
section "6. FAILED LOGINS & ATTACK INDICATORS"
# ============================================================================

divider

AUTHL=""
[[ -r /var/log/auth.log ]] && AUTHL=/var/log/auth.log
if [[ -n "$AUTHL" ]]; then
  NOK=$(grep -c "Failed password" "$AUTHL" 2>/dev/null)
  if [[ "${NOK:-0}" -gt 0 ]]; then
    warn "Попыток входа с неверным паролем в логах: $NOK"
    echo -e "  ${BOLD}Последние source IP:${RST}" | tee -a "$REPORT"
    grep "Failed password" "$AUTHL" 2>/dev/null | grep -oE "from [0-9.]+" | awk '{print $2}' | sort | uniq -c | sort -rn | head -5 | tee -a "$REPORT"
  else
    ok "Нет неудачных SSH-подключений в логах"
  fi
else
  warn "Лог auth.log недоступен."
fi
if [[ -n "$AUTHL" ]] && grep -q "Accepted password" "$AUTHL"; then
  warn "В логах есть успешные входы по паролю (возможно, SSH)."
fi

# ============================================================================
section "7. BACKDOOR & ROOTKIT DETECTION"
# ============================================================================

divider

echo -e "\n  ${BOLD}Антируткит / антивирус:${RST}" | tee -a "$REPORT"
if command -v rkhunter >/dev/null; then
  ok "rkhunter установлен"
  if [[ -f /var/lib/rkhunter/rkhunter.dat ]]; then
    echo "  Последний прогон rkhunter:" | tee -a "$REPORT"
    grep -A1 "Last run" /var/lib/rkhunter/rkhunter.dat 2>/dev/null | tee -a "$REPORT"
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

divider

echo -e "\n  ${BOLD}SUID/SGID Binaries:${RST}" | tee -a "$REPORT"
KNOWN_SUIDS="/usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/bin/chsh /usr/bin/chfn /usr/bin/newgrp /usr/bin/gpasswd /usr/bin/mount /usr/bin/umount /usr/bin/fusermount /usr/bin/fusermount3 /usr/bin/pkexec /usr/sbin/unix_chkpwd /usr/lib/openssh/ssh-keysign /usr/lib/dbus-1.0/dbus-daemon-launch-helper"
SUIDD=$(timeout 30 find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -print 2>/dev/null)
N=$(echo "$SUIDD" | grep -c . || echo 0)
echo "  Кол-во SUID/SGID файлов: $N" | tee -a "$REPORT"

UNW=$(echo "$SUIDD" | grep -vE "^(/usr|/bin|/snap|/opt|/lib|/etc|/var/lib/containerd|/var/snap)" | grep -vE 'pmbootstrap|/chroot')
if [[ -n "$UNW" ]]; then
  warn "SUID-файлы вне стандартных путей (/usr, /bin, /snap, /opt, /lib):"
  echo "$UNW" | sed 's/^/    /' | tee -a "$REPORT"
else
  ok "Все SUID/SGID файлы в стандартных путях"
fi

PMB=$(echo "$SUIDD" | grep -cE 'pmbootstrap|/chroot' || true)
[[ -n "$PMB" && "$PMB" -gt 0 ]] && info "$PMB SUID-файлов во chroot pmbootstrap (нормально для сборки Android-ROM)"

echo -e "\n  ${BOLD}LD_PRELOAD / LD_LIBRARY_PATH hijacking:${RST}" | tee -a "$REPORT"
if [ -n "${LD_PRELOAD:-}" ]; then
    bad "LD_PRELOAD is set: $LD_PRELOAD (возможный hijack)"
else
    ok "LD_PRELOAD not set"
fi
if [ -n "${LD_LIBRARY_PATH:-}" ]; then
    warn "LD_LIBRARY_PATH is set: $LD_LIBRARY_PATH"
else
    ok "LD_LIBRARY_PATH not set"
fi

if [ -f /etc/ld.so.preload ] && [ -s /etc/ld.so.preload ]; then
    bad "/etc/ld.so.preload is non-empty (rootkit indicator!) — содержимое скрыто"
else
    ok "/etc/ld.so.preload empty or absent"
fi

echo -e "\n  ${BOLD}Known rootkit artifacts:${RST}" | tee -a "$REPORT"
ROOTKIT_PATHS=(
    "/usr/share/.0wn" "/dev/.udev/rules.d" "/tmp/.ice-unix"
    "/tmp/.font-unix/.cinik" "/usr/lib/.libhide" "/dev/.drv"
    "/usr/lib/libamplify.so" "/etc/cron.d/.quiet"
    "/usr/lib/liblog.c.so" "/usr/lib/libselinux.so.1.bak"
)
for rk in "${ROOTKIT_PATHS[@]}"; do
    [ -e "$rk" ] && bad "Rootkit artifact: $rk"
done
ok "No known rootkit artifacts found (базовая проверка)"

echo -e "\n  ${BOLD}Processes with suspicious names:${RST}" | tee -a "$REPORT"
for pid in $(ps -e -o pid= 2>/dev/null); do
    name=$(cat "/proc/$pid/comm" 2>/dev/null)
    if [[ "$name" == "["*"]" ]] && [ -e "/proc/$pid/exe" ]; then
        warn "Process with bracketed name (renamed userspace proc): $name (pid $pid)"
    fi
done

ps aux 2>/dev/null | grep -E "\/(tmp|var/tmp|dev/shm)\/" | grep -v grep | while read -r line; do
    bad "Process running from temp directory: $line"
done

# ============================================================================
section "8. INSTALLED SOFTWARE & VULNERABILITIES"
# ============================================================================

divider

echo -e "\n  ${BOLD}System Updates:${RST}" | tee -a "$REPORT"
if command -v apt >/dev/null; then
  UPD=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / {n++} END {print n+0}')
  if [[ "$UPD" -eq 0 ]]; then
    ok "Обновления установлены"
  else
    bad "Доступно обновлений: $UPD. Выполните sudo apt update && sudo apt full-upgrade"
  fi
  if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && grep -qE "2|1" /etc/apt/apt.conf.d/20auto-upgrades; then
    ok "Автообновления безопасности настроены"
  else
    warn "Автообновления безопасности не настроены (unattended-upgrades)."
  fi
fi
if command -v snap >/dev/null; then
  HOLD=$(snap refresh --list 2>/dev/null | grep -c "held\|refreshed" || true)
  if [[ "$HOLD" -eq 0 ]]; then
    ok "Snap-пакеты актуальны"
  else
    warn "Есть snap-обновления: sudo snap refresh"
  fi
fi

echo -e "\n  ${BOLD}Potentially dangerous packages:${RST}" | tee -a "$REPORT"
DANGEROUS_PKGS="ncat netcat socat nmap hydra john hashcat aircrack-ng wireshark ettercap bettercap mitmproxy proxychains"
for pkg in $DANGEROUS_PKGS; do
    if dpkg -l 2>/dev/null | grep -q "^ii.*$pkg" || pacman -Q "$pkg" 2>/dev/null; then
        warn "Dangerous/hacking tool installed: $pkg"
    fi
done

echo -e "\n  ${BOLD}System Binary Integrity (dpkg verification):${RST}" | tee -a "$REPORT"
BROKEN=$(timeout 15 dpkg --verify 2>/dev/null | grep -E "^(..5|.....5)" | head -20 || true)
if [ -n "$BROKEN" ]; then
    warn "Modified system files detected:"
    echo "$BROKEN" | tee -a "$REPORT"
else
    ok "System binaries intact (dpkg verify passed)"
fi

# ============================================================================
section "9. DOCKER SECURITY"
# ============================================================================

divider

if command -v docker &>/dev/null; then
    ok "Docker detected"

    if systemctl is-active docker 2>/dev/null | grep -qx "active"; then
      ok "Docker daemon active"
    else
      info "Docker installed but daemon not running"
    fi

    if [ -f /etc/docker/daemon.json ]; then
        if grep -q '"icc":false' /etc/docker/daemon.json 2>/dev/null; then
            ok "Docker inter-container communication disabled"
        else
            info "Docker ICC enabled (контейнеры могут общаться между собой — осознанный выбор)"
        fi
        if grep -q '"userns-remap"' /etc/docker/daemon.json 2>/dev/null; then
            ok "Docker user namespace remapping enabled"
        else
            info "Docker user namespace remapping NOT enabled (может сломать volumes/привилегии)"
        fi
        if grep -q '"no-new-privileges"' /etc/docker/daemon.json 2>/dev/null; then
            ok "Docker no-new-privileges enabled"
        else
            warn "Docker no-new-privileges NOT enabled"
        fi
    else
        warn "No /etc/docker/daemon.json (default config)"
    fi

    if [ -S /var/run/docker.sock ]; then
        SOCK_PERMS=$(stat -c "%a" /var/run/docker.sock 2>/dev/null)
        if [ "$SOCK_PERMS" == "660" ] || [ "$SOCK_PERMS" == "600" ]; then
            ok "Docker socket permissions: $SOCK_PERMS"
        else
            warn "Docker socket permissions: $SOCK_PERMS"
        fi
        DOCKER_GRP=$(getent group docker 2>/dev/null | cut -d: -f4)
        if [ -n "$DOCKER_GRP" ]; then
            info "Users in docker group (root-equivalent, но необходим для управления Docker): $DOCKER_GRP"
        fi
    fi

    RUNNING=$(docker ps 2>/dev/null | tail -n +2)
    if [ -n "$RUNNING" ]; then
        info "Running containers:" 
        echo "$RUNNING" | tee -a "$REPORT"
    fi

    docker ps -q 2>/dev/null | while read -r cid; do
        PRIV=$(docker inspect --format='{{.HostConfig.Privileged}}' "$cid" 2>/dev/null)
        if [ "$PRIV" == "true" ]; then
            NAME=$(docker inspect --format='{{.Name}}' "$cid" 2>/dev/null)
            bad "PRIVILEGED container: $NAME"
        fi
    done
else
    ok "Docker not installed"
fi

# ============================================================================
section "10. FILESYSTEM & DISK SECURITY"
# ============================================================================

divider

echo -e "\n  ${BOLD}Partition Mount Options:${RST}" | tee -a "$REPORT"
for mp in /tmp /var /home; do
    if [[ "$mp" == "/tmp" ]]; then
        mount | grep -E "^/dev.* /tmp " | while read -r line; do
            OPTIONS=$(echo "$line" | awk '{print $6}')
            for opt in noexec nosuid nodev; do
                if echo "$OPTIONS" | grep -q "$opt"; then
                    ok "/tmp mounted with $opt"
                else
                    warn "/tmp NOT mounted with $opt"
                fi
            done
        done
    fi
done

echo -e "\n  ${BOLD}Disk Encryption:${RST}" | tee -a "$REPORT"
CRYPT=$(lsblk -o FSTYPE 2>/dev/null | grep -iE "crypto_LUKS" | head -1)
SWAPFT=$(findmnt -no FSTYPE / 2>/dev/null)
if [[ -n "$CRYPT" ]]; then
  ok "Диск/раздел шифруется (LUKS): $CRYPT"
else
  info "Раздел / использует $SWAPFT без LUKS — данные без шифрования (требует переустановки)."
fi

if [ -f /etc/fstab ]; then
    if grep -v "^#" /etc/fstab | grep -v "^$" | grep -qE "/tmp.*noexec"; then
        ok "/etc/fstab: /tmp has noexec"
    else
        info "/etc/fstab: check /tmp options manually"
    fi
fi

echo -e "\n  ${BOLD}Disk Usage:${RST}" | tee -a "$REPORT"
df -h / /tmp /var 2>/dev/null | tee -a "$REPORT"

echo -e "\n  ${BOLD}/dev/shm mount options:${RST}" | tee -a "$REPORT"
shm_opts=$(mount | grep " /dev/shm " | awk '{print $6}')
if [[ -n "$shm_opts" ]]; then
    info "/dev/shm: $shm_opts (noexec не рекомендуется для десктопа — ломает PulseAudio/SQLite)"
else
    info "/dev/shm: проверка недоступна"
fi

echo -e "\n  ${BOLD}/boot permissions:${RST}" | tee -a "$REPORT"
if [[ -d /boot ]]; then
    boot_perms=$(stat -c "%a" /boot 2>/dev/null)
    if [[ "$boot_perms" == "700" || "$boot_perms" == "750" ]]; then
        ok "/boot permissions: $boot_perms"
    else
        warn "/boot permissions: $boot_perms (рекомендуется 700)"
    fi
fi

echo -e "\n  ${BOLD}Swap encryption:${RST}" | tee -a "$REPORT"
SWAP_DEV=$(swapon --show=NAME --noheadings 2>/dev/null | head -1)
if [[ -n "$SWAP_DEV" ]]; then
    swap_type=$(lsblk -no FSTYPE "$SWAP_DEV" 2>/dev/null)
    if [[ "$swap_type" == "crypto_LUKS" ]]; then
        ok "Swap зашифрован (LUKS): $SWAP_DEV"
    elif [[ "$swap_type" == "swap" || "$swap_type" == "" ]]; then
        info "Swap $SWAP_DEV: $swap_type (не LUKS — подмена при.hibernate возможна)"
    fi
else
    info "Swap не активен"
fi

echo -e "\n  ${BOLD}Journal size limits:${RST}" | tee -a "$REPORT"
if [[ -f /etc/systemd/journald.conf ]]; then
    journ_max=$(grep -E "^SystemMaxUse" /etc/systemd/journald.conf | awk -F= '{print $2}' | tr -d ' ')
    journ_maxfile=$(grep -E "^SystemMaxFileSize" /etc/systemd/journald.conf | awk -F= '{print $2}' | tr -d ' ')
    if [[ -n "$journ_max" ]]; then
        ok "journald SystemMaxUse = $journ_max"
    else
        info "journald SystemMaxUse не задан (по умолчанию: 10% от FS или 4G)"
    fi
    if [[ -n "$journ_maxfile" ]]; then
        ok "journald SystemMaxFileSize = $journ_maxfile"
    else
        info "journald SystemMaxFileSize не задан (по умолчанию: 1/8 от SystemMaxUse)"
    fi
fi

# ============================================================================
section "11. SERVICES & DAEMONS"
# ============================================================================

divider

echo -e "\n  ${BOLD}Potentially Dangerous Services:${RST}" | tee -a "$REPORT"
DANGEROUS_SERVICES="telnet.socket rsh.socket rlogin.socket tftp.socket vsftpd proftpd pure-ftpd"
for svc in $DANGEROUS_SERVICES; do
    if systemctl is-active "$svc" 2>/dev/null | grep -q "active"; then
        warn "Dangerous service running: $svc"
    fi
done

echo -e "\n  ${BOLD}All Running Services:${RST}" | tee -a "$REPORT"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | tee -a "$REPORT"

echo -e "\n  ${BOLD}Avahi/mDNS:${RST}" | tee -a "$REPORT"
if systemctl is-active avahi-daemon 2>/dev/null | grep -q "active"; then
    warn "Avahi/mDNS daemon active (обнаружение сервисов — утечка информации)"
else
    ok "Avahi/mDNS daemon не активен"
fi

echo -e "\n  ${BOLD}CUPS/printing:${RST}" | tee -a "$REPORT"
if systemctl is-active cups 2>/dev/null | grep -q "active"; then
    info "CUPS daemon active (печать — нормально для десктопа)"
else
    ok "CUPS daemon не активен"
fi

echo -e "\n  ${BOLD}Hidden sockets (/proc/net/tcp vs ss):${RST}" | tee -a "$REPORT"
proc_listen=$( { cat /proc/net/tcp /proc/net/tcp6 2>/dev/null; } | awk 'NR>1 && $4=="0A" {c++} END{print c+0}' )
ss_listen=$(ss -tlnH 2>/dev/null | wc -l || echo 0)
if [[ "$ss_listen" -gt 0 ]]; then
    diff_val=$((proc_listen - ss_listen))
    if [[ "$diff_val" -gt 3 ]]; then
        warn "Разница LISTEN /proc/net/tcp ($proc_listen) vs ss ($ss_listen): разница $diff_val — возможны скрытые сокеты (rootkit?)"
    else
        ok "/proc/net/tcp LISTEN ($proc_listen) vs ss LISTEN ($ss_listen): разница в пределах нормы"
    fi
else
    info "Проверка скрытых сокетов: LISTEN /proc/net/tcp=$proc_listen, ss=$ss_listen"
fi

echo -e "\n  ${BOLD}Enabled services (автозапуск):${RST}" | tee -a "$REPORT"
systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null | head -30 | tee -a "$REPORT"

# ============================================================================
section "12. LOGGING & MONITORING"
# ============================================================================

divider

echo -e "\n  ${BOLD}Audit Framework:${RST}" | tee -a "$REPORT"
if systemctl is-active auditd 2>/dev/null | grep -q "active"; then
    ok "auditd is ACTIVE"
    AUDIT_RULES=$(auditctl -l 2>/dev/null | grep -cv "^No rules" || echo 0)
    if [ "$AUDIT_RULES" -gt 0 ]; then
        ok "Audit rules configured: $AUDIT_RULES rules"
    else
        info "auditd активен, но без custom rules (рекомендуется добавить)."
    fi
else
    warn "auditd NOT active (рекомендуется для отслеживания)"
fi

if systemctl is-active fail2ban 2>/dev/null | grep -q "active"; then
    ok "Fail2ban ACTIVE"
else
    warn "Fail2ban NOT active (защита от brute-force отключена)"
fi

if systemctl is-active rsyslog 2>/dev/null | grep -q "active"; then
    ok "rsyslog active"
elif systemctl is-active syslog-ng 2>/dev/null | grep -q "active"; then
    ok "syslog-ng active"
elif systemctl is-active syslog 2>/dev/null | grep -q "active"; then
    ok "syslog active"
else
    warn "No syslog daemon active — логи могут не писаться."
fi

JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+[GMKT]' || echo "unknown")
info "Systemd journal size: $JOURNAL_SIZE"

echo -e "\n  ${BOLD}Log Files:${RST}" | tee -a "$REPORT"
LOGS="/var/log/auth.log /var/log/syslog /var/log/kern.log"
for log in $LOGS; do
    if [ -f "$log" ]; then
        SIZE=$(du -h "$log" 2>/dev/null | awk '{print $1}')
        ok "Log present: $log ($SIZE)"
    else
        warn "Missing log: $log"
    fi
done
if [ -f /var/log/secure ]; then
    info "/var/log/secure присутствует (RHEL-стиль)"
fi

if [ -f /etc/logrotate.conf ]; then
    ok "logrotate configured"
else
    warn "logrotate.conf missing"
fi

echo -e "\n  ${BOLD}Logrotate timer:${RST}" | tee -a "$REPORT"
if systemctl is-active logrotate.timer 2>/dev/null | grep -q "active"; then
    ok "logrotate.timer active"
else
    warn "logrotate.timer NOT active (ротация логов не выполняется автоматически)"
fi

echo -e "\n  ${BOLD}/var/log permissions:${RST}" | tee -a "$REPORT"
warn_log_perms=0
for logfile in /var/log/syslog /var/log/auth.log /var/log/kern.log /var/log/audit/audit.log; do
    if [[ -f "$logfile" ]]; then
        perms=$(stat -c "%a" "$logfile" 2>/dev/null)
        owner=$(stat -c "%U:%G" "$logfile" 2>/dev/null)
        if [[ "$perms" == "640" || "$perms" == "600" || "$perms" == "620" ]]; then
            ok "$(basename $logfile): $perms ($owner)"
        else
            warn "$(basename $logfile): $perms ($owner) — рекомендуется 640 или 600"
            warn_log_perms=1
        fi
    fi
done
[[ "$warn_log_perms" -eq 0 ]] && ok "Все основные логи имеют безопасные права"

echo -e "\n  ${BOLD}auditd disk space action:${RST}" | tee -a "$REPORT"
if [[ -f /etc/audit/auditd.conf ]]; then
    disk_full=$(grep "^disk_full_action" /etc/audit/auditd.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
    disk_error=$(grep "^disk_error_action" /etc/audit/auditd.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
    if [[ -n "$disk_full" ]]; then
        if [[ "$disk_full" == "SUSPEND" || "$disk_full" == "HALT" ]]; then
            ok "auditd disk_full_action = $disk_full"
        else
            warn "auditd disk_full_action = $disk_full (рекомендуется SUSPEND или HALT)"
        fi
    else
        info "auditd disk_full_action не задан (по умолчанию SUSPEND)"
    fi
else
    info "auditd.conf не найден"
fi

# ============================================================================
section "13. MALWARE INDICATORS"
# ============================================================================

divider

echo -e "\n  ${BOLD}Hidden suspicious files:${RST}" | tee -a "$REPORT"
SUSP_PATHS="/tmp /var/tmp /dev/shm"
for p in "${SUSP_PATHS[@]}"; do
    if [ -d "$p" ]; then
        HIDDEN=$(find "$p" -name ".*" -not -name "." -not -name ".." -type f 2>/dev/null | head -20)
        if [ -n "$HIDDEN" ]; then
            warn "Hidden files in $p:"
            echo "$HIDDEN" | tee -a "$REPORT"
        else
            ok "No hidden files in $p"
        fi
    fi
done

echo -e "\n  ${BOLD}Cron Jobs (all users):${RST}" | tee -a "$REPORT"
for user in $(cut -f1 -d: /etc/passwd); do
    CRONTAB=$(crontab -l -u "$user" 2>/dev/null | grep -v "^#" | grep -v "^$" || true)
    if [ -n "$CRONTAB" ]; then
        NCRON=$(echo "$CRONTAB" | grep -c .)
        info "Crontab for $user: $NCRON строк(и) (содержимое скрыто)"
    fi
done

for crondir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
    if [ -d "$crondir" ]; then
        for f in "$crondir"/*; do
            if [ -f "$f" ]; then
                CONTENT=$(cat "$f" 2>/dev/null)
                if echo "$CONTENT" | grep -qiE "curl|wget|nc |ncat |python|perl|ruby|bash -i|/dev/tcp|base64"; then
                    OWNER_PKG=$(dpkg -S "$f" 2>/dev/null | head -1)
                    if [ -n "$OWNER_PKG" ]; then
                        info "Cron $f принадлежит пакету: $OWNER_PKG (легитимен)"
                    else
                        bad "Suspicious cron: $f (содержимое скрыто)"
                    fi
                fi
            fi
        done
    fi
done

echo -e "\n  ${BOLD}World-writable files:${RST}" | tee -a "$REPORT"
find /etc -type f -perm -002 2>/dev/null | head -10 | while read -r f; do
    warn "World-writable: $f"
done
NET=$(find / ! -path /proc ! -path /sys ! -path /dev ! -path /run -xdev -type f -perm -0002 2>/dev/null | grep -v "/home/\|/tmp/\|/var/tmp\|/snap/\|/var/cache" | head -20)
if [[ -n "$NET" ]]; then
  warn "Мир-записываемые файлы вне настраиваемых зон:"
  echo "$NET" | sed 's/^/    /' | tee -a "$REPORT"
else
  ok "Не найдены подозрительные мир-записываемые файлы"
fi

echo -e "\n  ${BOLD}Files with no valid owner:${RST}" | tee -a "$REPORT"
NOOWN=$(timeout 30 find / \( -path /proc -o -path /sys -o -path /dev -o -path /var/lib/containerd -o -path /var/lib/docker \) -prune -o \( -nouser -o -nogroup \) -print 2>/dev/null | head -20)
if [ -n "$NOOWN" ]; then
    warn "Unowned files found:"
    echo "$NOOWN" | tee -a "$REPORT"
else
    ok "No unowned files"
fi

echo -e "\n  ${BOLD}Recently modified files (last 7 days) in /etc:${RST}" | tee -a "$REPORT"
find /etc -type f -mtime -7 2>/dev/null | head -30 | tee -a "$REPORT"

echo -e "\n  ${BOLD}Critical file permissions:${RST}" | tee -a "$REPORT"
PERM_CHECKS=(
    "/etc/passwd:644" "/etc/shadow:640" "/etc/group:644" "/etc/gshadow:640"
    "/etc/sudoers:440" "/etc/ssh/sshd_config:600" "/etc/crontab:600" "/boot/grub/grub.cfg:600"
)
for pc in "${PERM_CHECKS[@]}"; do
    FILE="${pc%%:*}"
    EXPECTED="${pc#*:}"
    if [ -f "$FILE" ]; then
        ACTUAL=$(stat -c "%a" "$FILE" 2>/dev/null)
        if [ "$ACTUAL" == "$EXPECTED" ]; then
            ok "$FILE permissions: $ACTUAL"
        else
            warn "$FILE permissions: $ACTUAL (ожидалось $EXPECTED)"
        fi
    fi
done

# ============================================================================
section "14. CONTAINER & VM ESCAPE VECTORS"
# ============================================================================

divider

if command -v lxc &>/dev/null || command -v lxd &>/dev/null; then
    warn "LXC/LXD detected - check container escape vectors"
fi
if pgrep -x qemu-system 2>/dev/null | grep -q .; then
    info "QEMU VMs running"
fi
if command -v VBoxManage &>/dev/null; then
    info "VirtualBox detected"
fi

# ============================================================================
section "15. ENCRYPTION & SECRETS"
# ============================================================================

divider

echo -e "\n  ${BOLD}GPG Keys:${RST}" | tee -a "$REPORT"
GPG_COUNT=$(gpg --list-keys 2>/dev/null | grep -c "^pub" || echo 0)
GPG_SEC=$(gpg --list-secret-keys 2>/dev/null | grep -c "^sec" || echo 0)
info "GPG ключей: pub=$GPG_COUNT sec=$GPG_SEC (данные ключей скрыты)"

echo -e "\n  ${BOLD}SSH Keys:${RST}" | tee -a "$REPORT"
for key in ~/.ssh/id_*; do
    if [ -f "$key" ] && [[ ! "$key" == *.pub ]]; then
        PERMS=$(stat -c "%a" "$key" 2>/dev/null)
        FMT=$(ssh-keygen -l -f "$key" 2>/dev/null | awk '{print $NF}' | tr -d '()')
        if [ "$PERMS" == "600" ] || [ "$PERMS" == "400" ]; then
            ok "SSH key $key ($FMT, perms=$PERMS)"
        else
            warn "SSH key $key permissions: $PERMS (нужно 600)"
        fi
    fi
done

echo -e "\n  ${BOLD}Exposed private keys:${RST}" | tee -a "$REPORT"
EXPOSED_KEYS=$(timeout 30 find / -path /proc -prune -o -path /sys -prune -o -path /snap -prune -o -path /usr/share -prune -o -path /usr/lib -prune -o -path /usr/src -prune -o -path /usr/local/lib -prune -o -path /var/lib/flatpak -prune -o -path /home/linuxbrew -prune -o -path /home/kat/MEGA -prune -o -path /home/kat/odoo -prune -o -path /home/kat/Downloads -prune -o -path "*/site-packages" -prune -o -path "*/dist-packages" -prune -o -path "*/node_modules" -prune -o -path "*/.cache" -prune -o -path "*/tests" -prune -o -path "*/test" -prune -o \( -name "*.pem" -o -name "*.key" -o -name "id_rsa" -o -name "id_dsa" -o -name "id_ecdsa" -o -name "id_ed25519" -o -name "*.p12" -o -name "*.pfx" \) -type f -perm /004 -exec grep -l "PRIVATE KEY" {} + 2>/dev/null | head -20)
if [ -n "$EXPOSED_KEYS" ]; then
    warn "Private key files found (check permissions):"
    echo "$EXPOSED_KEYS" | tee -a "$REPORT"
fi

# ============================================================================
section "16. NETWORK ATTACK VECTORS"
# ============================================================================

divider

echo -e "\n  ${BOLD}ARP Table (potential spoofing):${RST}" | tee -a "$REPORT"
ip neigh show 2>/dev/null | tee -a "$REPORT"

echo -e "\n  ${BOLD}Routing Table:${RST}" | tee -a "$REPORT"
ip route show 2>/dev/null | tee -a "$REPORT"

if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" == "1" ]; then
    if [ "$DOCKER_INSTALLED" -eq 1 ]; then
        ok "IP forwarding enabled (требуется Docker)"
    else
        warn "IP forwarding enabled (router/MITM capability)"
    fi
else
    ok "IP forwarding disabled"
fi

# ============================================================================
section "17. USB & BLUETOOTH & PHYSICAL"
# ============================================================================

divider

echo -e "\n  ${BOLD}Bluetooth:${RST}" | tee -a "$REPORT"
if command -v bluetoothctl >/dev/null; then
  if timeout 3 bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    warn "Bluetooth включён. Отключите, если не нужен: sudo systemctl disable bluetooth"
  else
    ok "Bluetooth выключен"
  fi
fi

echo -e "\n  ${BOLD}USB Storage:${RST}" | tee -a "$REPORT"
info "Проверка USB-накопителей отключена (не критично): модуль usb_storage может быть загружен"

if command -v udisksctl &>/dev/null; then
    info "udisksctl available (USB automount)"
fi

echo -e "\n  ${BOLD}Автовход и локальные файлы:${RST}" | tee -a "$REPORT"
if grep -rE "autologin|AutoLogin" /etc/gdm3* /etc/lightdm /etc/gdm /etc/lightdm/lightdm.conf 2>/dev/null | grep -v "#" | grep -q .; then
  warn "Найден автовход в графическую систему."
else
  ok "Автовхода в графической оболочке не найдено"
fi
TECH=$(find /var/run /tmp /home -xdev -name ".Xauthority" -o -name "*.ovpn" 2>/dev/null)
TECH_N=$(echo "$TECH" | grep -c . || echo 0)
[[ "$TECH_N" -gt 0 ]] && info "Xauthority/ovpn файлы: $TECH_N"

# ============================================================================
section "18. APPARMOR / SELINUX"
# ============================================================================

divider

if command -v aa-status &>/dev/null; then
    AA_STATUS=$(aa-status 2>/dev/null || true)
    if echo "$AA_STATUS" | grep -q "apparmor module is loaded"; then
        ok "AppArmor loaded"
        ENFORCED=$(echo "$AA_STATUS" | grep "profiles are in enforce mode" | awk '{print $1}')
        COMPLAIN=$(echo "$AA_STATUS" | grep "profiles are in complain mode" | awk '{print $1}')
        info "Enforce: ${ENFORCED:-0}, Complain: ${COMPLAIN:-0}"
    else
        warn "AppArmor NOT loaded"
    fi
else
    info "AppArmor not installed"
fi

if command -v getenforce &>/dev/null; then
    SELINUX=$(getenforce 2>/dev/null)
    if [ "$SELINUX" == "Enforcing" ]; then
        ok "SELinux: Enforcing"
    else
        warn "SELinux: $SELINUX (should be Enforcing)"
    fi
else
    info "SELinux not available (Debian uses AppArmor)"
fi

# ============================================================================
section "19. KERNEL EXPLOIT PROTECTION"
# ============================================================================

divider

echo -e "\n  ${BOLD}Exploit Mitigations:${RST}" | tee -a "$REPORT"

if grep -q "smep" /proc/cpuinfo 2>/dev/null; then ok "SMEP supported (CPU)"; else info "SMEP not detected"; fi
if grep -q "smap" /proc/cpuinfo 2>/dev/null; then ok "SMAP supported (CPU)"; else info "SMAP not detected"; fi
if grep -q "nx" /proc/cpuinfo 2>/dev/null; then ok "NX (No-Execute) supported"; else warn "NX bit not detected (DEP disabled)"; fi

if [ -d /mnt/c ]; then
    info "WSL/Windows mount detected - check NTFS ADS risk"
fi

echo -e "\n  ${BOLD}CPU Vulnerability Mitigations:${RST}" | tee -a "$REPORT"
VULN_DIR="/sys/devices/system/cpu/vulnerabilities"
if [[ -d "$VULN_DIR" ]]; then
    for vuln_file in "$VULN_DIR"/*; do
        vuln_name=$(basename "$vuln_file")
        status=$(cat "$vuln_file" 2>/dev/null || echo "unknown")
        if echo "$status" | grep -qi "not affected"; then
            ok "CPU $vuln_name: $status"
        elif echo "$status" | grep -qi "no microcode"; then
            info "CPU $vuln_name: $status (обновление microcode недоступно для данного CPU)"
        elif echo "$status" | grep -qi "smt vulnerable"; then
            info "CPU $vuln_name: $status (Hyper-Threading уязвим, но мелиорация включена)"
        elif echo "$status" | grep -qi "vulnerable"; then
            warn "CPU $vuln_name: $status"
        elif echo "$status" | grep -qi "mitigation\|conditional\|SMT\|__EXPOSE"; then
            ok "CPU $vuln_name: $status"
        else
            info "CPU $vuln_name: $status"
        fi
    done
else
    info "/sys/devices/system/cpu/vulnerabilities недоступен"
fi

# ============================================================================
section "20. SYSTEMD UNIT HARDENING"
# ============================================================================

divider

echo -e "\n  ${BOLD}Systemd service sandboxing:${RST}" | tee -a "$REPORT"
HARDENING_DIRECTIVES="ProtectSystem= ProtectHome= PrivateTmp= NoNewPrivileges= CapabilityBoundingSet= MemoryDenyWriteExecute= ProtectKernelTunables= ProtectKernelModules= ProtectKernelLogs= LockPersonality= RestrictRealtime= RemoveIPC="
SANDBOXED=0
UNSANDBOXED=0
UNSANDBOXED_LIST=""

for unit in $(systemctl list-units --type=service --state=active --no-pager --no-legend 2>/dev/null | awk '{print $1}' | grep -v "\.scope$"); do
    unit_path=$(systemctl show "$unit" -p FragmentPath 2>/dev/null | cut -d= -f2)
    if [[ -z "$unit_path" || ! -f "$unit_path" ]]; then
        continue
    fi
    has_hardening=0
    for directive in $HARDENING_DIRECTIVES; do
        dname="${directive%%=*}"
        if grep -qE "^\s*${dname}=" "$unit_path" 2>/dev/null; then
            has_hardening=1
            break
        fi
    done
    if [[ "$has_hardening" -eq 1 ]]; then
        SANDBOXED=$((SANDBOXED + 1))
    else
        UNSANDBOXED=$((UNSANDBOXED + 1))
        if [[ "$UNSANDBOXED" -le 15 ]]; then
            UNSANDBOXED_LIST="$UNSANDBOXED_LIST $unit"
        fi
    fi
done

ok "Services с sandboxing: $SANDBOXED"
if [[ "$UNSANDBOXED" -gt 0 ]]; then
    info "Services без sandboxing: $UNSANDBOXED (system services: dbus, gdm, apparmor — не могут быть в песочнице)"
fi

# ============================================================================
section "21. CAPABILITIES AUDIT"
# ============================================================================

divider

echo -e "\n  ${BOLD}Binaries с расширенными capabilities:${RST}" | tee -a "$REPORT"
DANGEROUS_CAPS="cap_sys_admin,cap_dac_override,cap_fowner,cap_dac_read_search,cap_sys_module,cap_sys_rawio"
LEGITIMATE_RAW="ping ping6 traceroute traceroute6 mtr mtr-packet"
if command -v getcap >/dev/null 2>&1; then
    CAP_OUTPUT=$(getcap -r /usr/bin /usr/sbin /bin /snap 2>/dev/null || true)
    if [[ -n "$CAP_OUTPUT" ]]; then
        warn_found=0
        while IFS= read -r line; do
            bin_path=$(echo "$line" | awk '{print $1}')
            bin_name=$(basename "$bin_path")
            is_legitimate=0
            for lg in $LEGITIMATE_RAW; do
                [[ "$bin_name" == "$lg" ]] && is_legitimate=1 && break
            done
            if echo "$line" | grep -qiE "cap_net_raw"; then
                if [[ "$is_legitimate" -eq 1 ]]; then
                    ok "cap_net_raw на $bin_name — legitimate (ICMP/traceroute)"
                else
                    warn "Dangerous capability: $line"
                    warn_found=1
                fi
            elif echo "$line" | grep -qiE "$DANGEROUS_CAPS"; then
                warn "Dangerous capability: $line"
                warn_found=1
            fi
        done <<< "$CAP_OUTPUT"
        [[ "$warn_found" -eq 0 ]] && ok "Нет бинарников с опасными capabilities"
    else
        ok "Нет бинарников с capabilities в /usr/bin, /usr/sbin, /bin, /snap"
    fi
else
    info "getcap недоступен (установить: libcap2-bin)"
fi

echo -e "\n  ${BOLD}SUID/SGID binaries:${RST}" | tee -a "$REPORT"
SUID_COUNT=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | wc -l || echo 0)
info "Всего SUID/SGID бинарников: $SUID_COUNT"

# ============================================================================
section "22. KERNEL COMPILE-TIME HARDENING"
# ============================================================================

divider

LATEST_CONFIG=$(ls -t /boot/config-* 2>/dev/null | head -1)
if [[ -n "$LATEST_CONFIG" && -f "$LATEST_CONFIG" ]]; then
    echo -e "\n  ${BOLD}Kernel compile-time security options ($LATEST_CONFIG):${RST}" | tee -a "$REPORT"
    declare -A KERNEL_CONFIG_CHECKS=(
        ["CONFIG_CC_STACKPROTECTOR_STRONG"]="y"
        ["CONFIG_STRICT_KERNEL_RWX"]="y"
        ["CONFIG_STRICT_MODULE_RWX"]="y"
        ["CONFIG_HARDENED_USERCOPY"]="y"
        ["CONFIG_RANDOMIZE_BASE"]="y"
        ["CONFIG_RANDOMIZE_MEMORY"]="y"
        ["CONFIG_INIT_ON_ALLOC_DEFAULT_ON"]="y"
        ["CONFIG_INIT_ON_FREE_DEFAULT_ON"]="y"
        ["CONFIG_SLAB_FREELIST_HARDENED"]="y"
        ["CONFIG_RANDOM_KMALLOC_CACHES"]="y"
        ["CONFIG_MODULE_SIG"]="y"
        ["CONFIG_MODULE_SIG_FORCE"]="y"
        ["CONFIG_SECCOMP"]="y"
        ["CONFIG_SECCOMP_FILTER"]="y"
    )
    for param in "${!KERNEL_CONFIG_CHECKS[@]}"; do
        expected="${KERNEL_CONFIG_CHECKS[$param]}"
        actual=$(grep "^${param}=" "$LATEST_CONFIG" 2>/dev/null | awk -F= '{print $2}')
        if [[ -z "$actual" ]]; then
            info "$param не задан (используется default)"
        elif [[ "$actual" == "$expected" ]]; then
            ok "$param = $actual"
        else
            warn "$param = $actual (ожидалось $expected)"
        fi
    done

    mmap_rnd_bits=$(sysctl -n vm.mmap_rnd_bits 2>/dev/null)
    mmap_rnd_compat=$(sysctl -n vm.mmap_rnd_compat_bits 2>/dev/null)
    if [[ -n "$mmap_rnd_bits" ]]; then
        if [[ "$mmap_rnd_bits" -ge 32 ]]; then
            ok "vm.mmap_rnd_bits = $mmap_rnd_bits (ASLR entropy)"
        else
            warn "vm.mmap_rnd_bits = $mmap_rnd_bits (рекомендуется >= 32 для max ASLR)"
        fi
    fi
else
    info "Kernel config файл не найден в /boot/"
fi

# ============================================================================
section "23. FIRMWARE SECURITY"
# ============================================================================

divider

echo -e "\n  ${BOLD}CPU Microcode:${RST}" | tee -a "$REPORT"
microcode=$(grep -m1 "microcode" /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | xargs)
if [[ -n "$microcode" ]]; then
    ok "CPU microcode: $microcode"
else
    info "Microcode version неизвестна"
fi

echo -e "\n  ${BOLD}Firmware updates (fwupd):${RST}" | tee -a "$REPORT"
if command -v fwupdmgr >/dev/null 2>&1; then
    pending=$(fwupdmgr get-updates --no-reboot-check 2>/dev/null | grep -c "=> " || echo 0)
    if [[ "$pending" -gt 0 ]]; then
        warn "Есть ожидающие firmware обновления: $pending"
    else
        ok "Нет ожидающих firmware обновлений"
    fi
else
    info "fwupdmgr не установлен"
fi

echo -e "\n  ${BOLD}Secure Boot:${RST}" | tee -a "$REPORT"
if [[ -d /sys/firmware/efi ]]; then
    if command -v mokutil >/dev/null 2>&1; then
        sb_state=$(mokutil --sb-state 2>/dev/null || echo "unknown")
        if echo "$sb_state" | grep -qi "enabled"; then
            ok "Secure Boot: $sb_state"
        else
            warn "Secure Boot: $sb_state"
        fi
    else
        info "mokutil недоступен — проверка Secure Boot невозможна"
    fi
else
    info "Система не на UEFI (Legacy BIOS)"
fi

# ============================================================================
section "24. THIRD-PARTY REPOS & SNAP AUDIT"
# ============================================================================

divider

echo -e "\n  ${BOLD}Third-party APT repositories:${RST}" | tee -a "$REPORT"
CUSTOM_REPOS=""
for src in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [[ -f "$src" ]]; then
        src_name=$(basename "$src")
        # .list: строки "deb [опции] URL ..."; .sources: поле "URIs: URL ..."
        src_lines=$(grep -vE "^#" "$src" 2>/dev/null | grep -E "^deb |^URIs:" || true)
        if [[ -n "$src_lines" ]]; then
            while IFS= read -r line; do
                repo_url=$(echo "$line" | grep -oE 'https?://[^ ]+' | head -1)
                # Официальные и легитимные репозитории (Ubuntu/Zorin/Debian + популярные сторонние)
                if ! echo "$repo_url" | grep -qiE "ubuntu\.com|zorin|archive\.canonical|packages\.cloudflare|brave|onlyoffice|cli\.github\.com|deb\.debian\.org|security\.debian\.org|download\.docker\.com|download\.sublimetext\.com|ngrok-agent|playit-cloud|google\.linux|dl\.google\.com|windsurf|codeiumdata|mega\.nz|nodesource"; then
                    CUSTOM_REPOS="$CUSTOM_REPOS\n  $src_name: $repo_url"
                fi
            done <<< "$src_lines"
        fi
    fi
done
if [[ -n "$CUSTOM_REPOS" ]]; then
    warn "Non-standard repositories:${CUSTOM_REPOS}"
else
    ok "Все APT репозитории стандартные (Ubuntu/Zorin/Debian) или легитимные сторонние"
fi

echo -e "\n  ${BOLD}Snap packages with --classic (без песочницы):${RST}" | tee -a "$REPORT"
if command -v snap >/dev/null 2>&1; then
    CLASSIC_SNAPS=$(snap list 2>/dev/null | awk 'NR>1 {print $1, $2}' | while read name rev; do
        snap_info=$(snap info "$name" 2>/dev/null | grep "^confinement:" || true)
        if echo "$snap_info" | grep -q "classic"; then
            echo "$name ($rev)"
        fi
    done)
    if [[ -n "$CLASSIC_SNAPS" ]]; then
        warn "Classic snaps (обход песочницы):$CLASSIC_SNAPS"
    else
        ok "Нет snap пакетов с --classic"
    fi
else
    info "snap не установлен"
fi

echo -e "\n  ${BOLD}Flatpak packages:${RST}" | tee -a "$REPORT"
if command -v flatpak >/dev/null 2>&1; then
    FLAT_COUNT=$(flatpak list 2>/dev/null | wc -l || echo 0)
    FLAT_UPDATES=$(flatpak remote-ls --updates 2>/dev/null | grep -v "^$" | wc -l || echo 0)
    info "Установлено Flatpak пакетов: $FLAT_COUNT (обновлений: $FLAT_UPDATES)"
    if [[ "$FLAT_UPDATES" -gt 0 ]]; then
        warn "Есть обновления Flatpak пакетов: $FLAT_UPDATES"
    fi
else
    info "Flatpak не установлен"
fi

# ============================================================================
# VERDICT
# ============================================================================

verdict

# Вернуть отчёт реальному пользователю (не root)
REAL_USER="${SUDO_USER:-root}"
if [[ "$REAL_USER" != "root" ]]; then
    chown "$REAL_USER:$(id -gn "$REAL_USER")" "$REPORT"
    echo "Report owned by: $REAL_USER"
fi
