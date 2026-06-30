import ".."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Reusable "glide": a small pill that slides OUT OF THE BAR (and back) from a bar module's position,
// glued to the bar's inner face with the same dock transition the OSD / menus use (concave fillets,
// or straight per the global transition style). One instance per screen; shows when `shown` on the
// matching monitor (`mine`). Content goes in via the default property and the pill auto-sizes to it.
//
// By default informational (empty input mask — never steals clicks), like the volume glide. Set
// `interactive` for clickable content (input only over the pill); pair it with `keepOpenOnHover` for
// a hover-triggered pill so it stays up while the pill itself is hovered (lets you reach its buttons).
PanelWindow {
    id: root
    default property alias content: bodyWrap.data

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    property bool   mine:    false
    property bool   shown:   false        // the module's hover / open trigger
    property string edge:    "top"        // bar edge the module sits on → glide direction
    property real   anchorX: 0            // module centre in screen coords (along-edge placement)
    property real   anchorY: 0
    property bool   interactive:     false  // pill takes input (clickable content)
    property bool   keepOpenOnHover: false  // stay open while the pill is hovered (hover-triggered)
    property int    padX: 22
    property int    padY: 12

    // Open while the module says so, or (for a hover pill with clickable content) while the pill
    // itself is hovered — so the cursor can travel from the module into the pill without it closing.
    readonly property bool open: root.shown || (root.keepOpenOnHover && pillHover.hovered)

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    visible: root.mine && (root.open || pill.reveal > 0.01)

    readonly property bool barOnEdge: VtlConfig.edgeActiveFor(root.edge, root.mon)
    readonly property int  barT:   root.barOnEdge
                                   ? VtlConfig.edgeThicknessFor(root.edge, root.mon)
                                     + (VtlConfig.barFloatingFor(root.mon) ? VtlConfig.barFloatGapFor(root.mon) : 0)
                                   : 0
    readonly property int  scrW:   screen ? screen.width  : 1920
    readonly property int  scrH:   screen ? screen.height : 1080
    readonly property string _tctx:   root.barOnEdge ? "bar" : "edge"
    readonly property bool   _fillet: VtlConfig.transitionFilletFor("glide", root._tctx)

    readonly property color cardColor: {
        var t = VtlConfig.osdColorful ? 0.12 : 0.0
        return Qt.rgba(Colors.bgPrimary.r * (1 - t) + Colors.bgActive.r * t,
                       Colors.bgPrimary.g * (1 - t) + Colors.bgActive.g * t,
                       Colors.bgPrimary.b * (1 - t) + Colors.bgActive.b * t, 1)
    }

    // ── Dock outline (free tab, concave fillets — or straight per the transition style) ──────────
    readonly property int flareR: VtlConfig.barInnerRadiusFor(root.mon)
    readonly property int seam:   root.barT + 24
    readonly property int pad:    root.flareR + root.seam
    function _paths(W, H) {
        var hz = (root.edge === "top" || root.edge === "bottom")
        var A = hz ? W : H, D = hz ? H : W
        var e = Math.max(0, Math.min(root.flareR, A / 3, D / 3))
        var f = root._fillet ? e : 0, s = root.seam, P = root.pad
        var flip = (root.edge === "bottom" || root.edge === "left")
        function XY(a, d) {
            var x, y
            if      (root.edge === "bottom") { x = a;     y = H - d }
            else if (root.edge === "left")   { x = d;     y = a     }
            else if (root.edge === "right")  { x = W - d; y = a     }
            else                             { x = a;     y = d     }
            return (x + P) + "," + (y + P)
        }
        function M(a, d)     { return "M" + XY(a, d) }
        function L(a, d)     { return " L" + XY(a, d) }
        function A_(r,a,d,w) { return r <= 0 ? (" L" + XY(a, d))
                                             : " A" + r + "," + r + " 0 0 " + (flip ? (1 - w) : w) + " " + XY(a, d) }
        var bd = M(A + f, 0) + A_(f, A, f, 0)
               + L(A, D - e)  + A_(e, A - e, D, 1)
               + L(e, D)      + A_(e, 0, D - e, 1)
               + L(0, f)      + A_(f, -f, 0, 0)
        var close = L(-f, -s) + L(A + f, -s) + " Z"
        return [bd, bd + close]
    }

    // Input over the pill whenever it's on screen (clickable content OR a hover-kept pill) — gating
    // on `open` would drop the region the instant the cursor leaves the module, before it reaches
    // the pill, so the bridge must stay live while the pill is still visible (reveal > 0).
    readonly property bool _takesInput: root.interactive || root.keepOpenOnHover
    Region { id: emptyMask }
    Region { id: pillMask; x: pill.openX; y: pill.openY; width: pill.width; height: pill.height }
    mask: (root._takesInput && root.mine && (root.open || pill.reveal > 0.01)) ? pillMask : emptyMask

    // Drawer clip: bar-side edge at the bar's inner face (+2px in so the seam has no gap). The pill
    // slides perpendicular; whatever slips past the bar edge is clipped → it reads as gliding out of
    // / into the bar. No bar on the edge → whole-screen viewport, plain slide + fade.
    Item {
        id: drawer
        readonly property int ov: root.barOnEdge ? 2 : 0
        x:      root.edge === "left" ? (root.barT - ov) : 0
        y:      root.edge === "top"  ? (root.barT - ov) : 0
        width:  (root.edge === "left" || root.edge === "right") ? (root.scrW - root.barT + ov) : root.scrW
        height: (root.edge === "top"  || root.edge === "bottom") ? (root.scrH - root.barT + ov) : root.scrH
        clip:   root.barOnEdge

        Item {
            id: pill
            width:  bodyWrap.childrenRect.width  + root.padX
            height: bodyWrap.childrenRect.height + root.padY

            property real reveal: (root.mine && root.open) ? 1 : 0
            Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            readonly property real openX: root.edge === "left"  ? root.barT
                                        : root.edge === "right" ? (root.scrW - width - root.barT)
                                        : Math.max(8, Math.min(root.anchorX - width / 2, root.scrW - width - 8))
            readonly property real openY: root.edge === "top"    ? root.barT
                                        : root.edge === "bottom" ? (root.scrH - height - root.barT)
                                        : Math.max(8, Math.min(root.anchorY - height / 2, root.scrH - height - 8))
            x: openX - drawer.x
            y: openY - drawer.y

            opacity: root.barOnEdge ? 1.0 : reveal
            transform: Translate {
                x: root.barOnEdge ? (root.edge === "left"  ? -(1 - pill.reveal) * pill.width
                                   : root.edge === "right" ?  (1 - pill.reveal) * pill.width : 0)
                                  : (root.edge === "left"  ? -(1 - pill.reveal) * 20
                                   : root.edge === "right" ?  (1 - pill.reveal) * 20 : 0)
                y: root.barOnEdge ? (root.edge === "top"    ? -(1 - pill.reveal) * pill.height
                                   : root.edge === "bottom" ?  (1 - pill.reveal) * pill.height : 0)
                                  : (root.edge === "top"    ? -(1 - pill.reveal) * 20
                                   : root.edge === "bottom" ?  (1 - pill.reveal) * 20 : 0)
            }

            // Dock background — concave fillets (or straight) flowing into the bar.
            Shape {
                visible: root.barOnEdge
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.GeometryRenderer
                ShapePath { fillColor: root.cardColor; strokeWidth: -1; fillRule: ShapePath.WindingFill
                            PathSvg { path: root._paths(pill.width, pill.height)[1] } }
            }
            Shape {
                visible: root.barOnEdge
                anchors.fill: parent; anchors.margins: -root.pad
                preferredRendererType: Shape.CurveRenderer
                ShapePath { fillColor: "transparent"; strokeColor: Colors.boNormal; strokeWidth: 1
                            PathSvg { path: root._paths(pill.width, pill.height)[0] } }
            }
            // Plain rounded pill when there's no bar on this edge.
            Rectangle {
                visible: !root.barOnEdge
                anchors.fill: parent
                radius: Math.min(16, height / 2)
                color:  root.cardColor
                border.width: 1; border.color: Colors.boNormal
            }

            HoverHandler { id: pillHover; enabled: root.keepOpenOnHover }

            // Content holder — centred in the pill at the content's natural bounds.
            Item {
                id: bodyWrap
                x: (pill.width  - childrenRect.width)  / 2 - childrenRect.x
                y: (pill.height - childrenRect.height) / 2 - childrenRect.y
            }
        }
    }
}
