import ".."
import QtQuick
import QtQuick.Shapes

// Token-styled surface: a plain Rectangle normally, a chamfered octagon (45° corner cuts)
// under ui_style = futuristic. Drop-in root for the shared widgets — Rectangle's grouped
// border.* can't be re-declared on a custom type, so it's borderWidth/borderColor here.
// The Loader means the three round variants pay zero Shape cost; the swap only happens on
// the (rare) variant switch. GeometryRenderer stays mandatory: these sit in Repeaters and
// grids, where the curve renderer's MSAA would actually hurt.
Item {
    id: sr
    property int   radius:      0              // corner radius; the cut size when Style.chamfer
    property color color:       "transparent"
    property int   borderWidth: 0
    property color borderColor: "transparent"

    Loader {
        anchors.fill: parent
        sourceComponent: Style.chamfer ? poly : rect
    }

    Component {
        id: rect
        Rectangle {
            radius:       sr.radius
            color:        sr.color
            border.width: sr.borderWidth
            border.color: sr.borderColor
        }
    }

    Component {
        id: poly
        Shape {
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                fillColor:   sr.color
                strokeColor: sr.borderWidth > 0 ? sr.borderColor : "transparent"
                strokeWidth: sr.borderWidth > 0 ? sr.borderWidth : -1
                PathSvg { path: sr._octagon(sr.width, sr.height) }
            }
        }
    }

    function _octagon(w, h) {
        var c = Math.max(0, Math.min(sr.radius, w / 2, h / 2))
        return "M" + c + ",0 L" + (w - c) + ",0 L" + w + "," + c
             + " L" + w + "," + (h - c) + " L" + (w - c) + "," + h
             + " L" + c + "," + h + " L0," + (h - c) + " L0," + c + " Z"
    }
}
