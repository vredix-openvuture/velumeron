import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire

// Volume menu content — the mixer. Picks the active output (sink) and input (source), sets each
// device's level, and gives every APPLICATION its own level and mute: the part pulsemixer exists
// for and the thing this menu was missing, since turning one app down used to mean leaving the bar.
// Hosted by VolumeMenu (the popout that grows out of the Volume module) and by GroupMenu
// (Control-Center groups); `active` mirrors the host menu's open state (volume needs no refresh —
// Pipewire binds live).
//
// Application streams are listed as ONE group rather than split into playback and recording: what
// Quickshell reports in `isSink` for a stream node isn't something this could verify without a live
// session, and a wrong guess would silently file apps under the wrong heading. Moving a stream to
// another device is missing for a related reason — that needs pactl's sink-input index, which is
// NOT the PipeWire node id Quickshell exposes (checked: node 157 is sink-input 6942).
Column {
    id: root
    property bool active: false
    spacing: 14

    // Keep the audio bound for every device node so volume reads/writes are live.
    PwObjectTracker { objects: Pipewire.nodes.values }

    function _sinks()   { return Pipewire.nodes.values.filter(function (n) { return n && n.isSink && !n.isStream && n.audio }) }
    function _sources() { return Pipewire.nodes.values.filter(function (n) { return n && !n.isSink && !n.isStream && n.audio && (n.name || "").indexOf("monitor") < 0 }) }
    // The shell's own capture (the cava visualiser feeding the bar) is not an app the user mixes.
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _streams() {
        return Pipewire.nodes.values.filter(function (n) {
            return n && n.isStream && n.audio
                && root._ownStreams.indexOf(("" + (n.name || "")).toLowerCase()) < 0
        })
    }

    function _label(n)  { return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "device") }
    // Streams carry no description or nick — node.name is the application ("LibreWolf"), which is
    // also the best handle for its icon.
    function _streamLabel(n) { return (n.name && n.name !== "") ? n.name : (n.description || "audio") }
    function _streamIcon(n) {
        var nm = ("" + (n.name ?? "")).trim()
        if (nm === "") return ""
        var e = DesktopEntries.heuristicLookup(nm)
        return Quickshell.iconPath((e && e.icon) ? e.icon : nm.toLowerCase(), "application-x-executable")
    }

    Process { id: defProc }
    function _setDefault(kind, name) {
        defProc.command = ["pactl", kind === "sink" ? "set-default-sink" : "set-default-source", name]
        defProc.running = false; defProc.running = true
    }

    DeviceSection { title: "Output";       kind: "sink";   nodes: root._sinks();   def: Pipewire.defaultAudioSink }
    DeviceSection { title: "Input";        kind: "source"; nodes: root._sources(); def: Pipewire.defaultAudioSource }
    DeviceSection { title: "Applications"; kind: "stream"; nodes: root._streams(); def: null
                    emptyText: "nothing playing" }

    // One labelled list. Devices get the default-selection check and click-to-select; application
    // streams get their app icon instead — there is nothing to select, only to set.
    component DeviceSection: Column {
        id: sec
        property string title: ""
        property string kind:  "sink"
        property var    nodes: []
        property var    def:   null
        property string emptyText: "no devices"
        readonly property bool isStream: sec.kind === "stream"
        width:  parent ? parent.width : 0
        spacing: 7

        Text {
            text: sec.title; color: Colors.fgMuted; font.bold: true
            font.pixelSize: 11; font.letterSpacing: 0.5; font.family: Style.font
        }
        Repeater {
            model: sec.nodes
            delegate: StyledRect {
                id: row
                required property var modelData
                readonly property bool isDef:  !sec.isStream && sec.def !== null && modelData === sec.def
                readonly property var  au:     row.modelData.audio
                readonly property bool muted:  !!(row.au && row.au.muted)
                readonly property real vol:    row.au ? Math.max(0, Math.min(1, row.au.volume)) : 0
                width:  sec.width
                height: 50
                radius: Style.rControl
                color:  rowHov.containsMouse || row.isDef
                        ? Style.tint(Colors.bgActive, row.isDef ? 0.30 : 0.16)
                        : Style.menuRowFill
                Behavior on color { ColorAnimation { duration: 100 } }

                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 12; rightMargin: 12 }
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: 8

                        // Devices: the default marker. Streams: the app's icon.
                        Text {
                            visible: !sec.isStream
                            anchors.verticalCenter: parent.verticalCenter
                            text:  row.isDef ? "󰄬" : "󰝥"
                            color: row.isDef ? Colors.boActive : Colors.fgMuted
                            font.family: Style.font; font.pixelSize: 13
                        }
                        IconImage {
                            visible: sec.isStream
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; implicitSize: 16
                            source: sec.isStream ? root._streamIcon(row.modelData) : ""
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width:  Math.max(0, parent.width - 28 - pctT.implicitWidth
                                                - muteT.implicitWidth - 16)
                            elide:  Text.ElideRight
                            text:   sec.isStream ? root._streamLabel(row.modelData) : root._label(row.modelData)
                            color:  row.isDef ? Colors.fgBright : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 12
                        }
                        Text {
                            id: pctT
                            anchors.verticalCenter: parent.verticalCenter
                            text:  Math.round(row.vol * 100) + "%"
                            color: row.muted ? Colors.fgMuted : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 11
                        }
                        // Mute — the level bar alone could never get to silence and back, because
                        // dragging it unmutes by design.
                        Text {
                            id: muteT
                            anchors.verticalCenter: parent.verticalCenter
                            text:  row.muted ? "󰝟" : "󰕾"
                            color: row.muted ? Colors.fgUrgent
                                 : muteHov.containsMouse ? Colors.fgBright : Colors.fgMuted
                            font.family: Style.font; font.pixelSize: 13
                            MouseArea {
                                id: muteHov
                                anchors.fill: parent; anchors.margins: -5
                                hoverEnabled: true
                                onClicked: if (row.au) row.au.muted = !row.au.muted
                            }
                        }
                    }

                    // Volume bar — click / drag to set this level.
                    Rectangle {
                        width:  parent.width
                        height: 8
                        radius: 4
                        color:  Colors.bgPrimary
                        Rectangle {
                            width:  parent.width * row.vol
                            height: parent.height; radius: parent.radius
                            color:  row.muted ? Colors.fgMuted : Colors.bgActive
                        }
                        MouseArea {
                            anchors.fill: parent
                            function apply(mx) {
                                if (!row.au) return
                                row.au.muted = false
                                // Snap to 5% steps so the slider only ever sets 0, 5, 10 … %.
                                row.au.volume = Math.max(0, Math.min(1, Math.round((mx / width) / 0.05) * 0.05))
                            }
                            onPressed:         e => apply(e.x)
                            onPositionChanged: e => { if (pressed) apply(e.x) }
                        }
                    }
                }

                // Click the row (not the bar) to make this the default device. Streams have no
                // default to pick, so their rows only hover.
                MouseArea {
                    id: rowHov
                    anchors.fill: parent
                    anchors.bottomMargin: 16   // leave the volume bar to its own MouseArea
                    hoverEnabled: true
                    onClicked: if (!sec.isStream) root._setDefault(sec.kind, row.modelData.name)
                }
            }
        }
        Text {
            visible: sec.nodes.length === 0
            text:  sec.emptyText
            color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font
        }
    }
}
