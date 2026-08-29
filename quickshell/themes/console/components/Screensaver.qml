pragma ComponentBehavior: Bound
import QtQuick

// Console idling out loud. A dimmed clock says the machine is on; this says what it is doing while
// you are not there.
//
//   IDLE
//   host    velumeron
//   uptime  3d 05:33
//   cpu     2 %      memory 31 %
//
//   23:41:07
//
// Left-aligned on a margin rather than centred: centred type reads as a title card, and this is a
// terminal that happens to have nothing to do.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent   || "#b269e0"
    readonly property color ink:    root.pal.fgBright || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted  || "#6b5480"

    readonly property int px:  Math.round(Math.max(13, Math.min(20, root.height * 0.016)))
    readonly property var load: root.ctx.load || ({})

    // Console's own ground. The screensaver runs a slideshow underneath, and a bright picture with
    // white monospace on it is unreadable — the shipped face gets away with a dimmed clock because
    // a clock is three big glyphs, while a report is forty small ones. Not black: a wash of the
    // scheme's own ground, so the picture darkens in its own colour instead of being punched out.
    Rectangle {
        anchors.fill: parent
        color: root.pal.bgPrimary || "#06030a"
        opacity: 0.82
    }

    Column {
        anchors { left: parent.left; leftMargin: Math.round(root.width * 0.08)
                  verticalCenter: parent.verticalCenter }
        spacing: Math.round(root.px * 0.45)

        Text {
            text: "IDLE"
            color: root.accent
            font.family: root.font; font.pixelSize: Math.round(root.px * 0.9)
            font.letterSpacing: root.px * 0.34
            bottomPadding: root.px
        }

        Line { k: "host";   v: root.ctx.host || "" }
        Line { k: "uptime"; v: root.ctx.uptime || "" }
        Line { k: "cpu";    v: (root.load.cpu || 0) + " %" }
        Line { k: "memory"; v: (root.load.mem || 0) + " %" }
        Line { k: "playing"
               v: (root.ctx.media && root.ctx.media.title !== "") ? root.ctx.media.title : "nothing" }

        Item { width: 1; height: root.px * 1.6 }

        // The time, big, and the seconds with it: a screensaver is the one surface where a running
        // second hand is the point rather than a distraction.
        Text {
            text: root.ctx.now ? Qt.formatTime(root.ctx.now, "hh:mm:ss") : ""
            color: root.ink
            font.family: root.font
            font.pixelSize: Math.round(root.height * 0.115)
            font.letterSpacing: root.height * 0.004
        }
        Text {
            text: root.ctx.now ? Qt.formatDate(root.ctx.now, "dddd, dd MMMM").toUpperCase() : ""
            color: root.faint
            font.family: root.font; font.pixelSize: Math.round(root.px * 0.85)
            font.letterSpacing: root.px * 0.3
        }
    }

    component Line: Row {
        id: ln
        property string k: ""
        property string v: ""
        spacing: Math.round(root.px * 0.9)
        Text { width: Math.round(root.px * 6); text: ln.k; color: root.faint
               font.family: root.font; font.pixelSize: root.px }
        Text { text: ln.v; color: root.ink
               font.family: root.font; font.pixelSize: root.px }
    }
}
