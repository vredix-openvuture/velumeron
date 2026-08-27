pragma ComponentBehavior: Bound
import QtQuick

// Console's own settings page, supplied by the THEME.
//
// This is the point of the third seam: the range of adjustment you get is the THEME's, not a global
// one. Console offers a rail, a seconds block and a bracket weight, because those are the things
// Console has. Mirobo would offer nothing of the sort.
//
// It draws its own controls rather than using the shell's, for the same reason it draws its own
// lock: it cannot see the shell's component library any more than it can see Style, and a rounded
// toggle in the middle of a terminal would be the wrong answer even if it could. Everything arrives
// in `ctx` — the palette, the tokens, the theme's own settings, and the one call that writes them.
//
// Values land in settings.json as `theme_console_<key>`, so they cannot collide with a shell key or
// with another theme's, and switching away and back gives you your knobs again.
Item {
    id: root

    property var ctx: ({})

    readonly property var  pal:  root.ctx.palette || ({})
    readonly property var  set:  root.ctx.settings || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#c9a0ff"
    readonly property color ink:    root.pal.fgPrimary || "#dddddd"
    readonly property color faint:  root.pal.fgMuted   || "#888888"
    readonly property color line:   root.pal.boNormal  || "#444444"

    function val(k, def) { var v = root.set[k]; return (v === undefined || v === null) ? def : v }
    function write(k, v) { if (root.ctx.set) root.ctx.set(k, v) }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: 14

            Text {
                text: "// console"
                color: root.faint
                font.family: root.font; font.pixelSize: 12
                font.letterSpacing: 1.6
            }

            Group {
                title: "LOCKSCREEN"
                CheckRow {
                    label: "rail"
                    sub:   "host, kernel, uptime and whatever widgets are on"
                    on:    root.val("lock_rail", true)
                    onToggled: root.write("lock_rail", !root.val("lock_rail", true))
                }
                CheckRow {
                    label: "seconds"
                    sub:   "the accent block beside the time"
                    on:    root.val("lock_seconds", true)
                    onToggled: root.write("lock_seconds", !root.val("lock_seconds", true))
                }
                CheckRow {
                    label: "brackets"
                    sub:   "corner registration marks"
                    on:    root.val("lock_brackets", true)
                    onToggled: root.write("lock_brackets", !root.val("lock_brackets", true))
                }
                PickRow {
                    label: "backdrop"
                    sub:   "how much black console lays over the wallpaper"
                    options: ["clear", "half", "solid"]
                    current: root.val("lock_backdrop", "half")
                    onPicked: (v) => root.write("lock_backdrop", v)
                }
            }
        }
    }

    // ── Console's own controls. Square, hairline, monospaced. ───────────────────────────────────
    component Group: Column {
        id: grp
        property string title: ""
        width: col.width
        spacing: 0

        Row {
            spacing: 8
            bottomPadding: 8
            Text {
                text: grp.title
                color: root.accent
                font.family: root.font; font.pixelSize: 11; font.letterSpacing: 2.2
            }
        }
        Rectangle { width: grp.width; height: 1; color: root.line; opacity: 0.7 }
        Item { width: 1; height: 6 }
    }

    component CheckRow: Item {
        id: cr
        property string label: ""
        property string sub:   ""
        property bool   on:    false
        signal toggled()
        width: col.width
        height: 40

        Rectangle {
            anchors.fill: parent
            color: crHov.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                                       : "transparent"
        }
        Rectangle {
            id: box
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 14; height: 14
            color: "transparent"
            border.width: 1
            border.color: cr.on ? root.accent : root.line
            Text {
                anchors.centerIn: parent
                text: "x"
                visible: cr.on
                color: root.accent
                font.family: root.font; font.pixelSize: 11
            }
        }
        Column {
            anchors { left: box.right; leftMargin: 12; verticalCenter: parent.verticalCenter
                      right: parent.right }
            spacing: 2
            Text { text: cr.label; color: root.ink
                   font.family: root.font; font.pixelSize: 13 }
            Text { text: cr.sub; color: root.faint; visible: cr.sub !== ""
                   width: parent.width; elide: Text.ElideRight
                   font.family: root.font; font.pixelSize: 11 }
        }
        MouseArea {
            id: crHov
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cr.toggled()
        }
    }

    component PickRow: Column {
        id: pr
        property string label: ""
        property string sub:   ""
        property var    options: []
        property string current: ""
        signal picked(string v)
        width: col.width
        spacing: 6
        topPadding: 8

        Text { text: pr.label; color: root.ink; font.family: root.font; font.pixelSize: 13 }
        Text { text: pr.sub; color: root.faint; visible: pr.sub !== ""
               font.family: root.font; font.pixelSize: 11 }
        Row {
            spacing: 6
            Repeater {
                model: pr.options
                delegate: Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool on: pr.current === opt.modelData
                    width: optT.implicitWidth + 20; height: 24
                    color: opt.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                         : optHov.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
                         : "transparent"
                    border.width: 1
                    border.color: opt.on ? root.accent : root.line
                    Text {
                        id: optT
                        anchors.centerIn: parent
                        text: "" + opt.modelData
                        color: opt.on ? root.accent : root.faint
                        font.family: root.font; font.pixelSize: 12
                    }
                    MouseArea {
                        id: optHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pr.picked(opt.modelData)
                    }
                }
            }
        }
    }
}
