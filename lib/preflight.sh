#!/usr/bin/env bash
# preflight.sh — prepare a newly-created LXC CT for reliable apt/networking + base OS sanity
# - Forces APT to IPv4 on IPv6-less networks
# - Prefers IPv4 in glibc resolver (for curl/wget, etc.)
# - Rewrites sources.list to official mirrors (Ubuntu or Debian, auto-detected)
# - Adds apt retries/timeouts
# - Updates apt; installs curl + CA certs and common base packages
# - Ensures noninteractive environment and UTF-8 locale
# - Optional DNS fallback and IPv6 disable if no default route
# - Provides MTU probe helper
# - Creates mcadmin with provided password, enables SSH and sudo
set -euo pipefail

# Usage (primary): preflight_net_apt <CTID>
preflight_net_apt() {
  local CTID="${1:?CTID required}"

  _in() { pct exec "$CTID" -- bash -lc "$*"; }

  echo "[preflight] Forcing APT to IPv4…"
  _in "install -d -m 0755 /etc/apt/apt.conf.d && printf 'Acquire::ForceIPv4 \"true\";\n' >/etc/apt/apt.conf.d/99force-ipv4"

  echo "[preflight] Preferring IPv4 in /etc/gai.conf…"
  _in "grep -q '^precedence ::ffff:0:0/96 100$' /etc/gai.conf || echo 'precedence ::ffff:0:0/96 100' >> /etc/gai.conf"

  echo "[preflight] Detecting OS family + codename…"
  local OS_ID OS_CODENAME
  OS_ID="$(_in 'source /etc/os-release && echo "$ID"')"
  OS_CODENAME="$(_in 'source /etc/os-release && echo "$VERSION_CODENAME"')"
  if [[ -z "$OS_ID" || -z "$OS_CODENAME" ]]; then
    echo "[preflight] ERROR: Could not determine OS and codename from /etc/os-release" >&2
    return 1
  fi
  echo "[preflight] -> ID=${OS_ID}, CODENAME=${OS_CODENAME}"

  echo "[preflight] Backing up sources.list (once)…"
  _in "test -f /etc/apt/sources.list.bak || cp -a /etc/apt/sources.list /etc/apt/sources.list.bak || true"

  echo "[preflight] Writing official mirrors to /etc/apt/sources.list…"
  if [[ "$OS_ID" == "ubuntu" ]]; then
    _in "cat > /etc/apt/sources.list <<'EOF'\n\
deb http://archive.ubuntu.com/ubuntu ${OS_CODENAME} main restricted universe multiverse\n\
deb http://archive.ubuntu.com/ubuntu ${OS_CODENAME}-updates main restricted universe multiverse\n\
deb http://archive.ubuntu.com/ubuntu ${OS_CODENAME}-backports main restricted universe multiverse\n\
deb http://security.ubuntu.com/ubuntu ${OS_CODENAME}-security main restricted universe multiverse\n\
EOF"
  elif [[ "$OS_ID" == "debian" ]]; then
    _in "cat > /etc/apt/sources.list <<'EOF'\n\
deb http://deb.debian.org/debian ${OS_CODENAME} main contrib non-free non-free-firmware\n\
deb http://deb.debian.org/debian ${OS_CODENAME}-updates main contrib non-free non-free-firmware\n\
deb http://deb.debian.org/debian ${OS_CODENAME}-backports main contrib non-free non-free-firmware\n\
deb http://security.debian.org/debian-security ${OS_CODENAME}-security main contrib non-free non-free-firmware\n\
EOF"
  else
    echo "[preflight] WARN: Unrecognized OS ID '${OS_ID}'. Leaving sources.list unchanged."
  fi

  echo "[preflight] Commenting out any stale custom mirrors (if present)…"
  _in "grep -rlE 'mirror\\.|azureedge|pnl\\.gov|internal' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | xargs -r sed -i 's/^deb /# deb /'"

  echo "[preflight] apt-get update…"
  _in "DEBIAN_FRONTEND=noninteractive apt-get update -y"

  echo "[preflight] Installing curl + ca-certificates…"
  _in "DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates"

  echo "[preflight] Hardening apt config (retries/timeouts)…"
  _in "cat >/etc/apt/apt.conf.d/90mc-apt-hardening <<'EOF'\n\
Acquire::Retries \"3\";\n\
Acquire::http::Timeout \"30\";\n\
Acquire::https::Timeout \"30\";\n\
# Keep this file separate from 99force-ipv4 so we can flip either independently\n\
EOF"

  echo "[preflight] Ensuring base packages…"
  _in "DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg lsb-release iproute2 iputils-ping jq"

  echo "[preflight] Default noninteractive profile…"
  _in "cat >/etc/profile.d/90-noninteractive.sh <<'EOF'\nexport DEBIAN_FRONTEND=noninteractive\nEOF\nchmod +x /etc/profile.d/90-noninteractive.sh"

  echo "[preflight] Locale = en_US.UTF-8…"
  _in "\nset -e\nif ! dpkg -s locales >/dev/null 2>&1; then apt-get install -y locales; fi\nif ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then\n  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen\nfi\nlocale-gen en_US.UTF-8\nupdate-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8\n"

  echo "[preflight] DNS fallback (only if lookups fail)…"
  _in "\nset -e\nif ! getent ahostsv4 archive.ubuntu.com >/dev/null 2>&1 && ! getent ahostsv4 deb.debian.org >/dev/null 2>&1; then\n  echo '[preflight] DNS lookup failed; writing fallback /etc/resolv.conf'\n  mkdir -p /run/systemd/resolve || true\n  chattr -i /etc/resolv.conf 2>/dev/null || true\n  cat >/etc/resolv.conf <<RESOLV\nnameserver 1.1.1.1\nnameserver 8.8.8.8\noptions edns0\nRESOLV\nfi\ntrue\n"

  # OPTIONAL: If you want to auto-disable IPv6 when there is no v6 default route, uncomment:
  # echo "[preflight] Disable IPv6 if there is no v6 default route…"
  # _in "if ! ip -6 route | grep -q '^default'; then cat >/etc/sysctl.d/99-disable-ipv6.conf <<EOF\nnet.ipv6.conf.all.disable_ipv6=1\nnet.ipv6.conf.default.disable_ipv6=1\nEOF\n sysctl --system >/dev/null 2>&1 || true; fi"

  echo "[preflight] Verifying IPv4 DNS + HTTP reachability…"
  if [[ "$OS_ID" == "ubuntu" ]]; then
    _in "getent ahostsv4 archive.ubuntu.com | head -n3 || true"
    _in "curl -4 -I --max-time 10 http://archive.ubuntu.com/ubuntu/dists/${OS_CODENAME}/Release || true"
    _in "curl -4 -I --max-time 10 http://security.ubuntu.com/ubuntu/dists/${OS_CODENAME}-security/Release || true"
  elif [[ "$OS_ID" == "debian" ]]; then
    _in "getent ahostsv4 deb.debian.org | head -n3 || true"
    _in "curl -4 -I --max-time 10 http://deb.debian.org/debian/dists/${OS_CODENAME}/Release || true"
    _in "curl -4 -I --max-time 10 http://security.debian.org/debian-security/dists/${OS_CODENAME}-security/Release || true"
  fi

  echo "[preflight] Done."
}

