# Velumeron install target — the single thing a package (velumeron-git PKGBUILD)
# needs to call:  make DESTDIR="$pkgdir" install
#
# Layout: the whole tree goes to /usr/share/velumeron (VELUMERON_DIR derives from
# the script location, so no path baking is needed), the launchers become symlinks
# in /usr/bin, and the wayland session file lands where greeters look for it —
# fresh install → pick "Velumeron" at the login screen → velumeron-session runs
# the unattended bootstrap and the onboarding wizard opens. Zero manual steps.

PREFIX  ?= /usr
SHARE    = $(DESTDIR)$(PREFIX)/share/velumeron
BIN      = $(DESTDIR)$(PREFIX)/bin
SESSIONS = $(DESTDIR)$(PREFIX)/share/wayland-sessions

PAYLOAD = assets bin docs fastfetch gamemode hypr.lua integrations kitty quickshell \
          wallust .setup welcome_to_velumeron.sh VERSION CHANGELOG.md README.md LICENSE

.PHONY: install
install:
	mkdir -p $(SHARE) $(BIN) $(SESSIONS)
	cp -r $(PAYLOAD) $(SHARE)/
	# Compiled plugin output must not ship stale — it rebuilds on first launch.
	rm -rf $(SHARE)/quickshell/plugins/*/build $(SHARE)/quickshell/plugins/Velumeron
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron          $(BIN)/velumeron
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron-session  $(BIN)/velumeron-session
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron-welcome  $(BIN)/velumeron-welcome
	ln -sf $(PREFIX)/share/velumeron/bin/velumeron-purge-goodby $(BIN)/velumeron-purge-goodby
	ln -sf $(PREFIX)/share/velumeron/welcome_to_velumeron.sh $(BIN)/velumeron-setup
	install -Dm644 assets/velumeron.desktop $(SESSIONS)/velumeron.desktop
