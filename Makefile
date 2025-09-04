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
VERSION       ?= $(shell git describe --tags --dirty --always 2>/dev/null || echo 0.1.0)

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
	         "$(DESTDIR)$(SYSCONFDIR)"
	# main dispatcher
	install -m0755 "$(DISPATCHER)" "$(DESTDIR)$(BINDIR)/mc"
	# optional wrapper for compatibility (/bin/mc -> /usr/bin/mc)
	install -m0755 "$(WRAPPER)" "/$(DESTDIR)bin/mc" || true
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
	         "$(PKGROOT)$(SYSCONFDIR)"
	install -m0755 "$(DISPATCHER)" "$(PKGROOT)$(BINDIR)/mc"
	install -m0755 "$(WRAPPER)"    "$(PKGROOT)/bin/mc"
	install -m0755 $(COMMANDS)     "$(PKGROOT)$(CMDDIR)/"
	install -m0644 $(LIBS)         "$(PKGROOT)$(LIBDIR)/"
	install -m0644 "$(CONF_DEFAULT)" "$(PKGROOT)$(SYSCONFDIR)/config"
