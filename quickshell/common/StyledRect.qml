import ".."
import QtQuick
import QtQuick.Shapes

// Token-styled surface: a plain Rectangle for the round/straight variants, a Shape outline for the
// vector ones (chamfer octagon · scallop cartouche · wobbly cloud · sketch hand-drawn), and a
// two-tone raised bevel for nostalgic. Drop-in root for the shared widgets — Rectangle's grouped
// border.* can't be re-declared on a custom type, so it's borderWidth/borderColor here. The Loader
// means the plain variants pay zero Shape cost; the swap only happens on the (rare) variant switch.
Item {
    id: sr
    property int   radius:      0              // corner radius; the cut/bite/bump size for the vector variants
    property color color:       "transparent"
    property int   borderWidth: 0
    property color borderColor: "transparent"
    // Per-corner overrides (docked surfaces square their merged edge); default to `radius`.
    property int radiusTL: radius
    property int radiusTR: radius
    property int radiusBR: radius
    property int radiusBL: radius

    Loader {
        anchors.fill: parent
        sourceComponent: Style.nostalgic ? bevel
                       : (Style.chamfer || Style.scallop || Style.wobbly || Style.sketch) ? poly
                       : rect
    }

    Component {
        id: rect
        Rectangle {
            radius:            sr.radius
            topLeftRadius:     sr.radiusTL
            topRightRadius:    sr.radiusTR
            bottomRightRadius: sr.radiusBR
            bottomLeftRadius:  sr.radiusBL
            color:             sr.color
            border.width:      sr.borderWidth
            border.color:      sr.borderColor
        }
    }

    Component {
        id: poly
        Shape {
            // Straight chamfer cuts keep the cheap geometry renderer; every curved outline
            // (scallop / cloud / sketch) needs the curve renderer's analytic anti-aliasing.
            preferredRendererType: Style.chamfer ? Shape.GeometryRenderer : Shape.CurveRenderer
            ShapePath {
                fillColor:   sr.color
                strokeColor: sr.borderWidth > 0 ? sr.borderColor : "transparent"
                strokeWidth: sr.borderWidth > 0 ? sr.borderWidth : -1
                joinStyle:   ShapePath.MiterJoin
                PathSvg {
                    path: Style.wobbly ? sr._cloud(sr.width, sr.height)
                        : Style.sketch ? sr._sketch(sr.width, sr.height)
                                       : sr._octagon(sr.width, sr.height)
                }
            }
        }
    }

    // Nostalgic (Win95): a flat face with a two-tone raised bevel — light on the top/left, shadow on
    // the bottom/right — derived from the fill. borderWidth doubles as the bevel thickness.
    Component {
        id: bevel
        Item {
            readonly property int  bw:    Math.max(1, sr.borderWidth)
            readonly property color face: sr.color
            readonly property color hi:   Qt.lighter(Qt.rgba(sr.color.r, sr.color.g, sr.color.b, 1), 1.7)
            readonly property color lo:   Qt.darker(Qt.rgba(sr.color.r, sr.color.g, sr.color.b, 1), 2.0)
            Rectangle { anchors.fill: parent; color: parent.face }
            // light edges (top, left)
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        height: parent.bw; color: parent.hi }
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.bottom: parent.bottom
                        width: parent.bw; color: parent.hi }
            // shadow edges (bottom, right) — drawn last so they win the two shared corners
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: parent.bw; color: parent.lo }
            Rectangle { anchors.top: parent.top; anchors.right: parent.right; anchors.bottom: parent.bottom
                        width: parent.bw; color: parent.lo }
        }
    }

    // Clockwise octagon (chamfer/scallop). Inset by half the stroke so the whole border sits inside
    // the item bounds — otherwise the outer half straddles the edge, gets clipped, and an edge (the
    // left, being last in the path) visibly drops out. Matches Rectangle's inside-border.
    function _octagon(w, h) {
        var s  = sr.borderWidth > 0 ? sr.borderWidth / 2 : 0
        var iw = w - s, ih = h - s
        function cl(v) { return Math.max(0, Math.min(v, (iw - s) / 2, (ih - s) / 2)) }
        var tl = cl(sr.radiusTL), tr = cl(sr.radiusTR), br = cl(sr.radiusBR), bl = cl(sr.radiusBL)
        return "M" + (s + tl) + "," + s + " L" + (iw - tr) + "," + s + " " + Style.cornerSeg(tr, iw, (s + tr))
             + " L" + iw + "," + (ih - br) + " " + Style.cornerSeg(br, (iw - br), ih)
             + " L" + (s + bl) + "," + ih + " " + Style.cornerSeg(bl, s, (ih - bl))
             + " L" + s + "," + (s + tl) + " " + Style.cornerSeg(tl, (s + tl), s) + " Z"
    }

    // Wobbly: a gently puffed "cloud" edge. Bumps are SHALLOW (a small fixed depth, not full
    // semicircles) and few per edge, so a wide card reads as softly wavy instead of a dense mass of
    // bubbles. The path is inset by the bump depth so peaks land on the item edge and nothing spills.
    function _cloud(w, h) {
        var s   = sr.borderWidth > 0 ? sr.borderWidth / 2 : 0
        var dep = Math.max(3, Math.min(sr.radius, (Math.min(w, h) - 2 * s) / 6))   // shallow bulge depth
        var lo  = s + dep
        var rx  = w - s - dep, ry = h - s - dep
        // Few, wide puffs: ~1 per 58px, at most 6 per edge.
        function cnt(len) { return Math.max(1, Math.min(Math.round(len / 58), 6)) }
        // Circular arc radius for a chord `c` bulging out by `dep` (sagitta): R = c²/8dep + dep/2.
        function R(c) { return c * c / (8 * dep) + dep / 2 }
        var nT = cnt(rx - lo), cT = (rx - lo) / nT
        var nR = cnt(ry - lo), cR = (ry - lo) / nR
        var nB = cnt(rx - lo), cB = (rx - lo) / nB
        var nL = cnt(ry - lo), cL = (ry - lo) / nL
        var d = "M" + lo + "," + lo, x = lo, y = lo, i
        for (i = 0; i < nT; i++) { x += cT; d += " A" + R(cT) + "," + R(cT) + " 0 0 1 " + x + "," + lo }
        for (i = 0; i < nR; i++) { y += cR; d += " A" + R(cR) + "," + R(cR) + " 0 0 1 " + rx + "," + y }
        for (i = 0; i < nB; i++) { x -= cB; d += " A" + R(cB) + "," + R(cB) + " 0 0 1 " + x + "," + ry }
        for (i = 0; i < nL; i++) { y -= cL; d += " A" + R(cL) + "," + R(cL) + " 0 0 1 " + lo + "," + y }
        return d + " Z"
    }

    // Sketch: a hand-drawn rectangle. Corners jitter a hair and each edge bows via a cubic whose two
    // control points are pushed perpendicular by a small deterministic amount — so it looks inked,
    // not ruled, yet stays perfectly stable per size (no boiling on every repaint).
    function _sketch(w, h) {
        function fr(k) { var v = Math.sin(k * 127.1 + w * 0.07 + h * 0.13) * 43758.5453; return v - Math.floor(v) }
        function j(k)  { return (fr(k) - 0.5) * 5.4 }        // ≈ ±2.7px — clearly inked, not ruled
        var m = 2.6
        var TLx = m + j(1), TLy = m + j(2), TRx = (w - m) + j(3), TRy = m + j(4)
        var BRx = (w - m) + j(5), BRy = (h - m) + j(6), BLx = m + j(7), BLy = (h - m) + j(8)
        function edge(ax, ay, bx, by, k) {
            var dx = bx - ax, dy = by - ay, len = Math.max(1, Math.hypot(dx, dy))
            var px = -dy / len, py = dx / len, o1 = j(k), o2 = j(k + 0.5)
            var c1x = ax + dx / 3 + px * o1, c1y = ay + dy / 3 + py * o1
            var c2x = ax + 2 * dx / 3 + px * o2, c2y = ay + 2 * dy / 3 + py * o2
            return " C" + c1x + "," + c1y + " " + c2x + "," + c2y + " " + bx + "," + by
        }
        return "M" + TLx + "," + TLy
             + edge(TLx, TLy, TRx, TRy, 11) + edge(TRx, TRy, BRx, BRy, 22)
             + edge(BRx, BRy, BLx, BLy, 33) + edge(BLx, BLy, TLx, TLy, 44) + " Z"
    }
}
