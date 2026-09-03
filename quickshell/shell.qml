//@ pragma UseQApplication
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // ── Boot gate: nothing maps before the splash curtain has painted ───────────────────────────
    // Every window below is modelled on THIS instead of on Quickshell.screens, so the shell waits
    // for the curtain to be on screen before it builds anything else.
    //
    // Measured on 2026-08-29, three monitors, warm cache. The splash reports its first frame 0.7 s
    // after launch when it is the only surface and 5.6 s when the rest of the shell comes up
    // alongside it — and 5.6 s was longer than the whole splash, so the curtain was torn down
    // before it had ever been seen. What the user got was five seconds of black followed by a
    // desktop popping into place. The cost is not QML construction (the object tree is complete
    // 0.9 s in) and not the wallpaper (5.9 s without it): it is ~130 layer-shell surfaces, three
    // screens × 43 of these blocks, each wanting its own configure/ack and first buffer, with the
    // splash's own frame queued behind all of them.
    //
    // SplashState.curtainUp is true on the first evaluation when the splash is switched off, so an
    // unsplashed start maps everything as immediately as it did before.
    //
    // Only the surfaces you actually SEE when the curtain tears ride this one: wallpaper, bar,
    // taskbar, tags, corners, the theme's layers. Together they cost 0.23 s. Everything else is
    // invisible until you ask for it, and goes in WAVES — see late().
    readonly property var bootScreens: SplashState.curtainUp ? Quickshell.screens : []

    // The ~36 surfaces nobody has asked for yet: every menu, glide, picker and overlay. Building
    // them all in one go costs 6.8 s of blocked GUI thread (0.23 s for the visible ones, 7 s for
    // the lot), and wherever that block sits it is a hole: under the curtain it is a splash that
    // stands still, after it a desktop that does. So they come up a wave at a time — the timer can
    // only fire once the event loop is free, which makes each tick "one more group, then breathe".
    //
    // Wave order is what you are likely to reach for first: OSD and notification popups, then the
    // launcher, then the settings menu, then the glides, the menus, and the rarities last. The
    // splash does NOT wait for any of this; it plays its own length and tears open on time, and the
    // rest arrives underneath a desktop that is already yours.
    //
    // `late()` is a function on purpose: a binding tracks every property it reads while it
    // evaluates, `lateWave` included, so each model re-evaluates on the wave that carries it.
    property int lateWave: 0
    readonly property int lastWave: 18
    function late(wave) { return root.lateWave >= wave ? Quickshell.screens : [] }
    // NOT while the splash is playing. Each wave blocks the GUI thread for a moment, and the
    // curtain's own animation runs on that same thread — the wordmark charged in visible steps and
    // the whole start read as a stutter. The waves wait for the curtain to be gone and then build
    // under a desktop that is already up and already yours; the surfaces they carry are invisible
    // until you ask for one anyway.
    Timer {
        interval: 1; repeat: true
        running: SplashState.curtainUp && !SplashState.active && root.lateWave < root.lastWave
        onTriggered: root.lateWave++
    }

    // ── Idle chain: screensaver → lock → suspend (ext-idle-notify-v1) ────────────────────────
    // Every stage is BUILT, not bound. Measured, three times, in one process against a reference
    // monitor on the same seat: an IdleMonitor whose `enabled` or `timeout` is a binding ends up
    // reporting the right values and never delivering an idle, while one created with literal
    // values fires on time. Changing a property after creation kills it just as dead. So each
    // stage is instantiated with its timeout as an INITIAL property, parented to this root (the
    // only place they arm at all — inside a singleton or an Item they stay silent), and a settings
    // change destroys the old object and builds a new one instead of touching it.
    Component {
        id: idleStage
        IdleMonitor { enabled: true }
    }
    property var saverMon:   null
    property var lockMon:    null
    property var suspendMon: null

    function _stage(old, sec, respect, onIdle) {
        if (old) old.destroy()
        if (sec <= 0) return null
        var m = idleStage.createObject(root, { timeout: sec, respectInhibitors: respect })
        if (m) m.isIdleChanged.connect(function () { onIdle(m.isIdle) })
        return m
    }
    function rebuildIdle() {
        var r = IdleService.respect
        root.saverMon = root._stage(root.saverMon, IdleService.saverSec, r, function (idle) {
            // The screensaver is the one stage that also has to come DOWN by itself: `isIdle` going
            // false is the resume signal, which is why neither surface has to grab the keyboard.
            UiState.screensaverOn = idle && !IdleService.awake
        })
        root.lockMon = root._stage(root.lockMon, IdleService.lockSec, r, function (idle) {
            // engageRequested (not `locked = true`) so the pre-lock screenshot pass still runs and
            // the iris grows out of the real desktop, exactly as it does for a manual lock.
            if (idle && !IdleService.awake && !LockState.locked) LockState.engageRequested()
        })
        root.suspendMon = root._stage(root.suspendMon, IdleService.suspendSec, r, function (idle) {
            // Still guarded by idle-suspend.sh: "no input" is not "no work".
            if (idle && !IdleService.awake) IdleService.runSuspend()
        })
    }
    // Keep-awake and the lock state are checked in the handlers above, never in `enabled`: they can
    // flip while you sit still, and rebuilding a monitor mid-idle would lose that idle period.
    Connections {
        target: IdleService
        function onSaverSecChanged()   { root.rebuildIdle() }
        function onLockSecChanged()    { root.rebuildIdle() }
        function onSuspendSecChanged() { root.rebuildIdle() }
        function onRespectChanged()    { root.rebuildIdle() }
    }

    // OnboardingState decides whether to open the first-run wizard / post-update changelog.
    // SoundService.boot() builds the sound cache and — once per session, never per shell restart —
    // fires the login sound. Each has to be TOUCHED, or the singleton is never created.
    Component.onCompleted: { root.rebuildIdle()
                             void Hyprwindows.windows
                             OnboardingState.boot(); SoundService.boot() }

    // Cold-start resync: Quickshell.Hyprland builds its workspace→monitor /
    // monitor→activeWorkspace graph from the event socket and can latch a bogus
    // association when the shell boots mid-stream — the bar then pinned ws1 as the
    // other monitor's active pill until the next workspace event (seen 2026-07-11,
    // typically right after wallust's qs_reload restart on a wallpaper change).
    // Two forced re-queries shortly after startup make the graph converge.
    Timer { running: true; interval: 1500
            onTriggered: { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces() } }
    Timer { running: true; interval: 6000
            onTriggered: { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces() } }
    // …and keep it converged for the whole session: the same stale association can also latch
    // AFTER boot (seen 2026-07-11 as the active pill missing on a secondary monitor — ws6 active on
    // DP-3 but no lit pill). Quickshell.Hyprland's own event processing does NOT self-correct it;
    // only a forced IPC re-query does. So re-query on the workspace / focused-monitor events,
    // debounced into one refresh so rapid switching never spams the socket.
    Timer { id: wsResync; interval: 120
            onTriggered: { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces() } }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "workspace":        case "workspacev2":
            case "focusedmon":       case "focusedmonv2":
            case "moveworkspace":    case "moveworkspacev2":
            case "createworkspace":  case "createworkspacev2":
            case "destroyworkspace": case "destroyworkspacev2":
                wsResync.restart()
            }
        }
    }

    // Hand the active THEME to Hyprland — window decoration (border colour, glow, shadow, gaps)
    // follows the theme, not the ui_style: hyprland.lua reads <USER_DIR>/active-theme and dofiles
    // hypr.lua/themes/<id>.lua. This is the ONLY hand-off, so every writer of the `theme` key
    // reaches the compositor the same way — the picker, the keybind, `ipc call theme wear`, a
    // settings restore — and none of them has to remember to call the script itself.
    //
    // The settle timer exists because `theme` arrives twice at startup: the property default first,
    // then the parsed settings.json a few ms later. Debouncing collapses that into one call, and
    // running it at startup at all is what corrects a stale file — one written by an older release
    // that handed over the ui_style, or a theme switched while the shell was down.
    // apply-window-look.sh reloads Hyprland only when the value actually changed, so a matching file
    // costs nothing.
    Process { id: themeHyprProc }
    Timer {
        id: themeSettle
        interval: 400
        onTriggered: {
            themeHyprProc.command = ["bash", "-c",
                "\"$VELUMERON_DIR/assets/scripts/apply-window-look.sh\" " + JSON.stringify(VtlConfig.theme)]
            themeHyprProc.running = false
            themeHyprProc.running = true
        }
    }
    QtObject {
        id: themeHypr
        property string cur: VtlConfig.theme
        Component.onCompleted: themeSettle.restart()
        onCurChanged: themeSettle.restart()
    }

    // IPC: force the onboarding window — `velumeron --onboarding [update]`:
    //   open   → first-run wizard (pages write real config!)
    //   update → changelog report for the current release
    //   close  → hide without stamping the version as seen
    // Sounds are reachable from the outside too: a bind or a script can make the shell speak, and
    // it is the only way to exercise the path without opening a menu.
    IpcHandler {
        target: "sound"
        function play(key: string):    void { SoundService.play(key) }
        function preview(key: string): void { SoundService.preview(key) }
    }

    IpcHandler {
        target: "onboarding"
        function open():   void { OnboardingState.openForced("first-run") }
        function update(): void { OnboardingState.openForced("update") }
        function close():  void { OnboardingState.close() }
    }

    // IPC: what the theme layer actually resolved to.
    //   qs -p <this-dir> ipc call theme report
    // This is not a convenience. qmllint cannot see a theme that is resolved at runtime, so asking
    // the running shell is the only way to check that a theme package was found and which token
    // table it ended up with — the cold load-check every new theme needs.
    // IPC: the screensaver and the splash, so both can be looked at without waiting out an idle
    // timer or a login. A theme that draws either of them has no other way to be checked.
    //   qs -p <this-dir> ipc call saver on|off
    //   qs -p <this-dir> ipc call splash play
    //
    // NOT `show` — see the note on the `zones` handler below, which already records why. It cost a
    // debugging pass to rediscover, because `ipc call <t> show` exits 0 and prints the function
    // list instead of failing.
    IpcHandler {
        target: "saver"
        function on():  void { UiState.screensaverOn = true }
        function off(): void { UiState.screensaverOn = false }
    }
    IpcHandler {
        target: "splash"
        function play(): void { SplashState.replay() }
    }

    IpcHandler {
        target: "theme"
        // `wear` is the whole switch: id, arrangement and window frames. Same path the picker takes.
        function wear(id: string): void { Theme.wear(id) }
        // Forget what you made of a theme and put its shipped arrangement back.
        function reset(id: string): void { Theme.resetArrangement(id === "" ? Theme.themeId : id) }
        function report(): string {
            return JSON.stringify({ id: Theme.themeId, name: Theme.name, base: Theme.base,
                                    loaded: Theme.loaded, contract: Theme.contract,
                                    tokens: Theme.tokens, lock: Theme.lock }, null, 1)
        }
        // The picker, bound to Super+Ctrl+Space. Which shape opens is a setting, so this is one
        // call and not two: `theme_picker_style` decides between the full screen and the bar panel,
        // and either shape toggles on the monitor that has focus.
        function toggle(): void {
            if (UiState.themePickerOpen) { UiState.themePickerOpen = false; return }
            if (UiState.flyout === "theme") { UiState.flyout = ""; return }
            var m = Hyprland.focusedMonitor
            if (!m) return
            UiState.openThemePicker(m.name, m.width, m.height)
        }
        function picker(): void { if (UiState.flyout !== "theme" && !UiState.themePickerOpen) toggle() }
        // Only OUR flyout: clearing UiState.flyout unconditionally would shut whatever else the
        // user has open (volume, mpris) because a script asked the theme picker to go away.
        function close():  void {
            if (UiState.flyout === "theme") UiState.flyout = ""
            UiState.themePickerOpen = false
        }
    }

    // IPC: toggle / open / close the corner menu from outside (e.g. a Hyprland keybind):
    //   qs -p <this-dir> ipc call menu toggle
    IpcHandler {
        target: "menu"
        function toggle(): void { UiState.openDropdown = UiState.openDropdown === "vuture-icon" ? "" : "vuture-icon" }
        function open():   void { UiState.openDropdown = "vuture-icon" }
        function close():  void { UiState.openDropdown = "" }
        // Jump straight to one settings page, the way the in-shell shortcuts into Settings
        // already do (`velumeron --settings workspaces`). An unknown name lands on Home.
        function section(name: string): void {
            UiState.settingsRequestSection = name
            UiState.openDropdown = "vuture-icon"
        }
    }

    // IPC: arrange the desk — `qs -p <dir> ipc call desk edit`.
    // The dashboard's editor is reachable from the settings pencil and nowhere else, which is right
    // for a page inside a menu. The desk is the desktop: rearranging it should not require finding
    // the menu that owns it, so it gets a door of its own for a keybind to knock on.
    IpcHandler {
        target: "desk"
        function edit():  void { UiState.openDashEdit(Compositor.focusedMonitorName, "desk") }
        function close(): void { UiState.closeDashEdit() }
    }

    // IPC: the shell's context menu, the one a right-click opens — `ipc call context desk 600 300`
    // / `context bar <x> <y>` / `context close`. A point on the focused monitor, in its own
    // coordinates: the pointer is deliberately not read here, because the caller knows where it
    // meant and a real right-click already carries its own position.
    IpcHandler {
        target: "context"
        function desk(x: real, y: real): void {
            UiState.openContextMenu("desk", Compositor.focusedMonitorName, x, y)
        }
        function bar(x: real, y: real): void {
            UiState.openContextMenu("bar", Compositor.focusedMonitorName, x, y)
        }
        function close(): void { UiState.ctxMenuOpen = false }
    }

    // IPC: show the volume / brightness OSD (poked by osd-show.sh):
    //   qs -p <dir> ipc call osd volume
    //   qs -p <dir> ipc call osd brightness 80
    // IPC: the screenshot picker — bound to SUPER+SHIFT+S via bin/velumeron --screenshot.
    IpcHandler {
        target: "screenshot"
        function open():   void { UiState.shotOpen = true }
        function close():  void { UiState.shotOpen = false }
        function toggle(): void { UiState.shotOpen = !UiState.shotOpen }
        // Skip the picker: `velumeron --screenshot region|window|output|all`.
        function capture(mode: string): void { UiState.shotFire = mode }
    }

    IpcHandler {
        target: "osd"
        function volume(): void                 { UiState.osdShow("volume", 0) }
        function brightness(percent: int): void { UiState.osdShow("brightness", percent) }
    }

    // IPC: open / toggle a module flyout (Volume routing, Mpris player) without clicking the module.
    // No module position available here, so it reuses the last-known anchor/edge on the focused mon.
    IpcHandler {
        target: "flyout"
        function _open(id: string): void {
            var m = Hyprland.focusedMonitor
            UiState.toggleFlyout(id, UiState.flyoutAnchorX, UiState.flyoutAnchorY,
                                 UiState.flyoutEdge, UiState.flyoutGroup, m ? m.name : UiState.flyoutMon)
        }
        function volume():   void { _open("volume") }
        function mpris():    void { _open("mpris") }
        function calendar(): void { _open("calendar") }
        function weather():  void { _open("weather") }
        function mic():      void { _open("mic") }
        function keyboard(): void { _open("keyboard") }
        function network():  void { _open("network") }
        function bluetooth():void { _open("bluetooth") }
        function close():    void { UiState.flyout = "" }
    }

    // IPC: wallpaper quick-menu — grows out of the bar on the focused monitor (successor to the
    // rofi wallpaper switcher). Anchors at the centre of that monitor's first active bar edge.
    IpcHandler {
        target: "wallpaper"
        // Either shape may be up (Settings → Wallpaper → Quickselect → Style), so "is it open" is
        // two questions. openWallpaperQuick() picks the shape and toggles it on the right monitor.
        function toggle(): void {
            if (UiState.wallpaperGalleryOpen) { UiState.wallpaperGalleryOpen = false; return }
            if (UiState.flyout === "wallpaper") { UiState.flyout = ""; return }
            var m = Hyprland.focusedMonitor
            if (!m) return
            UiState.openWallpaperQuick(m.name, m.width, m.height)
        }
        function open():  void { if (UiState.flyout !== "wallpaper" && !UiState.wallpaperGalleryOpen) toggle() }
        function close(): void { UiState.flyout = ""; UiState.wallpaperGalleryOpen = false }
    }

    // IPC: application launcher (replaces the rofi drun launcher; bound to Super+Space).
    // Latch the launcher to the monitor focused at open time so it stays there even if focus moves.
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (!UiState.launcherOpen) UiState.launcherMon = Hyprland.focusedMonitor?.name ?? ""
            UiState.launcherOpen = !UiState.launcherOpen
        }
        function open():   void { UiState.launcherMon = Hyprland.focusedMonitor?.name ?? ""; UiState.launcherOpen = true }
        function close():  void { UiState.launcherOpen = false }
        // Straight to the full-page board, whatever `launcher_fullscreen` says — a keybind can aim
        // at the big grid without the setting. Order matters: opening seeds launcherFs from the
        // setting (Launcher.qml), so the override has to land after it.
        function fullscreen(): void {
            if (!UiState.launcherOpen) UiState.launcherMon = Hyprland.focusedMonitor?.name ?? ""
            UiState.launcherOpen = true
            UiState.launcherFs   = true
        }
    }

    // IPC: rofi successors — clipboard history (Super+V), window switcher (Super+Tab), session menu
    // (Super+Ctrl+Q). Each latches to the monitor focused at open time (like the launcher).
    IpcHandler {
        target: "clipboard"
        function toggle(): void { if (!UiState.clipboardOpen) UiState.clipboardMon = Hyprland.focusedMonitor?.name ?? ""; UiState.clipboardOpen = !UiState.clipboardOpen }
        function open():   void { UiState.clipboardMon = Hyprland.focusedMonitor?.name ?? ""; UiState.clipboardOpen = true }
        function close():  void { UiState.clipboardOpen = false }
    }
    // Window switcher: Super+Tab opens it, then the overlay grabs the keyboard and handles the rest.
    // `open` while already open advances the selection (fallback if the grab didn't suppress the bind).
    IpcHandler {
        target: "window"
        function open(): void {
            if (!UiState.windowSwitcherOpen) { UiState.windowSwitcherMon = Hyprland.focusedMonitor?.name ?? ""; UiState.windowSwitcherOpen = true }
            else UiState.windowSwitcherNext++
        }
        function toggle(): void { if (UiState.windowSwitcherOpen) UiState.windowSwitcherOpen = false; else open() }
        function close():  void { UiState.windowSwitcherOpen = false }
    }
    // Layout quick-switcher: Super+Alt+Tab — same open-advances semantics as the window switcher.
    IpcHandler {
        target: "layoutswitch"
        function open(): void {
            if (!UiState.layoutSwitcherOpen) { UiState.layoutSwitcherMon = Hyprland.focusedMonitor?.name ?? ""; UiState.layoutSwitcherOpen = true }
            else UiState.layoutSwitcherNext++
        }
        function toggle(): void { if (UiState.layoutSwitcherOpen) UiState.layoutSwitcherOpen = false; else open() }
        function close():  void { UiState.layoutSwitcherOpen = false }
    }
    IpcHandler {
        target: "session"
        function toggle(): void { if (!UiState.sessionOpen) UiState.sessionMon = Hyprland.focusedMonitor?.name ?? ""; UiState.sessionOpen = !UiState.sessionOpen }
        function open():   void { UiState.sessionMon = Hyprland.focusedMonitor?.name ?? ""; UiState.sessionOpen = true }
        function close():  void { UiState.sessionOpen = false }
    }

    // IPC: engage the native lockscreen (Lock.qml). Wired from hypridle's lock_cmd via
    // assets/scripts/lock.sh, so `loginctl lock-session` → logind Lock → hypridle → here. Only
    // `lock` is exposed — UNLOCK happens exclusively through PAM inside Lock.qml, so the user-local
    // IPC socket can never bypass the password.
    IpcHandler {
        target: "lock"
        function lock(): void { LockState.engageRequested() }
        // TEMP DEBUG (2026-07-28, dead-keyboard-after-resume): rescue hatch so the suspend repro
        // never needs a reboot. REMOVE once the resume bug is fixed — this bypasses PAM!
        function unlock(): void { LockState.locked = false }
    }

    // IPC: FancyZones overlay — poked by hypr.lua/modules/fancyzones.lua while a floating
    // window is Super-dragged (show) and on release (hide).
    IpcHandler {
        target: "zones"
        // NOTE: `show` is unusable as an IPC function name (qs treats `ipc call <t> show`
        // as target introspection) — hence open/close.
        function open():  void { ZonesState.show() }
        function close(): void { ZonesState.hide() }
    }

    // IPC: btop dropdown — a themed terminal+btop window dropping out of the bar (btop-drop.sh).
    // No anchor here, so it opens top-centre on the focused monitor; the Performance module's
    // right-click passes its exact module anchor instead.
    Process { id: btopDropProc }
    IpcHandler {
        target: "btop"
        function _run(arg: string): void {
            btopDropProc.command = ["bash", "-c",
                "\"$VELUMERON_DIR/assets/scripts/btop-drop.sh\" " + arg]
            btopDropProc.running = false
            btopDropProc.running = true
        }
        function toggle(): void { _run("") }
        function close():  void { _run("close") }
    }

    // IPC: toggle / open / close the notification centre.
    IpcHandler {
        target: "notify"
        function toggle(): void { UiState.notifCenterOpen = !UiState.notifCenterOpen }
        function open():   void { UiState.notifCenterOpen = true }
        function close():  void { UiState.notifCenterOpen = false }
        function dnd():    void { NotifService.toggleDnd() }   // do-not-disturb (replaces swaync-client)
    }

    // IPC: keybind cheatsheet (replaces gui/keybind_help.py). One no-arg function per
    // context (qs ipc rejects string positionals), each toggles that context:
    //   qs -p <dir> ipc call keybind all      → full reference
    //   qs -p <dir> ipc call keybind window   → window submap   (also: apps | system)
    IpcHandler {
        target: "keybind"
        function all():    void { UiState.keybindContext = UiState.keybindContext === "all"    ? "" : "all" }
        function window(): void { UiState.keybindContext = UiState.keybindContext === "window" ? "" : "window" }
        function apps():   void { UiState.keybindContext = UiState.keybindContext === "apps"   ? "" : "apps" }
        function system(): void { UiState.keybindContext = UiState.keybindContext === "system" ? "" : "system" }
        function close():  void { UiState.keybindContext = "" }
    }

    // Wallpaper auto-change — fires every N minutes when enabled. The mode ("silent" / "show")
    // tells wallpaper-set.sh whether to do its workspace-switch showcase. One shell instance, so a
    // single timer drives it (the script picks the next wallpaper per the configured order).
    Process { id: wpAutoProc }
    Timer {
        interval: Math.max(1, VtlConfig.wallpaperAutoMinutes) * 60000
        repeat:   true
        running:  VtlConfig.wallpaperAutoMode !== "off"
        onTriggered: {
            wpAutoProc.command = ["bash",
                Quickshell.env("VELUMERON_DIR") + "/assets/scripts/wallpaper-auto.sh",
                VtlConfig.wallpaperAutoMode]
            wpAutoProc.running = false
            wpAutoProc.running = true
        }
    }

    // The weather fetch lives in WeatherService now — two surfaces want it (the lockscreen widget
    // and the bar module) and they share one weather.json, so it needs one owner rather than a
    // fetcher per reader. Only the theme trigger stays here: `Theme.lock` changes as one block, and
    // a service cannot bind to "any of these three fields moved".
    Connections {
        target: Theme
        function onLockChanged() { WeatherService.refresh() }
    }

    // Native wallpaper engine: one background-layer surface per monitor (static images + live video
    // with GPU crossfades), driven by the watched wallpapers.json. Sits below everything.
    Variants {
        model: VtlConfig.componentEnabled("wallpaper") ? root.bootScreens : []
        delegate: WallpaperWindow { required property var modelData; screen: modelData }
    }

    // The desk: widgets on the wallpaper. Bottom layer, so it stacks above the wallpaper (and above
    // a theme's backdrop, which is Background too) and below every window. `late` because a widget
    // is the least urgent thing on the screen — the bar and the wallpaper come first.
    Variants {
        model: VtlConfig.componentEnabled("desk") ? root.late(6) : []
        delegate: DeskWindow { required property var modelData; screen: modelData }
    }
    // The shell's context menu — one surface for the desktop's right-click and the bar's. On the
    // Overlay layer, because neither the desk (under the windows) nor the bar (a strip) could hold
    // a menu of its own. NOT gated on the desk: the bar's right-click has to work without it.
    Variants {
        model: root.late(6)
        delegate: ContextMenu { required property var modelData; screen: modelData }
    }

    // The theme's window veil, if it brings one: over your windows, UNDER everything the shell
    // draws. Declared HERE, before the bar, on purpose — both sit on the Top layer and the one
    // mapped first ends up underneath, which is the whole point of it.
    Variants {
        model: root.bootScreens
        delegate: ThemeMaterial { required property var modelData; screen: modelData; surface: "dim" }
    }

    // Bar visual: full-screen transparent surface, no exclusive zone (dynamic, multi-edge).
    // On the boot gate with everything else: the bar builds itself UNDER the curtain (strips, tray
    // icons, workspace pills) and is simply there when the curtain tears open, instead of
    // assembling in the frames before the curtain lands. The reserving surfaces below wait with it,
    // so the window layout settles while nobody can see it either.
    // Not on every screen: `bar_secondary` says what the screens you have NOT configured get, and
    // "off" (the shipped default) means no bar is built for them at all rather than one that is
    // hidden. A screen with its own module arrangement is never affected — see isSecondaryOff.
    Variants {
        model: VtlConfig.componentEnabled("bar")
               ? root.bootScreens.filter(function (s) {
                     return !VtlConfig.isSecondaryOff(s && s.name ? s.name : "")
                 })
               : []
        delegate: Bar {
            required property var modelData
            screen: modelData
        }
    }

    // Exclusive zones: one invisible reserving surface per screen × edge. Each only
    // reserves space when the bar actually occupies that edge (driven by VtlConfig).
    Variants {
        model: VtlConfig.componentEnabled("bar") ? root.bootScreens : []
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "top" }
    }
    Variants {
        model: VtlConfig.componentEnabled("bar") ? root.bootScreens : []
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "bottom" }
    }
    Variants {
        model: VtlConfig.componentEnabled("bar") ? root.bootScreens : []
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "left" }
    }
    Variants {
        model: VtlConfig.componentEnabled("bar") ? root.bootScreens : []
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "right" }
    }

    // Settings menu: one per screen, shown via UiState.openDropdown === "vuture-icon"
    Variants {
        model: root.late(3)
        delegate: Settings {
            required property var modelData
            screen: modelData
        }
    }

    // Build-your-own palette editor: centred overlay, one per screen (Settings → Style → Colours).
    Variants {
        model: root.late(18)
        delegate: PaletteEditor { required property var modelData; screen: modelData }
    }

    // Onboarding: first-run wizard / post-update changelog, one per screen (renders on the
    // monitor focused when it opened).
    Variants {
        model: VtlConfig.componentEnabled("onboarding") ? root.late(3) : []
        delegate: OnboardingWindow { required property var modelData; screen: modelData }
    }

    // Application launcher: one per screen, shows on the focused monitor (Super+Space).
    Variants {
        model: VtlConfig.componentEnabled("launcher") ? root.late(2) : []
        delegate: Launcher { required property var modelData; screen: modelData }
    }

    // Hot corners / screen edges: one transparent trigger overlay per screen (Settings → Corners).
    Variants {
        model: VtlConfig.componentEnabled("hotcorners") ? root.bootScreens : []
        delegate: HotCorners { required property var modelData; screen: modelData }
    }

    // rofi successors: window switcher, clipboard history, session menu — one per screen.
    Variants { model: VtlConfig.componentEnabled("windowswitcher") ? root.late(14) : []; delegate: WindowSwitcher { required property var modelData; screen: modelData } }
    Variants { model: VtlConfig.componentEnabled("windowswitcher") ? root.late(14) : []; delegate: LayoutQuickSwitcher { required property var modelData; screen: modelData } }
    Variants { model: VtlConfig.componentEnabled("clipboard") ? root.late(15) : []; delegate: ClipboardMenu  { required property var modelData; screen: modelData } }
    Variants { model: VtlConfig.componentEnabled("session") ? root.late(15) : []; delegate: SessionOverlay { required property var modelData; screen: modelData } }
    // Screensaver — one surface per output; each shows ITS OWN monitor's wallpaper folder.
    Variants { model: root.bootScreens; delegate: Screensaver { required property var modelData; screen: modelData } }
    // The idle chain has no visual of its own, so nothing else would ever instantiate the
    // singleton. A binding that reads it is what brings the three IdleMonitors up — and it has to
    // be a property, not a second Component.onCompleted: this root already has one, and QML rejects
    // the whole file for a repeated handler rather than merging them.

    // Startup splash — the curtain over the shell's own start (once per session; SplashState makes
    // that call). The surfaces only exist while it plays, so it costs nothing afterwards.
    Variants {
        model: SplashState.active ? Quickshell.screens : []
        delegate: Splash { required property var modelData; screen: modelData }
    }

    // Native lockscreen: a single WlSessionLock that manages one surface per monitor itself (not a
    // per-screen Variants). Engaged via the `lock` IPC / LockState.locked.
    Loader {
        active: VtlConfig.componentEnabled("lock")
        sourceComponent: Component { Lock { } }
    }

    // Taskbar OSD: a strip of open windows (Settings → Taskbar), one per screen. TaskbarReserve is the
    // invisible space-reserving surface for the "like bar" layer.
    Variants { model: VtlConfig.componentEnabled("taskbar") ? root.bootScreens : []; delegate: Taskbar        { required property var modelData; screen: modelData } }
    Variants { model: VtlConfig.componentEnabled("taskbar") ? root.bootScreens : []; delegate: TaskbarReserve { required property var modelData; screen: modelData } }

    // Window tags: a name chip on the edge of every window, fading out on cursor approach.
    Variants { model: VtlConfig.componentEnabled("windowtags") ? root.bootScreens : []; delegate: WindowTags     { required property var modelData; screen: modelData } }

    // OSD: one per screen, shows on the focused monitor (volume / brightness)
    Variants {
        model: VtlConfig.componentEnabled("osd") ? root.late(1) : []
        delegate: Osd {
            required property var modelData
            screen: modelData
        }
    }

    // Module glides: a pill that slides out of the bar from a module. Volume % (hover), performance
    // stats (hover), system-tray icons (hover), user session actions (click). One of each per screen.
    Variants {
        model: root.late(4)
        delegate: VolumeGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(6)
        delegate: PerformanceGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(6)
        delegate: UserGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(7)
        delegate: NetworkGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(7)
        delegate: BtGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(8)
        delegate: TrayGlide { required property var modelData; screen: modelData }
    }
    // The file-transfer card. Not gated on the phone module being placed in the bar: a transfer can
    // only start from the popout, and if you got that far you want to see where the file went.
    Variants {
        model: root.late(8)
        delegate: ShareGlide { required property var modelData; screen: modelData }
    }
    // ── Two surfaces that must NOT exist until they are wanted ───────────────────
    //
    // Both are full-screen layer surfaces, and until now both were built at login and simply kept
    // invisible. That put two new always-present surfaces into the session — the only thing about
    // startup this repo changed — and the session started wedging its display pipeline
    // (amdgpu: `[CRTC:369:crtc-0] flip_done timed out`, a freeze hard enough that a VT switch will
    // not save you).
    //
    // An invisible window is not a free window: it is a wl_surface the compositor tracks, composites
    // over and considers on every frame. A backdrop for the settings panel and a picker for
    // SUPER+SHIFT+S have no business being alive while you log in. The Loader builds them on the
    // first open and drops them on close — the same shape NotifService uses for its server, for the
    // same reason.
    Loader {
        active: UiState.menuFloating || dimLinger.running
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens
                delegate: SettingsDim { required property var modelData; screen: modelData }
            }
        }
    }
    Loader {
        // The LINGER matters. Closing the picker is something the picker itself does, from inside a
        // click handler — and tearing an object down while its own handler is still on the stack is
        // how you turn a screenshot into a crash. So the surface unmaps immediately (the overlay
        // binds `visible` to shotOpen) while the OBJECT outlives the handler that closed it.
        // It also keeps the overlay alive across the settle window, so the fade is finished and the
        // surface is gone before grim looks at the screen.
        active: UiState.shotOpen || shotLinger.running
        sourceComponent: Component {
            Variants {
                model: Quickshell.screens
                delegate: ShotOverlay { required property var modelData; screen: modelData }
            }
        }
    }
    Timer { id: shotLinger; interval: 320 }
    Connections {
        target: UiState
        function onShotOpenChanged() { if (!UiState.shotOpen) shotLinger.restart() }
    }
    Timer { id: dimLinger; interval: 320 }
    Connections {
        target: UiState
        function onMenuFloatingChanged() { if (!UiState.menuFloating) dimLinger.restart() }
    }

    // The capture itself. No window, no surface — so the picker above is free to be destroyed the
    // moment it closes, which is what lets it stay out of the login path entirely.
    ShotRunner { }
    Variants {
        model: root.late(4)
        delegate: WorkspaceGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(5)
        delegate: NotifPeekGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(5)
        delegate: UpdatesGlide { required property var modelData; screen: modelData }
    }

    // Module flyouts (hover/IPC-grown panels): one of each per screen.
    Variants {
        model: root.late(9)
        delegate: PerformanceMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(9)
        delegate: VolumeMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(11)
        delegate: PhoneMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(11)
        delegate: MprisMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(10)
        delegate: BluetoothMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(10)
        delegate: NetworkMenu { required property var modelData; screen: modelData }
    }
    // One generic GroupMenu per screen serves every dynamic "group:<n>" module (only one flyout
    // is ever open, so it re-binds to whichever group opened — no per-instance windows needed).
    Variants {
        model: root.late(12)
        delegate: GroupMenu { required property var modelData; screen: modelData }
    }
    // Shell-styled tray context menu (one overlay per screen; renders whichever item's menu opened).
    Variants {
        model: root.late(12)
        delegate: TrayMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(16)
        delegate: WallpaperQuick { required property var modelData; screen: modelData }
    }
    // The same picker's full-screen shape (Settings → Wallpaper → Quickselect → Style = Gallery).
    // Both surfaces exist on every screen; UiState.openWallpaperQuick() opens exactly one of them.
    Variants {
        model: root.late(16)
        delegate: WallpaperGallery { required property var modelData; screen: modelData }
    }
    // The THEME picker, in the same two shapes and by the same rule: both surfaces exist on every
    // screen, UiState.openThemePicker() opens exactly one of them (Settings → Style → Picker).
    Variants {
        model: root.late(16)
        delegate: ThemeQuick { required property var modelData; screen: modelData }
    }
    Variants {
        model: root.late(16)
        delegate: ThemeGallery { required property var modelData; screen: modelData }
    }
    Variants {
        model: VtlConfig.componentEnabled("calendar") ? root.late(13) : []
        delegate: CalendarMenu { required property var modelData; screen: modelData }
    }

    Variants {
        model: root.late(13)
        delegate: LayoutMenu { required property var modelData; screen: modelData }
    }

    // The round-two module popouts. Each is created only while its module is actually placed
    // somewhere — a per-screen surface for a panel nobody can open is a window for nothing.
    Variants {
        model: Popouts.inUse("weather") ? root.late(13) : []
        delegate: WeatherMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: Popouts.inUse("mic") ? root.late(13) : []
        delegate: MicMenu { required property var modelData; screen: modelData }
    }
    Variants {
        model: VtlConfig.barModulePlacedAnywhere("microphone") ? root.late(13) : []
        delegate: MicGlide { required property var modelData; screen: modelData }
    }
    Variants {
        model: Popouts.inUse("keyboard") ? root.late(13) : []
        delegate: KeyboardMenu { required property var modelData; screen: modelData }
    }

    // FancyZones: input-transparent zone fields per screen, shown while a float is dragged.
    Variants {
        model: VtlConfig.componentEnabled("zones") ? root.late(17) : []
        delegate: ZoneOverlay { required property var modelData; screen: modelData }
    }

    // Dashboard editor: a standalone window over everything, opened from the settings home page's
    // pencil (UiState.dashEditOpen). Shows on the monitor the menu was on; the menu hides meanwhile.
    Variants {
        model: root.late(17)
        delegate: DashEditor { required property var modelData; screen: modelData }
    }

    // Keybind cheatsheet: one per screen, shown via UiState.keybindContext
    Variants {
        model: VtlConfig.componentEnabled("keybind") ? root.late(18) : []
        delegate: KeybindHelp { required property var modelData; screen: modelData }
    }

    // Notifications: toast popups + the history centre, one per screen (focused monitor shows them)
    Variants {
        model: VtlConfig.componentEnabled("notifications") ? root.late(1) : []
        delegate: NotifPopups { required property var modelData; screen: modelData }
    }
    Variants {
        model: VtlConfig.componentEnabled("notifications") ? root.late(4) : []
        delegate: NotifCenter { required property var modelData; screen: modelData }
    }


    // The theme's two material layers, per monitor. LAST in this file on purpose: within one
    // layer-shell layer the stacking follows creation order, so a material declared earlier ends up
    // under the launcher and the settings panel — which is exactly what it must not be.
    //
    // The model is EMPTY unless the theme actually declares one, because an invisible layer surface
    // is not a free one; see the note above the settings backdrop for what a pair of always-present
    // full-screen surfaces did to this session.
    Variants {
        model: Theme.hasComponent("backdrop") ? root.bootScreens : []
        delegate: ThemeMaterial { required property var modelData; screen: modelData; surface: "backdrop" }
    }
    Variants {
        model: Theme.hasComponent("material") ? root.bootScreens : []
        delegate: ThemeMaterial { required property var modelData; screen: modelData; surface: "material" }
    }
}
