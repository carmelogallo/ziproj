# ziproj - https://github.com/carmelogallo/ziproj
#
#   make install                    install for the current user (~/.local)
#   make install PREFIX=/usr/local  install system-wide (may need sudo)
#   make uninstall                  remove what install added
#   make test                       run the test suite
#   make lint                       shellcheck, man page, completions, docs in sync
#   make docs                       regenerate docs/exclusions.md from bin/ziproj

PREFIX      ?= $(HOME)/.local
BINDIR      ?= $(PREFIX)/bin
MANDIR      ?= $(PREFIX)/share/man/man1
BASHCOMPDIR ?= $(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR  ?= $(PREFIX)/share/zsh/site-functions
FISHCOMPDIR ?= $(HOME)/.config/fish/completions

# On macOS, test with the system bash 3.2 that most users will run.
ifeq ($(shell uname -s),Darwin)
TEST_SHELL ?= /bin/bash
else
TEST_SHELL ?= bash
endif

.PHONY: help install uninstall test lint docs

help:
	@sed -n 's/^#   //p' Makefile

install:
	install -d "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(MANDIR)" \
		"$(DESTDIR)$(BASHCOMPDIR)" "$(DESTDIR)$(ZSHCOMPDIR)" "$(DESTDIR)$(FISHCOMPDIR)"
	install -m 755 bin/ziproj "$(DESTDIR)$(BINDIR)/ziproj"
	install -m 644 man/ziproj.1 "$(DESTDIR)$(MANDIR)/ziproj.1"
	install -m 644 completions/ziproj.bash "$(DESTDIR)$(BASHCOMPDIR)/ziproj"
	install -m 644 completions/_ziproj "$(DESTDIR)$(ZSHCOMPDIR)/_ziproj"
	install -m 644 completions/ziproj.fish "$(DESTDIR)$(FISHCOMPDIR)/ziproj.fish"
	@echo
	@echo "ziproj installed in $(BINDIR)"
	@case ":$$PATH:" in *":$(BINDIR):"*) ;; *) \
		echo "  add it to your PATH:"; \
		echo "    fish:  fish_add_path $(BINDIR)"; \
		echo "    zsh:   echo 'export PATH=\"$(BINDIR):\$$PATH\"' >> ~/.zshrc"; \
		echo "    bash:  echo 'export PATH=\"$(BINDIR):\$$PATH\"' >> ~/.bashrc";; esac
	@echo "  zsh completion: make sure $(ZSHCOMPDIR) is in your fpath, before compinit"
	@command -v gitleaks >/dev/null 2>&1 || echo "  recommended: install gitleaks (brew install gitleaks)"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/ziproj" "$(DESTDIR)$(MANDIR)/ziproj.1" \
		"$(DESTDIR)$(BASHCOMPDIR)/ziproj" "$(DESTDIR)$(ZSHCOMPDIR)/_ziproj" \
		"$(DESTDIR)$(FISHCOMPDIR)/ziproj.fish"

test:
	ZIPROJ_TEST_SHELL="$(TEST_SHELL)" tests/run.sh

docs:
	scripts/gen-exclusions-doc.sh >docs/exclusions.md

lint:
	shellcheck bin/ziproj tests/run.sh completions/ziproj.bash scripts/gen-exclusions-doc.sh
	@scripts/gen-exclusions-doc.sh | diff -u docs/exclusions.md - \
		|| { echo "docs/exclusions.md is out of date: run make docs"; exit 1; }
	@if command -v mandoc >/dev/null 2>&1; then mandoc -T lint -W warning man/ziproj.1; \
		else echo "mandoc not found, skipping the man page check"; fi
	@if command -v fish >/dev/null 2>&1; then fish --no-execute completions/ziproj.fish; \
		else echo "fish not found, skipping the fish completion check"; fi
	@if command -v zsh >/dev/null 2>&1; then zsh -n completions/_ziproj; \
		else echo "zsh not found, skipping the zsh completion check"; fi
	@bin/ziproj -n --no-gitleaks -o "$${TMPDIR:-/tmp}" >/dev/null \
		|| { echo "ziproj blocks its own repository"; exit 1; }
