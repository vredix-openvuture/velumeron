pragma ComponentBehavior: Bound
import QtQuick

// Console's notification centre is a log you scroll back through, not a stack of cards you dismiss.
//
//   14:02  System      142 packages, 3 from the AUR
//   13:47  Velumeron   Palette rebuilt from the picture
//
// Three columns and nothing else: when, who, what. A critical entry turns its app and its message
// the alarm colour rather than growing a badge — on a screen made of text, colour is the loudest
// thing available and a second shape would only compete with it.
//
// The shell keeps the service: pinning, do-not-disturb, clearing and the panel itself are all still
// its. This file receives entries that are already flattened, so it never has to know how the shell
// groups a stack by application.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgBright  || "#e5c7f6"
    readonly property color dim:    root.pal.fgPrimary || "#9e7fbe"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"
    readonly property color alarm:  root.pal.fgUrgent  || "#c25742"

    readonly property int px: Math.round(Math.max(11, Math.min(13, root.width * 0.032)))

    ListView {
        id: log
        anchors.fill: parent
        clip: true
        spacing: Math.round(root.px * 0.35)
        model: root.ctx.entries || []

        delegate: Item {
            id: line
            required property var modelData
            width: log.width
            height: Math.max(root.px * 1.7, msg.implicitHeight + root.px * 0.4)

            readonly property bool crit: line.modelData.critical === true

            // No timestamp in the contract yet, so this column carries the one mark the shell does
            // give us. Inventing a time would be worse than leaving the column honest.
            Text {
                id: when
                anchors { left: parent.left; top: parent.top; topMargin: 2 }
                width: Math.round(root.px * 3.4)
                text: line.modelData.pinned ? "pin" : "·"
                color: line.modelData.pinned ? root.accent : root.faint
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                id: who
                anchors { left: when.right; leftMargin: Math.round(root.px * 0.8)
                          top: parent.top; topMargin: 2 }
                width: Math.round(root.px * 7.4)
                text: line.modelData.app
                color: line.crit ? root.alarm : root.dim
                elide: Text.ElideRight
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                id: msg
                anchors { left: who.right; leftMargin: Math.round(root.px * 0.9)
                          right: parent.right; top: parent.top; topMargin: 2 }
                text: line.modelData.summary
                      + (line.modelData.body !== "" ? ("  " + line.modelData.body) : "")
                color: line.crit ? root.alarm : root.ink
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: root.font; font.pixelSize: root.px
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: (root.ctx.entries || []).length === 0
        text: root.ctx.dnd ? "do not disturb" : "log empty"
        color: root.faint
        font.family: root.font; font.pixelSize: root.px
    }
}
