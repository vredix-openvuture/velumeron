import "../.."
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon:   ""    // monitor name, for per-monitor icon/font size
    property string barEdge:  "top" // set by Bar; drives the hover-glide direction
    property string barGroup: "start" // set by Bar; start/end → menu merges into the corner
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property bool muted:   Pipewire.defaultAudioSink?.audio?.muted  ?? false
    readonly property int  volume:  Math.round((Pipewire.defaultAudioSink?.audio?.volume ?? 0) * 100)
    readonly property bool hovered: mouseArea.containsMouse

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:    VtlConfig.moduleFontFor("volume")
    readonly property color  _col:     Colors[VtlConfig.moduleColorName("volume")] ?? Colors.fgMuted
    readonly property bool   _showPct: VtlConfig.moduleSetting("volume", "show_percent", false)
    readonly property int    _scroll:  VtlConfig.moduleSetting("volume", "scroll_step", 5)

    // ── Hover-glide: publish hover + screen anchor so VolumeGlide can show the percentage
    // gliding out of the module toward the monitor centre. ──────────────────────────────
    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.volumeAnchorX = c.x
        UiState.volumeAnchorY = c.y
        UiState.volumeEdge    = root.barEdge
        UiState.volumeMon     = root.barMon
        UiState.volumeLevel   = root.volume
        UiState.volumeMuted   = root.muted
    }
    onHoveredChanged: {
        if (root.hovered) { _publishGlide(); UiState.volumeHover = true }
        else if (UiState.volumeMon === root.barMon) UiState.volumeHover = false
    }
    onVolumeChanged: if (root.hovered) { UiState.volumeLevel = root.volume; UiState.volumeMuted = root.muted }
    onMutedChanged:  if (root.hovered)   UiState.volumeMuted = root.muted

    // Click opens the Volume menu (docked out of the bar); hover only shows the glide.
    function _toggleMenu() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.toggleFlyout("volume", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
    }

    Row {
        id: label
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root.muted ? "󰝟" : "󰕾"
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleIconSizeFor("volume", root.barMon)
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Text {
            visible: root._showPct
            anchors.verticalCenter: parent.verticalCenter
            text:  root.volume + "%"
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleFontSizeFor("volume", root.barMon)
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill:    parent
        hoverEnabled:    true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.MiddleButton) {
                muteProc.running = false
                muteProc.running = true
            } else {
                root._toggleMenu()
            }
        }
        onWheel: event => {
            // Absolute set, clamped to 0–100: relative pactl steps let the sink run past 100%.
            var target = root.volume + (event.angleDelta.y > 0 ? root._scroll : -root._scroll)
            target = Math.max(0, Math.min(100, target))
            scrollProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@", target + "%"]
            scrollProc.running = false
            scrollProc.running = true
        }
    }

    Process { id: muteProc;  command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"] }
    Process { id: scrollProc }
}
