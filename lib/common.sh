# shellcheck shell=bash

STATE_DIR=/etc/mc-server-tools/servers
mkdir -p "$STATE_DIR"

say() { echo -e "[mc] $*"; }
err() { echo -e "[mc][error] $*" >&2; }

die() { err "$*"; exit 1; }

confirm() {
  local msg=$1
  read -r -p "$msg [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

save_server() {
  local file="$STATE_DIR/$NAME.env"
  cat >"$file" <<ENV
NAME="$NAME"
TYPE="$TYPE"
IMPL="${IMPL:-}"
CTID="$CTID"
HOSTNAME="$HOSTNAME"
SERVICE_NAME="$SERVICE_NAME"
ENV
  chmod 0644 "$file"
}

load_server() {
  local name=$1
  local file="$STATE_DIR/$name.env"
  [[ -f "$file" ]] || die "No metadata for '$name' in $STATE_DIR"
  # shellcheck disable=SC1090
  source "$file"
}

list_servers() {
  printf "%-18s %-6s %-6s %-10s %-10s\n" NAME CTID TYPE IMPL SERVICE
  for f in "$STATE_DIR"/*.env ; do
    [[ -e "$f" ]] || { echo "(none)"; return; }
    # shellcheck disable=SC1090
    source "$f"
    printf "%-18s %-6s %-6s %-10s %-10s\n" "$NAME" "$CTID" "$TYPE" "${IMPL:--}" "$SERVICE_NAME"
  done
}
