# shellcheck shell=bash

require() { command -v "$1" >/dev/null || die "Missing required command: $1"; }
require pct
require jq
require curl

# ---------- UI helpers ----------
_have_whiptail() { command -v whiptail >/dev/null; }
_prompt_input() {
  local title=$1 text=$2 default=${3:-}
  if _have_whiptail && [[ -t 1 ]]; then
    whiptail --title "$title" --inputbox "$text" 10 68 "$default" 3>&1 1>&2 2>&3
  else
    read -rp "$text [${default}] > " ans; echo "${ans:-$default}"
  fi
}
_prompt_menu() {
  local title=$1 text=$2 default=$3; shift 3
  local options=("$(printf "%s" "$@")")
  if _have_whiptail && [[ -t 1 ]]; then
    whiptail --title "$title" --notags --menu "$text" 18 72 10 "$@" 3>&1 1>&2 2>&3 || true
  else
    echo "$text" >&2
    local i=1; for o in "$@"; do printf "  %d) %s\n" "$i" "$o" >&2; i=$((i+1)); done
    read -rp "Select [${default}] > " sel
    sel=${sel:-$default}
    # options are "index label" pairs; return the chosen pair's label
    echo "$(echo "$@" | awk -v n="$sel" '{print $((2*n))}')"
  fi
}

# ---------- PVE helpers ----------
# Find next available CTID (>=101)
next_ctid() {
  local last
  last=$(pct list | awk 'NR>1 {print $1}' | sort -n | tail -1)
  if [[ -z "$last" ]]; then echo 101; else echo $((last+1)); fi
}

