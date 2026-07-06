import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Reusable click-flyout that grows out of the bar with the exact same dock transition the settings
// menu uses: a module in the bar's start/end group makes the panel snap to that corner and flow into
// the perpendicular bar arm (or the bare screen edge) with concave L-fillets; a center-group module
// grows a free tab (concave fillets on both bar corners). The panel morphs from a nub at the bar
// inner face to full size (grow-from-corner), so it reads identically to the main menu. One instance
// per screen; only the one whose monitor matches the published anchor opens. Content is supplied by
// the concrete menu via the default property; width is fixed (panelW), height auto-fits up to maxH.
// While open the input grab covers everything except the bar (lockRect) so the bar stays clickable;
// a click in that region or Escape closes. Geometry mirrors Settings.qml (the reference).
PanelWindow {
    id: root
    property string flyoutId: ""
    property int    panelW:   320
    property int    maxH:     560
    default property alias content: body.data

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:    monitor?.name ?? ""
    readonly property bool   isOpen: UiState.flyout === root.flyoutId && UiState.flyoutMon === root.mon
    // Open on SOME monitor (the panel only grows on `isOpen`'s monitor, but every screen grabs its
    // lock region so a click on any monitor — outside that monitor's bar — dismisses the flyout).
    readonly property bool   anyOpen: UiState.flyout === root.flyoutId

    // ── Anchor: which edge + group the module sits on (published via UiState.toggleFlyout) ──────
    readonly property string mEdge:  UiState.flyoutEdge    // top | left | bottom | right
    readonly property string mGroup: UiState.flyoutGroup   // start | center | end → shapes the dock
    readonly property bool   vert:   mEdge === "left" || mEdge === "right"
    readonly property int    sw:     screen ? screen.width  : 1920
    readonly property int    sh:     screen ? screen.height : 1080
    readonly property int    inPad:  14

    // Track the focused window's fullscreen state — when fullscreen the bar is hidden, so the panel
    // grows as a free tab from the bare screen edge instead of merging into the (absent) bar.
    property bool monFullscreen: false
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") root.monFullscreen = (("" + event.data).trim() === "1")
        }
    }

    // ── Dock geometry (ported from Settings.qml) ──────────────────────────────────────────────
    readonly property bool   edgeBar: VtlConfig.edgeActiveFor(mEdge, root.mon) && !root.monFullscreen
    readonly property int    barT:   edgeBar
                                     ? VtlConfig.edgeThicknessFor(mEdge, root.mon)
                                       + (VtlConfig.barFloatingFor(root.mon) ? VtlConfig.barFloatGapFor(root.mon) : 0)
                                     : 0
    // An icon in the start/end group merges the menu into that end of the bar (the concave
    // L-transition); the perpendicular target is the side bar if present, else the bare screen edge.
    readonly property string startEdge: vert ? "top"    : "left"
    readonly property string endEdge:   vert ? "bottom" : "right"
    readonly property string _tctx:      root.edgeBar ? "bar" : "edge"
    readonly property bool   _mergeAll:  VtlConfig.transitionMergeAllFor("flyout", root._tctx)
    readonly property bool   mergeStart: mGroup === "start" && root.edgeBar && _mergeAll
    readonly property bool   mergeEnd:   mGroup === "end"   && root.edgeBar && _mergeAll
    readonly property int    sideStart:  (mergeStart && VtlConfig.edgeActiveFor(startEdge, root.mon)) ? VtlConfig.edgeThicknessFor(startEdge, root.mon) : 0
    readonly property int    sideEnd:    (mergeEnd   && VtlConfig.edgeActiveFor(endEdge,   root.mon)) ? VtlConfig.edgeThicknessFor(endEdge,   root.mon)   : 0

    readonly property int edgeR:  VtlConfig.barInnerRadiusFor(root.mon)
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    readonly property int seam:   2
    readonly property int pad:    flareR + seam + 2
    readonly property color cardColor: {
        var t = VtlConfig.menuColorful ? 0.12 : 0.0
        return Qt.rgba(Colors.bgPrimary.r * (1 - t) + Colors.bgActive.r * t,
                       Colors.bgPrimary.g * (1 - t) + Colors.bgActive.g * t,
                       Colors.bgPrimary.b * (1 - t) + Colors.bgActive.b * t, 1)
    }

    // Outline in (a, d) space — a runs along the bar, d is the depth away from it — mapped onto the
    // actual edge. Returns [borderOpen, fillClosed]; the fill closes back through the merged edges.
    function _paths(W, H) {
        var horizA = (mEdge === "top" || mEdge === "bottom")
        var A = horizA ? W : H        // extent along the bar
        var D = horizA ? H : W        // depth away from the bar
        var e = Math.max(0, Math.min(edgeR,  A / 3, D / 3))
        var f = VtlConfig.transitionFilletFor("flyout", root._tctx) ? Math.max(0, Math.min(flareR, A / 3, D / 3)) : 0
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
        function A_(r,a,d,w) { return (r <= 0 || (w === 1 && Style.chamfer)) ? (" L" + XY(a, d))
                                             : " A" + r + "," + r + " 0 0 " + (flip ? (1 - w) : w) + " " + XY(a, d) }

        var bd, close
        if (mergeStart && !mergeEnd) {            // sidebar at the near end (classic L)
            bd = M(ca1 + f, 0) + A_(f, ca1, f, 0)
               + L(ca1, D - e) + A_(e, ca1 - e, D, 1)
               + L(ca0 + f, D) + A_(f, ca0, D + f, 0)
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

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1

    // Input: while open, grab everything except the bar (lockRect) so the rest is locked, the bar
    // stays clickable and a click outside the panel closes; passes through entirely when closed.
    readonly property var _lr: VtlConfig.lockRect(root.mon, root.sw, root.sh)
    Region { id: emptyRegion }
    Region { id: lockRegion; x: root._lr[0]; y: root._lr[1]; width: root._lr[2]; height: root._lr[3] }
    mask: root.anyOpen ? lockRegion : emptyRegion
    visible: root.anyOpen || panel.reveal > 0.01

    Shortcut { sequence: "Escape"; onActivated: if (root.anyOpen) UiState.flyout = "" }

    // Click-outside (within the locked lockRect) closes — on any monitor, since every screen grabs
    // its lock region while the flyout is open anywhere.
    MouseArea {
        anchors.fill: parent
        z: 0
        enabled: root.anyOpen
        onClicked: UiState.flyout = ""
    }

    // ── Menu panel: grows from the module's edge/corner into the content area ──────────────────
    Item {
        id: panel
        property real reveal: root.isOpen ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }

        readonly property int  collapsed: root.barT
        // Inner content fades in only once there's room for it.
        readonly property real contentReveal: Math.max(0.0, Math.min(1.0, (reveal - 0.5) / 0.45))
        // Auto-fit the content height, clamped to maxH and the screen.
        readonly property int  targetH: Math.min(root.maxH,
                                            Math.min(root.vert ? root.sh - 16 : root.sh - root.barT - 16,
                                                     body.implicitHeight + 2 * root.inPad))

        // Morph from a barT nub to full size (grow-from-corner), same as the settings menu.
        width:   collapsed + (root.panelW - collapsed) * reveal
        height:  collapsed + (targetH     - collapsed) * reveal
        opacity: Math.min(1.0, reveal * 4.0)

        // Docked edge pinned at the bar inner face; along the bar an icon in start/end snaps the
        // panel to that corner, a center icon tracks the anchor (clamped on-screen).
        readonly property real alongMax: root.vert ? (root.sh - height) : (root.sw - width)
        readonly property real anchor:   root.vert ? UiState.flyoutAnchorY : UiState.flyoutAnchorX
        // Centre the panel ON the anchor (was anchored at the panel's start → off-centre); start/end
        // groups still snap to the corner.
        readonly property real along: root.mergeStart ? 0
                                    : root.mergeEnd   ? alongMax
                                    : Math.max(0, Math.min(anchor - (root.vert ? height : width) / 2, alongMax))
        x: root.mEdge === "left"  ? root.barT
         : root.mEdge === "right" ? root.sw - root.barT - width
         : along
        y: root.mEdge === "top"    ? root.barT
         : root.mEdge === "bottom" ? root.sh - root.barT - height
         : along

        MouseArea { anchors.fill: parent; z: 0 }   // block click-through (keep the flyout open)

        // Dock fill — flows into the bar (GeometryRenderer, grown by `pad` so fillets + seam render).
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor: root.cardColor; strokeWidth: -1
                fillRule:  ShapePath.WindingFill
                PathSvg { path: root.fillPath(panel.width, panel.height) }
            }
        }
        // Content-side border only (the merged edges stay borderless).
        Shape {
            anchors.fill:          parent
            anchors.margins:       -root.pad
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"; strokeColor: Style.chromeBorder; strokeWidth: 1
                PathSvg { path: root.borderPath(panel.width, panel.height) }
            }
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.inPad
            implicitHeight: childrenRect.height
            opacity: panel.contentReveal
            clip: true   // clip the content to the (morphing) panel so it doesn't spill out before
                         // the panel has finished growing — the fillet Shapes (siblings) still overflow.
        }
    }
}
