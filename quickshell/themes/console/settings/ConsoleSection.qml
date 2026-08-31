pragma ComponentBehavior: Bound
import QtQuick

// Console's own settings, supplied by the THEME.
//
// This is the point of the third seam: the range of adjustment you get is the THEME's, not a global
// one. Console offers a scanline grid, registration marks and a lockscreen rail, because those are
// the things Console has. Mirobo would offer nothing of the sort.
//
// It is not a page in the menu. The shell hosts it as a card on Settings -> Style, under the picker
// that chose the theme, and it is simply absent under a theme that brings nothing.
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

    // Content, not a page: the shell puts this inside a card on the Style page and scrolls it with
    // everything else, so the only thing it owes the shell is a height.
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: root.width
        spacing: 14

        Text {
            text: "// console"
            color: root.faint
            font.family: root.font; font.pixelSize: 12
            font.letterSpacing: 1.6
        }
        Text {
            width: col.width
            wrapMode: Text.WordWrap
            text: "These belong to the Console theme, not to the shell. Wear another theme and "
                  + "they are gone, with their settings kept for when you come back."
            color: root.faint
            font.family: root.font; font.pixelSize: 11
        }

        Group {
            title: "SCREEN"
            CheckRow {
                label: "scanlines"
                sub:   "the phosphor grid over the whole desktop"
                on:    root.val("desk_scanlines", true)
                onToggled: root.write("desk_scanlines", !root.val("desk_scanlines", true))
            }
            CheckRow {
                label: "brackets"
                sub:   "registration marks in two corners, under the windows"
                on:    root.val("desk_brackets", true)
                onToggled: root.write("desk_brackets", !root.val("desk_brackets", true))
            }
            PickRow {
                label: "backdrop"
                sub:   "how far the wallpaper is pushed down behind the screen"
                options: ["clear", "half", "solid"]
                current: root.val("desk_backdrop", "half")
                onPicked: (v) => root.write("desk_backdrop", v)
            }
        }

        // The shell's dashboard editor arranges a raster of tiles. Console's dashboard is a report,
        // so there is no raster to arrange and the pencil in the menu stays away — what there is to
        // decide is which blocks stand and how wide the reading half is allowed to run. That is
        // this group, and it is the theme's own answer to the same question.
        Group {
            title: "DASHBOARD"
            CheckRow {
                label: "machine"
                sub:   "host, kernel, uptime, time"
                on:    root.val("dash_machine", true)
                onToggled: root.write("dash_machine", !root.val("dash_machine", true))
            }
            CheckRow {
                label: "load"
                sub:   "cpu, memory, disk, battery"
                on:    root.val("dash_load", true)
                onToggled: root.write("dash_load", !root.val("dash_load", true))
            }
            CheckRow {
                label: "session"
                sub:   "user, workspace, waiting, playing"
                on:    root.val("dash_session", true)
                onToggled: root.write("dash_session", !root.val("dash_session", true))
            }
            CheckRow {
                label: "control"
                sub:   "the half you operate: vol, lum, power, flags"
                on:    root.val("dash_control", true)
                onToggled: root.write("dash_control", !root.val("dash_control", true))
            }
            CheckRow {
                label: "go"
                sub:   "launcher, wallpaper, notifications, keys, lock"
                on:    root.val("dash_go", true)
                onToggled: root.write("dash_go", !root.val("dash_go", true))
            }
            NumRow {
                label: "columns"
                sub:   "how many blocks stand side by side"
                value: root.val("dash_columns", 3)
                from:  1
                to:    3
                onStepped: (v) => root.write("dash_columns", v)
            }
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

    // A number you step. Square brackets rather than round buttons, and the value between them,
    // because that is how every other figure on this screen is written.
    component NumRow: Item {
        id: nr
        property string label: ""
        property string sub:   ""
        property int    value: 0
        property int    from:  1
        property int    to:    9
        signal stepped(int v)
        width: col.width
        height: 40

        Column {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter
                      right: steps.left; rightMargin: 12 }
            spacing: 2
            Text { text: nr.label; color: root.ink
                   font.family: root.font; font.pixelSize: 13 }
            Text { text: nr.sub; color: root.faint; visible: nr.sub !== ""
                   width: parent.width; elide: Text.ElideRight
                   font.family: root.font; font.pixelSize: 11 }
        }
        Row {
            id: steps
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            Step { text: "-"; enabled: nr.value > nr.from; onFired: nr.stepped(nr.value - 1) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: root.width * 0.06
                horizontalAlignment: Text.AlignHCenter
                text: "" + nr.value
                color: root.accent
                font.family: root.font; font.pixelSize: 13
            }
            Step { text: "+"; enabled: nr.value < nr.to; onFired: nr.stepped(nr.value + 1) }
        }
    }

    // `enabled` is the Item's own: switched off it also stops the MouseArea underneath, so a step
    // at the end of its range cannot be clicked and does not light up under the pointer either.
    component Step: Rectangle {
        id: st
        property string text: ""
        signal fired()
        width: 22; height: 22
        color: (st.enabled && stHov.containsMouse)
               ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : "transparent"
        border.width: 1
        border.color: st.enabled ? root.line : Qt.rgba(root.line.r, root.line.g, root.line.b, 0.4)
        Text {
            anchors.centerIn: parent
            text: st.text
            color: st.enabled ? root.ink : root.faint
            font.family: root.font; font.pixelSize: 12
        }
        MouseArea {
            id: stHov
            anchors.fill: parent; hoverEnabled: true
            cursorShape: st.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: st.fired()
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
