import ".."
import QtQuick
import QtQuick.Shapes

// Signal strength as nested arcs — Wi-Fi, cellular. Four steps, because that is the resolution the
// sources actually report; a smooth ring would invent precision that isn't there.
//
// The four paths are written out rather than repeated: a Repeater needs Item delegates and a
// ShapePath is not one, so `Repeater { ShapePath {} }` silently produces nothing.
Item {
    id: s
    property real  value:   0            // 0..1
    property color arcColor: Colors.bgActive
    property bool  dim:     false

    implicitWidth: 34
    implicitHeight: 34

    readonly property color _off: Style.tint(Colors.bgPrimary, 0.85)
    readonly property color _on:  s.dim ? Colors.fgMuted : s.arcColor
    function _lit(i) { return s.value > (i + 0.5) / 4 }
    function _r(i)   { return s.height * 0.20 + i * s.height * 0.155 }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: s._lit(0) ? s._on : s._off
            strokeWidth: 2.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: s.width / 2; centerY: s.height * 0.76
                           radiusX: s._r(0); radiusY: s._r(0); startAngle: 207; sweepAngle: 126 }
        }
        ShapePath {
            strokeColor: s._lit(1) ? s._on : s._off
            strokeWidth: 2.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: s.width / 2; centerY: s.height * 0.76
                           radiusX: s._r(1); radiusY: s._r(1); startAngle: 207; sweepAngle: 126 }
        }
        ShapePath {
            strokeColor: s._lit(2) ? s._on : s._off
            strokeWidth: 2.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: s.width / 2; centerY: s.height * 0.76
                           radiusX: s._r(2); radiusY: s._r(2); startAngle: 207; sweepAngle: 126 }
        }
        ShapePath {
            strokeColor: s._lit(3) ? s._on : s._off
            strokeWidth: 2.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: s.width / 2; centerY: s.height * 0.76
                           radiusX: s._r(3); radiusY: s._r(3); startAngle: 207; sweepAngle: 126 }
        }
    }
}
