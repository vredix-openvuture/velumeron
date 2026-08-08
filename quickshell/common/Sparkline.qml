import ".."
import QtQuick
import QtQuick.Shapes

// A history curve with a filled area under it — the shape every popout uses to show "what this has
// been doing": audio level, cpu load, network throughput. Shape rather than Canvas because it is
// GPU-drawn and redraws on a property change instead of a repaint call, which matters when a panel
// holds one per tile.
//
// Feed it `values` (0..1, oldest first). It draws nothing but the baseline when they are all zero,
// which is the honest picture of silence — a curve that idles at a visible height would be lying.
Item {
    id: sl
    property var   values:    []
    property color lineColor: Colors.bgActive
    property real  lineWidth: 1.6
    property bool  dim:       false          // muted / inactive: the whole curve steps back
    // A faint floor line, so an empty tile still reads as a chart rather than a hole.
    property bool  baseline:  true

    implicitHeight: 34

    readonly property var _pts: {
        var v = sl.values, n = v.length
        if (n < 2 || sl.width <= 0) return []
        var out = []
        for (var i = 0; i < n; i++)
            out.push(Qt.point(i / (n - 1) * sl.width,
                              sl.height - 1 - Math.max(0, Math.min(1, v[i])) * (sl.height - 3)))
        return out
    }
    // The same points closed down to the floor, so the fill has a bottom.
    readonly property var _area: {
        if (sl._pts.length < 2) return []
        var out = sl._pts.slice()
        out.push(Qt.point(sl.width, sl.height))
        out.push(Qt.point(0, sl.height))
        return out
    }

    Rectangle {
        visible: sl.baseline
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Style.tint(Colors.boNormal, 0.45)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: sl.dim ? 0.45 : 1.0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: sl.height
                GradientStop { position: 0.0; color: Style.tint(sl.lineColor, 0.42) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            PathPolyline { path: sl._area }
        }
        ShapePath {
            strokeColor: sl.lineColor
            strokeWidth: sl.lineWidth
            fillColor:   "transparent"
            capStyle:    ShapePath.RoundCap
            joinStyle:   ShapePath.RoundJoin
            PathPolyline { path: sl._pts }
        }
    }
}
