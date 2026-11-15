# Install ntree on Linux/macOS without a package manager.
#   make install                      # to /usr/local (may need sudo)
#   make install PREFIX=$HOME/.local  # per-user
#   make uninstall PREFIX=...
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SHAREDIR ?= $(PREFIX)/share
COMPDIR ?= $(SHAREDIR)/bash-completion/completions
ZSHCOMPDIR ?= $(SHAREDIR)/zsh/site-functions

.PHONY: install uninstall check test
install:
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(COMPDIR) $(DESTDIR)$(ZSHCOMPDIR) $(DESTDIR)$(SHAREDIR)/ntree
	install -m 755 bin/ntree $(DESTDIR)$(BINDIR)/ntree
	install -m 644 completions/ntree.bash $(DESTDIR)$(COMPDIR)/ntree
	install -m 644 completions/_ntree $(DESTDIR)$(ZSHCOMPDIR)/_ntree
	install -m 644 .ntreerc.example $(DESTDIR)$(SHAREDIR)/ntree/.ntreerc.example

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/ntree $(DESTDIR)$(COMPDIR)/ntree $(DESTDIR)$(ZSHCOMPDIR)/_ntree
	rm -rf $(DESTDIR)$(SHAREDIR)/ntree

check:
	bash -n bin/ntree && bash -n completions/ntree.bash

test: check
	test/smoke.sh
