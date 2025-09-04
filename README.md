# mc-server-tools (Proxmox LXC)

A CLI to create and manage **Minecraft Java (Paper/Purpur)** and **Bedrock** servers inside **Ubuntu LXC containers on Proxmox**.

## Features
- One command `mc setup` with auto-populated defaults (CTID, hostname, IP via DHCP, memory/CPU/disk, template selection).
- Java: installs OpenJDK, downloads latest Paper by default (Purpur optional), configures systemd service.
- Bedrock: downloads the latest Bedrock dedicated server, configures systemd.
- Automatic EULA acceptance (Java) with timestamp.
- Per-server metadata in `/etc/mc-server-tools/servers/<name>.env`.
- Start/stop/status/update/backup from the Proxmox host.
- Rotated world backups to `/var/backups/minecraft/<name>-YYYYmmddHHMM.tar.gz` (inside the container).
- Sensible defaults; everything overrideable via flags or env.

## Requirements
- Proxmox VE host with `pct` and an Ubuntu LXC template downloaded (22.04 or 24.04).
- Network bridge `vmbr0` with DHCP (default). NAT/port-forwarding is optional and not required.
- Host packages: `curl`, `jq`, `unzip`, `whiptail` (installer uses them).

## Install
```bash
sudo make install
# or package
make tar VERSION=0.1.0
make deb VERSION=0.1.0
