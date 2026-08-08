import ".."
import QtQuick
import QtQuick.Shapes

// A load reading as a three-quarter dial: cpu, gpu, memory. Distinct from ValueRing on purpose —
// a full ring says "a share of a whole", an open dial says "a level on a scale", and the two sit
// next to each other often enough that they must not be confused.
Item {
    id: g
    property real  value:   0            // 0..1
    property color arcColor: Colors.bgActive
    property string label:  ""           // caption under the dial
    property bool  warn:    false        // over its limit → the urgent colour
    property int   thickness: 6

    implicitWidth: 64
    implicitHeight: 68
    readonly property real _d: Math.min(g.width, g.height - (g.label !== "" ? 14 : 0))
    readonly property real _a0: 135      // degrees; 135 → 405 leaves the bottom quarter open
    readonly property real _sw: 270

    Shape {
        id: dial
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
        width: g._d; height: g._d
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Style.tint(Colors.bgPrimary, 0.85); strokeWidth: g.thickness
            fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: g._d / 2; centerY: g._d / 2
                           radiusX: (g._d - g.thickness) / 2; radiusY: (g._d - g.thickness) / 2
                           startAngle: g._a0; sweepAngle: g._sw }
        }
        ShapePath {
            strokeColor: g.warn ? Colors.fgUrgent : g.arcColor
            strokeWidth: g.thickness; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: g._d / 2; centerY: g._d / 2
                           radiusX: (g._d - g.thickness) / 2; radiusY: (g._d - g.thickness) / 2
                           startAngle: g._a0
                           sweepAngle: g._sw * Math.max(0, Math.min(1, g.value)) }
        }
    }
    Text {
        anchors.centerIn: dial
        text: Math.round(Math.max(0, Math.min(1, g.value)) * 100) + "%"
        color: g.warn ? Colors.fgUrgent : Colors.fgBright
        font.family: Style.font; font.pixelSize: 13; font.bold: true
    }
    Text {
        visible: g.label !== ""
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        text: g.label
        color: Colors.fgMuted
        font.family: Style.font; font.pixelSize: 9; font.letterSpacing: 0.5
    }
}
