#!/usr/bin/env bash
# ============================================================================
# security-audit-2.sh — Comprehensive Security Audit
# Merge of security_audit.sh (comprehensive) + security-audit.sh (compact)
# Режим: только чтение/диагностика. Ничего не меняет.
# Использование: sudo ./security-audit-2.sh
# ============================================================================

set -uo pipefail

# Локаль C — чтобы ufw/apt/… выводили по-английски и тесты грепали стабильно.
export LC_ALL=C LANGUAGE=C LANG=C

if [[ $EUID -ne 0 ]]; then
  echo "Запустите с правами root: sudo $0" >&2
  exit 1
fi

REPORT="/home/kat/security-audit-2_report_$(date +%Y%m%d_%H%M%S).txt"
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
NOOWN=$(timeout 30 find / -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o \( -nouser -o -nogroup \) -print 2>/dev/null | head -20)
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

# ============================================================================
# VERDICT
# ============================================================================

verdict
