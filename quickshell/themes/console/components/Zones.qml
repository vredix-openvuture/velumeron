pragma ComponentBehavior: Bound
import QtQuick

// Console's drop targets are a labelled rack, not ghost rectangles. Each field is an outline with
// its slot number in the corner and its size printed in the middle, so you can tell two zones apart
// before you let go — which is the one thing a ghost rectangle cannot do.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent   || "#b269e0"
    readonly property color ink:    root.pal.fgBright || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted  || "#6b5480"

    readonly property int px: Math.round(Math.max(12, Math.min(18, root.height * 0.014)))

    Repeater {
        model: root.ctx.zones || []
        delegate: Rectangle {
            id: field
            required property var modelData
            x: field.modelData.x; y: field.modelData.y
            width: field.modelData.w; height: field.modelData.h
            color: field.modelData.hot
                   ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                   : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.05)
            border.width: field.modelData.hot ? 2 : 1
            border.color: field.modelData.hot ? root.accent
                                              : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.34)
            Behavior on color { ColorAnimation { duration: 110 } }

            Text {
                anchors { left: parent.left; top: parent.top
                          leftMargin: root.px * 0.7; topMargin: root.px * 0.5 }
                text: "[" + (field.modelData.index + 1) + "]"
                color: field.modelData.hot ? root.accent : root.faint
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                anchors.centerIn: parent
                text: Math.round(field.modelData.w) + " × " + Math.round(field.modelData.h)
                color: field.modelData.hot ? root.ink : root.faint
                font.family: root.font; font.pixelSize: Math.round(root.px * 1.1)
                font.letterSpacing: root.px * 0.1
            }
        }
    }
}
