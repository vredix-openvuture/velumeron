pragma ComponentBehavior: Bound
import ".."
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// What is listening, gliding out of the bar on hover of the Microphone module. A readout, not a
// control — the pill takes no input, so the cursor can pass straight over it.
//
// Read live off PipeWire rather than through UiState: a capture stream appears and disappears on
// its own schedule, and a snapshot published at hover time would go stale while the pill is up.
BarGlide {
    id: g
    glideId: "mic"
    mine:    UiState.micMon === g.mon && g.mon !== ""
    shown:   UiState.micHover
    edge:    UiState.micEdge
    anchorX: UiState.micAnchorX
    anchorY: UiState.micAnchorY

    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    readonly property var recorders: {
        var out = []
        var ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i]
            if (!n || !n.isStream || !n.audio || n.isSink) continue
            if (g._ownStreams.indexOf(("" + (n.name ?? "")).toLowerCase()) >= 0) continue
            out.push({ name: "" + (n.name ?? ""),
                       label: (n.description && n.description !== "") ? ("" + n.description)
                                                                      : ("" + (n.nickname || n.name || "")) })
        }
        return out
    }
    readonly property bool muted: Pipewire.defaultAudioSource?.audio?.muted ?? false

    Column {
        spacing: 6

        // Nothing recording is the answer people are actually looking for, so it gets a line of its
        // own rather than an empty pill.
        Row {
            visible: g.recorders.length === 0
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter
                   text: g.muted ? "󰍭" : "󰍬"
                   color: g.muted ? Colors.fgMuted : Colors.fgPrimary
                   font.family: Style.iconFont; font.pixelSize: 15 }
            Text { anchors.verticalCenter: parent.verticalCenter
                   text: g.muted ? "Microphone muted" : "Nothing is recording"
                   color: Colors.fgPrimary; font.family: Style.font; font.pixelSize: 13 }
        }

        Repeater {
            model: g.recorders
            delegate: Row {
                id: rec
                required property var modelData
                spacing: 8
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16; height: 16
                    source: {
                        var e = DesktopEntries.heuristicLookup(rec.modelData.name)
                        return Quickshell.iconPath((e && e.icon) ? e.icon : rec.modelData.name.toLowerCase(),
                                                   "application-x-executable")
                    }
                    sourceSize.width: 32; sourceSize.height: 32; asynchronous: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text:  rec.modelData.label
                    color: g.muted ? Colors.fgMuted : Colors.fgBright
                    font.family: Style.font; font.pixelSize: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: g.muted
                    text: "(muted)"
                    color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 11
                }
            }
        }
    }
}
