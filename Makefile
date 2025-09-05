PREFIX       ?= /usr
SHARE_DIR    := $(PREFIX)/share/mc-server-tools
BIN_DIR      := $(PREFIX)/bin
LIB_DIR      := $(SHARE_DIR)/lib
CMD_DIR      := $(SHARE_DIR)/commands

INSTALL      ?= install
MKDIR_P      ?= install -d

FILES_LIB    := lib/common.sh lib/preflight.sh
FILES_CMDS   := commands/mc-setup
FILES_BIN    := commands/mc-preflight

WRAPPER_SRC  := debian/wrappers/mc-setup
WRAPPER_BIN  := $(BIN_DIR)/mc-setup

VERSION      ?= 2.0.0
MAINTAINER   ?= Your Name <you@example.com>
PKGROOT      := build/pkg
DEBIAN_DIR   := $(PKGROOT)/DEBIAN

.PHONY: all install uninstall deb clean

all:
	@echo "Targets: install | uninstall | deb | clean"

install:
	$(MKDIR_P) $(DESTDIR)$(LIB_DIR)
	$(MKDIR_P) $(DESTDIR)$(CMD_DIR)
	$(MKDIR_P) $(DESTDIR)$(BIN_DIR)
	$(INSTALL) -m 0644 $(FILES_LIB) $(DESTDIR)$(LIB_DIR)/
	$(INSTALL) -m 0755 $(FILES_CMDS) $(DESTDIR)$(CMD_DIR)/
	$(INSTALL) -m 0755 $(FILES_BIN)  $(DESTDIR)$(BIN_DIR)/
	$(INSTALL) -m 0755 $(WRAPPER_SRC) $(DESTDIR)$(WRAPPER_BIN)

uninstall:
	rm -f $(DESTDIR)$(BIN_DIR)/mc-preflight
	rm -f $(DESTDIR)$(BIN_DIR)/mc-setup
	rm -rf $(DESTDIR)$(SHARE_DIR)

deb: clean
	@echo "==> Building mc-server-tools_$(VERSION)_all.deb"
	$(MAKE) DESTDIR=$(PKGROOT) install
	mkdir -p $(DEBIAN_DIR)
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
EOF
	dpkg-deb --build $(PKGROOT) ../mc-server-tools_$(VERSION)_all.deb
	@echo "==> Built ../mc-server-tools_$(VERSION)_all.deb"

clean:
	rm -f ../mc-server-tools_*.deb
	rm -rf build
