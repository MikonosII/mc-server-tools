#!/usr/bin/env bash
set -Eeuo pipefail

NAME=""
IMPL="paper"   # paper|purpur
VERSION="latest"
TZ="UTC"

while [[ $# -gt 0 ]]; do case $1 in
  --name) NAME=$2; shift 2 ;;
  --impl) IMPL=$2; shift 2 ;;
  --version) VERSION=$2; shift 2 ;;
  --timezone) TZ=$2; shift 2 ;;
  *) echo "Unknown flag $1"; exit 1 ;;
 esac; done

[[ -n "$NAME" ]] || { echo "--name is required"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y tzdata curl jq unzip ca-certificates openjdk-21-jre-headless screen
ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && dpkg-reconfigure -f noninteractive tzdata

useradd -m -r -s /bin/bash minecraft || true
mkdir -p /opt/minecraft/$NAME
chown -R minecraft:minecraft /opt/minecraft/$NAME

cd /opt/minecraft/$NAME

# Fetch latest server jar
JAR="server.jar"
if [[ "$IMPL" == "paper" ]]; then
  # Latest Paper for VERSION
  if [[ "$VERSION" == latest ]]; then
    MCVER=$(curl -fsSL https://api.papermc.io/v2/projects/paper | jq -r '.versions[-1]')
  else
    MCVER="$VERSION"
  fi
  BUILD=$(curl -fsSL https://api.papermc.io/v2/projects/paper/versions/$MCVER | jq -r '.builds[-1]')
  URL="https://api.papermc.io/v2/projects/paper/versions/$MCVER/builds/$BUILD/download/paper-$MCVER-$BUILD.jar"
  curl -fSL "$URL" -o "$JAR"
else
  # Purpur
  if [[ "$VERSION" == latest ]]; then
    MCVER=$(curl -fsSL https://api.purpurmc.org/v2/purpur | jq -r '.versions[-1]')
  else
    MCVER="$VERSION"
  fi
  BUILD=$(curl -fsSL https://api.purpurmc.org/v2/purpur/$MCVER | jq -r '.builds.latest')
  URL="https://api.purpurmc.org/v2/purpur/$MCVER/$BUILD/download"
  curl -fSL "$URL" -o "$JAR"
fi

# EULA and first run config
echo "eula=true" > eula.txt

chown -R minecraft:minecraft /opt/minecraft/$NAME

# Install systemd template and enable instance
install -Dm0644 /dev/stdin /etc/systemd/system/minecraft@.service <<'UNIT'
[Unit]
Description=Minecraft Java Server %i
After=network.target

[Service]
WorkingDirectory=/opt/minecraft/%i
User=minecraft
Group=minecraft
Restart=on-failure
RestartSec=10
ExecStart=/usr/bin/screen -DmS mc-%i /usr/bin/java -Xms1G -Xmx4G -jar server.jar nogui
ExecStop=/usr/bin/screen -S mc-%i -p 0 -X stuff "stop$(printf \\r)"

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
    if grep -q purpur "$base/server.jar" 2>/dev/null; then impl="purpur"; else impl="paper"; fi
    if [[ "$impl" == paper ]]; then
      v=$(curl -fsSL https://api.papermc.io/v2/projects/paper | jq -r '.versions[-1]')
      b=$(curl -fsSL https://api.papermc.io/v2/projects/paper/versions/$v | jq -r '.builds[-1]')
      curl -fSL "https://api.papermc.io/v2/projects/paper/versions/$v/builds/$b/download/paper-$v-$b.jar" -o server.jar
    else
      v=$(curl -fsSL https://api.purpurmc.org/v2/purpur | jq -r '.versions[-1]')
      b=$(curl -fsSL https://api.purpurmc.org/v2/purpur/$v | jq -r '.builds.latest')
      curl -fSL "https://api.purpurmc.org/v2/purpur/$v/$b/download" -o server.jar
    fi
    systemctl restart minecraft@"$name" ;;
  backup)
    mkdir -p /var/backups/minecraft
    ts=$(date +%Y%m%d%H%M)
    tar -czf /var/backups/minecraft/${name}-${ts}.tar.gz -C "$base" .
    echo "/var/backups/minecraft/${name}-${ts}.tar.gz" ;;
  status)
    systemctl --no-pager status minecraft@"$name" ;;
  start) systemctl start minecraft@"$name" ;;
  stop) systemctl stop minecraft@"$name" ;;
  *) echo "unknown subcommand"; exit 1 ;;
 esac
CTL

systemctl daemon-reload
systemctl enable --now minecraft@"$NAME"

echo "Java server '$NAME' ready."
