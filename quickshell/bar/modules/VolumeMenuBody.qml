import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// The mixer. A full replacement for reaching for pulsemixer: the active output up top as one big
// control, then every output and input to pick the default from, then every APPLICATION with its
// own level, its own mute, and — the part that needs help from outside Quickshell — a picker to
// send it to a different output.
//
// Routing goes through assets/scripts/audio-route.py, because the id Quickshell hands out for a
// stream is not the id pactl takes: node 64 is sink-input 6978. The script owns that lookup, so
// everything here deals in PipeWire node ids. It also reports which device each stream currently
// plays on, which Quickshell doesn't expose — polled only while the menu is open, and immediately
// after a move so the chip never lags behind the thing it just did.
//
// Hosted by VolumeMenu (the popout that grows out of the Volume module) and by GroupMenu; `active`
// mirrors the host's open state. Levels themselves need no polling — Pipewire binds live.
Column {
    id: root
    property bool active: false
    spacing: 12

    // Keep the audio bound for every device node so volume reads/writes are live.
    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/audio-route.py"

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
    // Human name for a device node NAME (what the routing script reports).
    function _deviceLabelFor(nodeName) {
        var ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++)
            if (ns[i] && ns[i].name === nodeName) return root._label(ns[i])
        return nodeName === "" ? "—" : nodeName
    }

    // ── Routing (see the header) ───────────────────────────────────────────────────────────────
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

    // ── Master: the active output, given the room it deserves ──────────────────────────────────
    StyledRect {
        id: master
        readonly property var  node:  Pipewire.defaultAudioSink
        readonly property var  au:    master.node ? master.node.audio : null
        readonly property bool muted: !!(master.au && master.au.muted)
        readonly property real vol:   master.au ? Math.max(0, Math.min(1, master.au.volume)) : 0

        width:  parent.width
        height: 74
        radius: Style.rControl
        color:  Style.tint(Colors.bgActive, 0.18)

        Column {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 14; rightMargin: 14 }
            spacing: 9

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

    DeviceSection { title: "Output"; kind: "sink";   nodes: root._sinks();   def: Pipewire.defaultAudioSink }
    DeviceSection { title: "Input";  kind: "source"; nodes: root._sources(); def: Pipewire.defaultAudioSource }

    // ── Applications ───────────────────────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 7
        SectionLabel { text: "Applications" }
        Repeater {
            model: root._streams()
            delegate: StyledRect {
                id: app
                required property var modelData
                readonly property var  au:     app.modelData.audio
                readonly property bool isOut:  app.modelData.isSink
                readonly property string devName: "" + (root._routes[app.modelData.id] ?? "")
                property bool pickOpen: false

                width:  parent.width
                height: 74 + (app.pickOpen ? devPick.implicitHeight + 8 : 0)
                radius: Style.rControl
                color:  Style.menuRowFill
                clip:   true
                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 12; rightMargin: 12; topMargin: 10 }
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 9
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22; implicitSize: 22
                            source: root._appIcon(app.modelData)
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 31 - aPct.implicitWidth - aMute.implicitWidth - 18
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text:  root._appName(app.modelData)
                                color: Colors.fgPrimary
                                font.family: Style.font; font.pixelSize: 12.5
                            }
                            // Where it plays — click to send it somewhere else.
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text:  (app.isOut ? "󰓃 " : "󰍬 ") + root._deviceLabelFor(app.devName)
                                color: devHov.containsMouse || app.pickOpen ? Style.accent : Colors.fgMuted
                                font.family: Style.font; font.pixelSize: 10.5
                                MouseArea {
                                    id: devHov
                                    anchors.fill: parent; anchors.margins: -3
                                    hoverEnabled: true
                                    onClicked: app.pickOpen = !app.pickOpen
                                }
                            }
                        }
                        Text {
                            id: aPct
                            anchors.verticalCenter: parent.verticalCenter
                            text:  Math.round(app.au ? Math.max(0, Math.min(1, app.au.volume)) * 100 : 0) + "%"
                            color: (app.au && app.au.muted) ? Colors.fgMuted : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 11
                        }
                        MuteBtn { id: aMute; anchors.verticalCenter: parent.verticalCenter; au: app.au }
                    }

                    MixTrack { width: parent.width; au: app.au }

                    // Target picker — the outputs (or inputs) this stream can be moved to.
                    Column {
                        id: devPick
                        width: parent.width
                        spacing: 3
                        visible: app.pickOpen
                        Repeater {
                            model: app.isOut ? root._sinks() : root._sources()
                            delegate: StyledRect {
                                id: tgt
                                required property var modelData
                                readonly property bool on: tgt.modelData.name === app.devName
                                width: devPick.width; height: 26
                                radius: Style.rTile
                                color: tgt.on ? Style.tint(Colors.bgActive, 0.30)
                                     : tgtHov.containsMouse ? Style.controlHover : "transparent"
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
                                        root.moveStream(app.modelData, tgt.modelData.name)
                                        app.pickOpen = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            visible: root._streams().length === 0
            text:  "nothing playing"
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }

    // ── Building blocks ────────────────────────────────────────────────────────────────────────
    component SectionLabel: Text {
        color: Colors.fgMuted; font.bold: true
        font.pixelSize: 11; font.letterSpacing: 0.5; font.family: Style.font
    }

    component MuteBtn: Text {
        property var au: null
        readonly property bool muted: !!(au && au.muted)
        text:  muted ? "󰝟" : "󰕾"
        color: muted ? Colors.fgUrgent : (mbHov.containsMouse ? Colors.fgBright : Colors.fgMuted)
        font.family: Style.font; font.pixelSize: 14
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
                Behavior on width { NumberAnimation { duration: 60 } }
            }
        }
        Rectangle {
            visible: trkHov.containsMouse || trkHov.pressed || trk.big
            x: Math.max(0, Math.min(rail.width - width, rail.width * trk.vol - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: trk.big ? 14 : 11; height: width; radius: width / 2
            color: trk.muted ? Colors.fgMuted : Colors.fgBright
            border.width: 1; border.color: Style.tint(Colors.bgActive, 0.6)
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

    // One labelled device list: click a row to make it the default.
    component DeviceSection: Column {
        id: sec
        property string title: ""
        property string kind:  "sink"
        property var    nodes: []
        property var    def:   null
        width:  parent ? parent.width : 0
        spacing: 7

        SectionLabel { text: sec.title }
        Repeater {
            model: sec.nodes
            delegate: StyledRect {
                id: row
                required property var modelData
                readonly property bool isDef: sec.def !== null && row.modelData === sec.def
                readonly property var  au:    row.modelData.audio
                width:  sec.width
                height: 56
                radius: Style.rControl
                color:  row.isDef ? Style.tint(Colors.bgActive, 0.26)
                      : rowHov.containsMouse ? Style.controlHover : Style.menuRowFill
                Behavior on color { ColorAnimation { duration: 100 } }

                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 12; rightMargin: 12 }
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text:  row.isDef ? "󰄬" : "󰝥"
                            color: row.isDef ? Colors.boActive : Colors.fgMuted
                            font.family: Style.font; font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - 29 - dPct.implicitWidth
                                               - dMute.implicitWidth - 16)
                            elide: Text.ElideRight
                            text:  root._label(row.modelData)
                            color: row.isDef ? Colors.fgBright : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 12.5
                        }
                        Text {
                            id: dPct
                            anchors.verticalCenter: parent.verticalCenter
                            text:  Math.round(row.au ? Math.max(0, Math.min(1, row.au.volume)) * 100 : 0) + "%"
                            color: (row.au && row.au.muted) ? Colors.fgMuted : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 11
                        }
                        MuteBtn { id: dMute; anchors.verticalCenter: parent.verticalCenter; au: row.au }
                    }
                    MixTrack { width: parent.width; au: row.au }
                }

                // Click the row (not the track) to make this the default device.
                MouseArea {
                    id: rowHov
                    anchors.fill: parent
                    anchors.bottomMargin: 18   // leave the track to its own MouseArea
                    hoverEnabled: true
                    onClicked: root.setDefault(sec.kind, row.modelData.name)
                }
            }
        }
        Text {
            visible: sec.nodes.length === 0
            text:  "no devices"
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }
}
