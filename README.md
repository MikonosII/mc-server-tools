Here’s a complete, polished `README.md` you can drop into the repo. It reflects everything we’ve built: CTID=Port, thin-provisioned disks, static IPs by edition, template picker w/ last-used default, no RCON, bridge-only networking, daily backups (HHMM, default 0400), `mc copy`, and `mc new` with random seed.

---

# mc-server-tools

Manage Minecraft servers on **Proxmox LXC**—fast.
Thin disks, static IPs, daily backups, and a one-liner dispatcher: `mc`.

> Java **and** Bedrock, with smart defaults. No RCON. Bridge-only networking. Autostart on boot.

---

## ✨ Features

* **One command** (`mc`) with subcommands: `setup`, `start`, `stop`, `restart`, `console`, `logs`, `backup`, `list`, `copy`, `new`
* **CTID = Port** policy for instant identification (e.g., CTID `25565` listens on port `25565`)
* **Static IPv4** (no DHCP) with per-edition ranges:

  * Java: starts at `192.168.205.100/24`
  * Bedrock: starts at `192.168.206.100/24`
* **Thin-provisioned storage** only (prefers `lvmthin`, then `zfspool`, then `btrfs`)
* **Template picker**: scans downloaded LXC templates and suggests your **last used** as the default
* **Autostart on boot** via systemd in each CT
* **Daily backups** (vzdump from host) at **HHMM** (24h), default **0400**
* **No RCON**, **bridge-only** networking
* **`mc copy`**: clone a server into a new CT via `mc setup`, auto-picking the next free CTID/port
* **`mc new`**: archive the current world and create a fresh one
  → **random seed by default** (or pass `--seed <N>`)

---

## ✅ Requirements

* Proxmox VE host (uses `pct`, `pvesm`, `pveam`, etc.)
* At least one **thin** storage (e.g., an LVM-thin pool like `local-lvm`)
* Downloaded LXC template(s) (e.g., `ubuntu-24.04-standard_*.tar.zst`)
* Root on the PVE host

The scripts install needed packages **inside** each CT (e.g., Java runtime for Java servers).

---

## 🧱 Install

### From source

```bash
# from repo root
sudo make install
```

Installs:

* `/usr/bin/mc` (dispatcher) + optional `/bin/mc` wrapper
* `/usr/share/mc-server-tools/commands/*`
* `/usr/share/mc-server-tools/lib/*`
* `/etc/mc-server-tools/config` (conffile)

### Build a .deb

```bash
make deb
sudo dpkg -i mc-server-tools_*.deb
```

The Makefile stamps `Version:` from `git describe` when building.

---

## ⚙️ Configuration

Main conffile (installed by default):

```
/etc/mc-server-tools/config
```

Default contents:

```bash
# Bridge for LXC containers
BRIDGE="vmbr0"

# Java range
NET_JAVA_START="192.168.205.100"
NET_JAVA_PREFIX="24"
NET_JAVA_GW="auto"   # "auto" -> first host (.1). Or set explicit IP.

# Bedrock range
NET_BEDROCK_START="192.168.206.100"
NET_BEDROCK_PREFIX="24"
NET_BEDROCK_GW="auto"
```

Runtime state (last-selected template) is stored here:

```
/etc/mc-server-tools/last_template
```

> Change ranges/gateway/bridge as needed. IPs are assigned **statically** and increment from the starting address for each new CT in that edition.

---

## 🚀 Quick start

### Create a new server (interactive)

```
$ mc setup

=== Minecraft Server Setup ===
Server Edition [Java]: [Enter]
Minecraft Version [Latest]: [Enter]

Available templates:
  1) local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst
  2) local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst
Template [1]: [Enter]

Memory (MB) [4096]: [Enter]
CPU cores [2]: [Enter]
Disk size (GB) [8]: [Enter]
Daily backup time (HHMM, 24h) [0400]: [Enter]
```

**What happens**

* CTID/Port auto-picked (Java seeds at **25565**; if busy, **25566**, etc.)
* Hostname auto-set to `mc-<CTID>` (no prompt)
* Static IPv4 auto-assigned from the edition’s range (e.g., `192.168.205.100/24`)
* Thin storage selected; CT created; Java installed into `/opt/minecraft` as **mcadmin**
* systemd unit enabled; vzdump cron added at the chosen HHMM

### Start/stop/console/logs/backup

```bash
mc start 25565
mc stop 25565
mc console 25565       # attaches to screen session "mc" as mcadmin
mc logs 25565
mc backup 25565
```

### Copy an existing CT into a new one

```bash
# Creates a new CT with next free CTID=Port, mirrors disk size by default
mc copy 25565 --disk-gb 24 --backup-hhmm 0130
```

* Auto-detects Java/Bedrock from the source
* Calls `mc setup` under the hood (inherits thin storage + policies)
* Copies worlds, fixes ownership to `mcadmin:mcadmin`

### Create a fresh world (random seed by default)

```bash
mc new 25565
# or with explicit seed:
mc new 25565 --seed 8675309
```

