import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

// Notification centre — a history panel that grows out of the bar from the notiftray bell, exactly
// like the settings menu grows from the vuture-icon: it butts the bell's edge and L-merges into the
// bar (and the perpendicular bar at a corner), morphing from a nub to full size. Toggled via
// UiState.notifCenterOpen (the bell / the `notify` IPC) or Escape. Lists NotifService.model.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    // Latched to the bell's monitor at open (UiState.notifMon) so the centre stays where it was
    // opened instead of following the focus; falls back to the focused monitor if nothing latched.
    readonly property bool onActiveMonitor: monitor !== null &&
        (UiState.notifMon !== "" ? root.mon === UiState.notifMon : monitor === Hyprland.focusedMonitor)
    readonly property bool isOpen: UiState.notifCenterOpen
    readonly property bool active: isOpen && onActiveMonitor
    onIsOpenChanged: if (isOpen) NotifService.unread = 0   // opening the centre clears the bell badge
    // Morph progress on this screen (other screens stay collapsed so the close morph still plays).
    readonly property real reveal: root.onActiveMonitor ? UiState.notifReveal : 0

    readonly property int scrW: screen ? screen.width  : 1920
    readonly property int scrH: screen ? screen.height : 1080
    readonly property var  _lr: VtlConfig.lockRect(root.mon, root.scrW, root.scrH)

    // Bar hidden by a fullscreen window → grow straight out of the bare screen edge.
    property bool monFullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.monFullscreen = (("" + event.data).trim() === "1")
        }
    }

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

    // Panel size — width + height from Settings → Notifications (height 0 = auto-fill the frame).
    readonly property int panelW: Math.max(220, VtlConfig.notifyCenterWidth)
    readonly property int panelH: VtlConfig.notifyCenterHeight > 0
                                  ? Math.max(200, Math.min(VtlConfig.notifyCenterHeight, root.scrH - 2 * root.barT - 16))
                                  : Math.max(360, Math.min(root.scrH - 2 * root.barT - 24, root._lr[3] - 16))

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
    readonly property color cFill: Style.panelColor(VtlConfig.osdColorful)
    // Overlap the anchored bar edge by a hair so the bar's own inner border line is hidden.
    readonly property int seam:   2
    // Grow the Shapes by `pad` on every side so the fillet wedges + seam (outside the panel rect)
    // still render; path coords are emitted in panel-local space + pad.
    readonly property int pad:    flareR + seam + 2

    // ── Outline builder (returns [borderD, fillD] in panel-local + pad coords) ──────
    function _paths(W, H) {
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
        if (mergeStart && !mergeEnd) {            // perpendicular arm at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)
               + L(ca1, D - e) + A_(e, ca1 - e, D, 1)
               + L(ca0 + f, D) + A_(f, ca0, D + f, 0)
            close = L(0, D + f) + L(0, -s) + L(ca1 + f, -s) + " Z"
        } else if (mergeEnd && !mergeStart) {     // perpendicular arm at the far end
            bd = M(ca1, D + f) + A_(f, ca1 - f, D, 0)
               + L(e, D)       + A_(e, 0, D - e, 1)
               + L(0, f)       + A_(f, -f, 0, 0)
            close = L(-f, -s) + L(A, -s) + L(A, D + f) + " Z"
        } else if (mergeStart && mergeEnd) {      // arms at both ends (U-bar)
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

        width:   collapsed + (root.panelW - collapsed) * root.reveal
        height:  collapsed + (root.panelH - collapsed) * root.reveal
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
                PathSvg { path: root.fillPath(panel.width, panel.height) }
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
                PathSvg { path: root.borderPath(panel.width, panel.height) }
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

            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                height: 28

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: Wording.s("notif.title"); color: Colors.fgBright
                    font.pixelSize: 15; font.bold: true; font.family: Style.font
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    // DND toggle
                    Rectangle {
                        width: 30; height: 24; radius: 7
                        color: NotifService.dnd ? Colors.bgActive
                             : (dndHov.containsMouse ? Style.tint(Colors.bgActive, 0.18) : Colors.bgElement)
                        Text { anchors.centerIn: parent; text: NotifService.dnd ? "󰂛" : "󰂚"
                               color: NotifService.dnd ? Colors.fgBright : Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        MouseArea { id: dndHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotifService.toggleDnd() }
                    }
                    // Clear all
                    Rectangle {
                        width: 30; height: 24; radius: 7
                        color: clrHov.containsMouse ? Colors.bgActive : Colors.bgElement
                        Text { anchors.centerIn: parent; text: "󰎟"; color: Colors.fgPrimary
                               font.pixelSize: 13; font.family: Style.font }
                        MouseArea { id: clrHov; anchors.fill: parent; hoverEnabled: true; onClicked: NotifService.clearAll() }
                    }
                }
            }

            // History list (shared component, honours the grouping setting).
            NotifList {
                anchors { top: header.bottom; topMargin: 10; left: parent.left; right: parent.right
                          bottom: parent.bottom; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
            }
        }
    }
}
