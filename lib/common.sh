#!/usr/bin/env bash
# lib/common.sh — shared helpers for mc-server-tools
# NOTE: This file is sourced by commands; do NOT set -e/-u here.

# Safe pipefail without breaking shells that lack it
set -o pipefail 2>/dev/null || true

# ---------- logging ----------
if [[ -t 2 ]]; then
  _RED=$'\033[31m'; _YEL=$'\033[33m'; _GRN=$'\033[32m'; _BLU=$'\033[34m'; _RST=$'\033[0m'
else
  _RED=""; _YEL=""; _GRN=""; _BLU=""; _RST=""
fi

_ts() { date +%H:%M:%S; }

info() { echo -e "${_GRN}[+]${_RST} $*"; }
warn() { echo -e "${_YEL}[!]${_RST} $*" >&2; }
err()  { echo -e "${_RED}[x]${_RST} $*" >&2; }
die()  { err "$@"; exit 1; }

# ---------- guards / validators ----------
require_root() {
  local uid=${EUID:-$(id -u)}
  if [[ "$uid" -ne 0 ]]; then
    die "This command must be run as root (try: sudo $0 …)"
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

validate_hhmm() {
  # HHMM 24-hour (e.g., 0400, 2359). No colon.
  [[ "$1" =~ ^([01][0-9]|2[0-3])[0-5][0-9]$ ]]
}

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ---------- Proxmox helpers ----------
ctid_exists() { pct config "$1" >/dev/null 2>&1; }

port_in_use_host() {
  local port="$1"
  if have_cmd ss; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"
  elif have_cmd netstat; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"
  else
    warn "Neither ss nor netstat found; cannot verify port usage."
    return 1
  fi
}

# Detect edition inside a CT: echoes "Java" or "Bedrock", else empty & nonzero return
detect_edition_in_ct() {
  local ctid="$1"
  if pct exec "$ctid" -- test -d /opt/minecraft 2>/dev/null; then
    echo "Java"; return 0
  elif pct exec "$ctid" -- test -d /opt/bedrock/worlds 2>/dev/null; then
    echo "Bedrock"; return 0
  fi
  return 1
}

# ---------- simple file utils ----------
ensure_dir() { install -d -m "${2:-0755}" "$1"; }
write_file() { # write_file <path> <mode> <<<"content"
  local path="$1" mode="${2:-0644}"
  install -m "$mode" /dev/stdin "$path"
}

# ---------- config loader ----------
# Loads /etc/mc-server-tools/config if present; safe to call multiple times.
mc_load_config() {
  local cfg="/etc/mc-server-tools/config"
  [[ -r "$cfg" ]] && . "$cfg"
}
mc_load_config
