import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// Notification centre — a history panel that grows out of the bar from the notiftray bell, exactly
// like the settings menu grows from the vuture-icon: it butts the bell's edge and L-merges into the
// bar (and the perpendicular bar at a corner), morphing from a nub to full size. Toggled via
// UiState.notifCenterOpen (the bell / the `notify` IPC) or Escape. Lists NotifService.model.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    // Latched to the bell's monitor at open (UiState.notifMon) so the centre stays where it was
    // opened instead of following the focus; falls back to the focused monitor if nothing latched.
    readonly property bool onActiveMonitor: monitor !== null &&
        (UiState.notifMon !== "" ? root.mon === UiState.notifMon : monitor === Compositor.focusedMonitor)
    readonly property bool isOpen: UiState.notifCenterOpen
    readonly property bool active: isOpen && onActiveMonitor
    onIsOpenChanged: if (isOpen) NotifService.unread = 0   // opening the centre clears the bell badge

    // ── The head's figures. Plain index loops on purpose: `model.values` is a QVariantList
    // sequence, and .concat()/.slice() on one of those is quadratic (it froze velora for seconds
    // on a few hundred items) — the same trap lives here.
    readonly property var _all: NotifService.model ? NotifService.model.values : []
    readonly property int _count: root._all.length
    readonly property int _apps: {
        var seen = ({}), c = 0
        for (var i = 0; i < root._all.length; i++) {
            var a = root._all[i].appName || ""
            if (!seen[a]) { seen[a] = true; c++ }
        }
        return c
    }
    readonly property int _pins: {
        var _touch = NotifService.pinned          // rebind the moment a pin is toggled
        var c = 0
        for (var i = 0; i < root._all.length; i++) if (NotifService.isPinned(root._all[i])) c++
        return c
    }
    // Morph progress on this screen (other screens stay collapsed so the close morph still plays).
    readonly property real reveal: root.onActiveMonitor ? UiState.notifReveal : 0

    readonly property int scrW: screen ? screen.width  : 1920
    readonly property int scrH: screen ? screen.height : 1080
    readonly property var  _lr: VtlConfig.lockRect(root.mon, root.scrW, root.scrH)

    // Bar hidden by a REAL fullscreen window on this monitor → grow straight out of the bare screen
    // edge. Per-monitor, from the live client list: a maximized window keeps the bar, so it must not
    // count (it used to, and the centre then rendered on top of the bar).
    readonly property bool monFullscreen: Compositor.fullscreenOn(root.monitor?.id ?? -1)

    // ── Anchor: the notiftray bell publishes its edge / group / position; else fall back to the
    // top-right corner (where the bell usually lives) so it still grows sensibly. ──────────────
    readonly property bool   hasBell: VtlConfig.barModulePlacedFor("notiftray", root.mon)
    readonly property string mEdge:  hasBell ? UiState.notifEdge  : "top"
    readonly property string mGroup: hasBell ? UiState.notifGroup : "end"
    readonly property real   mStart: hasBell ? UiState.notifStart : root.scrW
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"

    // Offset from the screen edge onto the bar's inner face (incl. the float gap); 0 when the
    // anchored edge has no bar or a fullscreen window hides it — then it grows from the bare edge.
    readonly property bool edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon) && !root.monFullscreen
    readonly property int  barT:   edgeBar
                                   ? VtlConfig.edgeThicknessFor(mEdge, root.mon)
                                     + (VtlConfig.barFloatingFor(root.mon) ? VtlConfig.barFloatGapFor(root.mon) : 0)
                                   : 0

    // Panel size — width + height from Settings → Notifications. 0 = match the settings menu
    // (same percent-of-screen formula as Settings.qml), so the centre defaults to the menu's size.
    // Matches the settings menu, which is now sized by the dashboard raster instead of a
    // percentage (see Style.dashGrid*). 52 stands in for the settings rail the centre has
    // no equivalent of, so the two panels still read as the same width.
    readonly property int menuW: Math.min(Math.round(root.scrW * 0.94), Style.menuContentW + 52)
    readonly property int menuH: Math.min(Math.round(root.scrH * 0.94), Style.dashGridH + Style.dashChromeH)
    readonly property int panelW: VtlConfig.notifyCenterWidth > 0
                                  ? Math.max(220, VtlConfig.notifyCenterWidth) : root.menuW
    readonly property int panelH: VtlConfig.notifyCenterHeight > 0
                                  ? Math.max(200, Math.min(VtlConfig.notifyCenterHeight, root.scrH - 2 * root.barT - 16))
                                  : Math.max(360, Math.min(root.menuH, root.scrH - 2 * root.barT - 24, root._lr[3] - 16))

    // ── How the panel merges into the bar (ported from Settings.qml) ───────────────
    // It butts its anchored edge (mEdge) and, on an L-bar, blends into the perpendicular arm at the
    // bell's end (mGroup): start → near end, end → far end. A merged edge draws no border and the
    // fill flows into it; a merged↔free corner gets a concave fillet, a free↔free corner a convex
    // round. Radii follow the bar's inner radius; seams sit at the bar's inner face → glued at any
    // thickness, any edge. With the bar hidden (fullscreen) it's a free tab out of the bare edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    readonly property string _tctx:    root.edgeBar ? "bar" : "edge"
    // A floating bar gets a floating panel: no merges, fully-rounded free outline, offset by the
    // same gap (see Settings.qml/Flyout.qml — same treatment on every bar-grown surface).
    // Cupertino detaches ALWAYS: macOS panels are free dropdowns under the strip.
    readonly property bool detached:  root.edgeBar && (VtlConfig.barFloatingFor(root.mon) || Style.isCupertino)
    readonly property int  detachGap: detached ? Math.max(6, VtlConfig.barFloatingFor(root.mon)
                                                             ? VtlConfig.barFloatGapFor(root.mon) : 8) : 0
    readonly property bool _mergeAll:  VtlConfig.transitionMergeAllFor("notify_center", root._tctx)
    readonly property bool mergeStart: mGroup === "start" && root.edgeBar && _mergeAll && !detached
    readonly property bool mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll && !detached
    readonly property int  sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int  sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    readonly property int edgeR:  Style.panelR(VtlConfig.barInnerRadiusFor(root.mon))
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    // Bar-panel colour (like the notification popups' tray) so the module-pill cards on it read the
    // same in the centre as in the toasts.
    readonly property color cFill: Style.panelColor(VtlConfig.barColorful)
    // Overlap the anchored bar edge by a hair so the bar's own inner border line is hidden.
    readonly property int seam:   2
    // Grow the Shapes by `pad` on every side so the fillet wedges + seam + the elastic bulge (all
    // outside the panel rect) still render; path coords are emitted in panel-local space + pad.
    readonly property int pad:    flareR + seam + 2 + Math.ceil(Math.max(Style.elTopBulge, Style.elSideBulge))

    // ── Outline builder (returns [borderD, fillD] in panel-local + pad coords) ──────
    // bT / bS = live elastic bulge (px) for the far edge / free side edges; 0 at rest → straight.
    function _paths(W, H, bT, bS) {
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H
        var D = horizA ? H : W
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        var f = VtlConfig.transitionFilletFor("notify_center", root._tctx) ? Math.max(0, Math.min(flareR, A / 3, D / 3)) : 0
        var s = seam
        var ca0 = mergeStart ? sideStart     : 0      // near-end content boundary
        var ca1 = mergeEnd   ? (A - sideEnd) : A      // far-end content boundary
        var flip = (mEdge === "bottom" || mEdge === "left")
        function XY(a, d) {
            var x, y
            if      (mEdge === "bottom") { x = a;     y = H - d }
            else if (mEdge === "left")   { x = d;     y = a     }
            else if (mEdge === "right")  { x = W - d; y = a     }
            else                         { x = a;     y = d     }   // top
            return (x + pad) + "," + (y + pad)
        }
        var cur = [0, 0]
        function M(a, d)     { cur = [a, d]; return "M" + XY(a, d) }
        function L(a, d)     { cur = [a, d]; return " L" + XY(a, d) }
        function A_(r,a,d,w) { cur = [a, d]; return Style.pathCorner(r, w, flip, XY(a, d)) }
        // Bulged line: quadratic from cur → (a,d), control = midpoint + (na,nd)·b (outward normal).
        function LB(a, d, na, nd, b) {
            var ma = (cur[0] + a) / 2 + na * b
            var md = (cur[1] + d) / 2 + nd * b
            cur = [a, d]
            return " Q" + XY(ma, md) + " " + XY(a, d)
        }

        var bd, close
        if (root.detached) {                      // floating bar → free-floating panel, all corners convex
            bd = M(A - e, 0) + A_(e, A, e, 1)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, e,     -1, 0, bS) + A_(e, e, 0, 1)
               + " Z"
            return [bd, bd]
        }
        if (mergeStart && !mergeEnd) {            // perpendicular arm at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)
               + LB(ca1, D - e,  1, 0, bS) + A_(e, ca1 - e, D, 1)
               + LB(ca0 + f, D,  0, 1, bT) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s) + " Z"
        } else if (mergeEnd && !mergeStart) {     // perpendicular arm at the far end
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(e, D,  0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f, -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else if (mergeStart && mergeEnd) {      // arms at both ends (U-bar)
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + LB(ca0 + f, D, 0, 1, bT) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else {                                  // free tab — concave fillets on both bar corners
            bd = M(A + f, 0) + A_(f, A, f, 0)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)
               + LB(0, f,     -1, 0, bS) + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A + f, -s) + " Z"
        }
        return [bd, bd + close]
    }
    function borderPath(W, H, bT, bS) { return _paths(W, H, bT, bS)[0] }
    function fillPath(W, H, bT, bS)   { return _paths(W, H, bT, bS)[1] }

    visible: root.active || root.reveal > 0.01
    color:   "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Grab everything except the bar (lockRect) so windows are locked + click-outside dismisses,
    // while the bar (incl. the bell) stays clickable.
    Region { id: emptyMask }
    Region { id: lockMask; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    // Grab the lock region on EVERY monitor while open so a click on any monitor (outside that
    // monitor's bar) dismisses; only the latched monitor actually renders the panel.
    mask: root.isOpen ? lockMask : emptyMask

    Shortcut { sequence: "Escape"; onActivated: UiState.notifCenterOpen = false }

    // Click-outside dismisses — on any monitor.
    MouseArea { anchors.fill: parent; z: 0; enabled: root.isOpen; onClicked: UiState.notifCenterOpen = false }

    // ── Panel: grows from the bell's edge into the content area ───────────────────
    Item {
        id: panel

        readonly property int  collapsed: root.barT
        // Content fades in only once there's room for it.
        readonly property real contentReveal: Math.max(0.0, Math.min(1.0, (root.reveal - 0.5) / 0.45))

        // Elastic emergence — spring error drives the edge bulge + a touch of size overshoot.
        readonly property real target: root.onActiveMonitor ? (root.isOpen ? 1.0 : 0.0) : 0.0
        readonly property real elDim:  Math.min(width, height)
        readonly property real bulgeT: Style.elBulge(root.reveal, target, Style.elTopBulge,  elDim)
        readonly property real bulgeS: Style.elBulge(root.reveal, target, Style.elSideBulge, elDim)
        readonly property real sizeF:  Style.elSizeF(root.reveal, target)

        width:   collapsed + (root.panelW - collapsed) * sizeF
        height:  collapsed + (root.panelH - collapsed) * sizeF
        opacity: Math.min(1.0, root.reveal * 4.0)

        // Centre the morph nub on the bell and clamp along the edge; start/end groups snap to the
        // screen corner (merging into the perpendicular bar there, or the bare edge if none).
        readonly property real alongMax: root.vert ? (root.scrH - height) : (root.scrW - width)
        readonly property real along: root.mergeStart ? 0
                                    : root.mergeEnd   ? alongMax
                                    : Math.max(0, Math.min(root.mStart - collapsed / 2, alongMax))
        x: root.mEdge === "left"  ? root.barT + root.detachGap
         : root.mEdge === "right" ? root.scrW - root.barT - root.detachGap - width
         : along
        y: root.mEdge === "top"    ? root.barT + root.detachGap
         : root.mEdge === "bottom" ? root.scrH - root.barT - root.detachGap - height
         : along

        // Block click-through to the desktop, but stay below the content widgets (z:0).
        MouseArea { anchors.fill: parent; z: 0 }

        // ── Fill ──────────────────────────────────────────────────────────────
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor:   root.cFill
                strokeWidth: -1
                PathSvg { path: root.fillPath(panel.width, panel.height, panel.bulgeT, panel.bulgeS) }
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
                PathSvg { path: root.borderPath(panel.width, panel.height, panel.bulgeT, panel.bulgeS) }
            }
        }

        // ── Content (header + history) — inset clear of the merged perpendicular bars ──────────
        Item {
            id: body
            anchors.fill:         parent
            anchors.leftMargin:   root.vert ? 0 : root.sideStart
            anchors.rightMargin:  root.vert ? 0 : root.sideEnd
            anchors.topMargin:    root.vert ? root.sideStart : 0
            anchors.bottomMargin: root.vert ? root.sideEnd   : 0
            opacity: panel.contentReveal

            // ── Head: what the history holds, as figures, before a single card is read ──
            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                height: 28 + 6 + 34 + 8 + 16

                Text {
                    id: hTitle
                    anchors { left: parent.left; top: parent.top }
                    height: 28; verticalAlignment: Text.AlignVCenter
                    text: Wording.s("notif.title"); color: Colors.fgBright
                    font.pixelSize: 15; font.bold: true; font.family: Style.font
                }
                Row {
                    anchors { right: parent.right; top: parent.top }
                    height: 28
                    spacing: 6
                    // DND toggle
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 24; radius: Style.rTile
                        color: NotifService.dnd ? Style.tint(Style.accent, Style.lift(0.34))
                             : (dndHov.containsMouse ? Style.tint(Colors.bgActive, Style.lift(0.24))
                                                     : Style.tint(Colors.bgElement, Style.lift(0.14)))
                        Behavior on color { ColorAnimation { duration: 110 } }
                        Text { anchors.centerIn: parent; text: NotifService.dnd ? "󰂛" : "󰂚"
                               color: NotifService.dnd ? Colors.fgBright : Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        MouseArea { id: dndHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotifService.toggleDnd() }
                    }
                    // Clear all
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 24; radius: Style.rTile
                        color: clrHov.containsMouse ? Style.tint(Colors.bgActive, Style.lift(0.24))
                                                    : Style.tint(Colors.bgElement, Style.lift(0.14))
                        Behavior on color { ColorAnimation { duration: 110 } }
                        Text { anchors.centerIn: parent; text: "󰎟"; color: Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        MouseArea { id: clrHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotifService.clearAll() }
                    }
                }

                Row {
                    id: nStats
                    anchors { left: parent.left; right: parent.right; top: hTitle.bottom; topMargin: 6 }
                    height: 34
                    readonly property int cellW: Math.floor((width - 3 * 10) / 4)
                    spacing: 10
                    StatCell { width: nStats.cellW; value: root._count + ""; caption: "In history"
                               dim: root._count === 0 }
                    StatCell { width: nStats.cellW; value: root._apps + "";  caption: "Apps"
                               dim: root._apps === 0 }
                    StatCell { width: nStats.cellW; glyph: root._pins > 0 ? "󰐃" : ""
                               value: root._pins + ""; caption: "Pinned"
                               good: root._pins > 0; dim: root._pins === 0 }
                    StatCell { width: nStats.cellW; glyph: NotifService.dnd ? "󰂛" : "󰂚"
                               value: NotifService.dnd ? "On" : "Off"; caption: "Do not disturb"
                               warn: NotifService.dnd; dim: !NotifService.dnd }
                }

                SectionRule {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    text: "History"
                    trailing: NotifService.dnd ? "muted" : ""
                }
            }

            // History list (shared component, honours the grouping setting).
            NotifList {
                anchors { top: header.bottom; topMargin: 8; left: parent.left; right: parent.right
                          bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
            }
        }
    }
}
