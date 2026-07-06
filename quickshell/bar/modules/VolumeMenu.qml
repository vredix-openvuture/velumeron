import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Volume flyout: pick the active output (sink) and input (source) and set each device's level.
// Grows out of the bar from the Volume module on hover (see Volume.qml + UiState.flyout).
Flyout {
    id: root
    flyoutId: "volume"
    panelW:   330
    maxH:     540

    // Keep the audio bound for every device node so volume reads/writes are live.
    PwObjectTracker { objects: Pipewire.nodes.values }

    function _sinks()   { return Pipewire.nodes.values.filter(function (n) { return n && n.isSink && !n.isStream && n.audio }) }
    function _sources() { return Pipewire.nodes.values.filter(function (n) { return n && !n.isSink && !n.isStream && n.audio && (n.name || "").indexOf("monitor") < 0 }) }
    function _label(n)  { return (n.description && n.description !== "") ? n.description : (n.nickname || n.name || "device") }

    Process { id: defProc }
    function _setDefault(kind, name) {
        defProc.command = ["pactl", kind === "sink" ? "set-default-sink" : "set-default-source", name]
        defProc.running = false; defProc.running = true
    }

    Column {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 14

        DeviceSection { title: "Output";  kind: "sink";   nodes: root._sinks();   def: Pipewire.defaultAudioSink }
        DeviceSection { title: "Input";   kind: "source"; nodes: root._sources(); def: Pipewire.defaultAudioSource }
    }

    // One labelled list of devices, each with a selectable default + a draggable volume bar.
    component DeviceSection: Column {
        id: sec
        property string title: ""
        property string kind:  "sink"
        property var    nodes: []
        property var    def:   null
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
                readonly property bool isDef: sec.def !== null && modelData === sec.def
                width:  sec.width
                height: 50
                radius: Style.rControl
                color:  rowHov.containsMouse || isDef
                        ? Style.tint(Colors.bgActive, isDef ? 0.30 : 0.16)
                        : Colors.bgElement
                Behavior on color { ColorAnimation { duration: 100 } }

                Column {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: 12; rightMargin: 12 }
                    spacing: 6

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
                            width:  parent.width - 28
                            elide:  Text.ElideRight
                            text:   root._label(row.modelData)
                            color:  row.isDef ? Colors.fgBright : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 12
                        }
                    }

                    // Volume bar — click / drag to set this device's level.
                    Rectangle {
                        width:  parent.width
                        height: 8
                        radius: 4
                        color:  Colors.bgPrimary
                        Rectangle {
                            width:  parent.width * Math.max(0, Math.min(1, row.modelData.audio ? row.modelData.audio.volume : 0))
                            height: parent.height; radius: parent.radius
                            color:  (row.modelData.audio && row.modelData.audio.muted) ? Colors.fgMuted : Colors.bgActive
                        }
                        MouseArea {
                            anchors.fill: parent
                            function apply(mx) {
                                if (!row.modelData.audio) return
                                row.modelData.audio.muted = false
                                row.modelData.audio.volume = Math.max(0, Math.min(1, mx / width))
                            }
                            onPressed:        e => apply(e.x)
                            onPositionChanged: e => { if (pressed) apply(e.x) }
                        }
                    }
                }

                // Click the row (not the bar) to make this the default device.
                MouseArea {
                    id: rowHov
                    anchors.fill: parent
                    anchors.bottomMargin: 16   // leave the volume bar to its own MouseArea
                    hoverEnabled: true
                    onClicked: root._setDefault(sec.kind, row.modelData.name)
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
