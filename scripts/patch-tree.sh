#!/usr/bin/env bash
set -euo pipefail

mf=Makefile
bak=Makefile.bak.$(date +%s)

cp -v "$mf" "$bak"

awk '
BEGIN{in_tree=0}
/^[[:space:]]*tree:[[:space:]]*$/ && in_tree==0 {
  print $0
  print "\t@echo \"[tree] staging files\""
  print "\tinstall -d \"$(PKGROOT)$(BINDIR)\" \\"
  print "\t        \"$(PKGROOT)$(CMDDIR)\" \\"
  print "\t        \"$(PKGROOT)$(LIBDIR)\" \\"
  print "\t        \"$(PKGROOT)/etc/mc-server-tools\""
  print ""
  print "\t# Dispatcher"
  print "\tinstall -m0755 \"usr/bin/mc\" \"$(PKGROOT)$(BINDIR)/mc\""
  print ""
  print "\t# Commands (install if any)"
  print "ifneq ($(strip $(COMMANDS)),)"
  print "\t@echo \"[tree] installing commands: $(COMMANDS)\""
  print "\tinstall -m0755 $(COMMANDS) \"$(PKGROOT)$(CMDDIR)/\""
  print "else"
  print "\t@echo \"[tree] (no commands found under ./commands)\""
  print "endif"
  print ""
  print "\t# Libraries (sourced only, not executable)"
  print "ifneq ($(strip $(LIBS)),)"
  print "\t@echo \"[tree] installing libs: $(LIBS)\""
  print "\tinstall -m0644 $(LIBS) \"$(PKGROOT)$(LIBDIR)/\""
  print "else"
  print "\t@echo \"[tree] (no libs found under ./lib)\""
  print "endif"
  in_tree=1
  next
}
# while skipping the old tree body, keep skipping lines that look like recipe or if/else/endif
in_tree==1 {
  if ($0 ~ /^[[:graph:]]/ && $0 !~ /^[[:space:]]/ && $0 !~ /^(ifn?eq|else|endif)/) {
    # a new make directive starts — stop skipping and print this line
    in_tree=0
    print
  }
  next
}
{ print }
' "$bak" > "$mf"

echo "[patch] Updated tree target. Backup at $bak"
