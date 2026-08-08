pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The sound dashboard, composed from the shared data kit (DataTile / Sparkline / ValueRing /
// DataChip / ChipPicker) rather than drawn by hand — the first version was hand-drawn and drifted
// away from every other popout, which is exactly what the kit exists to prevent.
//
// Every level is the area curve of the REAL signal, and every application sits inside the device it
// plays through as its own icon with its volume as the ring around it. Routing is a place, not a
// label: carry a puck to another device tile and the stream moves.
//
// Three sources feed it, because no single one has everything:
//   · Quickshell's Pipewire   live volume / mute / peaks / spectrum, and the node list
//   · audio-route.py streams  which device each stream plays on + its media title (not exposed)
//   · audio-route.py devices  ports, card profiles, sample format, Bluetooth codec (not exposed)
// The script feeds are polled only while the panel is open and refreshed the moment an action
// lands, so a closed panel costs nothing.
//
// Card profiles go behind ONE picker. Laid out as chips they produced thirteen pills across four
// rows on a single device here and the tile stopped being readable — a long list of alternatives is
// a picker, and only a short meaningful set (a device's two or three ports) belongs on the surface.
Column {
    id: root
    property bool active: false
    spacing: 10

    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

    // One tick drives every curve — a timer per tile would be a wake-up per tile for the same job.
    property int tick: 0
    Timer { interval: 60; repeat: true; running: root.active; onTriggered: root.tick++ }

    property string tab: "out"          // out | in | apps | rec
    // The shell's own capture (cava feeds the bar's wave) is not an app anyone mixes.
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _isOwn(n) { return root._ownStreams.indexOf(("" + ((n && n.name) ?? "")).toLowerCase()) >= 0 }

    // ── Node lists ─────────────────────────────────────────────────────────────────────────────
    function _sinks()   { return Pipewire.nodes.values.filter(n => n && n.isSink && !n.isStream && n.audio) }
    function _sources() { return Pipewire.nodes.values.filter(n => n && !n.isSink && !n.isStream && n.audio
                                                                && ("" + (n.name ?? "")).indexOf("monitor") < 0) }
    function _apps()      { return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio && n.isSink && !root._isOwn(n)) }
    function _recorders() { return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio && !n.isSink) }

    function _label(n) {
        if (!n) return "device"
        return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "device")
    }
    function _appName(n) { return (n && n.name && n.name !== "") ? n.name : ((n && n.description) || "audio") }
    // The ACTIVE icon theme, through the desktop entry — not a font glyph.
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
    property var _routes:  ({})       // node id → { deviceName, media }
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
    function setDefault(kind, name)    { root._act([kind === "sink" ? "default-sink" : "default-source", name]) }
    function setPort(devName, port)    { root._act(["set-port", devName, port]) }
    function setProfile(card, profile) { root._act(["set-profile", card, profile]) }
    function moveStream(node, deviceName) {
        if (!node || !deviceName) return
        root._act([node.isSink ? "move" : "move-source", "" + node.id, deviceName])
    }

    function _info(n)  { return (n && root._routes[n.id]) ? root._routes[n.id] : null }
    function _media(n) { var i = root._info(n); return i ? ("" + (i.media ?? "")) : "" }
    function _devOf(n) { var i = root._info(n); return i ? ("" + (i.deviceName ?? "")) : "" }
    function _dev(n)   { return (n && root._devInfo[n.name]) ? root._devInfo[n.name] : null }
    function _fmt(n)   { var d = root._dev(n); return d ? ("" + (d.format ?? "")) : "" }
    function _codec(n) { var d = root._dev(n); return d ? ("" + (d.codec ?? "")) : "" }

    // ── Master ─────────────────────────────────────────────────────────────────────────────────
    DataTile {
        id: master
        readonly property var  node:  Pipewire.defaultAudioSink
        readonly property var  au:    master.node ? master.node.audio : null
        readonly property bool muted: !!(master.au && master.au.muted)
        readonly property real vol:   master.au ? Math.max(0, Math.min(1, master.au.volume)) : 0
        active: true
        pad: 14

        PwAudioSpectrum {
            id: spectrum
            node: master.node; enabled: root.active && !master.muted
            barCount: 44; smoothing: true
        }

        Row {
            width: parent.width
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: master.muted ? "󰝟" : "󰕾"
                color: Colors.fgBright; font.family: Style.font; font.pixelSize: 18
                MouseArea { anchors.fill: parent; anchors.margins: -6
                            onClicked: if (master.au) master.au.muted = !master.au.muted }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 34 - mPct.implicitWidth - 20)
                spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root._label(master.node)
                    color: Colors.fgBright; font.family: Style.font; font.pixelSize: 14; font.bold: true
                }
                Row {
                    spacing: 8
                    MetaTag { text: root._fmt(master.node) }
                    MetaTag { text: root._codec(master.node); good: true }
                }
            }
            Text {
                id: mPct
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(master.vol * 100) + "%"
                color: Colors.fgBright; font.family: Style.font; font.pixelSize: 19; font.bold: true
            }
        }

        // The spectrum as the master's floor — a texture the name sits on, not a chart.
        Row {
            width: parent.width
            height: 34
            spacing: 3
            Repeater {
                model: spectrum.values.length
                delegate: Rectangle {
                    required property int index
                    readonly property real v: Math.max(0, Math.min(1, spectrum.values[index] ?? 0))
                    width:  Math.max(1, (master.width - 28 - 3 * (spectrum.values.length - 1))
                                        / Math.max(1, spectrum.values.length))
                    height: Math.max(2, parent.height * v)
                    anchors.bottom: parent.bottom
                    radius: Math.min(3, width / 2, height / 2)
                    color: Style.tint(Colors.bgSecondary, 0.75)
                    opacity: 0.6
                    Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                }
            }
        }

        VolBar  { width: parent.width; au: master.au; big: true }
        Balance { width: parent.width; au: master.au }
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

    // ══ Parts that only the sound panel needs ══════════════════════════════════════════════════

    // Volume as a capsule you drag. Steps of 5% — the snap IS the stepping; nothing draws it.
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
        height: vb.big ? 8 : 6

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
            anchors.fill: parent; anchors.margins: -7
            function apply(mx) {
                if (!vb.au) return
                vb.au.muted = false
                vb.au.volume = Math.max(0, Math.min(1, Math.round(((mx - 7) / rail.width) / 0.05) * 0.05))
            }
            onPressed:         e => apply(e.x)
            onPositionChanged: e => { if (pressed) apply(e.x) }
            onWheel: e => { if (vb.au) vb.au.volume =
                Math.max(0, Math.min(1, vb.au.volume + (e.angleDelta.y > 0 ? .05 : -.05))) }
        }
    }

    // Left / right, from the per-channel volumes PipeWire carries and nothing ever showed.
    component Balance: Item {
        id: bal
        property var au: null
        readonly property var  vols:   (bal.au && bal.au.volumes) ? bal.au.volumes : []
        readonly property bool stereo: bal.vols.length === 2
        readonly property real value: {
            if (!bal.stereo) return 0
            var l = bal.vols[0], r = bal.vols[1], m = Math.max(l, r)
            return m <= 0 ? 0 : (r - l) / m
        }
        visible: bal.stereo
        width: parent ? parent.width : 0
        height: bal.stereo ? 16 : 0

        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter }
               text: "L"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9 }
        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               text: "R"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9 }
        Rectangle {
            id: btrack
            anchors { left: parent.left; right: parent.right; leftMargin: 13; rightMargin: 13
                      verticalCenter: parent.verticalCenter }
            height: 3; radius: 1.5
            color: Style.tint(Colors.bgPrimary, 0.85)
            Rectangle { anchors.centerIn: parent; width: 1; height: 7; color: Colors.fgMuted; opacity: .5 }
            Rectangle {
                width: 9; height: 9; radius: 4.5
                anchors.verticalCenter: parent.verticalCenter
                x: (btrack.width - width) / 2 * (1 + bal.value)
                color: Colors.fgBright
                Behavior on x { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: .3 } }
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -8
                function apply(mx) {
                    if (!bal.stereo) return
                    var v = Math.round(Math.max(-1, Math.min(1, ((mx - 8) / btrack.width) * 2 - 1)) * 10) / 10
                    var peak = Math.max(bal.vols[0], bal.vols[1])
                    bal.au.volumes = [peak * (v > 0 ? 1 - v : 1), peak * (v < 0 ? 1 + v : 1)]
                }
                onPressed:         e => apply(e.x)
                onPositionChanged: e => { if (pressed) apply(e.x) }
            }
        }
    }

    // A node's live level, fed into the shared Sparkline. Fast attack, decaying fall — the way a
    // level reads as motion rather than flicker.
    component Level: Sparkline {
        id: lv
        property var node: null
        property bool muted: false
        property var _h: new Array(56).fill(0)
        values: lv._h
        dim: lv.muted
        implicitHeight: 32

        PwNodePeakMonitor { id: mon; node: lv.node; enabled: root.active }
        property real disp: 0
        Connections {
            target: root
            function onTickChanged() {
                var ps = mon.peaks ?? [], p = 0
                for (var i = 0; i < ps.length; i++) p = Math.max(p, Math.max(0, Math.min(1, ps[i])))
                lv.disp = p > lv.disp ? p : lv.disp * 0.84
                var h = lv._h.slice(1); h.push(lv.muted ? 0 : lv.disp)
                lv._h = h
            }
        }
    }

    component MuteBtn: StyledRect {
        property var au: null
        readonly property bool muted: !!(au && au.muted)
        width: 28; height: 22; radius: 11
        color: muted ? Style.tint(Colors.fgUrgent, 0.28)
             : mh.containsMouse ? Style.controlHover : Style.controlFill
        Behavior on color { ColorAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: parent.muted ? "󰝟" : "󰕾"
               color: parent.muted ? Colors.fgUrgent : Colors.fgPrimary
               font.family: Style.font; font.pixelSize: 11 }
        MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                    onClicked: if (parent.au) parent.au.muted = !parent.au.muted }
    }

    // An application inside the device it plays through: its own icon from the active icon theme,
    // its volume as the ring, and a halo that swells with what it is playing. Drag up/down for the
    // level, sideways to carry it to another device, tap to mute.
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

        width: 62; height: 70

        ValueRing {
            id: vr
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
            width: 48; height: 48
            value: pk.shown
            halo:  pk.muted ? 0 : pk.lvl
            dim:   pk.muted
            ringColor: pk.vol > 0.9 ? Colors.fgUrgent : Colors.bgActive
            IconImage {
                anchors.centerIn: parent
                width: 22; height: 22; implicitSize: 22
                source: root._appIcon(pk.node)
                opacity: pk.muted ? 0.45 : 1.0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: vr.bottom; topMargin: 3 }
            width: pk.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: root._appName(pk.node)
            color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9
        }

        // One gesture, three meanings — decided by the first direction, the way a file manager
        // tells a drag from a click.
        MouseArea {
            id: pma
            anchors.fill: parent
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

    // Which puck is in the air, so device tiles can light up as targets.
    property var carrying: null
    property var _dropZones: ({})
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

    // ── Tiles ──────────────────────────────────────────────────────────────────────────────────
    component DeviceTile: DataTile {
        id: dt
        property var node: null
        readonly property var  au:    dt.node ? dt.node.audio : null
        readonly property bool isOut: root.tab === "out"
        readonly property bool isDef: dt.node !== null && dt.node ===
                                      (dt.isOut ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource)
        readonly property var  info:  root._dev(dt.node)
        readonly property var  mine:  (dt.isOut && dt.node)
                                      ? root._apps().filter(a => root._devOf(a) === dt.node.name) : []
        readonly property bool isTarget: root.carrying !== null && dt.isOut && dt.node
                                         && root._devOf(root.carrying) !== dt.node.name

        active:      dt.isDef
        interactive: true
        highlight:   dt.isTarget
        Component.onCompleted: if (dt.node) root.registerZone(dt.node.name, dt)

        Row {
            width: parent.width
            spacing: 8
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - dPct.implicitWidth - dMute.width - 24)
                spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root._label(dt.node)
                    color: dt.isDef ? Colors.fgBright : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 13; font.bold: dt.isDef
                }
                Row {
                    spacing: 8
                    MetaTag { text: root._fmt(dt.node) }
                    MetaTag { text: root._codec(dt.node); good: true }
                    MetaTag { text: dt.isDef ? "default" : ""; good: true }
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

        Level  { width: parent.width; node: dt.node; muted: !!(dt.au && dt.au.muted) }
        VolBar { width: parent.width; au: dt.au }

        // Ports on the surface (two or three, a real choice), profiles behind a picker.
        Flow {
            width: parent.width
            spacing: 5
            visible: (dt.info && dt.info.ports && dt.info.ports.length > 1) || !dt.isDef
            Repeater {
                model: (dt.info && dt.info.ports && dt.info.ports.length > 1) ? dt.info.ports : []
                delegate: DataChip {
                    required property var modelData
                    label: modelData.label; on: modelData.active === true
                    onTap: if (dt.node) root.setPort(dt.node.name, modelData.name)
                }
            }
            DataChip {
                visible: !dt.isDef
                label: "Make default"
                onTap: if (dt.node) root.setDefault(dt.isOut ? "sink" : "source", dt.node.name)
            }
        }
        ChipPicker {
            width: parent.width
            visible: !!(dt.info && dt.info.profiles && dt.info.profiles.length > 1)
            options: (dt.info && dt.info.profiles) ? dt.info.profiles.map(
                         p => ({ label: p.label, key: p.name, on: p.active === true })) : []
            onPicked: key => { if (dt.info) root.setProfile(dt.info.card, key) }
        }

        // The apps playing through this device.
        Item {
            visible: dt.isOut
            width: parent.width
            height: visible ? hereCol.implicitHeight + 9 : 0
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 1; color: Style.tint(Colors.boNormal, 0.45) }
            Column {
                id: hereCol
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 9 }
                spacing: 5
                Text {
                    text: dt.mine.length > 0 ? "PLAYING HERE"
                        : dt.isTarget ? "DROP TO MOVE HERE" : "NOTHING PLAYING HERE"
                    color: dt.isTarget ? Style.accent : Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5
                }
                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater { model: dt.mine; delegate: Puck { required property var modelData; node: modelData } }
                }
            }
        }
    }

    // A stream on its own — the Apps and Recording tabs, where there is room for the track title.
    component StreamTile: DataTile {
        id: st
        property var node: null
        readonly property var  au:  st.node ? st.node.audio : null
        readonly property bool rec: root.tab === "rec"
        interactive: true

        Row {
            width: parent.width
            spacing: 10
            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; implicitSize: 24
                source: root._appIcon(st.node)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 34 - sPct.implicitWidth - sMute.width - 24)
                spacing: 2
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: root._appName(st.node)
                    color: Colors.fgPrimary; font.family: Style.font; font.pixelSize: 13
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: (st.rec ? "󰍬 " : "󰓃 ") + root._deviceLabelFor(root._devOf(st.node))
                          + (root._media(st.node) !== "" ? "   " + root._media(st.node) : "")
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
        Level  { width: parent.width; node: st.node; muted: !!(st.au && st.au.muted) }
        VolBar { width: parent.width; au: st.au }
    }
}
