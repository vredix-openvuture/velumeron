pragma ComponentBehavior: Bound
import QtQuick

// Console's window switcher is every window on the machine as a list, not a row of thumbnails.
//
//   ▸ kitty        ~/DEV/velumeron
//     firefox      Velumeron — the wiki
//     obsidian     Openvuture
//
// A thumbnail strip answers "which one looks like the one I want"; a list answers "which one is
// it", and on a machine with nine terminals open the second question is the one you actually have.
//
// The shell keeps the keyboard, the most-recently-used order and the raise on release.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgBright  || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"

    readonly property int px:   Math.round(Math.max(12, Math.min(15, root.height * 0.11)))
    readonly property int rowH: Math.round(root.px * 1.85)

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        interactive: false
        model: root.ctx.windows || []
        currentIndex: root.ctx.index || 0
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: win
            required property var modelData
            required property int index
            readonly property bool on: win.index === list.currentIndex
            width: list.width
            height: root.rowH

            Rectangle {
                anchors.fill: parent
                color: win.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
                              : "transparent"
            }
            Text {
                id: mark
                anchors { left: parent.left; leftMargin: Math.round(root.px * 0.4)
                          verticalCenter: parent.verticalCenter }
                text: "▸"
                color: root.accent
                opacity: win.on ? 1 : 0
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                id: cls
                anchors { left: mark.right; leftMargin: Math.round(root.px * 0.8)
                          verticalCenter: parent.verticalCenter }
                width: Math.round(root.px * 11)
                text: win.modelData["class"]
                color: win.on ? root.accent : root.ink
                elide: Text.ElideRight
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                anchors { left: cls.right; leftMargin: Math.round(root.px * 1.2)
                          right: parent.right; rightMargin: Math.round(root.px * 0.6)
                          verticalCenter: parent.verticalCenter }
                text: win.modelData.title
                color: root.faint
                elide: Text.ElideRight
                font.family: root.font; font.pixelSize: root.px
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: (root.ctx.windows || []).length === 0
        text: "no windows"
        color: root.faint
        font.family: root.font; font.pixelSize: root.px
    }
}
