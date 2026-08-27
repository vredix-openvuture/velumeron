pragma ComponentBehavior: Bound
import QtQuick

// Console's bar is not a bar. It is a status line: one row of text along the bottom that reads out
// what the machine is doing, in the order you would ask.
//
//   [3] user@host  ws 3/9   up 3d 05:33   ♪ ascend   bat 84%              23:56
//
// The workspace marker is inverted rather than outlined, because on a phosphor screen a filled
// block is the only mark that reads at a glance from across the room.
//
// Everything comes from `ctx`; this file cannot see the shell's singletons. See Style.themeContext()
// for the shared half and Bar.qml's barContext() for the rest.
//
// NOT DECLARED IN theme.json YET, and this is why: measured in the capture rig, this component
// loads, is handed a complete context (`user vredix`, a live clock, real workspaces) and paints its
// own background across the strip — a probe fill showed up at x 429..2130, y 1412..1439 — but none
// of its TEXT reaches the screen. The Row reports a width of 327 px and the label a width of 45 px,
// so the items exist and are laid out; they simply do not draw, and a plain Text with a fixed size
// and colour and no binding at all behaves the same. Ruled out so far: the context not arriving,
// zero geometry, the font, and the material layer covering it.
//
// Until that is understood, Console's bar is the shipped bar under Console's arrangement and tokens,
// which works. Declaring a component that renders an empty strip would be worse than not having one.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgPrimary || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"
    readonly property color ground: root.pal.bgPrimary || "#040207"

    readonly property int px: Math.round(Math.max(10, Math.min(13, root.height * 0.42)))
    readonly property int gap: Math.round(root.px * 1.9)

    // A vertical strip would need the whole line rotated, and a status line read sideways is not a
    // status line. Console's arrangement puts the bar on the bottom; on any other edge it says so
    // rather than drawing something it does not mean.
    readonly property bool horizontal: root.ctx.horizontal !== false

    // The rule along the inner edge. Not a border on a panel — the panel has no border; this is the
    // line the screen is divided by.
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
        visible: root.horizontal
    }

    Row {
        id: line
        visible: root.horizontal
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: root.gap

        // The focused workspace, inverted. The others are slots, dim, so the row also tells you how
        // many there are without a second widget for it.
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(root.px * 0.55)
            Repeater {
                model: root.ctx.workspaces || []
                delegate: Rectangle {
                    id: ws
                    required property var modelData
                    width: Math.max(root.px * 1.3, wsT.implicitWidth + root.px * 0.8)
                    height: Math.round(root.px * 1.5)
                    color: ws.modelData.focused ? root.accent : "transparent"
                    Text {
                        id: wsT
                        anchors.centerIn: parent
                        text: "" + ws.modelData.slot
                        color: ws.modelData.focused ? root.ground
                             : ws.modelData.occupied ? root.ink : root.faint
                        font.family: root.font; font.pixelSize: root.px
                    }
                }
            }
        }

        Field { k: ""; v: (root.ctx.user || "user") + "@" + (root.ctx.host || "velumeron") }
        Field { k: "up"; v: root.ctx.uptime || "" }
        Field {
            k: root.ctx.media && root.ctx.media.playing ? "♪" : ""
            v: root.ctx.media ? root.ctx.media.title : ""
            show: !!(root.ctx.media && root.ctx.media.title !== "")
            max: Math.round(root.width * 0.22)
        }
        Field {
            k: "bat"
            v: root.ctx.battery ? (root.ctx.battery.percent + "%"
                                   + (root.ctx.battery.charging ? " +" : "")) : ""
            show: !!(root.ctx.battery && root.ctx.battery.present)
        }
    }

    Text {
        visible: root.horizontal
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: root.ctx.now ? Qt.formatTime(root.ctx.now, "hh:mm") : ""
        color: root.ink
        font.family: root.font; font.pixelSize: root.px
        font.letterSpacing: root.px * 0.06
    }

    // On an edge Console does not arrange for, say so instead of drawing a sideways status line.
    Text {
        visible: !root.horizontal
        anchors.centerIn: parent
        rotation: -90
        text: "console: bar is a bottom edge"
        color: root.faint
        font.family: root.font; font.pixelSize: root.px
    }

    // key value, the key dim and the value bright. The whole line is built out of this one shape,
    // which is what makes it read as a report rather than as a row of unrelated widgets.
    component Field: Row {
        id: f
        property string k: ""
        property string v: ""
        property bool   show: true
        property int    max: 0
        visible: f.show && f.v !== ""
        spacing: Math.round(root.px * 0.6)
        anchors.verticalCenter: parent.verticalCenter
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: f.k !== ""
            text: f.k
            color: root.faint
            font.family: root.font; font.pixelSize: root.px
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: f.v
            color: root.ink
            font.family: root.font; font.pixelSize: root.px
            width: f.max > 0 ? Math.min(f.max, implicitWidth) : implicitWidth
            elide: Text.ElideRight
        }
    }
}
