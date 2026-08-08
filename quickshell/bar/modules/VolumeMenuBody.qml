pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The sound dashboard. Not a mixer strip and not a settings form: a panel where every level is the
// area curve of the REAL signal, and every application sits inside the device it plays through as
// an icon with its volume as a ring around it. Routing is a place, not a label — carry a puck to
// another device tile and the stream moves.
//
// Three sources feed it, because no single one has everything:
//   · Quickshell's Pipewire   live volume / mute / peaks / spectrum, and the node list
//   · audio-route.py streams  which device each stream plays on + its media title (not exposed)
//   · audio-route.py devices  ports, card profiles, sample format, Bluetooth codec (not exposed)
// The two script feeds are polled only while the panel is open and refreshed the moment an action
// lands, so a closed panel costs nothing.
//
// Why the script at all: the id Quickshell hands out for a stream is not the id pactl takes —
// node 64 is sink-input 6978 — and pactl reports no card on a sink, so the card's profiles are
// reached through the device id both names share (alsa_card.pci-… ↔ alsa_output.pci-…).
Column {
    id: root
    property bool active: false
    spacing: 12

    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

    // One tick drives every trace and every meter — a timer per tile would be a wake-up per tile.
    property int tick: 0
    Timer { interval: 60; repeat: true; running: root.active; onTriggered: root.tick++ }

    property string tab: "out"          // out | in | apps | rec
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]

    // ── Node lists ─────────────────────────────────────────────────────────────────────────────
    function _sinks()   { return Pipewire.nodes.values.filter(n => n && n.isSink && !n.isStream && n.audio) }
    function _sources() { return Pipewire.nodes.values.filter(n => n && !n.isSink && !n.isStream && n.audio
                                                                && ("" + (n.name ?? "")).indexOf("monitor") < 0) }
    function _allStreams() { return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio) }
    function _apps() {
        return root._allStreams().filter(n => n.isSink
               && root._ownStreams.indexOf(("" + (n.name ?? "")).toLowerCase()) < 0)
    }
    function _recorders() { return root._allStreams().filter(n => !n.isSink) }

    function _label(n) {
        if (!n) return "device"
        return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "device")
    }
    function _appName(n) { return (n && n.name && n.name !== "") ? n.name : ((n && n.description) || "audio") }
    // The ACTIVE icon theme, via the desktop entry — not a glyph.
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

    // ── Script feeds ───────────────────────────────────────────────────────────────────────────
    property var _routes: ({})        // node id → { deviceName, app, media }
    property var _devInfo: ({})       // device node name → { format, codec, ports, profiles, card }

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
            } catch (e) {}
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
            } catch (e) {}
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
    function setDefault(kind, name) { root._act([kind === "sink" ? "default-sink" : "default-source", name]) }
    function moveStream(node, deviceName) {
        if (!node || !deviceName) return
        root._act([node.isSink ? "move" : "move-source", "" + node.id, deviceName])
    }
    function setPort(devName, port)    { root._act(["set-port", devName, port]) }
    function setProfile(card, profile) { root._act(["set-profile", card, profile]) }

    function _info(n)  { return (n && root._routes[n.id]) ? root._routes[n.id] : null }
    function _media(n) { var i = root._info(n); return i ? ("" + (i.media ?? "")) : "" }
    function _devOf(n) { var i = root._info(n); return i ? ("" + (i.deviceName ?? "")) : "" }
    function _dev(n)   { return (n && root._devInfo[n.name]) ? root._devInfo[n.name] : null }
    function _fmt(n)   { var d = root._dev(n); return d ? ("" + (d.format ?? "")) : "" }
    function _codec(n) { var d = root._dev(n); return d ? ("" + (d.codec ?? "")) : "" }

    // ── Level history, shared by every trace ───────────────────────────────────────────────────
    // One store keyed by node id: a tile that scrolls out of view and back keeps its curve.
    property var _hist: ({})
    readonly property int histLen: 56
    function histOf(id) {
        var h = root._hist[id]
        if (h === undefined) { h = new Array(root.histLen).fill(0); root._hist[id] = h }
        return h
    }

    // ── Master ─────────────────────────────────────────────────────────────────────────────────
    StyledRect {
        id: master
        readonly property var  node:  Pipewire.defaultAudioSink
        readonly property var  au:    master.node ? master.node.audio : null
        readonly property bool muted: !!(master.au && master.au.muted)
        readonly property real vol:   master.au ? Math.max(0, Math.min(1, master.au.volume)) : 0

        width: parent.width
        height: masterCol.implicitHeight + 26
        radius: Style.rCard
        color:  Style.tint(Colors.bgActive, 0.18)

        PwAudioSpectrum {
            id: spectrum
            node: master.node; enabled: root.active && !master.muted
            barCount: 48; smoothing: true
        }

        Column {
            id: masterCol
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 15; rightMargin: 15; topMargin: 13 }
            spacing: 9

            Row {
                width: parent.width
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: master.muted ? "󰝟" : "󰕾"
                    color: Colors.fgBright; font.family: Style.font; font.pixelSize: 19
                    MouseArea { anchors.fill: parent; anchors.margins: -5
                                onClicked: if (master.au) master.au.muted = !master.au.muted }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 36 - mPct.implicitWidth - 20)
                    spacing: 2
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root._label(master.node)
                        color: Colors.fgBright; font.family: Style.font; font.pixelSize: 15; font.bold: true
                    }
                    Row {
                        spacing: 6
                        Tag { text: root._fmt(master.node) }
                        Tag { text: root._codec(master.node); good: true }
                        Tag { text: "default" }
                    }
                }
                Text {
                    id: mPct
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(master.vol * 100) + "%"
                    color: Colors.fgBright; font.family: Style.font; font.pixelSize: 21; font.bold: true
                }
            }

            // The spectrum as the master's floor.
            Row {
                width: parent.width
                height: 44
                spacing: 3
                Repeater {
                    model: spectrum.values.length
                    delegate: Rectangle {
                        required property int index
                        readonly property real v: Math.max(0, Math.min(1, spectrum.values[index] ?? 0))
                        width:  Math.max(1, (masterCol.width - 3 * (spectrum.values.length - 1)) / spectrum.values.length)
                        height: Math.max(3, parent.height * v)
                        anchors.bottom: parent.bottom
                        radius: Math.min(3, width / 2, height / 2)
                        color: Style.tint(Colors.bgSecondary, 0.75)
                        opacity: 0.6
                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    }
                }
            }

            VolBar { width: parent.width; au: master.au; big: true }
            Balance { width: parent.width; au: master.au }
        }
    }

    // ── Tabs ───────────────────────────────────────────────────────────────────────────────────
    Segmented {
        width: parent.width
        equal: true
        current: root.tab
        segments: [{ label: "Output "    + root._sinks().length,     key: "out" },
                   { label: "Input "     + root._sources().length,   key: "in" },
                   { label: "Apps "      + root._apps().length,      key: "apps" },
                   { label: "Recording " + root._recorders().length, key: "rec" }]
        onPicked: key => root.tab = key
    }

    // ── Body ───────────────────────────────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 8

        Repeater {
            model: root.tab === "out" ? root._sinks() : root.tab === "in" ? root._sources() : []
            delegate: DeviceTile { required property var modelData; node: modelData }
        }
        Repeater {
            model: root.tab === "apps" ? root._apps() : root.tab === "rec" ? root._recorders() : []
            delegate: StreamTile { required property var modelData; node: modelData }
        }
        Text {
            visible: (root.tab === "out"  ? root._sinks().length
                    : root.tab === "in"   ? root._sources().length
                    : root.tab === "apps" ? root._apps().length : root._recorders().length) === 0
            text: root.tab === "rec" ? "nothing is listening"
                : root.tab === "apps" ? "nothing playing" : "no devices"
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }

    // ══ Building blocks ════════════════════════════════════════════════════════════════════════

    component Tag: Text {
        property bool good: false
        visible: text !== ""
        color: good ? Style.accent : Colors.fgMuted
        font.family: Style.font; font.pixelSize: 10
    }

    // Volume as a capsule you drag. Steps of 5% — the snap is the stepping, nothing draws it.
    component VolBar: Item {
        id: vb
        property var  au: null
        property bool big: false
        readonly property real vol:   vb.au ? Math.max(0, Math.min(1, vb.au.volume)) : 0
        readonly property bool muted: !!(vb.au && vb.au.muted)
        property real shown: vb.vol
        onVolChanged: vb.shown = vb.vol
        Behavior on shown { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: .002 } }
        width: parent ? parent.width : 0
        height: vb.big ? 10 : 8

        Rectangle {
            id: rail
            anchors.fill: parent
            radius: height / 2
            color: Style.tint(Colors.bgPrimary, 0.85)
            Rectangle {
                width: Math.max(parent.height, parent.width * vb.shown)
                height: parent.height; radius: parent.radius
                color: vb.muted ? Colors.fgMuted : vb.vol > 0.9 ? Colors.fgUrgent : Colors.bgActive
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -6
            function apply(mx) {
                if (!vb.au) return
                vb.au.muted = false
                vb.au.volume = Math.max(0, Math.min(1, Math.round(((mx - 6) / rail.width) / 0.05) * 0.05))
            }
            onPressed:         e => apply(e.x)
            onPositionChanged: e => { if (pressed) apply(e.x) }
            onWheel: e => { if (vb.au) vb.au.volume =
                Math.max(0, Math.min(1, vb.au.volume + (e.angleDelta.y > 0 ? .05 : -.05))) }
        }
    }

    // Left / right, from the per-channel volumes PipeWire already carries and nothing exposed.
    component Balance: Item {
        id: bal
        property var au: null
        readonly property var vols: (bal.au && bal.au.volumes) ? bal.au.volumes : []
        readonly property bool stereo: bal.vols.length === 2
        // −1 … +1, derived from the two channel volumes.
        readonly property real value: {
            if (!bal.stereo) return 0
            var l = bal.vols[0], r = bal.vols[1], m = Math.max(l, r)
            if (m <= 0) return 0
            return (r - l) / m
        }
        visible: bal.stereo
        width: parent ? parent.width : 0
        height: bal.stereo ? 18 : 0

        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: "L"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 10 }
        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               text: "R"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 10 }
        Rectangle {
            id: btrack
            anchors { left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14
                      verticalCenter: parent.verticalCenter }
            height: 4; radius: 2
            color: Style.tint(Colors.bgPrimary, 0.85)
            Rectangle { anchors.centerIn: parent; width: 1; height: 8; color: Colors.fgMuted; opacity: .6 }
            Rectangle {
                width: 10; height: 10; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                x: (btrack.width - width) / 2 * (1 + bal.value)
                color: Colors.fgBright
                Behavior on x { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: .3 } }
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -7
                function apply(mx) {
                    if (!bal.stereo) return
                    var v = Math.max(-1, Math.min(1, ((mx - 7) / btrack.width) * 2 - 1))
                    v = Math.round(v * 10) / 10
                    var peak = Math.max(bal.vols[0], bal.vols[1])
                    bal.au.volumes = [peak * (v > 0 ? 1 - v : 1), peak * (v < 0 ? 1 + v : 1)]
                }
                onPressed:         e => apply(e.x)
                onPositionChanged: e => { if (pressed) apply(e.x) }
            }
        }
    }

    // The signal, as the area curve. Shape rather than Canvas: it is GPU-drawn and redraws on a
    // property change instead of a repaint call, which matters with a tile per device.
    component Trace: Item {
        id: tr
        property var node: null
        readonly property var  peaks: mon.peaks ?? []
        property real disp: 0
        width: parent ? parent.width : 0
        height: 42

        PwNodePeakMonitor { id: mon; node: tr.node; enabled: root.active }

        property var pts: []
        Connections {
            target: root
            function onTickChanged() {
                if (!tr.node) return
                var ps = tr.peaks
                var p = 0
                for (var i = 0; i < ps.length; i++) p = Math.max(p, Math.max(0, Math.min(1, ps[i])))
                tr.disp = p > tr.disp ? p : tr.disp * 0.84        // snap up, glide down
                var h = root.histOf(tr.node.id)
                h.shift(); h.push(tr.disp)
                // Rebuild the polyline; the closing corners make it an area.
                var out = [], n = h.length
                for (var k = 0; k < n; k++)
                    out.push(Qt.point(k / (n - 1) * tr.width, tr.height - 1 - h[k] * (tr.height - 3)))
                out.push(Qt.point(tr.width, tr.height))
                out.push(Qt.point(0, tr.height))
                tr.pts = out
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: tr.height
                    GradientStop { position: 0.0; color: Style.tint(Colors.bgActive, 0.55) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                PathPolyline { path: tr.pts }
            }
            ShapePath {
                strokeColor: Colors.bgActive
                strokeWidth: 1.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: tr.pts.slice(0, Math.max(0, tr.pts.length - 2)) }
            }
        }
    }

    component Chip: StyledRect {
        id: ch
        property string label: ""
        property bool   on:    false
        property bool   ghost: false
        signal tap()
        width: chT.implicitWidth + 20
        height: 22
        radius: 11
        color: ch.on ? Style.tint(Colors.bgActive, 0.32)
             : ch.ghost ? "transparent"
             : chHov.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: ch.ghost ? 1 : 0
        borderColor: Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: 90 } }
        Text {
            id: chT; anchors.centerIn: parent; text: ch.label
            color: ch.on ? Colors.fgBright : Colors.fgMuted
            font.family: Style.font; font.pixelSize: 10
        }
        MouseArea { id: chHov; anchors.fill: parent; hoverEnabled: true; onClicked: ch.tap() }
    }

    component MuteBtn: StyledRect {
        property var au: null
        readonly property bool muted: !!(au && au.muted)
        width: 30; height: 24; radius: 12
        color: muted ? Style.tint(Colors.fgUrgent, 0.28)
             : mbHov.containsMouse ? Style.controlHover : Style.controlFill
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: parent.muted ? "󰝟" : "󰕾"
               color: parent.muted ? Colors.fgUrgent : Colors.fgPrimary
               font.family: Style.font; font.pixelSize: 12 }
        MouseArea { id: mbHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: if (parent.au) parent.au.muted = !parent.au.muted }
    }

    // An application inside the device it plays through: the app's own icon from the ACTIVE icon
    // theme, its volume as the ring around it, and a halo that swells with what it is playing.
    // Drag up/down for the level, sideways to carry it to another device, tap to mute.
    component Puck: Item {
        id: pk
        property var node: null
        readonly property var  au:    pk.node ? pk.node.audio : null
        readonly property bool muted: !!(pk.au && pk.au.muted)
        readonly property real vol:   pk.au ? Math.max(0, Math.min(1, pk.au.volume)) : 0
        property real shown: pk.vol
        onVolChanged: pk.shown = pk.vol
        Behavior on shown { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: .002 } }

        property real lvl: 0
        PwNodePeakMonitor { id: pmon; node: pk.node; enabled: root.active }
        Connections {
            target: root
            function onTickChanged() {
                var ps = pmon.peaks ?? [], p = 0
                for (var i = 0; i < ps.length; i++) p = Math.max(p, Math.max(0, Math.min(1, ps[i])))
                pk.lvl = p > pk.lvl ? p : pk.lvl * 0.84
            }
        }

        width: 62; height: 76
        readonly property int ring: 52

        // Halo — the live signal, outside the ring.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (pk.ring - height) / 2
            width: pk.ring + 6 + 10 * pk.lvl; height: width; radius: width / 2
            color: pk.vol > .9 ? Colors.fgUrgent : Colors.bgActive
            opacity: pk.muted ? 0 : (0.10 + 0.30 * pk.lvl)
            visible: opacity > 0.01
        }
        Shape {
            anchors.horizontalCenter: parent.horizontalCenter
            width: pk.ring; height: pk.ring
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Style.tint(Colors.bgPrimary, 0.85); strokeWidth: 4; fillColor: "transparent"
                PathAngleArc { centerX: pk.ring / 2; centerY: pk.ring / 2
                               radiusX: pk.ring / 2 - 2; radiusY: pk.ring / 2 - 2
                               startAngle: -90; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: pk.muted ? Colors.fgMuted : pk.vol > .9 ? Colors.fgUrgent : Colors.bgActive
                strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: pk.ring / 2; centerY: pk.ring / 2
                               radiusX: pk.ring / 2 - 2; radiusY: pk.ring / 2 - 2
                               startAngle: -90; sweepAngle: 360 * pk.shown }
            }
        }
        IconImage {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: (pk.ring - 24) / 2 }
            width: 24; height: 24; implicitSize: 24
            source: root._appIcon(pk.node)
            opacity: pk.muted ? 0.45 : 1.0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: pk.ring + 3 }
            width: pk.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: root._appName(pk.node)
            color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9
        }

        // One gesture, three meanings — decided by the first direction, the way a file manager
        // tells a drag from a click.
        MouseArea {
            id: pma
            anchors.fill: parent
            hoverEnabled: true
            property string mode: ""
            property real x0: 0
            property real y0: 0
            property real v0: 0
            onPressed: e => { pma.mode = "?"; pma.x0 = e.x; pma.y0 = e.y; pma.v0 = pk.vol }
            onPositionChanged: e => {
                if (!pressed) return
                var dx = e.x - pma.x0, dy = e.y - pma.y0
                if (pma.mode === "?") {
                    if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) { pma.mode = "carry"; root.carrying = pk.node }
                    else if (Math.abs(dy) > 4) pma.mode = "vol"
                }
                if (pma.mode === "vol" && pk.au) {
                    pk.au.muted = false
                    pk.au.volume = Math.max(0, Math.min(1, Math.round((pma.v0 - dy / 110) * 20) / 20))
                } else if (pma.mode === "carry") {
                    var g = pk.mapToItem(null, e.x, e.y)
                    root.carryX = g.x; root.carryY = g.y
                }
            }
            onReleased: e => {
                if (pma.mode === "carry") {
                    var g = pk.mapToItem(null, e.x, e.y)
                    root.dropCarry(g.x, g.y)
                } else if (pma.mode === "?" && pk.au) {
                    pk.au.muted = !pk.au.muted
                }
                pma.mode = ""; root.carrying = null
            }
            onCanceled: { pma.mode = ""; root.carrying = null }
            onWheel: e => { if (pk.au) pk.au.volume =
                Math.max(0, Math.min(1, pk.au.volume + (e.angleDelta.y > 0 ? .05 : -.05))) }
        }
    }

    // Carry state — which puck is in the air and where, so device tiles can light up as targets.
    property var  carrying: null
    property real carryX: 0
    property real carryY: 0
    property var  _dropZones: ({})       // device node name → the tile, for hit testing
    function registerZone(name, item) { root._dropZones[name] = item }
    function dropCarry(gx, gy) {
        var z = root._dropZones
        for (var name in z) {
            var it = z[name]
            if (!it || !it.visible) continue
            var p = it.mapFromItem(null, gx, gy)
            if (p.x >= 0 && p.y >= 0 && p.x <= it.width && p.y <= it.height) {
                if (root.carrying) root.moveStream(root.carrying, name)
                return
            }
        }
    }

    // A device: what it is, its curve, its level, its ports and profiles — and the apps inside it.
    component DeviceTile: StyledRect {
        id: dt
        property var node: null
        readonly property var  au:    dt.node ? dt.node.audio : null
        readonly property bool isOut: root.tab === "out"
        readonly property bool isDef: dt.node !== null && dt.node ===
                                      (dt.isOut ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource)
        readonly property var  info:  root._dev(dt.node)
        readonly property var  mine:  dt.isOut && dt.node
                                      ? root._apps().filter(a => root._devOf(a) === dt.node.name) : []
        readonly property bool target: root.carrying !== null && dt.isOut
                                       && dt.node && root._devOf(root.carrying) !== dt.node.name

        width: parent ? parent.width : 0
        height: dtCol.implicitHeight + 24
        radius: Style.rCard
        color: dt.isDef ? Style.tint(Colors.bgActive, 0.24)
             : dtHov.containsMouse ? Style.controlHover : Style.menuRowFill
        borderWidth: dt.target ? 1 : 0
        borderColor: Style.accent
        Behavior on color { ColorAnimation { duration: 110 } }

        Component.onCompleted: if (dt.node) root.registerZone(dt.node.name, dt)

        MouseArea { id: dtHov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        Column {
            id: dtCol
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 14; rightMargin: 14; topMargin: 12 }
            spacing: 7

            Row {
                width: parent.width
                spacing: 8
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - dPct.implicitWidth - dMute.width - 24)
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root._label(dt.node)
                        color: dt.isDef ? Colors.fgBright : Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 13; font.bold: dt.isDef
                    }
                    Row {
                        spacing: 6
                        Tag { text: root._fmt(dt.node) }
                        Tag { text: root._codec(dt.node); good: true }
                    }
                }
                Text {
                    id: dPct
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(dt.au ? Math.max(0, Math.min(1, dt.au.volume)) * 100 : 0) + "%"
                    color: (dt.au && dt.au.muted) ? Colors.fgMuted : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 12
                }
                MuteBtn { id: dMute; anchors.verticalCenter: parent.verticalCenter; au: dt.au }
            }

            Trace  { width: parent.width; node: dt.node }
            VolBar { width: parent.width; au: dt.au }

            Flow {
                width: parent.width
                spacing: 5
                Repeater {
                    model: dt.info ? dt.info.ports : []
                    delegate: Chip {
                        required property var modelData
                        label: modelData.label; on: modelData.active === true
                        onTap: if (dt.node) root.setPort(dt.node.name, modelData.name)
                    }
                }
                Repeater {
                    // Profiles only where there is a real choice — one profile is not a switch.
                    model: (dt.info && dt.info.profiles && dt.info.profiles.length > 1) ? dt.info.profiles : []
                    delegate: Chip {
                        required property var modelData
                        ghost: true
                        label: modelData.label; on: modelData.active === true
                        onTap: if (dt.info) root.setProfile(dt.info.card, modelData.name)
                    }
                }
                Chip {
                    visible: !dt.isDef
                    label: "Make default"
                    onTap: if (dt.node) root.setDefault(dt.isOut ? "sink" : "source", dt.node.name)
                }
                Chip { visible: dt.isDef; label: "default"; on: true }
            }

            // The apps playing through this device.
            Item {
                visible: dt.isOut
                width: parent.width
                height: visible ? hereCol.implicitHeight + 10 : 0
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 1; color: Style.tint(Colors.boNormal, 0.5) }
                Column {
                    id: hereCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 10 }
                    spacing: 6
                    Text {
                        text: dt.mine.length > 0 ? "PLAYING HERE" : (dt.target ? "DROP TO MOVE HERE" : "NOTHING PLAYING HERE")
                        color: dt.target ? Style.accent : Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 9
                        font.bold: true; font.letterSpacing: 0.5
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: dt.mine
                            delegate: Puck { required property var modelData; node: modelData }
                        }
                    }
                }
            }
        }
    }

    // A stream on its own — the Apps and Recording tabs, where there is room for the track title.
    component StreamTile: StyledRect {
        id: st
        property var node: null
        readonly property var  au:  st.node ? st.node.audio : null
        readonly property bool rec: root.tab === "rec"

        width: parent ? parent.width : 0
        height: stCol.implicitHeight + 24
        radius: Style.rCard
        color: stHov.containsMouse ? Style.controlHover : Style.menuRowFill
        Behavior on color { ColorAnimation { duration: 110 } }
        MouseArea { id: stHov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        Column {
            id: stCol
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 14; rightMargin: 14; topMargin: 12 }
            spacing: 7

            Row {
                width: parent.width
                spacing: 10
                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; implicitSize: 26
                    source: root._appIcon(st.node)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 36 - sPct.implicitWidth - sMute.width - 24)
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: root._appName(st.node)
                        color: Colors.fgPrimary; font.family: Style.font; font.pixelSize: 13
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: (st.rec ? "󰍬 " : "󰓃 ") + root._deviceLabelFor(root._devOf(st.node))
                              + (root._media(st.node) !== "" ? "  ·  " + root._media(st.node) : "")
                        color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 10
                    }
                }
                Text {
                    id: sPct
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(st.au ? Math.max(0, Math.min(1, st.au.volume)) * 100 : 0) + "%"
                    color: (st.au && st.au.muted) ? Colors.fgMuted : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 12
                }
                MuteBtn { id: sMute; anchors.verticalCenter: parent.verticalCenter; au: st.au }
            }
            Trace  { width: parent.width; node: st.node }
            VolBar { width: parent.width; au: st.au }
        }
    }
}
