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
# Version logic:
# - On a tag like v1.2.3-4-gABCDEF:  ->  1.2.3+git4.ABCDEF
# - On exact tag v1.2.3:             ->  1.2.3
# - No tags:                          ->  0.0.0+gitYYYYMMDD.SHA
VERSION ?= $(shell sh -c '\
  set -e; \
  D=$$(git describe --tags --match "v[0-9]*" --abbrev=7 --dirty 2>/dev/null || true); \
  if echo "$$D" | grep -Eq "^v[0-9]"; then \
    echo "$$D" \
      | sed -E "s/^v//" \
      | sed -E "s/-([0-9]+)-g([0-9a-f]+)/+git\1.\2/" \
      | sed -E "s/-dirty/+dirty/"; \
  else \
    S=$$(git rev-parse --short HEAD 2>/dev/null || echo unknown); \
    echo "0.0.0+git$$(date -u +%Y%m%d).$$S"; \
  fi')


# Staging for the deb
PKGROOT       := build/pkgroot
DEBFILE       := $(PKG)_$(VERSION)_$(ARCH).deb

# Source files in this repo
DISPATCHER    := usr/bin/mc
WRAPPER       := bin/mc
COMMANDS      := $(wildcard commands/mc-*)
LIBS          := $(wildcard lib/*)
CONF_DEFAULT  := config/etc/mc-server-tools/config

.PHONY: all install uninstall clean deb tree

all:
	@echo "Targets: install, deb, uninstall, clean"

install:
	install -d "$(DESTDIR)$(BINDIR)" \
	         "$(DESTDIR)$(CMDDIR)" \
	         "$(DESTDIR)$(LIBDIR)" \
	         "$(DESTDIR)$(SYSCONFDIR)" \
			 "$(DESTDIR)/bin"
	# main dispatcher
	install -m0755 "$(DISPATCHER)" "$(DESTDIR)$(BINDIR)/mc"
	# optional wrapper for compatibility (/bin/mc -> /usr/bin/mc)
	install -m0755 "$(WRAPPER)" "$(DESTDIR)/bin/mc" || true
	# commands + libs
	install -m0755 $(COMMANDS) "$(DESTDIR)$(CMDDIR)/"
	install -m0644 $(LIBS)      "$(DESTDIR)$(LIBDIR)/"
	# default config (as regular install; deb will mark as conffile)
	install -m0644 "$(CONF_DEFAULT)" "$(DESTDIR)$(SYSCONFDIR)/config"
	@echo "Installed to $(DESTDIR:=/)"

uninstall:
	rm -f  "$(DESTDIR)$(BINDIR)/mc"
	rm -f  "/$(DESTDIR)bin/mc"
	rm -rf "$(DESTDIR)$(CMDDIR)"
	rm -rf "$(DESTDIR)$(LIBDIR)"
	# Do not delete user config on uninstall
	@echo "Uninstalled. (Left $(SYSCONFDIR)/config in place)"

clean:
	rm -rf build *.deb *.ipk *.tar.gz

# --- Debian package build ---
deb: clean tree
	# copy control files
	install -d "$(PKGROOT)/DEBIAN"
	install -m0644 debpkg/DEBIAN/control    "$(PKGROOT)/DEBIAN/control"
	install -m0644 debpkg/DEBIAN/conffiles  "$(PKGROOT)/DEBIAN/conffiles"
	install -m0755 debpkg/DEBIAN/postinst   "$(PKGROOT)/DEBIAN/postinst"
	# fill version in control if it contains @VERSION@
	sed -i "s/@VERSION@/$(VERSION)/g" "$(PKGROOT)/DEBIAN/control"
	# build
	dpkg-deb --build "$(PKGROOT)" "$(DEBFILE)"
	@echo "Built: $(DEBFILE)"

tree:
	# stage filesystem into $(PKGROOT)
	install -d "$(PKGROOT)$(BINDIR)" \
	         "$(PKGROOT)$(CMDDIR)" \
	         "$(PKGROOT)$(LIBDIR)" \
	         "$(PKGROOT)$(SYSCONFDIR)" \
			 "$(PKGROOT)/bin"
	install -m0755 "$(DISPATCHER)" "$(PKGROOT)$(BINDIR)/mc"
	install -m0755 "$(WRAPPER)"    "$(PKGROOT)/bin/mc"
	install -m0755 $(COMMANDS)     "$(PKGROOT)$(CMDDIR)/"
	install -m0644 $(LIBS)         "$(PKGROOT)$(LIBDIR)/"
	install -m0644 "$(CONF_DEFAULT)" "$(PKGROOT)$(SYSCONFDIR)/config"
