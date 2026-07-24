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
        { icon: "󰤄", label: "Suspend",  cmd: "systemctl suspend" },
        { icon: "󰗽", label: "Logout",   cmd: "hyprctl dispatch exit" },
        { icon: "󰜉", label: "Reboot",   cmd: "systemctl reboot" },
        { icon: "󰐥", label: "Shutdown", cmd: "systemctl poweroff" }
    ]

    property string openDropdown:   ""      // key of the currently open module dropdown
    // A surface can request the settings menu to open on a specific section (e.g. the calendar
    // flyout's gear → "calendar"): set this, then openDropdown = "vuture-icon". Settings clears it.
    property string settingsRequestSection: ""
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
}
