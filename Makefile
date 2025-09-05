# Makefile for mc-server-tools
# Installs to the system and builds a .deb (staging under build/pkgroot)

SHELL := /bin/bash

PREFIX        ?= /usr
BINDIR        := $(PREFIX)/bin
SHAREDIR      := $(PREFIX)/share/mc-server-tools
CMDDIR        := $(SHAREDIR)/commands
LIBDIR        := $(SHAREDIR)/lib
SYSCONFDIR    := /etc/mc-server-tools

PKG           := mc-server-tools
ARCH          := all

# --- Automatic versioning from git describe ---
# Formats:
#   v1.2.3-4-gABCDEF  ->  1.2.3+git4.ABCDEF
#   v1.2.3            ->  1.2.3
GIT_DESCRIBE  := $(shell git describe --tags --long --always --dirty 2>/dev/null || true)
ifneq ($(strip $(GIT_DESCRIBE)),)
  VERSION_BASE := $(shell echo "$(GIT_DESCRIBE)" | sed -E 's/^v?([0-9]+(\.[0-9]+)*).*/\1/')
  VERSION_COMM := $(shell echo "$(GIT_DESCRIBE)" | sed -nE 's/^v?[0-9.]+-([0-9]+)-.*/\1/p')
  VERSION_SHA7 := $(shell echo "$(GIT_DESCRIBE)" | sed -nE 's/.*-g([0-9a-fA-F]+).*/\1/p' | cut -c1-7)
  ifneq ($(strip $(VERSION_COMM)),)
    VERSION := $(VERSION_BASE)+git$(VERSION_COMM).$(VERSION_SHA7)
  else
    VERSION := $(VERSION_BASE)
  endif
else
  VERSION := 0.0.0+local.$(shell date -u +%Y%m%d%H%M)
endif

# --- Inputs ---
DISPATCHER    := usr/bin/mc
COMMANDS      := commands/mc-setup commands/mc-preflight
LIBS          := lib/common.sh lib/preflight.sh
CONF_DEFAULT  := debpkg/etc/config

# --- Staging / output paths ---
BUILDROOT     := build
PKGROOT       := $(BUILDROOT)/pkgroot
DEBIAN_DIR    := $(PKGROOT)/DEBIAN
DEBFILE       := $(BUILDROOT)/$(PKG)_$(VERSION)_$(ARCH).deb

# Helpful echo
define echo_kv
	@printf "%-12s %s\n" "$(1):" "$(2)"
endef

.PHONY: all install uninstall clean tree
.PHONY: deb
deb: all

all: clean tree
	$(call echo_kv,VERSION,$(VERSION))
	# Build control from template
	install -d "$(DEBIAN_DIR)"
	sed 's/@VERSION@/$(VERSION)/' debpkg/DEBIAN/control.in > "$(DEBIAN_DIR)/control"
	# Optional maintainer scripts
	if [ -f debpkg/DEBIAN/postinst ]; then install -m0755 debpkg/DEBIAN/postinst "$(DEBIAN_DIR)/postinst"; fi
	if [ -f debpkg/DEBIAN/prerm ];    then install -m0755 debpkg/DEBIAN/prerm    "$(DEBIAN_DIR)/prerm";    fi
	if [ -f debpkg/DEBIAN/postrm ];   then install -m0755 debpkg/DEBIAN/postrm   "$(DEBIAN_DIR)/postrm";   fi
	# Build .deb
	dpkg-deb --build "$(PKGROOT)" "$(DEBFILE)"
	$(call echo_kv,DEBFILE,$(DEBFILE))

tree:
	# Stage filesystem into $(PKGROOT)
	install -d "$(PKGROOT)$(BINDIR)" \
	         "$(PKGROOT)$(CMDDIR)" \
	         "$(PKGROOT)$(LIBDIR)" \
	         "$(PKGROOT)$(SYSCONFDIR)"
	# Dispatcher (single entrypoint for commands)
	install -m0755 "$(DISPATCHER)"     "$(PKGROOT)$(BINDIR)/mc"
	# Commands (+x)
	install -m0755 $(COMMANDS)         "$(PKGROOT)$(CMDDIR)/"
	# Libraries (read-only)
	install -m0644 $(LIBS)             "$(PKGROOT)$(LIBDIR)/"
	# Default config
	if [ -f "$(CONF_DEFAULT)" ]; then install -m0644 "$(CONF_DEFAULT)" "$(PKGROOT)$(SYSCONFDIR)/config"; fi

install:
	# Local install from staged tree (for dev machines)
	cp -a "$(PKGROOT)"/. /

uninstall:
	# Not a full uninstall; for development convenience only
	rm -f  "$(BINDIR)/mc"
	rm -rf "$(SHAREDIR)"
	rm -rf "$(SYSCONFDIR)"

clean:
	rm -rf "$(BUILDROOT)"
