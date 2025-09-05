#!/usr/bin/env bash
# common.sh — small shared helpers
set -euo pipefail

# Root requirement for host-side actions
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This command must be run as root." >&2
    exit 1
  fi
}

# Logging helpers used by mc-setup
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERROR] $*" >&2; }

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[mc] $*"; }

# Yes/No prompt with default (host-side)
# Usage: ask_yes_no "question" "y|n"
ask_yes_no() {
  local q="$1"; local def="${2:-y}"; local yn
  local prompt="[y/N]"; [[ "$def" =~ ^[Yy]$ ]] && prompt="[Y/n]"
  while true; do
    read -r -p "$q $prompt " yn </dev/tty || yn="$def"
    yn="${yn:-$def}"
    case "$yn" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

# Prompt for a secret twice, confirm match, and export into the named variable
# Usage: prompt_password_confirm VAR_NAME "Prompt label"
prompt_password_confirm() {
  local __var_name="${1:?var name required}"
  local __label="${2:-Password}"
  local __p1 __p2
  while true; do
    read -r -s -p "Enter ${__label}: " __p1 </dev/tty; echo
    read -r -s -p "Confirm ${__label}: " __p2 </dev/tty; echo
    if [[ -z "${__p1}" ]]; then
      echo "Error: ${__label} cannot be empty. Try again."; continue
    fi
    if (( ${#__p1} < 8 )); then
      echo "Error: ${__label} must be at least 8 characters. Try again."; continue
    fi
    if [[ "${__p1}" != "${__p2}" ]]; then
      echo "Error: entries did not match. Try again."; continue
    fi
    printf -v "${__var_name}" '%s' "${__p1}"
    unset __p1 __p2
    return 0
  done
}
