import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Dropdown menu that grows from the inner corner of the L-bar.
// Layout: a left icon rail (visually continuing the bar's sidebar) that switches
// the content area on the right. Size is dynamic: 1/5 screen width × 1/2 height.
PanelWindow {
    id: root

    // This monitor's name → per-monitor bar settings.
    readonly property string mon: root.monitor?.name ?? ""

    // ── Anchor: which edge the menu attaches to + where along it ──────────────
    // The vuture-icon module publishes its position into UiState. When no such module is
    // placed, there's nothing to grow from — fall back to the top-left corner.
    readonly property bool   hasIcon: VtlConfig.barModulePlacedFor("vuture-icon", root.mon)
    readonly property string mEdge:  hasIcon ? UiState.menuEdge  : "top"     // top | left | bottom | right
    readonly property string mGroup: hasIcon ? UiState.menuGroup : "start"   // start | center | end → shapes the L
    readonly property real   mStart: hasIcon ? UiState.menuStart : 0         // icon centre along the edge
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"
    // Offset from the screen edge to sit on the bar's inner face. When the anchored edge has
    // no bar — or a fullscreen window is hiding it — sit flush at the edge (no empty column).
    readonly property bool   edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon) && !root.monFullscreen
    readonly property int    barT:   edgeBar
                                     ? VtlConfig.edgeThicknessFor(mEdge, root.mon)
                                       + (VtlConfig.barFloatingFor(root.mon) ? VtlConfig.barFloatGapFor(root.mon) : 0)
                                     : 0
    readonly property int    sw:     screen ? screen.width  : 1920
    readonly property int    sh:     screen ? screen.height : 1080

    // Track the focused window's fullscreen state (Hyprland "fullscreen>>0/1").
    property bool monFullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.monFullscreen = (("" + event.data).trim() === "1")
        }
    }

    // Menu dimensions — a % of the monitor (set in Settings → Bar; per-monitor capable). A % of a
    // NARROW (e.g. portrait) monitor collapses the menu until the content truncates, so guard both
    // axes: never smaller than a usable floor, never larger than 94% of the screen (so the floor
    // itself can't overflow a small monitor either).
    readonly property int menuW:  screen
        ? Math.min(Math.round(screen.width  * 0.94),
                   Math.max(420, Math.round(screen.width  * VtlConfig.menuWidthPctFor(root.mon)  / 100))) : 300
    readonly property int menuH:  screen
        ? Math.min(Math.round(screen.height * 0.94),
                   Math.max(460, Math.round(screen.height * VtlConfig.menuHeightPctFor(root.mon) / 100))) : 540

    // ── How the menu merges into the bar ─────────────────────────────────────────
    // The menu butts against its anchored edge (mEdge) and, on an L-bar, also blends into the
    // perpendicular arm (the sidebar) at the *end* of that edge where the icon sits: mGroup
    // start → the near end (left for a top/bottom bar, top for a left/right bar), end → the far
    // end. A merged edge draws no border and the fill flows into it; each corner joining a merged
    // edge to a *free* edge gets a concave fillet (the "L transition"), a free+free corner a
    // convex round. Radii follow the bar's inner radius and every seam sits at the bar's inner
    // face, so the menu stays glued to the bar at *any* thickness, on *any* edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    // No merging into the perpendicular arm when the bar is hidden (fullscreen) — then the
    // menu is a free tab growing straight out of the edge.
    // An icon in the start/end group merges the menu into that end of the bar — the concave
    // L-transition. The perpendicular target is the side bar if one is there, otherwise the SCREEN
    // EDGE treated as a zero-thickness bar (sideStart/End = 0), so a top-only bar's corner icon
    // still grows a menu whose corner curves down into the screen edge (instead of a rounded free
    // tab). Only requires the anchored edge to have a bar (edgeBar); falls back to a free tab when
    // that's hidden (fullscreen).
    // Transition style depends on whether the menu hangs on a bar or a bare screen edge.
    readonly property string _tctx:    root.edgeBar ? "bar" : "edge"
    // A floating bar gets a floating menu: no merges, fully-rounded free outline, offset by the
    // same gap — docking into a bar that itself floats reads as glued-on. Cupertino detaches
    // ALWAYS: macOS menus are free dropdowns under the strip.
    readonly property bool detached:  root.edgeBar && (VtlConfig.barFloatingFor(root.mon) || Style.isCupertino)
    readonly property int  detachGap: detached ? Math.max(6, VtlConfig.barFloatingFor(root.mon)
                                                             ? VtlConfig.barFloatGapFor(root.mon) : 8) : 0
    // The perpendicular (corner) merge is suppressed by the "origin edge only" transition style.
    readonly property bool _mergeAll:  VtlConfig.transitionMergeAllFor("menu", root._tctx)
    readonly property bool mergeStart: mGroup === "start" && root.edgeBar && _mergeAll && !detached
    readonly property bool mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll && !detached
    readonly property int  sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int  sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    // Content-corner radius + concave-fillet radius both track the bar's inner radius
    // (cupertino rounds generously via panelR).
    readonly property int edgeR:  Style.panelR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Menu fill — optionally accent-tinted ("colorful"); frosted under cupertino.
    readonly property color cFill: Style.panelColor(VtlConfig.menuColorful)
    // Overlap the anchored bar edge by a hair so LBar's own inner border line is hidden.
    readonly property int seam:   2
    // Grow the fill/border Shapes by `pad` on every side so the fillet wedges + seam (which spill
    // outside the menu rect) still render; path coords are emitted in menu-local space + pad.
    readonly property int pad:    flareR + seam + 2

    // Icon rail width — continue the left bar exactly when the menu sits against it.
    readonly property bool _leftBar: VtlConfig.edgeActiveFor("left", root.mon)
                                     && (mEdge === "left" || (!vert && mGroup === "start"))
    readonly property int  railW:    _leftBar ? VtlConfig.edgeThicknessFor("left", root.mon) : 52

    // ── Outline builder ──────────────────────────────────────────────────────────
    // Returns [borderD, fillD] in Shape-local coords (menu-local + pad). Geometry is built once in
    // (a, d) space — a runs along the bar, d is the depth away from it (anchored edge at d = 0) —
    // then mapped onto the actual edge. The border is the open content-side outline; the fill
    // closes it back through the merged bar edges, seam-extended into the bar.
    function _paths(W, H) {
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H        // extent along the bar
        var D = horizA ? H : W        // depth away from the bar
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        // Concave merge fillets collapse to 0 (straight corners) for the non-fillet styles.
        var f = VtlConfig.transitionFilletFor("menu", root._tctx) ? Math.max(0, Math.min(flareR, A / 3, D / 3)) : 0
        var s = seam
        var ca0 = mergeStart ? sideStart     : 0      // near-end content boundary
        var ca1 = mergeEnd   ? (A - sideEnd) : A      // far-end content boundary
        var flip = (mEdge === "bottom" || mEdge === "left")   // reflection → invert arc sweep
        function XY(a, d) {
            var x, y
            if      (mEdge === "bottom") { x = a;     y = H - d }
            else if (mEdge === "left")   { x = d;     y = a     }
            else if (mEdge === "right")  { x = W - d; y = a     }
            else                         { x = a;     y = d     }   // top
            return (x + pad) + "," + (y + pad)
        }
        function M(a, d)     { return "M" + XY(a, d) }
        function L(a, d)     { return " L" + XY(a, d) }
        function A_(r,a,d,w) { return Style.pathCorner(r, w, flip, XY(a, d)) }

        var bd, close
        if (root.detached) {                      // floating bar → free-floating panel, all corners convex
            bd = M(A - e, 0) + A_(e, A, e, 1)
               + L(A, D - e) + A_(e, A - e, D, 1)
               + L(e, D)     + A_(e, 0, D - e, 1)
               + L(0, e)     + A_(e, e, 0, 1)
               + " Z"
            return [bd, bd]
        }
        if (mergeStart && !mergeEnd) {            // sidebar at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)         // concave fillet into the bar
               + L(ca1, D - e) + A_(e, ca1 - e, D, 1)     // free far edge → convex round
               + L(ca0 + f, D) + A_(f, ca0, D + f, 0)     // free edge → concave into the sidebar
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s) + " Z"
        } else if (mergeEnd && !mergeStart) {     // sidebar at the far end
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + L(e, D)       + A_(e, 0, D - e, 1)
               + L(0, f)       + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else if (mergeStart && mergeEnd) {      // sidebars at both ends (U-bar)
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + L(ca0 + f, D) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else {                                  // free tab — concave fillets on both bar corners
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + L(A, D - e) + A_(e, A - e, D, 1)
               + L(e, D)     + A_(e, 0, D - e, 1)
               + L(0, f)     + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A + f, -s) + " Z"
        }
        return [bd, bd + close]
    }
    function borderPath(W, H) { return _paths(W, H)[0] }
    function fillPath(W, H)   { return _paths(W, H)[1] }

    // Which section's content is shown.
    property string activeSection: "home"

    // ── Section registry — ONE list drives the rail, the page loader and the titles ──
    // (rail: false → reachable only via navigation, e.g. the home hub's sub-pages; comp: null →
    // the placeholder page with `hint`.) Component ids resolve file-wide, so forward refs are fine.
    // Rail order groups by altitude: hardware/system first (monitors → peripherals),
    // then the shell chrome and look, then window behaviour. Info stays pinned at
    // the rail bottom regardless of its position here.
    readonly property var sections: [
        { key: "home",          icon: "󰋜", title: "Velumeron",     comp: homeComp },
        // ── Hardware & system ──
        { key: "monitors",      icon: "󰍺", title: "Monitors",      comp: monitorsComp },
        { key: "workspaces",    icon: "󱂬", title: "Workspaces",    comp: workspacesComp },
        { key: "peripherals",   icon: "󰍽", title: "Peripherals",   comp: peripheralsComp },
        { key: "autostart",     icon: "󱓞", title: "Autostart",     comp: autostartComp },
        { key: "quickaccess",   icon: "󱊫", title: "Quick access",  comp: quickAccessComp },
        // ── Shell chrome & look ──
        { key: "bar",           icon: "󰕮", title: "Bar",           comp: barComp },
        { key: "taskbar",       icon: "󱂩", title: "Taskbar",       comp: taskbarComp },
        { key: "style",         icon: "󰏘", title: "Style",         comp: styleComp },
        { key: "wallpaper",     icon: "󰸉", title: "Wallpaper",     comp: wallpaperComp },
        { key: "lockscreen",    icon: "󰌾", title: "Lockscreen",    comp: lockComp },
        { key: "launcher",      icon: "󰀻", title: "Launcher",      comp: launcherComp },
        { key: "osd",           icon: "󰍹", title: "OSD",           comp: osdComp },
        { key: "notifications", icon: "󰂚", title: "Notifications", comp: notifyComp },
        { key: "calendar",      icon: "󰃭", title: "Calendar",      comp: calendarComp },
        // ── Windows & input behaviour ──
        { key: "keybinds",      icon: "󰌌", title: "Keybindings",   comp: keybindsComp },
        { key: "corners",       icon: "󰊓", title: "Hot corners",   comp: cornersComp },
        { key: "zones",         icon: "󰝘", title: "Zones",         comp: zonesComp },
        { key: "layouts",       icon: "󰕴", title: "Layouts",       comp: layoutsComp },
        { key: "windowtags",    icon: "󰓹", title: "Window tags",   comp: windowTagsComp },
        { key: "windowrules",   icon: "󱪯", title: "Window rules",  comp: windowRulesComp },
        { key: "backup",        icon: "󰆓", title: "Import / Export", comp: backupComp },
        { key: "info",          icon: "󰋽", title: "Info",          comp: null,
          hint: "System information." },
        { key: "network",       rail: false, title: "Network",     comp: networkComp },
        { key: "bluetooth",     rail: false, title: "Bluetooth",   comp: bluetoothComp }
    ]
    function sectionMeta(s) {
        for (var i = 0; i < sections.length; i++) if (sections[i].key === s) return sections[i]
        return null
    }
    function sectionTitle(s) { return root.sectionMeta(s)?.title ?? s }
    // info's hint goes through Wording so the persona re-voices it; routing it here (not in the
    // sections array) keeps the array non-reactive — a style switch must not reload the open page.
    function sectionHint(s)  { return s === "info" ? Wording.s("hint.info") : (root.sectionMeta(s)?.hint ?? "") }

    // The menu is opened globally (one instance per screen) but shows on a single monitor. It LATCHES
    // to the monitor focused at open time (UiState.menuMon) and stays there — it does NOT follow the
    // focus afterwards. Each instance gates on whether it owns that latched monitor.
    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property bool isOpen: UiState.openDropdown === "vuture-icon"
    readonly property bool onActiveMonitor: root.mon !== "" && root.mon === UiState.menuMon
    readonly property bool active: isOpen && onActiveMonitor

    visible: true   // keep alive so the hide animation can play
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: (active && !UiState.pickerOpen)
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // When inactive: empty region → no input (mouse passes through to windows).
    // When active: grab everything except the bar (lockRect) so windows are locked + click-outside
    // dismisses, while the bar stays clickable. While a native picker is open: drop the grab so the
    // dialog underneath is usable.
    readonly property var _lr: VtlConfig.lockRect(root.mon, root.sw, root.sh)
    Region { id: emptyMask }
    Region { id: lockMask; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    // Grab the lock region on EVERY monitor while open (not just the active one) so a click on any
    // monitor — outside that monitor's bar — dismisses the menu. The panel only renders on the
    // active monitor; other instances are invisible full-screen click catchers.
    mask: (root.isOpen && !UiState.pickerOpen) ? lockMask : emptyMask

    Shortcut { sequence: "Escape"; onActivated: UiState.openDropdown = "" }

    // On open: reset to the home section — unless another surface requested a specific page
    // (e.g. the calendar flyout's gear → "calendar") — and latch the menu to the focused monitor
    // so it stays there (doesn't follow the focus). Only the focused instance claims the latch.
    onIsOpenChanged: {
        if (isOpen) {
            activeSection = UiState.settingsRequestSection !== "" ? UiState.settingsRequestSection : "home"
            // One instance per screen and all of them read the request — clear it only after
            // every handler has run.
            Qt.callLater(function () { UiState.settingsRequestSection = "" })
        }
        if (isOpen && monitor !== null && monitor === Hyprland.focusedMonitor) UiState.menuMon = root.mon
    }

    // Click-outside dismisses the menu — on any monitor (every screen grabs while open).
    MouseArea {
        anchors.fill: parent
        z:            0
        enabled:      root.isOpen
        onClicked:    UiState.openDropdown = ""
    }

    // ── Menu panel: grows from the vuture-icon's edge into the content area ───────
    Item {
        id: menu

        // Morph from a small nub at the icon to full size, driven by the shared reveal
        // (UiState.menuReveal). Gate on the monitor only (not isOpen) so the close morph
        // (1→0) still plays here; other monitors stay collapsed at 0.
        readonly property real reveal:    root.onActiveMonitor ? UiState.menuReveal : 0
        readonly property int  collapsed: root.barT
        // Inner content (rail + text) fades in only once there's room for it.
        readonly property real contentReveal: Math.max(0.0, Math.min(1.0, (reveal - 0.5) / 0.45))

        width:   collapsed + (root.menuW - collapsed) * reveal
        height:  collapsed + (root.menuH - collapsed) * reveal
        opacity: Math.min(1.0, reveal * 4.0)   // fade the panel in fast at the very start

        // Sit on the content side of the icon's edge; centre the morph nub on the icon and
        // clamp the along-edge position so the panel stays on screen.
        readonly property real alongMax: root.vert ? (root.sh - height) : (root.sw - width)
        // Along the bar: an icon in the start/end group snaps the menu to that end (the screen
        // corner — merging into a perpendicular bar there, or into the bare screen edge if none);
        // a centre-group icon tracks the icon position. This pins corner menus to the corner.
        readonly property real along: root.mergeStart ? 0
                                    : root.mergeEnd   ? alongMax
                                    : Math.max(0, Math.min(root.mStart - collapsed / 2, alongMax))
        x: root.mEdge === "left"  ? root.barT + root.detachGap
         : root.mEdge === "right" ? root.sw - root.barT - root.detachGap - width
         : along
        y: root.mEdge === "top"    ? root.barT + root.detachGap
         : root.mEdge === "bottom" ? root.sh - root.barT - root.detachGap - height
         : along

        // Block click-through to the desktop, but stay BELOW the rail/content widgets
        // (declared first + z:0) so their MouseAreas still receive clicks.
        MouseArea { anchors.fill: parent; z: 0 }

        // ── Fill ──────────────────────────────────────────────────────────────
        // The menu body flows into the bar (same bgPrimary): merged edges have no border and
        // are seam-extended into the bar, the corners joining a merged edge to a free edge get
        // concave L-fillets, and the free/free corner a convex round. The Shape is grown by
        // `pad` on all sides so those fillet wedges + seam can render outside the menu rect.
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor:   root.cFill
                strokeWidth: -1
                PathSvg { path: root.fillPath(menu.width, menu.height) }
            }
        }

        // ── Border (content-side only) ──────────────────────────────────────────
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor:   "transparent"
                strokeColor: Style.chromeBorder
                strokeWidth: Style.chromeBorderWidth
                PathSvg { path: root.borderPath(menu.width, menu.height) }
            }
        }

        // ── Icon rail (left) — navigation only ───────────────────────────────
        Item {
            id: rail
            width:   root.railW
            opacity: menu.contentReveal
            z:       5    // above the content pane, so the hover tooltips aren't painted under it
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }

            // The section list has outgrown short menus — the rail PAGES instead of
            // scrolling: every page shows as many icons as fit, Info stays pinned at
            // the bottom next to the pager arrow, and the mouse wheel flips pages.
            readonly property var  railItems: root.sections.filter(function (s) {
                return s.rail !== false && s.key !== "info"
            })
            readonly property var  infoMeta: root.sectionMeta("info")
            readonly property int  iconSz:   Math.max(30, Math.min(42, root.railW - 6))
            readonly property int  slotH:    iconSz + 4
            // Space reserved at the bottom: pinned Info icon + pager arrow + gaps.
            readonly property int  bottomH:  iconSz + 22 + 12
            readonly property int  perPage:  Math.max(1, Math.floor((height - 26 - bottomH - 8) / slotH))
            readonly property int  pages:    Math.max(1, Math.ceil(railItems.length / perPage))
            property int page: 0
            onPagesChanged: page = Math.min(page, pages - 1)
            readonly property var pageItems: railItems.slice(page * perPage, (page + 1) * perPage)

            function flip(dir) { rail.page = ((rail.page + dir) % rail.pages + rail.pages) % rail.pages }
            function ensureVisible(key) {
                for (var i = 0; i < railItems.length; i++)
                    if (railItems[i].key === key) { rail.page = Math.floor(i / rail.perPage); return }
            }
            Connections {
                target: root
                function onActiveSectionChanged() { rail.ensureVisible(root.activeSection) }
            }

            // Wheel-only layer under the icons (clicks pass through untouched).
            // Touchpads stream many small angleDeltas per swipe — accumulate to a full
            // detent (120) and rate-limit so one swipe flips one page, not five.
            MouseArea {
                id: railWheel
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                property real _acc: 0
                Timer { id: flipCooldown; interval: 250 }
                onWheel: wheel => {
                    if (flipCooldown.running) return
                    if ((railWheel._acc > 0) !== (wheel.angleDelta.y > 0)) railWheel._acc = 0
                    railWheel._acc += wheel.angleDelta.y
                    if (Math.abs(railWheel._acc) < 120) return
                    rail.flip(railWheel._acc < 0 ? 1 : -1)
                    railWheel._acc = 0
                    flipCooldown.restart()
                }
            }

            Column {
                anchors { top: parent.top; topMargin: 26; horizontalCenter: parent.horizontalCenter }
                spacing: 4

                Repeater {
                    model: rail.pageItems
                    delegate: RailIcon {
                        required property var modelData
                        icon:    modelData.icon
                        section: modelData.key
                    }
                }
            }

            // Pinned bottom: Info + pager arrow.
            Column {
                anchors { bottom: parent.bottom; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
                spacing: 4

                RailIcon {
                    icon:    rail.infoMeta?.icon ?? "󰋽"
                    section: "info"
                }
                Rectangle {
                    visible: rail.pages > 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: rail.iconSz; height: 18
                    radius: 6
                    color: pagerHov.containsMouse ? Style.tint(Style.accent, 0.18) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰅀"
                        color: pagerHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                        font.pixelSize: 13; font.family: Style.font
                    }
                    MouseArea {
                        id: pagerHov
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: rail.flip(1)
                    }
                }
            }
        }

        // Vertical separator between rail and content (inset to dodge the corners).
        Rectangle {
            x:       root.railW
            width:   1
            opacity: menu.contentReveal
            anchors { top: parent.top; bottom: parent.bottom
                      topMargin: 12; bottomMargin: 12 }
            color:  Style.tint(Colors.boNormal, 0.25)
        }

        // ── Content area (right) ─────────────────────────────────────────────
        Item {
            id: content
            opacity: menu.contentReveal
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: parent.left
                      leftMargin: root.railW + 1 }

            // The active section's page, straight from the registry.
            readonly property var activeMeta: root.sectionMeta(root.activeSection)
            Loader {
                anchors.fill:         parent
                anchors.topMargin:    18
                anchors.leftMargin:   18
                anchors.rightMargin:  18
                anchors.bottomMargin: 12
                active:  (content.activeMeta?.comp ?? null) !== null
                visible: active
                sourceComponent: content.activeMeta?.comp ?? null
            }
            Component { id: homeComp;      HomeHub          { onNavigate: s => root.activeSection = s } }
            Component { id: networkComp;   NetworkManager   { onBack: root.activeSection = "home" } }
            Component { id: bluetoothComp; BluetoothManager { onBack: root.activeSection = "home" } }
            Component { id: barComp;       BarSection       {} }
            Component { id: launcherComp;  LauncherSection  {} }
            Component { id: wallpaperComp; WallpaperSection {} }
            Component { id: styleComp;     StyleSection     {} }
            Component { id: backupComp;    BackupSection    {} }
            Component { id: osdComp;       OsdSection       {} }
            Component { id: notifyComp;    NotifSettings    {} }
            Component { id: lockComp;      LockscreenSection {} }
            Component { id: cornersComp;   CornerActionsSection {} }
            Component { id: taskbarComp;   TaskbarSection {} }
            Component { id: windowTagsComp; WindowTagsSection {} }
            Component { id: calendarComp;  CalendarSection {} }
            Component { id: zonesComp;     ZonesSection {} }
            Component { id: layoutsComp;   LayoutsSection {} }
            Component { id: keybindsComp;  KeybindsSection {} }
            Component { id: monitorsComp;    MonitorsSection {} }
            Component { id: workspacesComp;  WorkspacesSection {} }
            Component { id: autostartComp;   AutostartSection {} }
            Component { id: quickAccessComp; QuickAccessSection {} }
            Component { id: peripheralsComp; PeripheralsSection {} }
            Component { id: windowRulesComp; WindowRulesSection {} }

            // Placeholder for registry entries without a page yet (comp: null).
            Column {
                visible: (content.activeMeta?.comp ?? null) === null
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 18; leftMargin: 20; rightMargin: 20 }
                spacing: 6

                Text {
                    text:           root.sectionTitle(root.activeSection)
                    color:          Colors.fgBright
                    font.pixelSize: 17
                    font.bold:      true
                    font.family:    Style.font
                }
                Text {
                    text:           root.sectionHint(root.activeSection)
                    color:          Colors.fgMuted
                    font.pixelSize: 12
                    font.family:    Style.font
                    width:          parent.width
                    wrapMode:       Text.WordWrap
                }
            }
        }
    }


    // ── Rail icon button ──────────────────────────────────────────────────────
    component RailIcon: Item {
        id: ri
        property string icon:    ""
        property string section: ""
        property bool   accent:  false
        signal triggered()

        readonly property bool active: root.activeSection === ri.section

        // Shrink to fit when the rail follows a thin sidebar, so icons never overflow it.
        readonly property int sz: Math.max(30, Math.min(42, root.railW - 6))
        width:  ri.sz
        height: ri.sz

        // The selection/hover chip goes through StyledRect so it picks up the active variant's
        // corners (round / chamfer / scallop) instead of staying a plain rounded square.
        StyledRect {
            anchors.fill: parent
            radius: Style.rTile
            color:  ri.active
                    ? Style.accent
                    : (riHov.containsMouse ? Style.tint(Style.accent, 0.18) : "transparent")
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        Text {
            anchors.centerIn: parent
            text:           ri.icon
            color:          ri.active ? Colors.fgBright
                            : (riHov.containsMouse ? Colors.fgBright : Colors.fgMuted)
            font.pixelSize: 18
            font.family:    Style.font
        }

        MouseArea {
            id:           riHov
            anchors.fill: parent
            hoverEnabled: true
            z:            2
            onClicked: {
                if (ri.accent) ri.triggered()
                else           root.activeSection = ri.section
            }
        }

        // Hover tooltip: the section name, floating right of the rail (the rail is raised above the
        // content pane so the label isn't painted under it).
        readonly property string tipText: root.sectionTitle(ri.section)
        Rectangle {
            visible: opacity > 0.01 && ri.tipText !== ""
            opacity: riHov.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            anchors { left: parent.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            width:  tipTxt.implicitWidth + 16
            height: tipTxt.implicitHeight + 10
            radius: Style.rControl
            color:  Colors.bgPrimary
            border.width: 1; border.color: Colors.boNormal
            Text {
                id: tipTxt
                anchors.centerIn: parent
                text: ri.tipText
                color: Colors.fgPrimary
                font.pixelSize: 12; font.family: Style.font
            }
        }
    }

    // ── Power tile (main-page power block) — square, icon only ───────────────────
    component PowerTile: Rectangle {
        id: pt
        property string icon:  ""
        property string label: ""   // unused (kept so existing call sites don't break)
        property string cmd:   ""
        width:  48
        height: 48
        radius: Style.rTile
        color:  ptHov.containsMouse ? Style.accent : Style.controlFill
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text:           pt.icon
            color:          ptHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
            font.pixelSize: 18
            font.family:    Style.font
        }
        MouseArea {
            id: ptHov; anchors.fill: parent; hoverEnabled: true
            onClicked: {
                powerProc.command = ["bash", "-c", pt.cmd]
                powerProc.running = false
                powerProc.running = true
                UiState.openDropdown = ""
            }
        }
    }
    Process { id: powerProc }
}
