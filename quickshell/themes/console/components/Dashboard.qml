pragma ComponentBehavior: Bound
import QtQuick

// Console's dashboard is a status report you can operate, not a raster of tiles you scan.
//
//   MACHINE                  LOAD                     SESSION
//   host    velumeron        cpu     4 %              user      vredix
//   kernel  7.1.8-1-cachyos  memory  38 %             workspace slot 3
//
//   CONTROL ─────────────────────────────────────────────────────────
//   vol    ████████░░░░░░░░  72 %
//   power  [perf] [balanced] [saver]
//   go     launcher  wallpaper  notifications  keys  lock
//
// The top half reads, the bottom half acts. A report you cannot act on is a poster, and the shell's
// own dashboard is a grid of controls — so this one carries the same handles in its own voice: a
// meter you drag, a bracket you tick, a word you click. They all go through `ctx.actions`, which is
// the same state the shipped tiles drive, so a theme and a tile can never disagree about the volume.
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

    // Body size. The floor is the shell's own row-label size (tokens.fsLabel, 13) rather than
    // something smaller: docked, this panel is ~420 px wide, and a size derived from that width
    // alone landed on 11 px — a report you lean in to read. It still grows with a wide floating
    // panel, it just never goes under what every other row in the shell uses.
    readonly property int base: (root.ctx.tokens && root.ctx.tokens.fsLabel) ? root.ctx.tokens.fsLabel : 13
    readonly property int px:  Math.round(Math.max(root.base, Math.min(root.base + 4, root.width * 0.013)))
    readonly property int gap: Math.round(root.px * 2.2)

    // Above 85 % is a problem, above 65 % is worth a glance. Two thresholds, because a third would
    // be a colour nobody can name at a distance.
    function tone(pct) { return pct >= 85 ? root.alarm : pct >= 65 ? root.warm : root.ink }

    // What the report is made of. Console has no raster to arrange, so the shell's dashboard editor
    // stays out of the way (see HomeHub) and THIS is the adjustment on offer instead: which blocks
    // stand, and how many columns the reading half is allowed. Written by the theme's settings card
    // as `theme_console_dash_*`.
    readonly property var set: root.ctx.settings || ({})
    function on(k) { return root.set[k] !== false }        // absent means on
    readonly property bool hasMachine: root.on("dash_machine")
    readonly property bool hasLoad:    root.on("dash_load")
    readonly property bool hasSession: root.on("dash_session")
    readonly property bool hasControl: root.on("dash_control")
    readonly property bool hasGo:      root.on("dash_go")

    readonly property var load: root.ctx.load || ({})
    readonly property var battery: root.ctx.battery || ({})
    readonly property var media: root.ctx.media || ({})
    readonly property var notifications: root.ctx.notifications || ({})
    readonly property var workspaces: root.ctx.workspaces || []
    readonly property var live: root.ctx.state || ({})
    readonly property var actions: root.ctx.actions || ({})
    readonly property int wsFocused: {
        for (var i = 0; i < root.workspaces.length; i++)
            if (root.workspaces[i].focused) return root.workspaces[i].slot
        return 0
    }
    function act(name, arg) { if (root.actions[name]) root.actions[name](arg) }

    // Three columns need room for three. The settings panel is about 420 px wide docked and much
    // wider floating, and a three-column report at 420 px is three columns of ellipses — so the
    // width sets a CEILING and the setting picks anything at or under it. Asking for three on a
    // narrow panel still gets you what fits, which is why this is a clamp and not an override.
    readonly property int fitCols: root.width >= root.px * 62 ? 3
                                 : root.width >= root.px * 40 ? 2 : 1
    readonly property int wantCols: Math.max(1, Math.min(3, root.set.dash_columns || 3))
    readonly property int cols: Math.max(1, Math.min(root.fitCols, root.wantCols))
    readonly property real colW: (root.width - root.gap * (root.cols - 1)) / root.cols
    readonly property int keyW: Math.round(root.px * 6)

    // ── Pages, not a scroll ─────────────────────────────────────────────────────────────────────
    // The panel is not always as tall as the report is long — docked it is a column about 460 px
    // wide, and the CONTROL half runs past the bottom. This used to be a Flickable, which meant the
    // dashboard ended mid-row: half a "go" line at the fold, and the rest behind a scroll nobody
    // was told about. The shipped raster does not do that — it turns whole PAGES — and this is the
    // same rule in this theme's own terms: a page break falls BETWEEN blocks, never inside one.
    //
    // A block is any leaf of the report: a reading block, a meter, the power row. Containers that
    // are only there for spacing mark themselves `pageUnits` so the break can fall inside them.
    readonly property real markH: Math.round(root.px * 1.7)     // the page mark's own line
    readonly property real viewH: Math.max(0, root.height - root.markH)

    property int pageIdx: 0
    readonly property int pages: root.tops.length
    onPagesChanged: if (root.pageIdx > root.pages - 1) root.pageIdx = Math.max(0, root.pages - 1)

    function _collect(item, offset, out) {
        var kids = item.children
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (!k || k.visible === false || k.height <= 0) continue
            if (k.pageUnits === true) root._collect(k, offset + k.y, out)
            else out.push({ "top": offset + k.y, "bottom": offset + k.y + k.height,
                            "keep": k.keepWithNext === true })
        }
    }
    // Every block the report is currently drawing, top to bottom. Recomputed whenever anything that
    // could move one changes — the listed dependencies are read for exactly that reason.
    readonly property var units: {
        var _deps = [page.implicitHeight, root.viewH, root.cols, root.px,
                     root.hasMachine, root.hasLoad, root.hasSession, root.hasControl, root.hasGo]
        var out = []
        root._collect(page, 0, out)
        return out
    }
    // Where each page starts. A block that would not fit whole begins the next one instead of being
    // cut, and a heading that would be left standing alone at the foot goes along with it.
    readonly property var tops: {
        var units = root.units
        var out = [0], top = 0
        for (var i = 0; i < units.length; i++) {
            var u = units[i]
            if (u.bottom - top <= root.viewH || u.top <= top) continue
            var start = (i > 0 && units[i - 1].keep && units[i - 1].top > top) ? units[i - 1].top
                                                                              : u.top
            top = start
            out.push(top)
        }
        return out
    }

    // How tall the page ON SHOW is: up to the next break, never past the panel. Clipping to the
    // PANEL alone was not enough — the break was computed right, but the window it was shown
    // through still ran to the bottom edge, so the first rows of the block that starts the NEXT
    // page were drawn under the fold. That was the half "flags" row. The window ends where the
    // page does, and that is a block boundary by construction.
    readonly property real pageH: {
        var i = Math.max(0, Math.min(root.tops.length - 1, root.pageIdx))
        var next = (i + 1 < root.tops.length) ? root.tops[i + 1] : page.implicitHeight
        return Math.max(0, Math.min(root.viewH, next - root.tops[i]))
    }

    Item {
        id: viewport
        anchors { fill: parent; bottomMargin: root.markH }

    Item {
        id: fold
        width: parent.width
        height: root.pageH
        clip: true
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Column {
        id: page
        anchors { left: parent.left; right: parent.right; top: parent.top }
        y: -(root.tops[Math.max(0, Math.min(root.tops.length - 1, root.pageIdx))] || 0)
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        spacing: Math.round(root.px * 1.3)

        Grid {
            // Side by side these share a top edge, so they read as one unit anyway; stacked in one
            // column each block can start a page of its own.
            property bool pageUnits: true
            visible: root.hasMachine || root.hasLoad || root.hasSession
            width: parent.width
            columns: root.cols
            columnSpacing: root.gap
            rowSpacing: Math.round(root.px * 1.4)

            Section {
                visible: root.hasMachine
                width: root.colW
                title: "MACHINE"
                rows: [{ k: "host",   v: root.ctx.host   || "" },
                       { k: "kernel", v: root.ctx.kernel || "" },
                       { k: "uptime", v: root.ctx.uptime || "" },
                       { k: "time",   v: root.ctx.now ? Qt.formatTime(root.ctx.now, "hh:mm:ss") : "" }]
            }
            Section {
                visible: root.hasLoad
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
                visible: root.hasSession
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

        // ── The half you operate ────────────────────────────────────────────────────────────────
        Column {
            property bool pageUnits: true
            visible: root.hasControl || root.hasGo
            width: parent.width
            spacing: Math.round(root.px * 0.45)

            // The heading names whatever is actually under it: with the controls switched off the
            // go line is the only thing left, and "CONTROL" over a row of links is a wrong label.
            Rule {
                // Never the last thing on a page: a heading at the foot promises a block that is
                // on the next one.
                property bool keepWithNext: true
                width: parent.width; title: root.hasControl ? "CONTROL" : "GO"
            }
            Item { width: 1; height: Math.round(root.px * 0.4) }

            Meter {
                visible: root.hasControl
                width: parent.width
                k: root.live.muted ? "mute" : "vol"
                level: root.live.volume || 0
                lit: !root.live.muted
                onSetLevel: (v) => root.act("volume", v)
                onKeyClicked: root.act("mute")
            }
            Meter {
                visible: root.hasControl
                width: parent.width
                k: "lum"
                level: root.live.brightness === undefined ? 1 : root.live.brightness
                onSetLevel: (v) => root.act("brightness", v)
            }

            Item { visible: root.hasControl; width: 1; height: Math.round(root.px * 0.4) }

            Picks {
                visible: root.hasControl
                width: parent.width
                k: "power"
                options: [{ v: "performance", l: "perf" },
                          { v: "balanced",    l: "balanced" },
                          { v: "power-saver", l: "saver" }]
                current: root.live.profile || "balanced"
                onPicked: (v) => root.act("profile", v)
            }
            Flags    { visible: root.hasControl; width: parent.width }
            Commands { visible: root.hasGo;      width: parent.width }
        }
    }

    }

        // Wheel turns the page, and it wraps. Accumulated to a full detent and rate-limited, or a
        // touchpad swipe (many small deltas) runs through every page at once. NoButton, so a notch
        // over a meter still reaches the meter's own drag.
        MouseArea {
            id: turner
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            enabled: root.pages > 1
            property int  acc: 0
            property bool cooling: false
            Timer { id: turnCool; interval: 320; onTriggered: turner.cooling = false }
            onWheel: wheel => {
                if (root.pages <= 1) return
                if (turner.cooling) { turner.acc = 0; return }
                if ((turner.acc > 0) !== (wheel.angleDelta.y > 0)) turner.acc = 0
                turner.acc += wheel.angleDelta.y
                if (Math.abs(turner.acc) < 120) return
                root.pageIdx = (root.pageIdx + (turner.acc < 0 ? 1 : -1) + root.pages) % root.pages
                turner.acc = 0
                turner.cooling = true
                turnCool.restart()
            }
        }
    }

    // Which page of how many, and the way to the others. The line is reserved whether or not there
    // is a second page (`markH`), so switching a block off cannot change the height the page break
    // is computed from — that would be a binding that feeds itself.
    Row {
        anchors { right: parent.right; bottom: parent.bottom }
        visible: root.pages > 1
        spacing: Math.round(root.px * 0.8)

        Repeater {
            model: root.pages
            delegate: Text {
                id: dot
                required property int index
                readonly property bool on: dot.index === root.pageIdx
                text: dot.on ? "[" + (dot.index + 1) + "]" : "" + (dot.index + 1)
                color: dot.on ? root.accent : (dotHov.containsMouse ? root.ink : root.faint)
                font.family: root.font; font.pixelSize: root.px
                MouseArea {
                    id: dotHov
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pageIdx = dot.index
                }
            }
        }
    }

    // A heading and the rule that ends it — on a screen with no boxes, the rule is what says where
    // a section stops.
    component Rule: Row {
        id: rule
        property string title: ""
        spacing: Math.round(root.px * 0.9)
        Text {
            id: ruleT
            text: rule.title
            color: root.accent
            font.family: root.font; font.pixelSize: Math.round(root.px * 0.82)
            font.letterSpacing: root.px * 0.26
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, rule.width - ruleT.width - root.px * 0.9)
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
        }
    }

    // A heading, a rule, and the lines under it.
    component Section: Column {
        id: sec
        property string title: ""
        property var rows: []
        spacing: Math.round(root.px * 0.28)

        Rule { width: sec.width; title: sec.title }
        Item { width: 1; height: Math.round(root.px * 0.5) }

        Repeater {
            model: sec.rows
            delegate: Row {
                id: kv
                required property var modelData
                width: sec.width
                spacing: Math.round(root.px * 0.9)
                Text {
                    width: root.keyW
                    text: kv.modelData.k !== undefined ? ("" + kv.modelData.k) : ""
                    color: root.faint
                    font.family: root.font; font.pixelSize: root.px
                }
                Text {
                    width: sec.width - root.keyW - root.px * 0.9
                    text: kv.modelData.v !== undefined ? ("" + kv.modelData.v) : ""
                    color: kv.modelData.c !== undefined ? kv.modelData.c : root.ink
                    elide: Text.ElideRight
                    font.family: root.font; font.pixelSize: root.px
                }
            }
        }
    }

    // A level you can set: the OSD's block meter, with the cell count measured against the width it
    // actually has. Press or drag anywhere on the cells; the key itself is the mute switch.
    component Meter: Item {
        id: m
        property string k: ""
        property real   level: 0
        property bool   lit: true
        signal setLevel(real v)
        signal keyClicked()
        height: Math.round(root.px * 1.7)

        TextMetrics { id: cellM; font.family: root.font; font.pixelSize: root.px; text: "█" }
        readonly property real cellW: cellM.advanceWidth > 0 ? cellM.advanceWidth : root.px * 0.6
        readonly property real span:  Math.max(0, m.width - root.keyW - root.px * 5)
        readonly property int  cells: Math.max(6, Math.min(28, Math.floor(m.span / m.cellW)))
        readonly property int  filled: Math.round(Math.max(0, Math.min(1, m.level)) * m.cells)

        Text {
            id: mk
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: root.keyW
            text: m.k
            color: keyHov.containsMouse ? root.accent : root.faint
            font.family: root.font; font.pixelSize: root.px
            MouseArea {
                id: keyHov
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: m.keyClicked()
            }
        }
        Text {
            id: cellsT
            anchors { left: mk.right; verticalCenter: parent.verticalCenter }
            text: {
                var on = "", off = ""
                for (var i = 0; i < m.filled; i++) on += "█"
                for (var j = m.filled; j < m.cells; j++) off += "░"
                return on + off
            }
            color: m.lit ? root.ink : root.faint
            font.family: root.font; font.pixelSize: root.px
            MouseArea {
                anchors { fill: parent; topMargin: -5; bottomMargin: -5 }
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function apply(x) { m.setLevel(Math.max(0, Math.min(1, x / Math.max(1, cellsT.width)))) }
                onPressed: (e) => apply(e.x)
                onPositionChanged: (e) => { if (pressed) apply(e.x) }
            }
        }
        Text {
            anchors { left: cellsT.right; leftMargin: Math.round(root.px * 0.9)
                      verticalCenter: parent.verticalCenter }
            text: Math.round(Math.max(0, Math.min(1, m.level)) * 100) + " %"
            color: root.ink
            font.family: root.font; font.pixelSize: root.px
        }
    }

    // One key, a row of bracketed words, one of them lit.
    component Picks: Row {
        id: pk
        property string k: ""
        property var    options: []
        property string current: ""
        signal picked(string v)
        height: Math.round(root.px * 1.8)
        spacing: Math.round(root.px * 0.9)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.keyW
            text: pk.k
            color: root.faint
            font.family: root.font; font.pixelSize: root.px
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(root.px * 0.6)
            Repeater {
                model: pk.options
                delegate: Text {
                    id: opt
                    required property var modelData
                    readonly property bool on: pk.current === opt.modelData.v
                    text: "[" + opt.modelData.l + "]"
                    color: opt.on ? root.accent : (optHov.containsMouse ? root.ink : root.faint)
                    font.family: root.font; font.pixelSize: root.px
                    MouseArea {
                        id: optHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pk.picked(opt.modelData.v)
                    }
                }
            }
        }
    }

    // The three session switches, as ticked boxes.
    component Flags: Row {
        height: Math.round(root.px * 1.8)
        spacing: Math.round(root.px * 0.9)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.keyW
            text: "flags"
            color: root.faint
            font.family: root.font; font.pixelSize: root.px
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(root.px * 1.4)
            Repeater {
                model: [{ a: "dnd",      l: "dnd",      on: root.live.dnd === true },
                        { a: "night",    l: "night",    on: root.live.night === true },
                        { a: "caffeine", l: "caffeine", on: root.live.caffeine === true }]
                delegate: Text {
                    id: flag
                    required property var modelData
                    text: (flag.modelData.on ? "[x] " : "[ ] ") + flag.modelData.l
                    color: flag.modelData.on ? root.accent
                                             : (flagHov.containsMouse ? root.ink : root.faint)
                    font.family: root.font; font.pixelSize: root.px
                    MouseArea {
                        id: flagHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(flag.modelData.a)
                    }
                }
            }
        }
    }

    // What you can start from here. Words, not buttons — a button would be a shape this screen does
    // not have.
    component Commands: Flow {
        spacing: Math.round(root.px * 1.4)

        Text {
            width: root.keyW
            text: "go"
            color: root.faint
            font.family: root.font; font.pixelSize: root.px
        }
        Repeater {
            model: [{ t: "launcher",      l: "launcher" },
                    { t: "wallpaper",     l: "wallpaper" },
                    { t: "notifications", l: "notifications" },
                    { t: "cheatsheet",    l: "keys" },
                    { t: "lock",          l: "lock" }]
            delegate: Text {
                id: go
                required property var modelData
                text: go.modelData.l
                color: goHov.containsMouse ? root.accent : root.dim
                font.family: root.font; font.pixelSize: root.px
                MouseArea {
                    id: goHov
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.act("fire", go.modelData.t)
                }
            }
        }
    }
}
