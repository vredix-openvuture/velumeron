# Velumeron install target — the single thing a package (velumeron-git PKGBUILD)
# needs to call:  make DESTDIR="$pkgdir" install
#
# Layout: the whole tree goes to /usr/share/velumeron (VELUMERON_DIR derives from
# the script location, so no path baking is needed) and the launchers become
# symlinks in /usr/bin. Deliberately NO wayland-sessions entry: velumeron is a
# shell for the Hyprland you already run, not a session of its own. The bootstrap
# writes ~/.config/hypr/hyprland.lua and Hyprland picks it up on the next start.

PREFIX  ?= /usr
SHARE    = $(DESTDIR)$(PREFIX)/share/velumeron
BIN      = $(DESTDIR)$(PREFIX)/bin

PAYLOAD = assets bin boot cursors docs fastfetch gamemode hypr.lua integrations quickshell \
          wallust .setup welcome_to_velumeron.sh VERSION CHANGELOG.md README.md LICENSE

.PHONY: install
install:
	mkdir -p $(SHARE) $(BIN)
	cp -r $(PAYLOAD) $(SHARE)/
	# Compiled plugin output must not ship stale — it rebuilds on first launch.
	rm -rf $(SHARE)/quickshell/plugins/*/build $(SHARE)/quickshell/plugins/Velumeron
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron          $(BIN)/velumeron
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron-welcome  $(BIN)/velumeron-welcome
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron-purge-goodbye $(BIN)/velumeron-purge-goodbye
	ln -sf $(PREFIX)/share/velumeron/welcome_to_velumeron.sh $(BIN)/velumeron-setup
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/velumeron/LICENSE
	# Exec bits explicitly: a tree that arrived as a tarball (or through a copy that
	# dropped them) would otherwise install scripts nobody can run.
	find $(SHARE) -name '*.sh' -exec chmod 755 {} +
	find $(SHARE)/assets/scripts -name '*.py' -exec chmod 755 {} +
	chmod 755 $(SHARE)/welcome_to_velumeron.sh $(SHARE)/bin/*
