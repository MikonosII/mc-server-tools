#!/usr/bin/env bash
# preflight.sh — prepare LXC guest for Minecraft server install
# - Forces APT to prefer IPv4 (helps in NAT'd/proxy'd environments)
# - Tweaks /etc/gai.conf to prefer IPv4 for getaddrinfo()
# - Detects OS/codename and writes a clean /etc/apt/sources.list
# - Runs apt-get update with retries
#
# Can be sourced by other scripts or executed directly.
# Idempotent: safe to re-run.

set -euo pipefail

# --- Lightweight logging helpers (use repo's common.sh if present) ---
if [ -f /usr/share/mc-server-tools/lib/common.sh ]; then
  # shellcheck disable=SC1091
  . /usr/share/mc-server-tools/lib/common.sh
  : "${LOG_PREFIX:="[preflight] "}"
  log() { printf "%s%s\n" "${LOG_PREFIX}" "$*"; }
  warn() { printf "%sWARNING: %s\n" "${LOG_PREFIX}" "$*" >&2; }
  err() { printf "%sERROR: %s\n" "${LOG_PREFIX}" "$*" >&2; }
else
  log()  { printf "[preflight] %s\n" "$*"; }
  warn() { printf "[preflight] WARNING: %s\n" "$*" >&2; }
  err()  { printf "[preflight] ERROR: %s\n" "$*" >&2; }
fi

# --- Noninteractive apt environment ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# --- Helpers ---
retry() {
  # retry <attempts> <delay_seconds> -- <command...>
  local -i tries=$1; shift
  local -i delay=$1; shift
  local -i n=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( n >= tries )); then
      return 1
    fi
    warn "command failed (attempt $n/$tries): $* ; retrying in ${delay}s…"
    sleep "$delay"
    ((n++))
  done
}

backup_once() {
  # backup_once <path>
  local p="$1"
  if [ -f "$p" ] && [ ! -f "${p}.bak" ]; then
    cp -a "$p" "${p}.bak"
  fi
}

force_apt_ipv4() {
  # Create /etc/apt/apt.conf.d/99force-ipv4
  local f="/etc/apt/apt.conf.d/99force-ipv4"
  if ! grep -qs 'Acquire::ForceIPv4' "$f" 2>/dev/null; then
    log "Forcing APT to IPv4…"
    install -d -m 0755 /etc/apt/apt.conf.d
    cat >"$f" <<'EOF'
Acquire::ForceIPv4 "true";
EOF
  else
    log "APT IPv4 preference already set."
  fi
}

prefer_gai_ipv4() {
  # Uncomment/append precedence to prefer IPv4 (RFC 6724 tweak)
  local f="/etc/gai.conf"
  if ! grep -qsE '^\s*precedence\s+::ffff:0:0/96\s+100' "$f" 2>/dev/null; then
    log "Preferring IPv4 in /etc/gai.conf…"
    if [ -f "$f" ]; then
      backup_once "$f"
      # If commented default exists, uncomment it; otherwise append a new line
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
  # Sets globals: OS_ID, OS_CODENAME
  OS_ID=""
  OS_CODENAME=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"
  fi
  if [ -z "$OS_ID" ] || [ -z "$OS_CODENAME" ]; then
    err "Could not detect OS/codename from /etc/os-release"
    return 1
  fi
  log "Detected OS=$OS_ID, CODENAME=$OS_CODENAME"
}

write_apt_sources() {
  # Write a clean /etc/apt/sources.list for Ubuntu/Debian
  # Mirrors can be overridden via env or config sourced earlier.
  local UBU_MIRROR="${UBU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
  local SEC_MIRROR="${SEC_MIRROR:-http://security.ubuntu.com/ubuntu}"
  local DEB_MIRROR="${DEB_MIRROR:-http://deb.debian.org/debian}"
  local DEB_SEC_MIRROR="${DEB_SEC_MIRROR:-http://security.debian.org/debian-security}"

  case "$OS_ID" in
    ubuntu)
      log "Writing official Ubuntu mirrors to /etc/apt/sources.list…"
      backup_once /etc/apt/sources.list
      cat >/etc/apt/sources.list <<EOF
deb ${UBU_MIRROR} ${OS_CODENAME} main restricted universe multiverse
deb ${UBU_MIRROR} ${OS_CODENAME}-updates main restricted universe multiverse
deb ${UBU_MIRROR} ${OS_CODENAME}-backports main restricted universe multiverse
deb ${SEC_MIRROR} ${OS_CODENAME}-security main restricted universe multiverse
EOF
      ;;
    debian)
      log "Writing official Debian mirrors to /etc/apt/sources.list…"
      backup_once /etc/apt/sources.list
      cat >/etc/apt/sources.list <<EOF
deb ${DEB_MIRROR} ${OS_CODENAME} main contrib non-free non-free-firmware
deb ${DEB_MIRROR} ${OS_CODENAME}-updates main contrib non-free non-free-firmware
deb ${DEB_MIRROR} ${OS_CODENAME}-backports main contrib non-free non-free-firmware
deb ${DEB_SEC_MIRROR} ${OS_CODENAME}-security main contrib non-free non-free-firmware
EOF
      ;;
    *)
      warn "Unknown distro ID='${OS_ID}', leaving sources.list unchanged."
      ;;
  esac
}

apt_update() {
  log "Updating APT package lists…"
  # Use retries; APT is finicky in new CTs, especially right after first boot
  retry 4 5 bash -lc 'apt-get update -o Acquire::ForceIPv4=true -y'
}

# --- Main flow (when executed directly) ---
main() {
  force_apt_ipv4
  prefer_gai_ipv4
  detect_os
  write_apt_sources
  apt_update
  log "Preflight complete."
}

# If sourced, don't run main. If executed, run main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
