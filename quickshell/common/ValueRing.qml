import ".."
import QtQuick
import QtQuick.Shapes

// A value as a ring: battery on a phone, volume on an app puck, charge on a headset. The shape the
// popouts use whenever a number is a share of something, because a ring reads before the digits do.
//
// `halo` is the second, live reading — a signal that swells outside the ring while the value itself
// stays put. That is how an app puck shows "playing" without a second widget beside it.
Item {
    id: r
    property real  value:   0            // 0..1
    property real  halo:    0            // 0..1, 0 = no halo
    property color ringColor: Colors.bgActive
    property color trackColor: Style.tint(Colors.bgPrimary, 0.85)
    property int   thickness: 4
    property bool  dim:     false
    // Content sits in the middle: a glyph, an icon, a number — whatever the caller puts there.
    default property alias content: hole.data

    implicitWidth: 48
    implicitHeight: 48
    readonly property real _d: Math.min(r.width, r.height)

    // Live signal, outside the ring.
    Rectangle {
        anchors.centerIn: parent
        width: r._d + 4 + 10 * Math.max(0, Math.min(1, r.halo)); height: width; radius: width / 2
        color: r.ringColor
        opacity: r.halo > 0.01 && !r.dim ? 0.10 + 0.28 * r.halo : 0
        visible: opacity > 0.01
    }

    Shape {
        anchors.centerIn: parent
        width: r._d; height: r._d
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: r.trackColor; strokeWidth: r.thickness; fillColor: "transparent"
            PathAngleArc { centerX: r._d / 2; centerY: r._d / 2
                           radiusX: (r._d - r.thickness) / 2; radiusY: (r._d - r.thickness) / 2
                           startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: r.dim ? Colors.fgMuted : r.ringColor
            strokeWidth: r.thickness; fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: r._d / 2; centerY: r._d / 2
                           radiusX: (r._d - r.thickness) / 2; radiusY: (r._d - r.thickness) / 2
                           startAngle: -90
                           sweepAngle: 360 * Math.max(0, Math.min(1, r.value)) }
        }
    }

    Item { id: hole; anchors.centerIn: parent; width: r._d - r.thickness * 3; height: width }
}
