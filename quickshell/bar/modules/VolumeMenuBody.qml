pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The sound rack — a hardware face, not a list.
//
// Four earlier attempts were all the same architecture underneath: a column of rectangular tiles
// with rectangular bars inside them. Swapping what went in the boxes could never fix that. This is
// the shape a mixing desk actually has, and it is built around the one thing a desk is good at:
//
//   · a METER BRIDGE across the top showing every channel at once — outputs, inputs, apps, all of
//     them, so "what is making noise" is answered by looking rather than by opening something
//   · a KNOB per channel underneath it
//   · one DETAIL STRIP at the foot for the channel you selected — ports, profile, routing, format
//     get one place instead of one tile each. That strip is why there are no tiles at all now.
//
// Three sources feed it, because no single one has everything:
//   · Quickshell's Pipewire   live volume / mute / peaks, and the node list
//   · audio-route.py streams  which device each stream plays on + its media title (not exposed)
//   · audio-route.py devices  ports, card profiles, sample format, Bluetooth codec (not exposed)
// The script feeds are polled only while the panel is open and refreshed the moment an action
// lands, so a closed panel costs nothing.
Item {
    id: root
    property bool active: false
    implicitHeight: frame.implicitHeight

    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

    // One tick drives every meter — a timer per channel would be a wake-up per channel.
    property int tick: 0
    Timer { interval: 55; repeat: true; running: root.active; onTriggered: root.tick++ }

    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _isOwn(n) { return root._ownStreams.indexOf(("" + ((n && n.name) ?? "")).toLowerCase()) >= 0 }

    function _sinks()   { return Pipewire.nodes.values.filter(n => n && n.isSink && !n.isStream && n.audio) }
    function _sources() { return Pipewire.nodes.values.filter(n => n && !n.isSink && !n.isStream && n.audio
                                                                && ("" + (n.name ?? "")).indexOf("monitor") < 0) }
    function _apps()    { return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio && n.isSink && !root._isOwn(n)) }
    function _recs()    { return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio && !n.isSink) }

    // Every channel on the desk, in desk order: outputs, inputs, then what is running through them.
    readonly property var channels: {
        var out = []
        var s = root._sinks();   for (var i = 0; i < s.length; i++) out.push({ node: s[i], kind: "OUT" })
        var p = root._sources(); for (var j = 0; j < p.length; j++) out.push({ node: p[j], kind: "IN" })
        var a = root._apps();    for (var k = 0; k < a.length; k++) out.push({ node: a[k], kind: "APP" })
        var r = root._recs();    for (var m = 0; m < r.length; m++) out.push({ node: r[m], kind: "REC" })
        return out
    }
    property string selId: ""
    readonly property var sel: {
        var c = root.channels
        for (var i = 0; i < c.length; i++) if ("" + c[i].node.id === root.selId) return c[i]
        return c.length > 0 ? c[0] : null
    }

    function _label(n) {
        if (!n) return "—"
        return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "—")
    }
    function _short(ch) {
        if (!ch) return ""
        var n = ch.node
        if (ch.kind === "APP" || ch.kind === "REC") return "" + (n.name ?? "")
        var l = root._label(n)
        // A desk strip is 60px wide: "Built-in Audio Analog Stereo" has to become "Built-in".
        return l.split(/[ (]/)[0]
    }
    function _appIcon(n) {
        var nm = ("" + ((n && n.name) ?? "")).trim()
        if (nm === "") return ""
        var e = DesktopEntries.heuristicLookup(nm)
        return Quickshell.iconPath((e && e.icon) ? e.icon : nm.toLowerCase(), "application-x-executable")
    }
    function _nodeByName(nm) {
        var ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++) if (ns[i] && ns[i].name === nm) return ns[i]
        return null
    }
    function _deviceLabelFor(nm) { var n = root._nodeByName(nm); return n ? root._label(n) : (nm === "" ? "—" : nm) }
    function isDefault(ch) {
        if (!ch) return false
        return ch.kind === "OUT" ? ch.node === Pipewire.defaultAudioSink
             : ch.kind === "IN"  ? ch.node === Pipewire.defaultAudioSource : false
    }

    // ── Script feeds ───────────────────────────────────────────────────────────────────────────
    property var _routes:  ({})
    property var _devInfo: ({})
    Process {
        id: streamProc
        property string _acc: ""
        command: ["python3", root.script, "streams"]
        stdout: SplitParser { onRead: line => { streamProc._acc += line } }
        onRunningChanged: if (!running) {
            try {
                var a = JSON.parse(streamProc._acc.trim()), m = {}
                for (var i = 0; i < a.length; i++) m[a[i].nodeId] = a[i]
                root._routes = m
            } catch (e) { /* keep the last good map */ }
            streamProc._acc = ""
        }
    }
    Process {
        id: devProc
        property string _acc: ""
        command: ["python3", root.script, "devices"]
        stdout: SplitParser { onRead: line => { devProc._acc += line } }
        onRunningChanged: if (!running) {
            try {
                var a = JSON.parse(devProc._acc.trim()), m = {}
                for (var i = 0; i < a.length; i++) m[a[i].name] = a[i]
                root._devInfo = m
            } catch (e) { /* keep the last good map */ }
            devProc._acc = ""
        }
    }
    function refresh() {
        streamProc._acc = ""; streamProc.running = false; streamProc.running = true
        devProc._acc    = ""; devProc.running    = false; devProc.running    = true
    }
    onActiveChanged: if (root.active) root.refresh()
    Timer { interval: 2500; repeat: true; running: root.active; onTriggered: root.refresh() }

    Process { id: actProc; onRunningChanged: if (!running) root.refresh() }
    function _act(args) {
        actProc.command = ["python3", root.script].concat(args)
        actProc.running = false; actProc.running = true
    }
    function setDefault(kind, name)    { root._act([kind === "OUT" ? "default-sink" : "default-source", name]) }
    function setPort(devName, port)    { root._act(["set-port", devName, port]) }
    function setProfile(card, profile) { root._act(["set-profile", card, profile]) }
    function moveStream(node, devName) {
        if (!node || !devName) return
        root._act([node.isSink ? "move" : "move-source", "" + node.id, devName])
    }
    function _info(n)  { return (n && root._routes[n.id]) ? root._routes[n.id] : null }
    function _media(n) { var i = root._info(n); return i ? ("" + (i.media ?? "")) : "" }
    function _devOf(n) { var i = root._info(n); return i ? ("" + (i.deviceName ?? "")) : "" }
    function _dev(n)   { return (n && root._devInfo[n.name]) ? root._devInfo[n.name] : null }

    // ── The unit ───────────────────────────────────────────────────────────────────────────────
    Column {
        id: frame
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12

        // ── Meter bridge + knob row: one strip per channel, scrolling sideways if there are many
        StyledRect {
            width: parent.width
            height: 232
            radius: Style.rCard
            color: Style.tint(Colors.bgPrimary, 0.55)

            Flickable {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 12; bottomMargin: 10 }
                contentWidth: strips.width
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: strips
                    height: parent.height
                    spacing: 2
                    Repeater {
                        model: root.channels
                        delegate: ChannelStrip { required property var modelData; ch: modelData }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: root.channels.length === 0
                text: "no audio devices"
                color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 11
            }
        }

        // ── The selected channel, in full. One strip instead of a tile per channel.
        StyledRect {
            width: parent.width
            height: detail.implicitHeight + 24
            radius: Style.rCard
            color: Style.menuRowFill
            visible: root.sel !== null

            Column {
                id: detail
                anchors { left: parent.left; right: parent.right; top: parent.top
                          leftMargin: 14; rightMargin: 14; topMargin: 12 }
                spacing: 8

                readonly property var  ch:   root.sel
                readonly property var  node: detail.ch ? detail.ch.node : null
                readonly property var  au:   detail.node ? detail.node.audio : null
                readonly property bool isDev: detail.ch && (detail.ch.kind === "OUT" || detail.ch.kind === "IN")
                readonly property var  info: root._dev(detail.node)

                Row {
                    width: parent.width
                    spacing: 10
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !detail.isDev
                        width: 24; height: 24; implicitSize: 24
                        source: detail.isDev ? "" : root._appIcon(detail.node)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - (detail.isDev ? 0 : 34) - dMute.width - 12)
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: detail.isDev ? root._label(detail.node) : ("" + (detail.node ? detail.node.name : ""))
                            color: Colors.fgBright
                            font.family: Style.font; font.pixelSize: 14; font.bold: true
                        }
                        Row {
                            spacing: 9
                            MetaTag { text: detail.info ? ("" + (detail.info.format ?? "")) : "" }
                            MetaTag { text: detail.info ? ("" + (detail.info.codec ?? "")) : ""; good: true }
                            MetaTag { text: root.isDefault(detail.ch) ? "default" : ""; good: true }
                            MetaTag {
                                text: detail.isDev ? "" : root._deviceLabelFor(root._devOf(detail.node))
                            }
                            MetaTag { text: detail.isDev ? "" : root._media(detail.node) }
                        }
                    }
                    MuteBtn { id: dMute; anchors.verticalCenter: parent.verticalCenter; au: detail.au }
                }

                // Ports on the surface (a real two- or three-way choice); profiles behind a picker,
                // because one card here offers thirteen and a row of chips buried the panel.
                Flow {
                    width: parent.width
                    spacing: 5
                    visible: detail.isDev
                    Repeater {
                        model: (detail.info && detail.info.ports && detail.info.ports.length > 1)
                               ? detail.info.ports : []
                        delegate: DataChip {
                            required property var modelData
                            label: modelData.label; on: modelData.active === true
                            onTap: if (detail.node) root.setPort(detail.node.name, modelData.name)
                        }
                    }
                    DataChip {
                        visible: detail.isDev && !root.isDefault(detail.ch)
                        label: "Make default"
                        onTap: if (detail.node) root.setDefault(detail.ch.kind, detail.node.name)
                    }
                }
                ChipPicker {
                    width: parent.width
                    visible: !!(detail.isDev && detail.info && detail.info.profiles
                                && detail.info.profiles.length > 1)
                    options: (detail.info && detail.info.profiles) ? detail.info.profiles.map(
                                 p => ({ label: p.label, key: p.name, on: p.active === true })) : []
                    onPicked: key => { if (detail.info) root.setProfile(detail.info.card, key) }
                }
                // A stream's channel: where it goes.
                ChipPicker {
                    width: parent.width
                    visible: !!(detail.ch && !detail.isDev)
                    options: {
                        if (!detail.node) return []
                        var t = detail.node.isSink ? root._sinks() : root._sources()
                        var cur = root._devOf(detail.node)
                        return t.map(d => ({ label: root._label(d), key: d.name, on: d.name === cur }))
                    }
                    onPicked: key => root.moveStream(detail.node, key)
                }
            }
        }
    }

    // ══ Parts ══════════════════════════════════════════════════════════════════════════════════

    component MuteBtn: StyledRect {
        property var au: null
        readonly property bool muted: !!(au && au.muted)
        width: 30; height: 24; radius: 12
        color: muted ? Style.tint(Colors.fgUrgent, 0.28)
             : mh.containsMouse ? Style.controlHover : Style.controlFill
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: parent.muted ? "󰝟" : "󰕾"
               color: parent.muted ? Colors.fgUrgent : Colors.fgPrimary
               font.family: Style.font; font.pixelSize: 12 }
        MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                    onClicked: if (parent.au) parent.au.muted = !parent.au.muted }
    }

    // One channel of the desk: LED meter, knob, name, kind.
    component ChannelStrip: Item {
        id: cs
        property var ch: null
        readonly property var  node:  cs.ch ? cs.ch.node : null
        readonly property var  au:    cs.node ? cs.node.audio : null
        readonly property bool muted: !!(cs.au && cs.au.muted)
        readonly property real vol:   cs.au ? Math.max(0, Math.min(1, cs.au.volume)) : 0
        readonly property bool isSel: cs.node && ("" + cs.node.id) === (root.sel ? "" + root.sel.node.id : "")
        readonly property bool isDef: root.isDefault(cs.ch)

        width: 64; height: 210

        // Live level, fast attack / slow decay — the way a meter reads as motion, not flicker.
        property real lvl: 0
        PwNodePeakMonitor { id: mon; node: cs.node; enabled: root.active }
        Connections {
            target: root
            function onTickChanged() {
                var ps = mon.peaks ?? [], p = 0
                for (var i = 0; i < ps.length; i++) p = Math.max(p, Math.max(0, Math.min(1, ps[i])))
                cs.lvl = p > cs.lvl ? p : cs.lvl * 0.86
            }
        }
        property real shown: cs.vol
        onVolChanged: cs.shown = cs.vol
        Behavior on shown { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: .002 } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Style.rTile
            color: cs.isSel ? Style.tint(Colors.bgActive, 0.16) : "transparent"
            Behavior on color { ColorAnimation { duration: 110 } }
        }

        // ── LED meter
        Column {
            id: leds
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
            spacing: 2
            readonly property int count: 16
            Repeater {
                model: leds.count
                delegate: Rectangle {
                    required property int index
                    // Index 0 is the TOP lamp, so it stands for the loudest step.
                    readonly property real step: (leds.count - index) / leds.count
                    readonly property bool on:   cs.lvl >= step - 0.001
                    width: 22; height: 4; radius: 2
                    color: !on ? Style.tint(Colors.bgPrimary, 0.8)
                         : step > 0.86 ? Colors.fgUrgent
                         : step > 0.68 ? Style.tint(Colors.fgUrgent, 0.5)
                                       : Colors.bgActive
                    opacity: on ? 1.0 : 0.55
                }
            }
        }

        // ── Knob
        Item {
            id: knob
            anchors { horizontalCenter: parent.horizontalCenter; top: leds.bottom; topMargin: 10 }
            width: 46; height: 46
            readonly property real a0: 135
            readonly property real sw: 270

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Style.tint(Colors.bgPrimary, 0.8); strokeWidth: 5
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 23; centerY: 23; radiusX: 20; radiusY: 20
                                   startAngle: knob.a0; sweepAngle: knob.sw }
                }
                ShapePath {
                    strokeColor: cs.muted ? Colors.fgMuted
                               : cs.vol > 0.9 ? Colors.fgUrgent
                               : cs.ch && cs.ch.kind === "OUT" ? Colors.bgActive : Style.accent
                    strokeWidth: 5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 23; centerY: 23; radiusX: 20; radiusY: 20
                                   startAngle: knob.a0; sweepAngle: knob.sw * cs.shown }
                }
            }
            Text {
                anchors.centerIn: parent
                text: Math.round(cs.vol * 100) + ""
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                font.family: Style.font; font.pixelSize: 13; font.bold: true
            }
            // Pointer, so the knob reads as turned rather than merely filled.
            Rectangle {
                readonly property real ang: (knob.a0 + knob.sw * cs.shown) * Math.PI / 180
                width: 2; height: 7; radius: 1
                color: cs.muted ? Colors.fgMuted : Colors.fgBright
                x: 23 + Math.cos(ang) * 15 - width / 2
                y: 23 + Math.sin(ang) * 15 - height / 2
                rotation: (knob.a0 + knob.sw * cs.shown) + 90
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -5
                property real y0: 0
                property real v0: 0
                onPressed: e => { y0 = e.y; v0 = cs.vol; root.selId = cs.node ? "" + cs.node.id : "" }
                onPositionChanged: e => {
                    if (!pressed || !cs.au) return
                    cs.au.muted = false
                    cs.au.volume = Math.max(0, Math.min(1, Math.round((v0 - (e.y - y0) / 120) * 20) / 20))
                }
                onWheel: e => { if (cs.au) cs.au.volume =
                    Math.max(0, Math.min(1, cs.au.volume + (e.angleDelta.y > 0 ? .05 : -.05))) }
            }
        }

        // ── Name + kind
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: knob.bottom; topMargin: 8 }
            width: parent.width - 4
            spacing: 3
            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: cs.ch && (cs.ch.kind === "APP" || cs.ch.kind === "REC")
                width: 16; height: 16; implicitSize: 16
                source: visible ? root._appIcon(cs.node) : ""
                opacity: cs.muted ? 0.45 : 1.0
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root._short(cs.ch)
                color: cs.isSel ? Colors.fgBright : Colors.fgPrimary
                font.family: Style.font; font.pixelSize: 10; font.bold: cs.isSel
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: cs.ch ? cs.ch.kind : ""
                color: cs.isDef ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 8; font.bold: cs.isDef; font.letterSpacing: 0.5
            }
        }

        // Selecting a channel is what fills the detail strip; the knob's own press does it too.
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: root.selId = cs.node ? "" + cs.node.id : ""
        }
    }
}
