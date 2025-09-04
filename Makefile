PREFIX ?= /usr/local
SHARE  ?= $(PREFIX)/share/mc-server-tools
BIN    ?= $(PREFIX)/bin
VERSION ?= 0.1.0
PKGNAME := mc-server-tools-$(VERSION)

install:
	install -d $(SHARE)/{bin,lib,scripts,systemd,config}
	install -d /etc/mc-server-tools/servers
	install -d $(DESTDIR)/etc/mc-server-tools
	install -m0644 config/etc/mc-server-tools/config \
			$(DESTDIR)/etc/mc-server-tools/config
	install -m 0755 bin/mc $(BIN)/mc
	cp -r lib $(SHARE)/
	cp -r scripts $(SHARE)/
	cp -r systemd $(SHARE)/
	cp -r config $(SHARE)/
	@echo "Installed mc to $(BIN)/mc"

uninstall:
	rm -f $(BIN)/mc
	rm -rf $(SHARE)
	@echo "Removed mc-server-tools"

clean:
	rm -rf build dist *.deb *.tar.gz

# tarball
 tar: clean
	mkdir -p build/$(PKGNAME)
	rsync -a --exclude build --exclude dist --exclude .git ./ build/$(PKGNAME)/
	cd build && tar -czf ../$(PKGNAME).tar.gz $(PKGNAME)
	@echo "Created $(PKGNAME).tar.gz"

# Debian package
 deb: clean
	# stage filesystem
	mkdir -p build/debpkg/DEBIAN
	mkdir -p build/debpkg$(BIN)
	mkdir -p build/debpkg$(SHARE)
	mkdir -p build/debpkg/etc/mc-server-tools/servers
	install -m 0755 bin/mc build/debpkg$(BIN)/mc
	cp -r lib build/debpkg$(SHARE)/
	cp -r scripts build/debpkg$(SHARE)/
	cp -r systemd build/debpkg$(SHARE)/
	cp -r config build/debpkg$(SHARE)/
	# control file
	sed "s/@VERSION@/$(VERSION)/" packaging/control.template > build/debpkg/DEBIAN/control
	chmod 0644 build/debpkg/DEBIAN/control
	# build
	dpkg-deb --build build/debpkg $(PKGNAME).deb
	@echo "Created $(PKGNAME).deb"
