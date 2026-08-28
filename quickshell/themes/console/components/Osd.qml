pragma ComponentBehavior: Bound
import QtQuick

// Console's OSD is a readout, not a slider.
//
//   VOL  ██████████░░░░░░░░░░  48 %
//
// The bar is drawn out of block characters rather than as a rectangle, for the same reason the
// dashboard has no meters: on a screen made of type, a graphic next to a number is a second voice
// saying the same thing. Twenty cells is enough to read a level at a glance and coarse enough that
// it never pretends to a precision the number does not have.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgBright  || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"

    readonly property int px: Math.round(Math.max(11, Math.min(15, root.height * 0.30)))
    readonly property int cells: 20
    readonly property int filled: Math.round(Math.max(0, Math.min(1, root.ctx.level || 0)) * root.cells)

    readonly property string label: root.ctx.kind === "brightness" ? "LUM"
                                  : root.ctx.muted ? "MUTE" : "VOL"

    Row {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: Math.round(root.px * 1.2); rightMargin: Math.round(root.px * 1.2) }
        spacing: Math.round(root.px * 0.9)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(root.px * 3.2)
            text: root.label
            color: root.ctx.muted ? root.faint : root.accent
            font.family: root.font; font.pixelSize: root.px
            font.letterSpacing: root.px * 0.12
        }
        Text {
            id: meter
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var on = "", off = ""
                for (var i = 0; i < root.filled; i++) on += "█"
                for (var j = root.filled; j < root.cells; j++) off += "░"
                return on + off
            }
            color: root.ctx.muted ? root.faint : root.ink
            font.family: root.font; font.pixelSize: root.px
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.ctx.percent !== undefined ? root.ctx.percent : 0) + " %"
            color: root.ink
            font.family: root.font; font.pixelSize: root.px
            horizontalAlignment: Text.AlignRight
        }
    }

    // The active sink, when the shell says to show it. One line, no second card.
    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                  bottomMargin: Math.round(root.px * 0.4) }
        visible: (root.ctx.device || "") !== ""
        width: parent.width - root.px * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.ctx.device || ""
        color: root.faint
        font.family: root.font; font.pixelSize: Math.round(root.px * 0.82)
    }
}