* Stops service, archives current world (timestamped), wipes it
* Sets new seed (random if not specified), restarts

---

## 🧩 Non-interactive `mc setup` (flags)

```bash
mc setup \
  --edition Java \
  --version Latest \
  --mem 4096 \
  --cores 2 \
  --backup-hhmm 0400 \
  --template local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst \
  --disk-gb 8 \
  --storage local-lvm
```

**Notes**

* If you supply `--ctid` and/or `--port`, they **must be equal** (CTID=Port policy) and unused.
* Hostname is not prompted; override with `--hostname <name>` if needed.
* If a flag is omitted and the value can be safely inferred, **no prompt** is shown (e.g., CTID/Port, hostname, IP).

---

## 🧠 Design details

### CTID = Port

* CTID `25565` ⟷ TCP `25565` (Java); Bedrock seeds at `19132`
* Enforced in both interactive and flag mode (error if mismatched)

### Thin-provisioned storage

* Auto-picks the first available **thin** pool in priority: `lvmthin` → `zfspool` → `btrfs`
* Fails with a clear message if only non-thin pools are present
* Override with `--storage <thin-pool>`; validated type still must be thin

### Static IPv4

* Edition-based ranges (see config)
* Gateway is `.1` by default for `/24` ranges (or computed “first host”); override in config if different
* Uses `-net0 ... ip=<addr>/<prefix>,gw=<gw>` in `pct create`

### Template selection

* Scans:

  * `/var/lib/vz/template/cache/*.tar*`
  * `/mnt/pve/*/template/cache/*.tar*`
* Prompts with a numbered list and suggests the **last used** template as default
* Accepts `--template <storage>:vztmpl/<file.tar.*>` for fully non-interactive runs

### Users & services inside the CT

* Creates **`mcadmin`** and installs the server under:

  * Java: `/opt/minecraft` (owns files)
  * Bedrock: `/opt/bedrock` (owns files)
* Java starts via systemd service + `screen` session `mc` (owned by mcadmin)
* Bedrock service support is **minimal/beta** in these scripts; world management and copying work, but the service unit may be pending depending on your commit level

### Backups

* Host-level cron: `/etc/cron.d/mc-server-<CTID>` runs `mc backup <CTID>` daily at the chosen HHMM

---

## 📂 Repository layout

```
usr/bin/mc                        # dispatcher
bin/mc                            # thin wrapper -> /usr/bin/mc

commands/                         # subcommands (mc-setup, mc-copy, mc-new, etc.)
lib/                              # shared helpers

config/etc/mc-server-tools/config # packaged default conffile
debpkg/DEBIAN/*                   # control, conffiles, postinst
Makefile                          # install + deb build
```

Optional niceties (if you add them):

```
usr/share/bash-completion/completions/mc
usr/share/zsh/site-functions/_mc
usr/share/man/man1/mc.1
```

---

## 🧪 Examples (inline style)

**Java with defaults**

```
Server Edition [Java]: [Enter]
Minecraft Version [Latest]: [Enter]
Template [1]: [Enter]
Memory (MB) [4096]: [Enter]
CPU cores [2]: [Enter]
Disk size (GB) [8]: [Enter]
Daily backup time (HHMM, 24h) [0400]: [Enter]
```

**Bedrock, custom**

```
Server Edition [Java]: Bedrock
Minecraft Version [Latest]: [Enter]
Template [1]: 2
Memory (MB) [4096]: 6144
CPU cores [2]: 4
Disk size (GB) [8]: 16
Daily backup time (HHMM, 24h) [0400]: 0230
```

---

## 🛠️ Troubleshooting

* **No thin-provisioned storage found**
  Create/enable an LVM-thin pool (or ZFS/Btrfs thin) and re-run. You can force a specific pool via `--storage <name>`.

* **No downloaded templates found**

  ```
  pveam update
  pveam available | grep ubuntu
  pveam download local ubuntu-24.04-standard_24.04-1_amd64.tar.zst
  ```

* **CTID already exists / Port in use**
  The tool will error (flag mode) or automatically pick the **next free** number (interactive).

* **Static IP exhausted**
  Increase the subnet or starting address in `/etc/mc-server-tools/config`.

---

## 📦 Packaging notes

* `make install` copies the default config to `/etc/mc-server-tools/config`
* The `.deb` declares `/etc/mc-server-tools/config` as a **conffile**, so local edits aren’t clobbered
* `postinst` ensures `/var/lib/mc-server-tools` exists for runtime state (future-proofing)

---

## 🔐 Security

* No RCON provisioning or prompts
* Bridge-only networking
* You control IP ranges and gateway; defaults are conservative

---

## 📄 License

Add your preferred license to `LICENSE` (e.g., MIT). Mention it here.

---

## 🙌 Credits

Thanks to the Proxmox and Minecraft communities—and you—for making homelab life fun.

---

If you want this split into sections for your GitHub wiki or need badges/screenshots, say the word and I’ll tailor it.
