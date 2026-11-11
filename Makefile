# Install ntree on Linux/macOS without a package manager.
#   make install                      # to /usr/local (may need sudo)
#   make install PREFIX=$HOME/.local  # per-user
#   make uninstall PREFIX=...
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share
COMPDIR ?= $(SHAREDIR)/bash-completion/completions

.PHONY: install uninstall check
install:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(COMPDIR) $(DESTDIR)$(SHAREDIR)/ntree
	install -m 755 bin/ntree $(DESTDIR)$(BINDIR)/ntree
	install -m 644 completions/ntree.bash $(DESTDIR)$(COMPDIR)/ntree
	install -m 644 .ntreerc.example $(DESTDIR)$(SHAREDIR)/ntree/.ntreerc.example

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/ntree $(DESTDIR)$(COMPDIR)/ntree
	rm -rf $(DESTDIR)$(SHAREDIR)/ntree

check:
	bash -n bin/ntree && bash -n completions/ntree.bash
