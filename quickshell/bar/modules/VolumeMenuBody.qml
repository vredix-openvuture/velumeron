import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The sound menu. Not a stack of sliders — a menu you can read at a glance: the active output on a
// card with its own live spectrum behind it, then Output / Input / Apps as tabs rather than three
// lists fighting for the same column, and every row carrying a real LEVEL METER next to its volume
// slider. A slider says what you asked for; the meter says what is actually coming out, and those
// are different questions — "is this app the one making noise" was unanswerable before.
//
// The levels are real: Quickshell exposes PwNodePeakMonitor (per-channel peaks) and PwAudioSpectrum
// (banded FFT) per node, so nothing is faked and no cava process is involved. Both are gated on the
// menu being open — they cost CPU per node and there is no reason to meter a closed panel.
//
// Meter movement is fast-attack / slow-decay off one shared tick, the way a VU behaves: jumping up
// instantly and falling back smoothly is what makes a level read as motion rather than flicker.
//
// Spectrum colour follows CavaWave's rule — a surface tone, never the accent: it sits BEHIND the
// device name, and an accent-bright spectrum turns the text into something you read twice.
//
// Routing goes through assets/scripts/audio-route.py, because the id Quickshell hands out for a
// stream is not the id pactl takes: node 64 is sink-input 6978. The script owns that lookup and
// also reports which device each stream plays on, which Quickshell doesn't expose.
Column {
    id: root
    property bool active: false
    spacing: 12

    // Keep the audio bound for every device node so volume reads/writes are live.
    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

    // One tick drives every meter's decay — six rows with six timers would be six wake-ups for the
    // same 20 Hz job.
    property int tick: 0
    Timer { interval: 45; repeat: true; running: root.active; onTriggered: root.tick++ }

    property string tab: "out"          // out | in | apps

    function _sinks()   { return Pipewire.nodes.values.filter(n => n && n.isSink && !n.isStream && n.audio) }
    function _sources() { return Pipewire.nodes.values.filter(n => n && !n.isSink && !n.isStream && n.audio
                                                                && ("" + (n.name ?? "")).indexOf("monitor") < 0) }
    // The shell's own capture (cava, feeding the bar's wave) is not an app anyone mixes.
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _streams() {
        return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio
                                            && root._ownStreams.indexOf(("" + (n.name ?? "")).toLowerCase()) < 0)
    }

    function _label(n) {
        if (!n) return "device"
        return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "device")
    }
    // Streams carry no description or nick — node.name is the application ("LibreWolf"), which is
    // also the best handle for its icon.
    function _appName(n) { return (n && n.name && n.name !== "") ? n.name : ((n && n.description) || "audio") }
    function _appIcon(n) {
        var nm = ("" + ((n && n.name) ?? "")).trim()
        if (nm === "") return ""
        var e = DesktopEntries.heuristicLookup(nm)
        return Quickshell.iconPath((e && e.icon) ? e.icon : nm.toLowerCase(), "application-x-executable")
    }
    function _deviceLabelFor(nodeName) {
        var ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++)
            if (ns[i] && ns[i].name === nodeName) return root._label(ns[i])
        return nodeName === "" ? "—" : nodeName
    }

    // ── Routing ────────────────────────────────────────────────────────────────────────────────
    property var _routes: ({})            // PipeWire node id → device node name
    Process {
        id: routeProc
        property string _acc: ""
        command: ["python3", root.script, "streams"]
        stdout: SplitParser { onRead: line => { routeProc._acc += line } }
        onRunningChanged: if (!running) {
            try {
                var arr = JSON.parse(routeProc._acc.trim())
                var m = {}
                for (var i = 0; i < arr.length; i++) m[arr[i].nodeId] = arr[i].deviceName ?? ""
                root._routes = m
            } catch (e) { /* keep the last good map */ }
            routeProc._acc = ""
        }
    }
    function refreshRoutes() { routeProc._acc = ""; routeProc.running = false; routeProc.running = true }
    onActiveChanged: if (root.active) root.refreshRoutes()
    Timer { interval: 2000; repeat: true; running: root.active; onTriggered: root.refreshRoutes() }

    Process { id: actProc; onRunningChanged: if (!running) root.refreshRoutes() }
    function _act(args) {
        actProc.command = ["python3", root.script].concat(args)
        actProc.running = false; actProc.running = true
    }
    function setDefault(kind, name) { root._act([kind === "sink" ? "default-sink" : "default-source", name]) }
    function moveStream(node, deviceName) {
        if (!node || !deviceName) return
        root._act([node.isSink ? "move" : "move-source", "" + node.id, deviceName])
    }

    // ── Master: the active output, its spectrum, its level ─────────────────────────────────────
    StyledRect {
        id: master
        readonly property var  node:  Pipewire.defaultAudioSink
        readonly property var  au:    master.node ? master.node.audio : null
        readonly property bool muted: !!(master.au && master.au.muted)
        readonly property real vol:   master.au ? Math.max(0, Math.min(1, master.au.volume)) : 0

        width:  parent.width
        height: 104
        radius: Style.rControl
        color:  Style.tint(Colors.bgActive, 0.18)

        PwAudioSpectrum {
            id: spectrum
            node:     master.node
            enabled:  root.active && !master.muted
            barCount: 32
            smoothing: true
        }

        // Spectrum as the card's floor — a texture the name sits on, not a chart.
        ClippingRectangle {
            anchors.fill: parent
            radius: Style.rControl
            color:  "transparent"
            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 46
                spacing: 2
                Repeater {
                    model: spectrum.values.length
                    delegate: Rectangle {
                        required property int index
                        readonly property real v: Math.max(0, Math.min(1, spectrum.values[index] ?? 0))
                        width:  Math.max(1, (master.width - 2 * (spectrum.values.length - 1)) / spectrum.values.length)
                        height: Math.max(2, parent.height * v)
                        anchors.bottom: parent.bottom
                        radius: 1
                        color:  Style.tint(Colors.bgSecondary, 0.75)
                        opacity: 0.55
                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 14; rightMargin: 14; topMargin: 13 }
            spacing: 10

            Row {
                width: parent.width
                spacing: 9
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text:  master.muted ? "󰝟" : "󰕾"
                    color: Colors.fgBright; font.family: Style.font; font.pixelSize: 17
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 34 - mPct.implicitWidth - 18)
                    elide: Text.ElideRight
                    text:  root._label(master.node)
                    color: Colors.fgBright
                    font.family: Style.font; font.pixelSize: 14; font.bold: true
                }
                Text {
                    id: mPct
                    anchors.verticalCenter: parent.verticalCenter
                    text:  Math.round(master.vol * 100) + "%"
                    color: Colors.fgBright
                    font.family: Style.font; font.pixelSize: 13; font.bold: true
                }
            }
            MixTrack { width: parent.width; big: true; au: master.au }
        }
    }

    // ── Tabs ───────────────────────────────────────────────────────────────────────────────────
    Segmented {
        width: parent.width
        equal: true
        current: root.tab
        segments: [{ label: "Output", key: "out" },
                   { label: "Input",  key: "in" },
                   { label: "Apps" + (root._streams().length > 0 ? "  " + root._streams().length : ""),
                     key: "apps" }]
        onPicked: key => root.tab = key
    }

    // ── The active tab ─────────────────────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 7
        opacity: 1
        // A tab swap that just snaps reads as a redraw; a short fade reads as a move.
        Behavior on opacity { NumberAnimation { duration: 110 } }

        Repeater {
            model: root.tab === "out" ? root._sinks() : root.tab === "in" ? root._sources() : []
            delegate: DeviceRow {
                required property var modelData
                node: modelData
                kind: root.tab === "out" ? "sink" : "source"
                def:  root.tab === "out" ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
            }
        }
        Repeater {
            model: root.tab === "apps" ? root._streams() : []
            delegate: AppRow { required property var modelData; node: modelData }
        }
        Text {
            visible: (root.tab === "apps" ? root._streams().length
                    : root.tab === "out"  ? root._sinks().length : root._sources().length) === 0
            text:  root.tab === "apps" ? "nothing playing" : "no devices"
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }

    // ── Building blocks ────────────────────────────────────────────────────────────────────────

    // Per-channel level meter. Fast attack, decaying fall — a level that only followed the raw peak
    // flickers; one that only eased lags behind the beat.
    component Meter: Row {
        id: met
        property var  node: null
        readonly property var peaks: mon.peaks ?? []
        property var _disp: [0, 0]
        spacing: 2
        width:  12
        height: 18

        PwNodePeakMonitor {
            id: mon
            node:    met.node
            enabled: root.active
        }
        Connections {
            target: root
            function onTickChanged() {
                var ps = met.peaks
                var out = []
                for (var i = 0; i < 2; i++) {
                    var p = Math.max(0, Math.min(1, ps.length > i ? ps[i] : (ps.length > 0 ? ps[0] : 0)))
                    var prev = met._disp.length > i ? met._disp[i] : 0
                    out.push(p > prev ? p : prev * 0.80)      // snap up, glide down
                }
                met._disp = out
            }
        }

        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                readonly property real v: met._disp.length > index ? met._disp[index] : 0
                width: 5; height: met.height; radius: 2
                color: Style.tint(Colors.bgSecondary, 0.5)
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: Math.max(0, parent.height * parent.v)
                    radius: parent.radius
                    color: parent.v > 0.92 ? Colors.fgUrgent : Colors.bgActive
                    Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                }
            }
        }
    }

    component MuteBtn: Text {
        property var au: null
        readonly property bool muted: !!(au && au.muted)
        text:  muted ? "󰝟" : "󰕾"
        color: muted ? Colors.fgUrgent : (mbHov.containsMouse ? Colors.fgBright : Colors.fgMuted)
        font.family: Style.font; font.pixelSize: 14
        Behavior on color { ColorAnimation { duration: 90 } }
        MouseArea {
            id: mbHov
            anchors.fill: parent; anchors.margins: -5
            hoverEnabled: true
            onClicked: if (parent.au) parent.au.muted = !parent.au.muted
        }
    }

    // Level track with a knob. `big` is the master's. Dragging unmutes by design — the mute button
    // is what gets you to silence and back.
    component MixTrack: Item {
        id: trk
        property var  au:  null
        property bool big: false
        readonly property real vol:   trk.au ? Math.max(0, Math.min(1, trk.au.volume)) : 0
        readonly property bool muted: !!(trk.au && trk.au.muted)
        width:  parent ? parent.width : 0
        height: trk.big ? 14 : 10

        Rectangle {
            id: rail
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: trk.big ? 8 : 6
            radius: height / 2
            color:  Colors.bgPrimary
            Rectangle {
                width:  parent.width * trk.vol
                height: parent.height; radius: parent.radius
                color:  trk.muted ? Colors.fgMuted : Colors.bgActive
                Behavior on width { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
            }
        }
        Rectangle {
            visible: trkHov.containsMouse || trkHov.pressed || trk.big
            x: Math.max(0, Math.min(rail.width - width, rail.width * trk.vol - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: trk.big ? 14 : 11; height: width; radius: width / 2
            color: trk.muted ? Colors.fgMuted : Colors.fgBright
            border.width: 1; border.color: Style.tint(Colors.bgActive, 0.6)
            Behavior on x { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: trkHov
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            function apply(mx) {
                if (!trk.au) return
                trk.au.muted = false
                // Snap to 5% steps so the slider only ever sets 0, 5, 10 … %.
                trk.au.volume = Math.max(0, Math.min(1, Math.round(((mx - 4) / rail.width) / 0.05) * 0.05))
            }
            onPressed:         e => apply(e.x)
            onPositionChanged: e => { if (pressed) apply(e.x) }
        }
    }

    // A device: click anywhere but the track to make it the default.
    component DeviceRow: StyledRect {
        id: drow
        property var    node: null
        property string kind: "sink"
        property var    def:  null
        readonly property bool isDef: drow.def !== null && drow.node === drow.def
        readonly property var  au:    drow.node ? drow.node.audio : null

        width:  parent ? parent.width : 0
        height: 62
        radius: Style.rControl
        color:  drow.isDef ? Style.tint(Colors.bgActive, 0.26)
              : dHov.containsMouse ? Style.controlHover : Style.menuRowFill
        Behavior on color { ColorAnimation { duration: 110 } }

        Row {
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 12; rightMargin: 12; topMargin: 9 }
            spacing: 10

            Meter { anchors.verticalCenter: parent.verticalCenter; node: drow.node }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 22 - 10)
                spacing: 7
                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:  drow.isDef ? "󰄬" : "󰝥"
                        color: drow.isDef ? Colors.boActive : Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - 29 - dPct.implicitWidth - dMute.implicitWidth - 16)
                        elide: Text.ElideRight
                        text:  root._label(drow.node)
                        color: drow.isDef ? Colors.fgBright : Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 13
                    }
                    Text {
                        id: dPct
                        anchors.verticalCenter: parent.verticalCenter
                        text:  Math.round(drow.au ? Math.max(0, Math.min(1, drow.au.volume)) * 100 : 0) + "%"
                        color: (drow.au && drow.au.muted) ? Colors.fgMuted : Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 11
                    }
                    MuteBtn { id: dMute; anchors.verticalCenter: parent.verticalCenter; au: drow.au }
                }
                MixTrack { width: parent.width; au: drow.au }
            }
        }

        MouseArea {
            id: dHov
            anchors.fill: parent
            anchors.bottomMargin: 20        // leave the track to its own MouseArea
            hoverEnabled: true
            onClicked: if (drow.node) root.setDefault(drow.kind, drow.node.name)
        }
    }

    // An application: same shape, plus where it plays and a picker to move it.
    component AppRow: StyledRect {
        id: arow
        property var node: null
        readonly property var  au:      arow.node ? arow.node.audio : null
        readonly property bool isOut:   arow.node ? arow.node.isSink : true
        readonly property string devName: arow.node ? ("" + (root._routes[arow.node.id] ?? "")) : ""
        property bool pickOpen: false

        width:  parent ? parent.width : 0
        height: 74 + (arow.pickOpen ? devPick.implicitHeight + 10 : 0)
        radius: Style.rControl
        color:  aHov.containsMouse ? Style.controlHover : Style.menuRowFill
        clip:   true
        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on color  { ColorAnimation  { duration: 110 } }

        MouseArea { id: aHov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        Row {
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 12; rightMargin: 12; topMargin: 10 }
            spacing: 10

            Meter { anchors.top: parent.top; anchors.topMargin: 4; node: arow.node }

            Column {
                width: Math.max(0, parent.width - 22 - 10)
                spacing: 7

                Row {
                    width: parent.width
                    spacing: 9
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; implicitSize: 22
                        source: root._appIcon(arow.node)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - 31 - aPct.implicitWidth - aMute.implicitWidth - 18)
                        spacing: 1
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text:  root._appName(arow.node)
                            color: Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 13
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text:  (arow.isOut ? "󰓃 " : "󰍬 ") + root._deviceLabelFor(arow.devName)
                            color: devHov.containsMouse || arow.pickOpen ? Style.accent : Colors.fgMuted
                            font.family: Style.font; font.pixelSize: 11
                            Behavior on color { ColorAnimation { duration: 90 } }
                            MouseArea {
                                id: devHov
                                anchors.fill: parent; anchors.margins: -3
                                hoverEnabled: true
                                onClicked: arow.pickOpen = !arow.pickOpen
                            }
                        }
                    }
                    Text {
                        id: aPct
                        anchors.verticalCenter: parent.verticalCenter
                        text:  Math.round(arow.au ? Math.max(0, Math.min(1, arow.au.volume)) * 100 : 0) + "%"
                        color: (arow.au && arow.au.muted) ? Colors.fgMuted : Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 11
                    }
                    MuteBtn { id: aMute; anchors.verticalCenter: parent.verticalCenter; au: arow.au }
                }

                MixTrack { width: parent.width; au: arow.au }

                Column {
                    id: devPick
                    width: parent.width
                    spacing: 3
                    visible: arow.pickOpen
                    Repeater {
                        model: arow.pickOpen ? (arow.isOut ? root._sinks() : root._sources()) : []
                        delegate: StyledRect {
                            id: tgt
                            required property var modelData
                            readonly property bool on: arow.node && tgt.modelData.name === arow.devName
                            width: devPick.width; height: 26
                            radius: Style.rTile
                            color: tgt.on ? Style.tint(Colors.bgActive, 0.30)
                                 : tgtHov.containsMouse ? Style.controlHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Text {
                                anchors { left: parent.left; leftMargin: 9; right: parent.right
                                          rightMargin: 9; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text:  (tgt.on ? "󰄬  " : "") + root._label(tgt.modelData)
                                color: tgt.on ? Colors.fgBright : Colors.fgPrimary
                                font.family: Style.font; font.pixelSize: 11
                            }
                            MouseArea {
                                id: tgtHov
                                anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    root.moveStream(arow.node, tgt.modelData.name)
                                    arow.pickOpen = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
