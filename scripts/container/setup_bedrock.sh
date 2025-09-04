#!/usr/bin/env bash
set -Eeuo pipefail

NAME=""
TZ="UTC"

while [[ $# -gt 0 ]]; do case $1 in
  --name) NAME=$2; shift 2 ;;
  --timezone) TZ=$2; shift 2 ;;
  *) echo "Unknown flag $1"; exit 1 ;;
 esac; done

[[ -n "$NAME" ]] || { echo "--name is required"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y tzdata curl unzip ca-certificates screen
ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && dpkg-reconfigure -f noninteractive tzdata

useradd -m -r -s /bin/bash minecraft || true
mkdir -p /opt/minecraft/$NAME
chown -R minecraft:minecraft /opt/minecraft/$NAME

cd /opt/minecraft/$NAME

# Fetch latest Bedrock server for Linux x64 by scraping the official page
PAGE=$(curl -fsSL https://www.minecraft.net/en-us/download/server/bedrock)
URL=$(echo "$PAGE" | grep -Eo 'https://[^\"]+bedrock-server-.*-linux.*\.zip' | head -n1)
[[ -n "$URL" ]] || { echo "Could not find Bedrock download URL"; exit 1; }
curl -fSL "$URL" -o bedrock.zip
unzip -o bedrock.zip
rm -f bedrock.zip

# Default server.properties tweaks: allow console & default ports
sed -i 's/^server-name=.*/server-name=Bedrock-'"$NAME"'/' server.properties || true

chown -R minecraft:minecraft /opt/minecraft/$NAME

# Install systemd template and enable instance
install -Dm0644 /dev/stdin /etc/systemd/system/bedrock@.service <<'UNIT'
[Unit]
Description=Minecraft Bedrock Server %i
After=network.target

[Service]
WorkingDirectory=/opt/minecraft/%i
User=minecraft
Group=minecraft
Restart=on-failure
RestartSec=10
ExecStart=/usr/bin/screen -DmS mcbe-%i /opt/minecraft/%i/bedrock_server
ExecStop=/usr/bin/screen -S mcbe-%i -p 0 -X stuff "stop$(printf \\r)"

[Install]
WantedBy=multi-user.target
UNIT

# helper for host actions
install -Dm0755 /dev/stdin /usr/local/bin/mc-serverctl <<'CTL'
#!/usr/bin/env bash
set -Eeuo pipefail
sub=${1:-}; name=${2:-}
[[ -z "$sub" || -z "$name" ]] && { echo "usage: mc-serverctl <update|backup|status|start|stop> <name>"; exit 1; }
base="/opt/minecraft/$name"
case "$sub" in
  update)
    cd "$base"
    PAGE=$(curl -fsSL https://www.minecraft.net/en-us/download/server/bedrock)
    URL=$(echo "$PAGE" | grep -Eo 'https://[^\"]+bedrock-server-.*-linux.*\.zip' | head -n1)
    curl -fSL "$URL" -o bedrock.zip
    unzip -o bedrock.zip
    rm -f bedrock.zip
    systemctl restart bedrock@"$name" ;;
  backup)
    mkdir -p /var/backups/minecraft
    ts=$(date +%Y%m%d%H%M)
    tar -czf /var/backups/minecraft/${name}-${ts}.tar.gz -C "$base" .
    echo "/var/backups/minecraft/${name}-${ts}.tar.gz" ;;
  status)
    systemctl --no-pager status bedrock@"$name" ;;
  start) systemctl start bedrock@"$name" ;;
  stop) systemctl stop bedrock@"$name" ;;
  *) echo "unknown subcommand"; exit 1 ;;
 esac
CTL

systemctl daemon-reload
systemctl enable --now bedrock@"$NAME"

echo "Bedrock server '$NAME' ready."
