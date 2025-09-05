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

deb:
	# Build source package and .deb using debhelper
	dpkg-buildpackage -us -uc -b

clean:
	rm -f ../mc-server-tools_*.deb ../mc-server-tools_*.buildinfo ../mc-server-tools_*.changes
	rm -rf debian/mc-server-tools debian/.debhelper debian/files
