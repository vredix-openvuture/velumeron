pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// The microphone panel: which input is live, how loud it is, and every application currently
// recording — each with its own level and its own mute, because "turn that one off" is the thing
// you actually want when a call and a recorder are both holding the mic.
//
// A small panel on purpose. The full sound desk (VolumeMenuBody) already exists and can be reached
// from the volume module; this is the one question the microphone button is asked.
Flyout {
    id: root
    flyoutId: "mic"
    panelW:   Math.max(300, Math.round(root.sw * VtlConfig.moduleSetting("microphone", "menu_width_pct", 17) / 100))
    maxH:     Math.round(root.sh * VtlConfig.moduleSetting("microphone", "menu_height_pct", 50) / 100)

    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    function _own(n) { return root._ownStreams.indexOf(("" + ((n && n.name) ?? "")).toLowerCase()) >= 0 }
    function _label(n) {
        if (!n) return "—"
        return (n.description && n.description !== "") ? ("" + n.description)
                                                       : ("" + (n.nickname || n.name || "—"))
    }

    // Real capture devices (not monitors, not streams) — what "which microphone" means.
    readonly property var sources: {
        var out = [], ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i]
            if (!n || n.isSink || n.isStream || !n.audio) continue
            if (("" + (n.name ?? "")).indexOf("monitor") >= 0) continue
            out.push(n)
        }
        return out
    }
    // Capture STREAMS — the applications listening.
    readonly property var recorders: {
        var out = [], ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i]
            if (!n || !n.isStream || !n.audio || n.isSink) continue
            if (root._own(n)) continue
            out.push(n)
        }
        return out
    }

    readonly property var def: Pipewire.defaultAudioSource
    Process { id: act }
    function run(cmd) { act.command = ["bash", "-c", cmd]; act.running = false; act.running = true }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        Text {
            text: "MICROPHONE"
            color: Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
        }

        // ── The default input ───────────────────────────────────────────────────────────────────
        StyledRect {
            width: parent.width
            height: defCol.implicitHeight + 20
            radius: Style.rTile
            color: Style.controlFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
            Column {
                id: defCol
                anchors { left: parent.left; right: parent.right; margins: 10
                          verticalCenter: parent.verticalCenter }
                spacing: 8
                Row {
                    width: parent.width
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text:  (root.def?.audio?.muted ?? false) ? "󰍭" : "󰍬"
                        color: (root.def?.audio?.muted ?? false) ? Colors.fgMuted : Style.accent
                        font.family: Style.iconFont; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.run("pactl set-source-mute @DEFAULT_SOURCE@ toggle") }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 26; elide: Text.ElideRight
                        text:  root._label(root.def)
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 12
                    }
                }
                Slider {
                    label: "Level"; labelWidth: 46; from: 0; to: 100; decimals: 0; step: 1
                    value: Math.round((root.def?.audio?.volume ?? 0) * 100)
                    onMoved: v => root.run("pactl set-source-volume @DEFAULT_SOURCE@ " + Math.round(v) + "%")
                }
            }
        }

        // ── Pick another input ──────────────────────────────────────────────────────────────────
        Text {
            visible: root.sources.length > 1
            text: "INPUT"
            color: Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
        }
        Repeater {
            model: root.sources.length > 1 ? root.sources : []
            delegate: StyledRect {
                id: src
                required property var modelData
                readonly property bool on: src.modelData === Pipewire.defaultAudioSource
                width: parent.width; height: 34
                radius: Style.rTile
                color: src.on ? Style.tint(Style.accent, 0.30)
                     : sHov.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Text {
                    anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    text:  root._label(src.modelData); elide: Text.ElideRight
                    color: src.on ? Colors.fgBright : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 12
                }
                MouseArea {
                    id: sHov
                    anchors.fill: parent; hoverEnabled: true
                    // Through pactl, the way the sound desk does it — Quickshell's PipeWire
                    // binding exposes the default source but not a setter for it.
                    onClicked: root.run("pactl set-default-source " + JSON.stringify("" + src.modelData.name))
                }
            }
        }

        // ── Who is listening ────────────────────────────────────────────────────────────────────
        Text {
            text: "RECORDING"
            color: Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
        }
        Text {
            visible: root.recorders.length === 0
            text: "Nothing is recording."
            color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 11
        }
        Repeater {
            model: root.recorders
            delegate: StyledRect {
                id: rec
                required property var modelData
                width: parent.width
                height: recCol.implicitHeight + 18
                radius: Style.rTile
                color: Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Column {
                    id: recCol
                    anchors { left: parent.left; right: parent.right; margins: 10
                              verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Row {
                        width: parent.width
                        spacing: 8
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            source: {
                                var nm = "" + (rec.modelData.name ?? "")
                                var e = DesktopEntries.heuristicLookup(nm)
                                return Quickshell.iconPath((e && e.icon) ? e.icon : nm.toLowerCase(),
                                                           "application-x-executable")
                            }
                            sourceSize.width: 32; sourceSize.height: 32; asynchronous: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24 - 26; elide: Text.ElideRight
                            text:  root._label(rec.modelData)
                            color: (rec.modelData.audio?.muted ?? false) ? Colors.fgMuted : Colors.fgBright
                            font.family: Style.font; font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text:  (rec.modelData.audio?.muted ?? false) ? "󰍭" : "󰍬"
                            color: (rec.modelData.audio?.muted ?? false) ? Colors.fgMuted : Colors.fgPrimary
                            font.family: Style.iconFont; font.pixelSize: 15
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (rec.modelData.audio)
                                               rec.modelData.audio.muted = !rec.modelData.audio.muted
                            }
                        }
                    }
                    Slider {
                        label: ""; labelWidth: 0; from: 0; to: 100; decimals: 0; step: 1
                        value: Math.round((rec.modelData.audio?.volume ?? 0) * 100)
                        onMoved: v => { if (rec.modelData.audio) rec.modelData.audio.volume = v / 100 }
                    }
                }
            }
        }
    }
}
