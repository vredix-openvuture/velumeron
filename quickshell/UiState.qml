pragma Singleton
import QtQuick

QtObject {
    id: ui

    // Canonical session actions — ONE list shared by the session overlay (Super+Ctrl+Q), the bar's
    // User-module glide and the settings home hub, so their icons/commands/order never diverge.
    readonly property var sessionActions: [
        { icon: "󰌾", label: "Lock",     cmd: "loginctl lock-session" },
        // Lock via logind: loginctl lock-session → hypridle lock_cmd → the native quickshell lock.
        // (Locking through logind, not a direct launch, also keeps the before_sleep_cmd +
        // inhibit_sleep=3 suspend sequencing consistent.)
        // Suspend goes through suspend.sh: it locks and WAITS until the lockscreen has actually
        // drawn before pulling the plug (inhibit_sleep=3 only waits for the lock surfaces to
        // exist, not to paint — the machine used to go down mid-reveal). Falls back to a bare
        // suspend if the script is missing, so this can never become a no-op.
        { icon: "󰤄", label: "Suspend",  cmd: "\"$VELUMERON_DIR/assets/scripts/suspend.sh\" || systemctl suspend" },
        { icon: "󰗽", label: "Logout",   cmd: "hyprctl dispatch exit" },
        { icon: "󰜉", label: "Reboot",   cmd: "systemctl reboot" },
        { icon: "󰐥", label: "Shutdown", cmd: "systemctl poweroff" }
    ]

    property string openDropdown:   ""      // key of the currently open module dropdown
    // A surface can request the settings menu to open on a specific section (e.g. the calendar
    // flyout's gear → "calendar"): set this, then openDropdown = "vuture-icon". Settings clears it.
    property string settingsRequestSection: ""
    // Double right-click on a bar module jumps straight to ITS customization page: set this
    // together with settingsRequestSection = "bar", then open the menu. BarSection consumes
    // and clears it, so it can never re-open the page on a later, unrelated visit.
    property string barCustomizeRequest: ""
    // Bumped after the tiling layout changed (LayoutMenu / LayoutsSection) — every LayoutSwitcher
    // module re-polls general:layout on change.
    property int layoutPollSerial: 0
    property bool   notifCenterOpen: false  // notification centre panel (the bar's bell)
    property bool   launcherOpen:    false  // application launcher (Super+Space / `launcher` IPC)
    property string launcherMon:     ""     // monitor the launcher latched to when opened

    // rofi successors — each latches to the monitor focused at open time (like the launcher).
    property bool   clipboardOpen:      false  // clipboard history (Super+V / `clipboard` IPC)
    property string clipboardMon:       ""
    property bool   windowSwitcherOpen: false  // Alt-Tab window switcher (Super+Tab / `window` IPC)
    property string windowSwitcherMon:  ""
    // The overlay grabs the keyboard and handles input itself; this counter is only a fallback for the
    // case where the grab doesn't suppress the Super+Tab bind (it re-fires `window open` → advance).
    property int    windowSwitcherNext:    0
    property bool   layoutSwitcherOpen: false  // layout quick-switcher (Super+Alt+Tab / `layoutswitch` IPC)
    property string layoutSwitcherMon:  ""
    // Same fallback-advance counter as the window switcher's (the bind re-fires `layoutswitch open`).
    property int    layoutSwitcherNext:    0
    property bool   sessionOpen:        false  // power / session menu (Super+Ctrl+Q / `session` IPC)
    property string sessionMon:         ""
    property bool   paletteEditorOpen:  false  // build-your-own palette editor (Settings → Style → Colours)
    property string paletteEditorMon:   ""
    // When set, the editor opens loaded with THIS saved palette for editing ({ colors, name });
    // null = start fresh from the live palette. Cleared by the editor once it has read it.
    property var    paletteEditorSeed:  null

    // ── Lockscreen build-your-own editor (Settings → Lockscreen → Build your own) ──────────────
    // Full-screen overlay that renders a live LockContent preview (no WlSessionLock/PAM) beside the
    // controls. seed = { id, source, name, settings } to edit an existing preset; null = fresh from
    // the live VtlConfig.lock* values. Cleared by the editor once read.
    property bool   lockEditorOpen: false
    property string lockEditorMon:  ""
    property var    lockEditorSeed: null

    // Keybind cheatsheet overlay context: "" = closed, "all" = full reference,
    // "window" | "apps" | "system" = that submap's binds. Driven by the `keybind` IPC.
    property string keybindContext: ""

    // True while a native dialog (e.g. the zenity folder picker) is open: the
    // corner menu drops its full-screen input grab + keyboard focus so the dialog
    // underneath is interactive, but stays visually open.
    property bool   pickerOpen:     false
    // The settings menu has left the bar and is floating (nav mode "float", off Home). Published
    // here because the BACKDROP is a separate layer surface — it has to be, or Hyprland's global
    // blur rule frosts the whole screen behind it (ignore_alpha is 0.1 and a dim is far above it).
    property bool   menuFloating:   false
    // A dialog belonging to ANOTHER process is up (the file chooser behind "Send files"). Distinct
    // from pickerOpen, which is an in-shell picker that only needs the keyboard: a foreign window
    // needs the panel out of its way entirely, and hiding the settings menu for a colour picker
    // that lives INSIDE it would be nonsense.
    property bool   externalPicker: false

    // Where the corner menu should attach: the edge the vuture-icon sits on, and the
    // icon's position along that edge (window/screen coords). Set by VutureIcon on open.
    property string menuEdge:       "top"   // top | left | bottom | right
    property string menuGroup:      "start" // start | center | end (shapes the L / fluid form)
    property real   menuStart:      0       // along-edge coordinate of the icon centre
    // Monitor the corner menu opened on — latched at open so the menu stays put even if the focus
    // moves to another monitor (it does NOT follow the focus). Set by Settings.qml on open.
    property string menuMon:        ""
    // Same idea for the notification centre — latched to the bell's monitor at open (NotifTray), so
    // the centre stays where it was opened instead of following the focused monitor.
    property string notifMon:       ""

    // ── Dashboard editor (the settings home page, rearranged) ─────────────────
    // A standalone floating window over everything: arranging a 500 px panel from inside that same
    // panel left no room for the module list. Opening it HIDES the settings menu (the editor joins
    // the draft-holding class in _closeMenusExcept — it closes others, nothing auto-closes it) and
    // Done brings the menu back exactly where it was.
    property bool   dashEditOpen: false
    property string dashEditMon:  ""
    property string _dashEditReturn: ""
    // Measured viewport of the live dashboard, published by HomeHub — the editor previews at the
    // real size instead of re-deriving it from menu %, rail, paddings and the session bar.
    // Pixels only — the editor derives the row count from these with the hub's own formula, so
    // changing the row height in the editor can't leave a stale page size behind.
    property real   dashWidth:    0
    property real   dashHeight:   0
    function openDashEdit(mon) {
        ui._dashEditReturn = ui.openDropdown
        ui.dashEditMon  = mon
        ui.dashEditOpen = true
    }
    function closeDashEdit() {
        var back = ui._dashEditReturn
        ui._dashEditReturn = ""
        ui.dashEditOpen = false
        if (back !== "") { ui.menuMon = ui.dashEditMon; ui.openDropdown = back }
    }

    // Anchor of the placed wallpaper-switcher module on the focused monitor — so the keybind opens the
    // wallpaper quick-menu from the module's position (like a click), falling back to the configured
    // quick position when no module is placed. Published by WallpaperSwitcher.qml.
    property string wpSwitcherMon:   ""
    property string wpSwitcherEdge:  "top"
    property string wpSwitcherGroup: "start"
    property real   wpSwitcherX:     0
    property real   wpSwitcherY:     0

    // ── Corner-menu morph progress ────────────────────────────────────────────
    // 0 = fully closed, 1 = fully open. Animated centrally so the menu panel (CornerMenu)
    // and the L-bar inner border opening (LBar) grow out of the corner in lockstep.
    readonly property bool cornerMenuOpen: openDropdown === "vuture-icon"
    // Elastic "soft-mass" reveal: springs PAST 1 on open and rings back, so the panel
    // overshoots its size and its free edges bow out (Settings.qml drives the bulge off
    // `reveal − target`). Tuned in the _lab/ElasticShapeTest.qml prototype.
    property real menuReveal: cornerMenuOpen ? 1.0 : 0.0
    Behavior on menuReveal {
        SpringAnimation { spring: VtlConfig.elasticSpring; damping: VtlConfig.elasticDamping; epsilon: 0.003 }
    }

    // ── Notification-centre anchor + morph ──────────────────────────────────────
    // The notiftray bell publishes its edge / group / along-edge position so the centre grows out
    // of the bar from the bell, exactly like the vuture-icon grows the corner menu. notifReveal
    // animates the grow/shrink morph in lockstep (driven by notifCenterOpen).
    property string notifEdge:   "top"   // top | left | bottom | right
    property string notifGroup:  "end"   // start | center | end (shapes the L)
    property real   notifStart:  0       // along-edge coordinate of the bell centre
    property real notifReveal: notifCenterOpen ? 1.0 : 0.0
    Behavior on notifReveal {
        SpringAnimation { spring: VtlConfig.elasticSpring; damping: VtlConfig.elasticDamping; epsilon: 0.003 }
    }

    // ── OSD trigger ─────────────────────────────────────────────────────────────
    // Poked by the `osd` IPC handler (shell.qml). Each Osd window reacts to osdSerial
    // changing (so re-triggering the same kind still re-shows). Volume reads the live
    // sink; brightness uses osdValue (percent passed from the brightness script).
    property string osdKind:   "volume"   // "volume" | "brightness"
    property int    osdValue:  0           // brightness percent (0–100)
    property int    osdSerial: 0           // bump to (re)show
    function osdShow(kind, value) { osdKind = kind; osdValue = value; osdSerial++ }

    // ── Volume hover-glide ────────────────────────────────────────────────────
    // The Volume bar module publishes its hover state + screen anchor (screen-local coords);
    // the per-screen VolumeGlide overlay shows the percentage gliding out of the module toward
    // the monitor centre. volumeMon gates which screen's overlay reacts.
    property bool   volumeHover:   false
    property real   volumeAnchorX: 0
    property real   volumeAnchorY: 0
    property string volumeEdge:    "top"   // bar edge the module sits on → glide direction
    property int    volumeLevel:   0       // 0..100
    property bool   volumeMuted:   false
    property string volumeMon:     ""      // monitor name the module lives on

    // ── Module glides (same out-of-the-bar pill as volume) ──────────────────────
    // The Performance / User / NotifTray modules publish hover (or click-open) + screen anchor +
    // edge here; the per-screen *Glide overlays show their content gliding out of the bar. Perf and
    // tray on hover, user on click. `*Mon` gates which screen's overlay reacts.
    property bool   perfHover:   false     // performance: stats glide (hover)
    property real   perfAnchorX: 0
    property real   perfAnchorY: 0
    property string perfEdge:    "top"
    property string perfMon:     ""
    property string perfStats:   ""        // formatted "cpu° mem gpu" string published by the module

    property bool   userHover:     false   // user: session actions glide (hover)
    property real   userAnchorX:   0
    property real   userAnchorY:   0
    property string userEdge:      "top"
    property string userMon:       ""

    property bool   netHover:   false      // network: down/up throughput glide (hover)
    property real   netAnchorX: 0
    property real   netAnchorY: 0
    property string netEdge:    "top"
    property string netMon:     ""
    property string netStats:   ""         // "󰇚 1.2 MB/s   󰕒 80 KB/s"

    property bool   btHover:    false      // bluetooth: active-connection glide (hover)
    property real   btAnchorX:  0
    property real   btAnchorY:  0
    property string btEdge:     "top"
    property string btMon:      ""
    property string btStatus:   ""         // connected device names for the hover glide

    property bool   wsHover:    false      // workspaces: windows-on-this-workspace preview glide (hover)
    property real   wsAnchorX:  0
    property real   wsAnchorY:  0
    property string wsEdge:     "top"
    property string wsMon:      ""
    property int    wsPreviewId: 0         // Hyprland id of the workspace being hovered

    property bool   trayHover:   false     // tray (collapsed): the SNI icons glide (hover)
    property real   trayAnchorX: 0
    property real   trayAnchorY: 0
    property string trayEdge:    "top"
    property string trayMon:     ""

    property bool   npkHover:   false      // notiftray: recent-notifications peek glide (hover)
    property real   npkAnchorX: 0
    property real   npkAnchorY: 0
    property string npkEdge:    "top"
    property string npkMon:     ""

    property bool   updHover:   false      // updates: available-package list glide (hover)
    property real   updAnchorX: 0
    property real   updAnchorY: 0
    property string updEdge:    "top"
    property string updMon:     ""
    property var    updList:    []         // ["pkg 1.0 -> 1.1", …] published by the module (capped)
    property int    updTotal:   0          // true total (list may be capped) → drives "+N weitere"

    // ── Module flyouts (click-grown panels that dock into the bar: Volume routing, Mpris player) ──
    // A bar module publishes its id + screen anchor (screen-local coords) + edge on click; the
    // matching per-screen <X>Menu overlay grows a panel out of the bar at that anchor. Only one
    // flyout is open at a time; click-outside / Escape / re-click closes it.
    property string flyout:        ""    // "" | "volume" | "mpris" | … | "group:<n>" (dynamic group instances)
    property real   flyoutAnchorX: 0
    property real   flyoutAnchorY: 0
    property string flyoutEdge:    "top"
    property string flyoutGroup:   "start"  // start | center | end → free-tab vs corner-merge shape
    property string flyoutMon:     ""
    // Open the flyout at an anchor (or close it if the same one is already open). `group` (the
    // module's bar group) shapes the dock outline: start/end merge into the corner, center is a tab.
    function toggleFlyout(id, ax, ay, edge, group, mon) {
        if (flyout === id && flyoutMon === mon) { flyout = ""; return }
        flyout = id; flyoutAnchorX = ax; flyoutAnchorY = ay
        flyoutEdge = edge; flyoutGroup = group; flyoutMon = mon
    }

    // ── Tray context menu (custom, shell-styled — replaces the native QMenu) ────────────────────
    // A tray icon publishes the QsMenuHandle to display + its screen anchor + bar edge on right-click;
    // the per-screen TrayMenu overlay renders it with the shell's own tokens. trayMenuMon gates the
    // screen; only one is ever open.
    property var    trayMenuHandle:  null      // QsMenuHandle to show (null = none)
    property bool   trayMenuOpen:    false
    property real   trayMenuAnchorX: 0         // icon centre, screen coords (along-edge placement)
    property real   trayMenuAnchorY: 0
    property string trayMenuEdge:    "top"
    property string trayMenuMon:     ""
    function openTrayMenu(handle, ax, ay, edge, mon) {
        trayMenuHandle = handle; trayMenuAnchorX = ax; trayMenuAnchorY = ay
        trayMenuEdge = edge; trayMenuMon = mon; trayMenuOpen = true
    }
    function closeTrayMenu() { trayMenuOpen = false }

    // Map a wallpaper-quickselect position ("top-center", "center-left", "bottom-right", …) on a
    // monitor (mw × mh) to a flyout anchor { edge, group, ax, ay } the grow-from-bar Flyout uses.
    // THE answer to "where does the wallpaper quick-menu grow from" — used by every way of opening
    // it: the bar module, Super+Alt+Space (IPC), a hot corner, a dashboard tile. It used to be
    // answered in three places that disagreed: the module grew from itself, the IPC handler
    // preferred the module and fell back to the configured position, and the action path always
    // took the configured position — so the same panel appeared somewhere else depending on how you
    // asked for it. Rule: grow from the switcher module when one sits on this monitor's bar,
    // otherwise from Settings → Wallpaper → Quickselect position.
    function openWallpaperQuick(monName, mw, mh) {
        if (ui.wpSwitcherMon === monName && monName !== "") {
            ui.toggleFlyout("wallpaper", ui.wpSwitcherX, ui.wpSwitcherY,
                            ui.wpSwitcherEdge, ui.wpSwitcherGroup, monName)
            return
        }
        var a = ui.wallpaperAnchor(mw, mh, VtlConfig.wallpaperQuickPos)
        ui.toggleFlyout("wallpaper", a.ax, a.ay, a.edge, a.group, monName)
    }

    function wallpaperAnchor(mw, mh, pos) {
        var p = ("" + pos).split("-")
        var v = p[0], h = p[1] || "center"
        if (v === "top" || v === "bottom")
            return { edge: v, group: (h === "left" ? "start" : h === "right" ? "end" : "center"),
                     ax: (h === "left" ? 0 : h === "right" ? mw : mw / 2), ay: (v === "top" ? 0 : mh) }
        // centre row → a side edge
        var e = (h === "right") ? "right" : "left"
        return { edge: e, group: "center", ax: (e === "left" ? 0 : mw), ay: mh / 2 }
    }

    // ── One menu at a time ──────────────────────────────────────────────────────────────────────
    // Every click-opened surface below is mutually exclusive: opening one closes whatever else was
    // open. They are separate windows with separate input regions, and the bar stays clickable
    // while a menu is up, so they stacked far too easily — open the main menu, click the bell, and
    // both sat there, the older one only dismissable through its own dim area.
    //
    // Centralised here instead of at the ~40 call sites that flip these flags: a new surface only
    // has to be listed in _closeMenusExcept(). The handlers only ever CLOSE, and each close is
    // guarded by "is it actually open", so one assignment can never loop back through another.
    //
    // Deliberately NOT members: the hover glides and notification popups (transient, they belong to
    // whatever is underneath), and the palette / lockscreen editors — those hold unsaved drafts, so
    // they close everything else when they open but are never auto-closed themselves.
    // `keep` is the key of the surface that just opened; "" closes the whole set.
    function _closeMenusExcept(keep) {
        if (keep !== "dropdown"  && ui.openDropdown       !== "") ui.openDropdown       = ""
        if (keep !== "flyout"    && ui.flyout             !== "") ui.flyout             = ""
        if (keep !== "notif"     && ui.notifCenterOpen)           ui.notifCenterOpen    = false
        if (keep !== "launcher"  && ui.launcherOpen)              ui.launcherOpen       = false
        if (keep !== "clipboard" && ui.clipboardOpen)             ui.clipboardOpen      = false
        if (keep !== "window"    && ui.windowSwitcherOpen)        ui.windowSwitcherOpen = false
        if (keep !== "layout"    && ui.layoutSwitcherOpen)        ui.layoutSwitcherOpen = false
        if (keep !== "session"   && ui.sessionOpen)               ui.sessionOpen        = false
        if (keep !== "keybind"   && ui.keybindContext     !== "") ui.keybindContext     = ""
        if (keep !== "tray"      && ui.trayMenuOpen)              ui.trayMenuOpen       = false
    }
    onOpenDropdownChanged:       if (ui.openDropdown   !== "") ui._closeMenusExcept("dropdown")
    onFlyoutChanged:             if (ui.flyout         !== "") ui._closeMenusExcept("flyout")
    onNotifCenterOpenChanged:    if (ui.notifCenterOpen)       ui._closeMenusExcept("notif")
    onLauncherOpenChanged:       if (ui.launcherOpen)          ui._closeMenusExcept("launcher")
    onClipboardOpenChanged:      if (ui.clipboardOpen)         ui._closeMenusExcept("clipboard")
    onWindowSwitcherOpenChanged: if (ui.windowSwitcherOpen)     ui._closeMenusExcept("window")
    onLayoutSwitcherOpenChanged: if (ui.layoutSwitcherOpen)     ui._closeMenusExcept("layout")
    onSessionOpenChanged:        if (ui.sessionOpen)           ui._closeMenusExcept("session")
    onDashEditOpenChanged:       if (ui.dashEditOpen)          ui._closeMenusExcept("dashedit")
    onKeybindContextChanged:     if (ui.keybindContext !== "") ui._closeMenusExcept("keybind")
    onTrayMenuOpenChanged:       if (ui.trayMenuOpen)          ui._closeMenusExcept("tray")
    // The editors take over the whole screen — clear the set, but stay out of it themselves.
    onPaletteEditorOpenChanged:  if (ui.paletteEditorOpen)     ui._closeMenusExcept("")
    onLockEditorOpenChanged:     if (ui.lockEditorOpen)        ui._closeMenusExcept("")
}
