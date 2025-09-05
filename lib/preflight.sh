# --- Functions expected by mc-setup (host-side) ---

# Run network/apt hardening inside the container without needing files there
preflight_net_apt() {
  local ctid="${1:-}"
  if [ -z "$ctid" ]; then
    err "preflight_net_apt: missing CTID"
    return 1
  fi
  log "Running preflight networking/apt hardening in CT $ctid…"

  pct exec "$ctid" -- bash -s <<'CTSCRIPT'
set -euo pipefail

log()  { printf "[preflight] %s\n" "$*"; }
warn() { printf "[preflight] WARNING: %s\n" "$*" >&2; }
err()  { printf "[preflight] ERROR: %s\n" "$*" >&2; }

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

retry() {
  local -i tries=$1; shift
  local -i delay=$1; shift
  local -i n=1
  while true; do
    if "$@"; then return 0; fi
    if (( n >= tries )); then return 1; fi
    warn "command failed (attempt $n/$tries): $* ; retrying in ${delay}s…"
    sleep "$delay"; ((n++))
  done
}

backup_once() { [ -f "$1" ] && [ ! -f "$1.bak" ] && cp -a "$1" "$1.bak" || true; }

force_apt_ipv4() {
  local f="/etc/apt/apt.conf.d/99force-ipv4"
  if ! grep -qs 'Acquire::ForceIPv4' "$f" 2>/dev/null; then
    log "Forcing APT to IPv4…"
    install -d -m 0755 /etc/apt/apt.conf.d
    printf 'Acquire::ForceIPv4 "true";\n' >"$f"
  else
    log "APT IPv4 preference already set."
  fi
}

prefer_gai_ipv4() {
  local f="/etc/gai.conf"
  if ! grep -qsE '^\s*precedence\s+::ffff:0:0/96\s+100' "$f" 2>/dev/null; then
    log "Preferring IPv4 in /etc/gai.conf…"
    if [ -f "$f" ]; then
      backup_once "$f"
      if grep -qsE '^\s*#\s*precedence\s+::ffff:0:0/96\s+100' "$f"; then
        sed -i -E 's/^\s*#\s*(precedence\s+::ffff:0:0\/96\s+100)/\1/' "$f"
      else
        echo 'precedence ::ffff:0:0/96 100' >>"$f"
      fi
    else
      echo 'precedence ::ffff:0:0/96 100' >"$f"
    fi
  else
    log "gai.conf already prefers IPv4."
  fi
}

detect_os() {
  . /etc/os-release 2>/dev/null || true
  OS_ID="${ID:-}"; OS_CODENAME="${VERSION_CODENAME:-}"
  if [ -z "$OS_ID" ] || [ -z "$OS_CODENAME" ]; then
    err "Could not detect OS/codename"; exit 1
  fi
  log "Detected OS=$OS_ID, CODENAME=$OS_CODENAME"
}

write_apt_sources() {
  local UBU_MIRROR="${UBU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
  local SEC_MIRROR="${SEC_MIRROR:-http://security.ubuntu.com/ubuntu}"
  local DEB_MIRROR="${DEB_MIRROR:-http://deb.debian.org/debian}"
  local DEB_SEC_MIRROR="${DEB_SEC_MIRROR:-http://security.debian.org/debian-security}"
  case "$OS_ID" in
    ubuntu)
      backup_once /etc/apt/sources.list
      cat > /etc/apt/sources.list <<EOF
deb ${UBU_MIRROR} ${OS_CODENAME} main restricted universe multiverse
deb ${UBU_MIRROR} ${OS_CODENAME}-updates main restricted universe multiverse
deb ${UBU_MIRROR} ${OS_CODENAME}-backports main restricted universe multiverse
deb ${SEC_MIRROR} ${OS_CODENAME}-security main restricted universe multiverse
EOF
      ;;
    debian)
      backup_once /etc/apt/sources.list
      cat > /etc/apt/sources.list <<EOF
deb ${DEB_MIRROR} ${OS_CODENAME} main contrib non-free non-free-firmware
deb ${DEB_MIRROR} ${OS_CODENAME}-updates main contrib non-free non-free-firmware
deb ${DEB_MIRROR} ${OS_CODENAME}-backports main contrib non-free non-free-firmware
deb ${DEB_SEC_MIRROR} ${OS_CODENAME}-security main contrib non-free non-free-firmware
EOF
      ;;
  esac
}

apt_update() {
  log "Updating apt indexes…"
  retry 4 5 bash -lc 'apt-get update -o Acquire::ForceIPv4=true -y'
  log "apt update OK."
}

force_apt_ipv4
prefer_gai_ipv4
detect_os
write_apt_sources
apt_update
log "Preflight complete."
CTSCRIPT
}

# Create mcadmin user inside the container
preflight_create_mcadmin() {
  local ctid="${1:-}" pass="${2:-}"
  if [ -z "$ctid" ] || [ -z "$pass" ]; then
    err "preflight_create_mcadmin: need CTID and PASSWORD"
    return 1
  fi
  log "Creating mcadmin in CT $ctid…"
  pct exec "$ctid" -- bash -lc '
    set -euo pipefail
    if ! id mcadmin >/dev/null 2>&1; then
      adduser --disabled-password --gecos "" mcadmin
    fi
    usermod -aG sudo mcadmin
  '
  # set password via chpasswd (avoid exposing in ps history inside CT)
  echo "mcadmin:${pass}" | pct exec "$ctid" -- chpasswd
  log "mcadmin ready."
}
