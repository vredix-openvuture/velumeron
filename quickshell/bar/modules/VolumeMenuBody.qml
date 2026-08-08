import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The sound menu, built as a mixing desk: a rack of channel strips side by side, each with an
// upright fader you drag, a live meter beside it, and its own mute — the layout a console has
// because it is the one you can read across. Horizontal sliders stacked in a column made every
// row look like a settings field; strips make the levels comparable at a glance.
//
// The VALUE steps in 5% — that is what makes two channels at the same level look the same — but the
// column is one capsule, not twenty bricks: the steps are hairline detents drawn onto it, and the
// fill rides the shell's own spring (Style.elSpring/elDamping, the same one every panel emerges
// with), so a step settles instead of jumping. Twenty stacked blocks read as a bar chart; this
// reads as a fader, which is what the flat/rounded house style (Mirobo) asks for.
//
// The levels are real. Quickshell exposes PwNodePeakMonitor (per-channel peaks) and PwAudioSpectrum
// (banded FFT) per node, so nothing is faked and no cava process is involved. Both are gated on the
// menu being open, and only the visible tab builds strips — a closed panel meters nothing.
//
// Meter movement is fast-attack / slow-decay off one shared tick, the way a VU behaves: snapping up
// and gliding down is what makes a level read as motion rather than flicker.
//
// Spectrum colour follows CavaWave's rule — a surface tone, never the accent: it sits behind the
// device name, and an accent-bright spectrum turns the text into something you read twice.
//
// Routing and the app/track names come from assets/scripts/audio-route.py: the id Quickshell hands
// out for a stream is not the id pactl takes (node 64 is sink-input 6978), and neither the playing
// device nor the media title is available from Quickshell at all.
Column {
    id: root
    property bool active: false
    spacing: 12

    // Keep the audio bound for every device node so volume reads/writes are live.
    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

    // One tick drives every meter's decay — a timer per strip would be a wake-up per strip for the
    // same 20 Hz job.
    property int tick: 0
    Timer { interval: 45; repeat: true; running: root.active; onTriggered: root.tick++ }

    property string tab:     "out"        // out | in | apps
    property var    routeFor: null        // the stream whose target picker is open

    function _sinks()   { return Pipewire.nodes.values.filter(n => n && n.isSink && !n.isStream && n.audio) }
    function _sources() { return Pipewire.nodes.values.filter(n => n && !n.isSink && !n.isStream && n.audio
                                                                && ("" + (n.name ?? "")).indexOf("monitor") < 0) }
    // The shell's own capture (cava, feeding the bar's wave) is not an app anyone mixes.
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _streams() {
        return Pipewire.nodes.values.filter(n => n && n.isStream && n.audio
                                            && root._ownStreams.indexOf(("" + (n.name ?? "")).toLowerCase()) < 0)
    }
    function _strips() {
        return root.tab === "out" ? root._sinks() : root.tab === "in" ? root._sources() : root._streams()
    }

    function _label(n) {
        if (!n) return "device"
        return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "device")
    }
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
    function _channels(n) {
        var c = (n && n.audio && n.audio.channels) ? n.audio.channels.length : 0
        return c === 1 ? "mono" : c === 2 ? "stereo" : c > 2 ? c + " ch" : ""
    }
    // What the script knows and Quickshell doesn't: the playing device and the track title.
    function _info(n)  { return (n && root._routes[n.id]) ? root._routes[n.id] : null }
    function _media(n) { var i = root._info(n); return i ? ("" + (i.media ?? "")) : "" }
    function _devOf(n) { var i = root._info(n); return i ? ("" + (i.deviceName ?? "")) : "" }

    // ── Routing + stream info ──────────────────────────────────────────────────────────────────
    property var _routes: ({})            // PipeWire node id → { deviceName, app, media }
    Process {
        id: routeProc
        property string _acc: ""
        command: ["python3", root.script, "streams"]
        stdout: SplitParser { onRead: line => { routeProc._acc += line } }
        onRunningChanged: if (!running) {
            try {
                var arr = JSON.parse(routeProc._acc.trim())
                var m = {}
                for (var i = 0; i < arr.length; i++) m[arr[i].nodeId] = arr[i]
                root._routes = m
            } catch (e) { /* keep the last good map */ }
            routeProc._acc = ""
        }
    }
    function refreshRoutes() { routeProc._acc = ""; routeProc.running = false; routeProc.running = true }
    onActiveChanged: if (root.active) root.refreshRoutes(); else root.routeFor = null
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
        height: 96
        radius: Style.rCard
        color:  Style.tint(Colors.bgActive, 0.18)

        PwAudioSpectrum {
            id: spectrum
            node:      master.node
            enabled:   root.active && !master.muted
            barCount:  40
            smoothing: true
        }

        // Spectrum as the card's floor — a texture the name sits on, not a chart.
        ClippingRectangle {
            anchors.fill: parent
            radius: Style.rCard
            color:  "transparent"
            Row {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 44
                spacing: 3
                Repeater {
                    model: spectrum.values.length
                    delegate: Rectangle {
                        required property int index
                        readonly property real v: Math.max(0, Math.min(1, spectrum.values[index] ?? 0))
                        width:  Math.max(1, (master.width - 3 * (spectrum.values.length - 1)) / spectrum.values.length)
                        height: Math.max(3, parent.height * v)
                        anchors.bottom: parent.bottom
                        // CavaWave's rule: softened tops, not lozenges — a full pill radius turns
                        // a spectrum into a row of blobs. Capped by the height so a bar near the
                        // floor keeps its shape.
                        radius: Math.min(3, width / 2, height / 2)
                        color:  Style.tint(Colors.bgSecondary, 0.75)
                        opacity: 0.55
                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 14; rightMargin: 14; topMargin: 12 }
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text:  master.muted ? "󰝟" : "󰕾"
                color: Colors.fgBright; font.family: Style.font; font.pixelSize: 19
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 36 - mPct.implicitWidth - 20)
                spacing: 3
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text:  root._label(master.node)
                    color: Colors.fgBright
                    font.family: Style.font; font.pixelSize: 15; font.bold: true
                }
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text:  "master  ·  " + root._channels(master.node)
                    color: Style.tint(Colors.fgBright, 0.55)
                    font.family: Style.font; font.pixelSize: 11
                }
            }
            Text {
                id: mPct
                anchors.verticalCenter: parent.verticalCenter
                text:  Math.round(master.vol * 100) + "%"
                color: Colors.fgBright
                font.family: Style.font; font.pixelSize: 20; font.bold: true
            }
        }
    }

    // ── Tabs ───────────────────────────────────────────────────────────────────────────────────
    Segmented {
        width: parent.width
        equal: true
        current: root.tab
        segments: [{ label: "Output  " + root._sinks().length,   key: "out" },
                   { label: "Input  " + root._sources().length,  key: "in" },
                   { label: "Apps  " + root._streams().length,   key: "apps" }]
        onPicked: key => { root.tab = key; root.routeFor = null }
    }

    // ── The rack ───────────────────────────────────────────────────────────────────────────────
    Flickable {
        width:  parent.width
        height: 360
        contentWidth: rack.width
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: rack
            height: parent.height
            spacing: 8
            Repeater {
                model: root._strips()
                delegate: Strip { required property var modelData; node: modelData }
            }
        }
    }
    Text {
        visible: root._strips().length === 0
        text:  root.tab === "apps" ? "nothing playing" : "no devices"
        color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
    }

    // ── Target picker — full width under the rack, where a 96px strip has no room ───────────────
    Column {
        width: parent.width
        spacing: 4
        visible: root.routeFor !== null
        Text {
            text:  "Send " + (root.routeFor ? root._appName(root.routeFor) : "") + " to"
            color: Colors.fgMuted; font.bold: true
            font.pixelSize: 11; font.letterSpacing: 0.5; font.family: Style.font
        }
        Repeater {
            model: root.routeFor === null ? []
                 : (root.routeFor.isSink ? root._sinks() : root._sources())
            delegate: StyledRect {
                id: tgt
                required property var modelData
                readonly property bool on: root.routeFor && tgt.modelData.name === root._devOf(root.routeFor)
                width: parent.width; height: 30
                radius: Style.rTile
                color: tgt.on ? Style.tint(Colors.bgActive, 0.30)
                     : tgtHov.containsMouse ? Style.controlHover : Style.menuRowFill
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right
                              rightMargin: 10; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text:  (tgt.on ? "󰄬  " : "") + root._label(tgt.modelData)
                    color: tgt.on ? Colors.fgBright : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 12
                }
                MouseArea {
                    id: tgtHov
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: { root.moveStream(root.routeFor, tgt.modelData.name); root.routeFor = null }
                }
            }
        }
    }

    // ── Building blocks ────────────────────────────────────────────────────────────────────────

    // Upright fader. The value still steps in 5% — that was the ask and it is what makes two
    // channels at the same level look the same — but the COLUMN is one capsule, not twenty bricks.
    // The steps are drawn onto it as hairline detents instead of cut out of it, and the fill rides
    // the shell's own spring (Style.elSpring/elDamping, the same one every panel emerges with), so
    // a step settles rather than jumps. Blocks read as a bar chart; this reads as a fader.
    component Fader: Item {
        id: fad
        property var au: null
        readonly property real vol:   fad.au ? Math.max(0, Math.min(1, fad.au.volume)) : 0
        readonly property bool muted: !!(fad.au && fad.au.muted)
        readonly property int  steps: 20
        width: 38

        // What is drawn, as opposed to what is set: it chases `vol` on a spring.
        property real shown: fad.vol
        onVolChanged: fad.shown = fad.vol
        Behavior on shown { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.002 } }

        ClippingRectangle {
            id: track
            anchors.fill: parent
            radius: width / 2                       // a capsule, so both ends stay soft
            color:  Style.tint(Colors.bgPrimary, 0.85)

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.max(0, track.height * fad.shown)
                radius: track.radius
                color:  fad.muted     ? Colors.fgMuted
                      : fad.vol > 0.9 ? Colors.fgUrgent     // at the ceiling, the console cue
                                      : Colors.bgActive
                Behavior on color { ColorAnimation { duration: 160 } }
            }

            // The 5% grid, drawn ON the column: legible detents, no bricks.
            Column {
                anchors.fill: parent
                spacing: (track.height - fad.steps) / fad.steps
                topPadding: (track.height - fad.steps) / fad.steps
                Repeater {
                    model: fad.steps - 1
                    delegate: Rectangle {
                        width:  track.width; height: 1
                        color:  Colors.bgPrimary
                        opacity: 0.35
                    }
                }
            }
        }

        // Grip at the top of the fill — the thing your eye follows while dragging.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width:  fad.width + 4
            height: 5
            radius: 2.5
            y: Math.max(0, Math.min(fad.height - height, fad.height * (1 - fad.shown) - height / 2))
            color: fad.muted ? Colors.fgMuted : Colors.fgBright
            opacity: fad.shown > 0.001 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            function apply(my) {
                if (!fad.au) return
                fad.au.muted = false
                // Top of the column is 100%. Snap to the 5% grid — the steps are the point.
                var v = 1 - ((my + 4) / fad.height)
                fad.au.volume = Math.max(0, Math.min(1, Math.round(v * fad.steps) / fad.steps))
            }
            onPressed:         e => apply(e.y)
            onPositionChanged: e => { if (pressed) apply(e.y) }
            onWheel: e => {
                if (!fad.au) return
                fad.au.volume = Math.max(0, Math.min(1, fad.au.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)))
            }
        }
    }

    // Upright level meter — the actual signal, beside the fader that asks for it. Capsules with
    // soft caps, matching the fader beside them; the decay math stays in the tick (a spring here
    // would smear the attack, and a meter that lags is a meter that lies).
    component Meter: Item {
        id: met
        property var node: null
        readonly property var peaks: mon.peaks ?? []
        property var _disp: [0, 0]
        width: 12

        PwNodePeakMonitor { id: mon; node: met.node; enabled: root.active }
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

        Row {
            anchors.fill: parent
            spacing: 2
            Repeater {
                model: 2
                delegate: ClippingRectangle {
                    id: lane
                    required property int index
                    readonly property real v: met._disp.length > index ? met._disp[index] : 0
                    width:  5; height: met.height
                    radius: 2.5
                    color:  Style.tint(Colors.bgPrimary, 0.85)
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: Math.max(0, lane.height * lane.v)
                        radius: lane.radius
                        color:  lane.v > 0.92 ? Colors.fgUrgent : Colors.bgActive
                        Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                        Behavior on color  { ColorAnimation  { duration: 120 } }
                    }
                }
            }
        }
    }

    // One channel: what it is on top, fader and meter in the middle, level and mute at the foot.
    component Strip: StyledRect {
        id: strip
        property var node: null
        readonly property var  au:    strip.node ? strip.node.audio : null
        readonly property bool isApp: root.tab === "apps"
        readonly property bool isDef: !strip.isApp && strip.node !== null
                                      && strip.node === (root.tab === "out" ? Pipewire.defaultAudioSink
                                                                            : Pipewire.defaultAudioSource)
        readonly property bool muted: !!(strip.au && strip.au.muted)

        width:  96
        height: 360
        // A strip is a card in a panel, so it takes the card radius rather than the control one —
        // the rounder corner is what keeps a rack of them from reading as a row of boxes.
        radius: Style.rCard
        color:  strip.isDef ? Style.tint(Colors.bgActive, 0.26)
              : sHov.containsMouse ? Style.controlHover : Style.menuRowFill
        Behavior on color { ColorAnimation { duration: 110 } }

        // Strips arrive on the shell's spring rather than appearing — switching tabs should feel
        // like the rack sliding in, not like a redraw.
        property real appear: 0
        Component.onCompleted: strip.appear = 1
        Behavior on appear { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.004 } }
        opacity: Math.max(0, Math.min(1, strip.appear))
        y:       (1 - Math.max(0, Math.min(1, strip.appear))) * 14

        MouseArea { id: sHov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        // ── Head: what this channel is ──
        Column {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 8; rightMargin: 8; topMargin: 9 }
            spacing: 3

            Item {
                width: parent.width; height: 20
                IconImage {
                    visible: strip.isApp
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 20; height: 20; implicitSize: 20
                    source: strip.isApp ? root._appIcon(strip.node) : ""
                }
                Text {
                    visible: !strip.isApp
                    anchors.centerIn: parent
                    text:  strip.isDef ? "󰄬" : "󰝥"
                    color: strip.isDef ? Colors.boActive : Colors.fgMuted
                    font.family: Style.font; font.pixelSize: 14
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text:  strip.isApp ? root._appName(strip.node) : root._label(strip.node)
                color: strip.isDef ? Colors.fgBright : Colors.fgPrimary
                font.family: Style.font; font.pixelSize: 12; font.bold: strip.isDef
            }
            // The second line earns its place: the track for an app, the format for a device.
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text:  strip.isApp ? root._media(strip.node) : root._channels(strip.node)
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 10
            }
        }

        // ── Fader + meter ──
        Row {
            anchors { top: head.bottom; topMargin: 10; horizontalCenter: parent.horizontalCenter }
            height: 190
            spacing: 6
            Fader { height: parent.height; au: strip.au }
            Meter { height: parent.height; node: strip.node }
        }

        // ── Foot: level, mute, and where an app plays ──
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: 8; rightMargin: 8; bottomMargin: 9 }
            spacing: 5

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text:  Math.round((strip.au ? Math.max(0, Math.min(1, strip.au.volume)) : 0) * 100) + "%"
                color: strip.muted ? Colors.fgMuted : Colors.fgBright
                font.family: Style.font; font.pixelSize: 14; font.bold: true
            }
            StyledRect {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 36; height: 26
                radius: height / 2              // a pill, like everything else in the strip
                color: strip.muted ? Style.tint(Colors.fgUrgent, 0.30)
                     : mHov.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors.centerIn: parent
                    text:  strip.muted ? "󰝟" : "󰕾"
                    color: strip.muted ? Colors.fgUrgent : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 13
                }
                MouseArea {
                    id: mHov
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: if (strip.au) strip.au.muted = !strip.au.muted
                }
            }
            // Apps: where it plays, tap to move it. Devices: tap the strip to make it the default.
            Text {
                visible: strip.isApp
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text:  "󰓃 " + root._deviceLabelFor(root._devOf(strip.node))
                color: (root.routeFor === strip.node || rHov.containsMouse) ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 10
                Behavior on color { ColorAnimation { duration: 90 } }
                MouseArea {
                    id: rHov
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true
                    onClicked: root.routeFor = (root.routeFor === strip.node) ? null : strip.node
                }
            }
            Text {
                visible: !strip.isApp && !strip.isDef
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text:  defHov.containsMouse ? "make default" : "󰝥"
                color: defHov.containsMouse ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 10
                MouseArea {
                    id: defHov
                    anchors.fill: parent; anchors.margins: -4
                    hoverEnabled: true
                    onClicked: if (strip.node) root.setDefault(root.tab === "out" ? "sink" : "source",
                                                               strip.node.name)
                }
            }
            Text {
                visible: !strip.isApp && strip.isDef
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text:  "default"
                color: Colors.boActive
                font.family: Style.font; font.pixelSize: 10; font.bold: true
            }
        }
    }
}
