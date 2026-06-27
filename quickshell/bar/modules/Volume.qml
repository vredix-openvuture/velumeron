import "../.."
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property bool muted:   Pipewire.defaultAudioSink?.audio?.muted  ?? false
    readonly property int  volume:  Math.round((Pipewire.defaultAudioSink?.audio?.volume ?? 0) * 100)
    readonly property bool hovered: mouseArea.containsMouse

    Text {
        id: label
        text:  root.muted ? "󰝟" : root.volume + " 󰕾"
        color: root.hovered ? Colors.fgBright
             : root.muted   ? Colors.fgMuted
             : Colors.fgPrimary
        font.family:    "FantasqueSansM Nerd Font"
        font.pointSize: 10
        Behavior on color { ColorAnimation { duration: 100 } }
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
                mixerProc.running = false
                mixerProc.running = true
            }
        }
        onWheel: event => {
            scrollProc.command = ["pactl", "set-sink-volume", "@DEFAULT_SINK@",
                                  event.angleDelta.y > 0 ? "+5%" : "-5%"]
            scrollProc.running = false
            scrollProc.running = true
        }
    }

    Process { id: muteProc;  command: ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"] }
    Process { id: scrollProc }
    Process { id: mixerProc; command: ["bash", "-c", "$VUTURELAND_DIR/assets/scripts/launch-audio-mixer.sh 2>/dev/null || kitty --title pulsemixer -e pulsemixer"] }
}
