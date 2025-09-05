# Makefile for mc-server-tools
PREFIX       ?= /usr
SHARE_DIR    := $(PREFIX)/share/mc-server-tools
BIN_DIR      := $(PREFIX)/bin
LIB_DIR      := $(SHARE_DIR)/lib
CMD_DIR      := $(SHARE_DIR)/commands

INSTALL      ?= install
MKDIR_P      ?= install -d
CHMOD        ?= chmod

FILES_LIB    := lib/common.sh lib/preflight.sh
FILES_CMDS   := commands/mc-setup
FILES_BIN    := commands/mc-preflight

WRAPPER_SRC  := debian/wrappers/mc-setup
WRAPPER_BIN  := $(BIN_DIR)/mc-setup

VERSION       ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo 2.0.0)
MAINTAINER    ?= Your Name <you@example.com>
PKGROOT       := build/pkg
DEBIAN_DIR    := $(PKGROOT)/DEBIAN

.PHONY: all install uninstall deb clean

all:
	@echo "Targets: install | uninstall | deb | clean"

install:
	$(MKDIR_P) $(DESTDIR)$(LIB_DIR)
	$(MKDIR_P) $(DESTDIR)$(CMD_DIR)
	$(MKDIR_P) $(DESTDIR)$(BIN_DIR)
	# libs
	$(INSTALL) -m 0644 $(FILES_LIB) $(DESTDIR)$(LIB_DIR)/
	# commands under our namespace dir
	$(INSTALL) -m 0755 $(FILES_CMDS) $(DESTDIR)$(CMD_DIR)/
	# top-level helpers
	$(INSTALL) -m 0755 $(FILES_BIN)  $(DESTDIR)$(BIN_DIR)/
	# mc-setup wrapper on PATH
	$(INSTALL) -m 0755 $(WRAPPER_SRC) $(DESTDIR)$(WRAPPER_BIN)
	# ensure default config exists if installing to live system (DESTDIR empty)
	if [ -z "$(DESTDIR)" ]; then \
	  $(MKDIR_P) /etc/mc-server-tools; \
	  [ -f /etc/mc-server-tools/config ] || \
	    { echo 'BRIDGE="vmbr0"\nNET_JAVA_START="192.168.205.100"\nNET_JAVA_PREFIX="24"\nNET_JAVA_GW="auto"\nNET_BEDROCK_START="192.168.206.100"\nNET_BEDROCK_PREFIX="24"\nNET_BEDROCK_GW="auto"\nDEFAULT_TEMPLATE=""' \
	      > /etc/mc-server-tools/config; } ; \
	fi

uninstall:
	rm -f $(DESTDIR)$(BIN_DIR)/mc-preflight
	rm -f $(DESTDIR)$(BIN_DIR)/mc-setup
	rm -rf $(DESTDIR)$(SHARE_DIR)

deb: clean
	@echo "==> Building mc-server-tools_$(VERSION)_all.deb (no changelog, no debhelper)…"
	# Stage files into package root
	$(MAKE) DESTDIR=$(PKGROOT) install

	# Control files
	mkdir -p $(DEBIAN_DIR)
	# Control metadata (edit Depends if you add more runtime reqs)
	@cat > $(DEBIAN_DIR)/control <<EOF
Package: mc-server-tools
Version: $(VERSION)
Section: admin
Priority: optional
Architecture: all
Maintainer: $(MAINTAINER)
Depends: bash, curl, jq, lxc | proxmox-ve
Description: Minecraft server tools for Proxmox LXC
 Utilities and scripts to create and manage Minecraft servers in LXC.
 Includes preflight hardening, setup helpers, and convenience commands.
EOF

	# Optional maintainer scripts (if present)
	@if [ -f debian/postinst ]; then \
	  install -m 0755 debian/postinst $(DEBIAN_DIR)/postinst ; \
	fi

	# Build the .deb
	dpkg-deb --build $(PKGROOT) ../mc-server-tools_$(VERSION)_all.deb
	@echo "==> Built ../mc-server-tools_$(VERSION)_all.deb"

clean:
	rm -f ../mc-server-tools_*.deb ../mc-server-tools_*.buildinfo ../mc-server-tools_*.changes
	rm -rf debian/mc-server-tools debian/.debhelper debian/files