# Try to pick a recent Ubuntu template available locally
find_template() {
  local hint=${1:-ubuntu}
  local store line tmpl
  store=$(pvesm status | awk 'NR==2{print $1}')
  while read -r line; do
    tmpl=$(basename "$line")
    if [[ "$tmpl" == *amd64.tar.zst && "$tmpl" == *$hint* ]]; then
      echo "$store:vztmpl/$tmpl"; return 0
    fi
  done < <(ls /var/lib/vz/template/cache/*.tar.zst 2>/dev/null || true)
  if [[ -f /var/lib/vz/template/cache/ubuntu-24.04-standard_24.04-1_amd64.tar.zst ]]; then
    echo "$store:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst"; return 0
  fi
  die "No Ubuntu LXC template found. Download one with: pveam update && pveam available | grep ubuntu && pveam download local <template>"
}

_fetch_java_versions() {
  local impl=$1
  if [[ "$impl" == paper ]]; then
    curl -fsSL https://api.papermc.io/v2/projects/paper | jq -r '.versions[-12:] | reverse | @tsv'
  else
    curl -fsSL https://api.purpurmc.org/v2/purpur | jq -r '.versions[-12:] | reverse | @tsv'
  fi
}

setup_server() {
  # Defaults from config/defaults.env
  local TYPE="$MC_DEFAULT_TYPE" IMPL="$MC_DEFAULT_IMPL" VERSION="$MC_DEFAULT_VERSION"
  local MEMORY_MB="$MC_DEFAULT_MEMORY_MB" CORES="$MC_DEFAULT_CORES" DISK_GB="$MC_DEFAULT_DISK_GB"
  local BRIDGE="$MC_DEFAULT_BRIDGE" STORAGE="$MC_DEFAULT_STORAGE" TEMPLATE hint="$MC_DEFAULT_TEMPLATE_HINT"
  local NAME HOSTNAME CTID TZ="$MC_DEFAULT_TIMEZONE"
  local NONINT=0

  # Parse flags
  while [[ $# -gt 0 ]]; do case $1 in
    --type) TYPE=$2; shift 2 ;;
    --impl) IMPL=$2; shift 2 ;;
    --version) VERSION=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --memory) MEMORY_MB=$2; shift 2 ;;
    --cores) CORES=$2; shift 2 ;;
    --disk) DISK_GB=$2; shift 2 ;;
    --bridge) BRIDGE=$2; shift 2 ;;
    --storage) STORAGE=$2; shift 2 ;;
    --template) TEMPLATE=$2; shift 2 ;;
    --timezone) TZ=$2; shift 2 ;;
    --yes|-y) NONINT=1; shift ;;
    *) err "Unknown flag $1"; exit 1 ;;
  esac; done

  CTID=$(next_ctid)
  NAME=${NAME:-mc$CTID}
  HOSTNAME=${HOSTNAME:-$NAME}
  TEMPLATE=${TEMPLATE:-$(find_template "$hint")}

  if [[ $NONINT -eq 0 ]]; then
    # Type
    local sel_type
    sel_type=$(_prompt_menu "Server Type" "Choose Java or Bedrock" 1 "1 Java" "2 Bedrock")
    [[ "$sel_type" == *Bedrock* ]] && TYPE=bedrock || TYPE=java

    # Java choices
    if [[ "$TYPE" == java ]]; then
      local sel_impl
      sel_impl=$(_prompt_menu "Java Implementation" "Choose server implementation" 1 "1 Paper" "2 Purpur")
      [[ "$sel_impl" == *Purpur* ]] && IMPL=purpur || IMPL=paper

      # Version (latest + recent list)
      local vers=(latest)
      mapfile -t jvers < <(_fetch_java_versions "$IMPL" | tr '\t' '\n') || true
      vers+=("${jvers[@]}")
      local menu=()
      local idx=1
      for v in "${vers[@]}"; do menu+=("$idx" "$v"); idx=$((idx+1)); done
      local sel_ver=$(_prompt_menu "Minecraft Version" "Pick a version (or choose latest)" 1 "${menu[@]}")
      if [[ "$sel_ver" =~ latest ]]; then VERSION=latest; else VERSION=$(echo "$sel_ver" | awk '{print $2}'); fi
    else
      IMPL=""; VERSION=latest
    fi

    # Name/resources/network
    NAME=$(_prompt_input "Server Name" "Enter a short name" "$NAME")
    MEMORY_MB=$(_prompt_input "Memory (MB)" "RAM for the container" "$MEMORY_MB")
    CORES=$(_prompt_input "CPU Cores" "vCPU cores" "$CORES")
    DISK_GB=$(_prompt_input "Disk (GB)" "Rootfs size" "$DISK_GB")
    BRIDGE=$(_prompt_input "Bridge" "Linux bridge to attach" "$BRIDGE")
    STORAGE=$(_prompt_input "Storage" "Proxmox storage for rootfs" "$STORAGE")
    TZ=$(_prompt_input "Timezone" "IANA TZ (e.g., UTC, America/Chicago)" "$TZ")

    # Template confirmation/override
    local show_t
    show_t="$(basename "${TEMPLATE#*:vztmpl/}")"
    local resp=$(_prompt_input "Ubuntu Template" "Enter to use detected template or type another vzdump template name" "$show_t")
    if [[ "$resp" != "$show_t" && -n "$resp" ]]; then
      local store
      store=$(pvesm status | awk 'NR==2{print $1}')
      TEMPLATE="$store:vztmpl/$resp"
    fi
  else
    [[ "$TYPE" == java || "$TYPE" == bedrock ]] || die "--type must be java or bedrock"
    if [[ "$TYPE" == java ]]; then [[ "$IMPL" == paper || "$IMPL" == purpur || -z "$IMPL" ]] || die "--impl must be paper or purpur"; fi
  fi

  say "Creating $TYPE server '$NAME' in CTID $CTID (template: $TEMPLATE)"

  pct create "$CTID" "$TEMPLATE" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" --memory "$MEMORY_MB" --swap 0 \
    --rootfs "$STORAGE:${DISK_GB}G" \
    --net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
    --features nesting=1 \
    --unprivileged 1 \
    --onboot 1

  pct start "$CTID"
  say "Waiting for container networking..."
  sleep 6

  if [[ "$TYPE" == java ]]; then
    pct push "$CTID" "$SCRIPTS_DIR/container/setup_java.sh" /root/setup_java.sh -perms 0755
    pct exec "$CTID" -- bash /root/setup_java.sh \
      --name "$NAME" --impl "${IMPL:-paper}" --version "$VERSION" --timezone "$TZ"
    SERVICE_NAME="minecraft@$NAME"
  else
    pct push "$CTID" "$SCRIPTS_DIR/container/setup_bedrock.sh" /root/setup_bedrock.sh -perms 0755
    pct exec "$CTID" -- bash /root/setup_bedrock.sh \
      --name "$NAME" --timezone "$TZ"
    SERVICE_NAME="bedrock@$NAME"
  fi

  TYPE="$TYPE" IMPL="${IMPL:-}" NAME="$NAME" HOSTNAME="$HOSTNAME" SERVICE_NAME="$SERVICE_NAME" CTID="$CTID" save_server
  say "Done! Try: mc status $NAME"
}
