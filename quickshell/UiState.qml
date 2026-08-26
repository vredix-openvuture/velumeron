pragma Singleton
import QtQuick

QtObject {
    id: ui

    // Canonical session actions — ONE list shared by the session overlay (Super+Ctrl+Q), the bar's
    // User-module glide and the settings home hub, so their icons/commands/order never diverge.
    readonly property var sessionActions: [
        // Lock straight through the shell's own IPC, which is also what SUPER+CTRL+L runs
        // (hypr.lua `on_lock`) and what `velumeron --lock` runs. ONE path for every manual lock.
        //
        // It used to be `loginctl lock-session`, which reaches the same lock the long way round:
        // logind emits Lock → hypridle runs its lock_cmd → that pokes this very IPC. Every step is
        // a process that has to be alive, and if hypridle is not, the button does nothing at all,
        // silently. A lock control is the wrong place for that failure mode.
        //
        // Nothing is lost by shortening it: hypridle still owns the idle lock and before_sleep_cmd,
        // so the inhibit_sleep=3 sequencing that keeps the machine from sleeping unlocked runs
        // exactly as before. The one thing the short path skips is logind's locked-hint, which only
        // matters to other software asking logind whether this session is locked.
        { icon: "󰌾", label: "Lock",     cmd: "qs -p \"$VELUMERON_DIR/quickshell\" ipc call lock lock" },
        // Suspend goes through suspend.sh: it locks and WAITS until the lockscreen has actually
        // drawn before pulling the plug (inhibit_sleep=3 only waits for the lock surfaces to
        // exist, not to paint — the machine used to go down mid-reveal). Falls back to a bare
        // suspend if the script is missing, so this can never become a no-op.
        { icon: "󰤄", label: "Suspend",  cmd: "\"$VELUMERON_DIR/assets/scripts/suspend.sh\" || systemctl suspend" },
        // The three that end the session play their sound HERE rather than through SoundService,
        // and block on it: each of these kills the shell, so a sound started inside it would be cut
        // off mid-note. play-sound.sh waits for the file (capped, so it can never look like a hang)
        // and stays silent if sounds are off — the check lives in the script, not in this string.
        // The cap is passed explicitly: the pack's logout runs 4.4 s, and the script's default of 4
        // would cut it off outright. Sized with room for paplay's own start-up on top.
        { icon: "󰗽", label: "Logout",   cmd: "\"$VELUMERON_DIR/assets/scripts/play-sound.sh\" logout 6; hyprctl dispatch exit" },
        { icon: "󰜉", label: "Reboot",   cmd: "\"$VELUMERON_DIR/assets/scripts/play-sound.sh\" logout 6; systemctl reboot" },
        { icon: "󰐥", label: "Shutdown", cmd: "\"$VELUMERON_DIR/assets/scripts/play-sound.sh\" logout 6; systemctl poweroff" }
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
    // Windowed ⇄ fullscreen for THIS opening only. The launcher seeds it from launcher_fullscreen
    // every time it opens (Launcher.qml), so the rail's Fullscreen button is a look at the big grid
    // and back, never a silent edit of the setting.
    property bool   launcherFs:      false

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
    // Screensaver — one flag for every monitor: it is a whole-desk state, not a per-screen one.
    // Set by IdleService when the seat goes idle and cleared the moment anything happens.
    property bool   screensaverOn:  false
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
    // The screenshot picker is up (SUPER+SHIFT+S → the `screenshot` IPC).
    property bool   shotOpen:       false
    // A capture asked for WITHOUT the picker (IPC / a direct bind). The overlay watches this,
    // fires that mode and clears it. Also the only way to exercise the capture path without a
    // mouse, which is what two rounds of blind guessing cost.
    property string shotFire:       ""
    // Read while the picker is open, consumed by ShotRunner after it closes. They live here rather
    // than in the overlay because the overlay is now destroyed on close — see ShotRunner.qml.
    property string shotGeom:       ""
    property string shotMon:        ""
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
    // The size the menu currently HAS, as a % of its monitor — what the steppers on the Style page
    // start from when they leave "Auto", so the first step lands next to the current size instead
    // of teleporting the panel to some default.
    property int    menuPctDockW:  0
    property int    menuPctDockH:  0
    property int    menuPctFloatW: 0
    property int    menuPctFloatH: 0
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

    // The wallpaper picker's OTHER shape (Settings → Wallpaper → Quickselect → Style = Gallery): a
    // full-screen coverflow instead of a panel on the bar. It is the same picker, so it is never
    // open alongside the popout — openWallpaperQuick() below routes to one or the other.
    property bool   wallpaperGalleryOpen: false
    property string wallpaperGalleryMon:  ""

    // ── Corner-menu morph progress ────────────────────────────────────────────
    // 0 = fully closed, 1 = fully open. Animated centrally so the menu panel (CornerMenu)
    // and the L-bar inner border opening (LBar) grow out of the corner in lockstep.
    readonly property bool cornerMenuOpen: openDropdown === "vuture-icon"
    // Elastic "soft-mass" reveal: springs PAST 1 on open and rings back, so the panel
    // overshoots its size and its free edges bow out (Settings.qml drives the bulge off
    // `reveal − target`). Tuned in the _lab/ElasticShapeTest.qml prototype.
    property real menuReveal: cornerMenuOpen ? 1.0 : 0.0
    Behavior on menuReveal {
        id: menuRevealB
        // Direction from the Behavior's own targetValue, NOT the surface's open flag:
        // the flag flips in the same signal that starts the animation, and the animation
        // latched the OLD spring — opening ran on the closing spring and vice versa.
        SpringAnimation {
            spring:  Style.springFor(menuRevealB.targetValue > 0.5)
            damping: Style.dampingFor(menuRevealB.targetValue > 0.5)
            epsilon: 0.003
        }
    }

    // ── Where the bar's inner face ACTUALLY is ──────────────────────────────────────────────────
    // Published by Bar.qml from the very numbers it draws with, and read by everything that docks
    // onto it. Computing it a second time from the config is what left the launcher hanging 20 px
    // off a bottom edge: that edge renders at half thickness, and the two sides disagreed about
    // whether it counted as empty (the minimal-secondary-bar rule can also empty an edge without
    // the config saying so). Reading the drawn value cannot disagree with the drawing.
    //
    // { "<monitor>": { top, bottom, left, right } } — pixels in from each screen edge, 0 = no bar.
    property var barInner: ({})
    function setBarInner(mon, t, b, l, r) {
        if (!mon) return
        var cur = barInner[mon]
        if (cur && cur.top === t && cur.bottom === b && cur.left === l && cur.right === r) return
        var m = {}
        for (var k in barInner) m[k] = barInner[k]
        m[mon] = { top: t, bottom: b, left: l, right: r }
        barInner = m
    }
    // Falls back to the config-derived value until the bar for that monitor has reported in (first
    // frame, or a monitor with no bar surface at all).
    function barInnerFor(edge, mon) {
        var e = barInner[mon]
        return (e && e[edge] !== undefined) ? e[edge] : VtlConfig.barInsetFor(edge, mon)
    }

    // ── Where a strip's MODULES actually sit ─────────────────────────────────────────────────────
    // A popout that merges into a bar it does not grow from would otherwise lie across whatever is
    // in that strip. Knowing the edge is "active" is not enough — an empty strip is pure chrome and
    // merging into it is exactly right, a strip carrying modules is CONTENT and nothing may cover
    // it. So each module group reports the stretch it occupies along its edge, keyed by owner like
    // the border gaps, and a popout can ask whether the piece of strip it wants is free.
    // from/to are screen coordinates ALONG the edge: x for top/bottom, y for left/right.
    property var barModules: ({})
    function setBarModuleSpan(id, mon, edge, from, to) {
        if (!id || !mon) return
        if (to - from < 0.5) { clearBarModuleSpan(id); return }
        var cur = barModules[id]
        if (cur && cur.mon === mon && cur.edge === edge
                && Math.abs(cur.from - from) < 0.25 && Math.abs(cur.to - to) < 0.25) return
        var m = {}
        for (var k in barModules) m[k] = barModules[k]
        m[id] = { mon: mon, edge: edge, from: from, to: to }
        barModules = m
    }
    function clearBarModuleSpan(id) {
        if (!(id in barModules)) return
        var m = {}
        for (var k in barModules) if (k !== id) m[k] = barModules[k]
        barModules = m
    }
    // Is any module on `edge` inside [from, to]? Reading the whole map keeps this a live binding.
    function barModulesIn(mon, edge, from, to) {
        var m = barModules
        for (var k in m) {
            var c = m[k]
            if (c.mon === mon && c.edge === edge && c.to > from && c.from < to) return true
        }
        return false
    }

    // ── The gap a popout tears in the bar's border ──────────────────────────────────────────────
    // A panel growing out of the bar used to simply lie ON TOP of the bar's inner border and hide
    // it under a 2 px seam. That works while the panel is big — and fails in the one moment you
    // notice: on the way out, the panel uncovers the bar's border a slice at a time, so a line you
    // had forgotten about reappears from under the closing menu.
    //
    // Instead the bar now LEAVES A GAP in its own border exactly where the panel meets it, and the
    // panel's outline spans that gap. The two are one continuous line: opening pulls a bulge out of
    // the bar's edge, closing lets it snap back flat. Nothing is ever drawn over anything.
    //
    // One slot is enough — only one surface grows out of the bar at a time (menu, flyout or
    // notification centre; opening any of them closes the others). `from`/`to` are screen
    // coordinates ALONG the docking edge: x for a top/bottom bar, y for left/right.
    // KEYED BY OWNER, one claim per surface — id → { mon, edge, from, to }. The first version was
    // a single shared slot, and that is what the "ghost border" turned out to be: two surfaces
    // animating at once (a menu closing while the launcher opened) would overwrite or clear each
    // other's claim, either drawing the bar's line through an open panel or leaving a dead gap —
    // no border, plus the 2 px fill notch as a groove — across an edge with nothing in front of
    // it. Now a claim can only be replaced or removed by its own id, and the bar unions all of
    // them (Bar.gapSpans).
    property var barGaps: ({})
    function setBarGap(id, mon, edge, from, to) {
        if (!id || !mon) return
        if (to - from < 0.5) { clearBarGap(id); return }
        var cur = barGaps[id]
        if (cur && cur.mon === mon && cur.edge === edge
                && Math.abs(cur.from - from) < 0.25 && Math.abs(cur.to - to) < 0.25) return
        var m = {}
        for (var k in barGaps) m[k] = barGaps[k]
        m[id] = { mon: mon, edge: edge, from: from, to: to }
        barGaps = m
    }
    function clearBarGap(id) {
        if (!(id in barGaps)) return
        var m = {}
        for (var k in barGaps) if (k !== id) m[k] = barGaps[k]
        barGaps = m
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
        id: notifRevealB
        // Direction from the Behavior's own targetValue, NOT the surface's open flag:
        // the flag flips in the same signal that starts the animation, and the animation
        // latched the OLD spring — opening ran on the closing spring and vice versa.
        SpringAnimation {
            spring:  Style.springFor(notifRevealB.targetValue > 0.5)
            damping: Style.dampingFor(notifRevealB.targetValue > 0.5)
            epsilon: 0.003
        }
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
        // Style first: the gallery belongs to the screen, not to the bar, so none of the anchor
        // work below applies to it. Same toggle semantics either way — asking for the picker a
        // second time puts it away.
        if (VtlConfig.wallpaperQuickStyle === "gallery") { ui.toggleWallpaperGallery(monName); return }
        if (ui.wpSwitcherMon === monName && monName !== "") {
            ui.toggleFlyout("wallpaper", ui.wpSwitcherX, ui.wpSwitcherY,
                            ui.wpSwitcherEdge, ui.wpSwitcherGroup, monName)
            return
        }
        var a = ui.wallpaperAnchor(mw, mh, VtlConfig.wallpaperQuickPos)
        ui.toggleFlyout("wallpaper", a.ax, a.ay, a.edge, a.group, monName)
    }

    // Full-screen picker: latched to the monitor it was asked for, so it stays there even if the
    // focus wanders. Re-asking on the SAME monitor closes it; on another one it moves across.
    function toggleWallpaperGallery(monName) {
        if (ui.wallpaperGalleryOpen && ui.wallpaperGalleryMon === monName) {
            ui.wallpaperGalleryOpen = false
            return
        }
        ui.wallpaperGalleryMon  = monName
        ui.wallpaperGalleryOpen = true
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
        if (keep !== "wallgal"   && ui.wallpaperGalleryOpen)      ui.wallpaperGalleryOpen = false
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
    onWallpaperGalleryOpenChanged: if (ui.wallpaperGalleryOpen) ui._closeMenusExcept("wallgal")
    // The editors take over the whole screen — clear the set, but stay out of it themselves.
    onPaletteEditorOpenChanged:  if (ui.paletteEditorOpen)     ui._closeMenusExcept("")
    onLockEditorOpenChanged:     if (ui.lockEditorOpen)        ui._closeMenusExcept("")
}