# Create mcadmin with a provided password (caller prompts)
# Usage: preflight_create_mcadmin <CTID> <PASSWORD>
preflight_create_mcadmin() {
  local CTID="${1:?CTID required}"
  local PASSWORD="${2:?PASSWORD required}"

  _in() { pct exec "$CTID" -- bash -lc "$*"; }

  echo "[preflight] Installing sudo + openssh-server…"
  _in "DEBIAN_FRONTEND=noninteractive apt-get install -y sudo openssh-server"

  echo "[preflight] Ensuring mcadmin user exists and is in sudo…"
  _in "\nset -e\nif id 'mcadmin' >/dev/null 2>&1; then\n  usermod -s /bin/bash 'mcadmin' || true\nelse\n  useradd -m -s /bin/bash 'mcadmin'\nfi\nusermod -aG sudo 'mcadmin'\n"

  echo "[preflight] Setting mcadmin password (from user input)…"
  local PASS_ESC
  PASS_ESC="$(printf "%s" "$PASSWORD" | sed "s/'/'\\''/g")"
  _in "echo 'mcadmin:${PASS_ESC}' | chpasswd"

  echo "[preflight] Hardening SSH (disable root password login, allow mcadmin)…"
  _in "\nset -e\nsystemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true\nsystemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true\n\nif grep -qE '^#?PermitRootLogin' /etc/ssh/sshd_config; then\n  sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config\nelse\n  echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config\nfi\npasswd -l root >/dev/null 2>&1 || true\n\nif grep -qE '^#?PasswordAuthentication' /etc/ssh/sshd_config; then\n  sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\nelse\n  echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config\nfi\nsystemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true\n"

  echo "[preflight] mcadmin ready with user-specified password."
}

# Optional: MTU helper (prints recommendation only)
# Usage: preflight_probe_mtu <CTID>
preflight_probe_mtu() {
  local CTID="${1:?CTID required}"
  pct exec "$CTID" -- bash -lc '
best=1472
for sz in 1472 1460 1452 1440 1420 1400 1380 1360 1340 1320 1300; do
  if ping -c1 -M do -s "$sz" 8.8.8.8 >/dev/null 2>&1; then best="$sz"; break; fi
done
echo "Max ICMP payload without fragmentation: $best (MTU ~= best + 28)"
'
}
