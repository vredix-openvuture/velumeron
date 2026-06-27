import "../.."
import QtQuick
import Quickshell.Io

Text {
    id: root
    text:  "󰂜"
    color: Colors.fgPrimary
    font.family:    "FantasqueSansM Nerd Font"
    font.pointSize: 11

    Process { id: proc; command: ["bash", "-c", "$VUTURELAND_DIR/bin/vutureland --panel-toggle"] }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            proc.running = false
            proc.running = true
        }
        onEntered: root.color = Colors.fgBright
        onExited:  root.color = Colors.fgPrimary
    }
}
