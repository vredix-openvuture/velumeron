pragma ComponentBehavior: Bound
import QtQuick

// Console's dashboard is a status report you read, not a raster of tiles you scan.
//
//   MACHINE                  LOAD                     SESSION
//   host    velumeron        cpu     4 %              user      vredix
//   kernel  7.1.8-1-cachyos  memory  38 %             workspace 3 of 9
//   uptime  3d 05:33         disk    61 %             waiting   2
//
// Three columns of key/value lines under ruled headings. The rule after a heading is not decoration
// — it is what tells you where a section ends on a screen that has no boxes.
//
// A figure worth noticing changes colour rather than growing a bar: on a screen made of type,
// colour is the loudest thing available, and a meter next to a number says the same thing twice.
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
    readonly property color warm:   root.pal.boActive  || "#c99367"
    readonly property color alarm:  root.pal.fgUrgent  || "#c25742"

    readonly property int px:  Math.round(Math.max(11, Math.min(14, root.width * 0.011)))
    readonly property int gap: Math.round(root.px * 2.2)

    // Above 85 % is a problem, above 65 % is worth a glance. Two thresholds, because a third would
    // be a colour nobody can name at a distance.
    function tone(pct) { return pct >= 85 ? root.alarm : pct >= 65 ? root.warm : root.ink }

    readonly property var load: root.ctx.load || ({})
    readonly property var battery: root.ctx.battery || ({})
    readonly property var media: root.ctx.media || ({})
    readonly property var notifications: root.ctx.notifications || ({})
    readonly property var workspaces: root.ctx.workspaces || []
    readonly property int wsFocused: {
        for (var i = 0; i < root.workspaces.length; i++)
            if (root.workspaces[i].focused) return root.workspaces[i].slot
        return 0
    }

    // Three columns need room for three. The settings panel is about 420 px wide docked and much
    // wider floating, and a three-column report at 420 px is three columns of ellipses.
    readonly property int cols: root.width >= root.px * 62 ? 3 : 1
    readonly property real colW: (root.width - root.gap * (root.cols - 1)) / root.cols

    Grid {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        columns: root.cols
        columnSpacing: root.gap
        rowSpacing: Math.round(root.px * 1.4)

        Section {
            width: root.colW
            title: "MACHINE"
            rows: [{ k: "host",   v: root.ctx.host   || "" },
                   { k: "kernel", v: root.ctx.kernel || "" },
                   { k: "uptime", v: root.ctx.uptime || "" },
                   { k: "time",   v: root.ctx.now ? Qt.formatTime(root.ctx.now, "hh:mm:ss") : "" }]
        }
        Section {
            width: root.colW
            title: "LOAD"
            rows: [{ k: "cpu",    v: (root.load.cpu  || 0) + " %", c: root.tone(root.load.cpu  || 0) },
                   { k: "memory", v: (root.load.mem  || 0) + " %", c: root.tone(root.load.mem  || 0) },
                   { k: "disk",   v: (root.load.disk || 0) + " %", c: root.tone(root.load.disk || 0) },
                   { k: "battery",
                     v: root.battery.present ? ((root.battery.percent || 0) + " %"
                                                + (root.battery.charging ? "  charging" : ""))
                                             : "on mains",
                     c: root.battery.present && !root.battery.charging
                        ? root.tone(100 - (root.battery.percent || 0)) : root.ink }]
        }
        Section {
            width: root.colW
            title: "SESSION"
            rows: [{ k: "user",      v: root.ctx.user || "" },
                   { k: "workspace", v: root.wsFocused > 0 ? ("slot " + root.wsFocused) : "none" },
                   { k: "waiting",   v: root.notifications.dnd ? "do not disturb"
                                                               : ("" + (root.notifications.count || 0)),
                     c: root.notifications.dnd ? root.faint
                        : (root.notifications.count > 0 ? root.accent : root.ink) },
                   { k: "playing",   v: root.media.title !== "" ? root.media.title : "nothing",
                     c: root.media.playing ? root.accent : root.faint }]
        }
    }

    // A heading, a rule, and the lines under it.
    component Section: Column {
        id: sec
        property string title: ""
        property var rows: []
        spacing: Math.round(root.px * 0.28)

        Row {
            width: sec.width
            spacing: Math.round(root.px * 0.9)
            Text {
                id: secTitle
                text: sec.title
                color: root.accent
                font.family: root.font; font.pixelSize: Math.round(root.px * 0.82)
                font.letterSpacing: root.px * 0.26
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, sec.width - secTitle.width - root.px * 0.9)
                height: 1
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
            }
        }
        Item { width: 1; height: Math.round(root.px * 0.5) }

        Repeater {
            model: sec.rows
            delegate: Row {
                id: kv
                required property var modelData
                width: sec.width
                spacing: Math.round(root.px * 0.9)
                Text {
                    width: Math.round(root.px * 6)
                    text: kv.modelData.k !== undefined ? ("" + kv.modelData.k) : ""
                    color: root.faint
                    font.family: root.font; font.pixelSize: root.px
                }
                Text {
                    width: sec.width - root.px * 6 - root.px * 0.9
                    text: kv.modelData.v !== undefined ? ("" + kv.modelData.v) : ""
                    color: kv.modelData.c !== undefined ? kv.modelData.c : root.ink
                    elide: Text.ElideRight
                    font.family: root.font; font.pixelSize: root.px
                }
            }
        }
    }
}
