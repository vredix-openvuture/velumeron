import "../.."
import QtQuick
import Quickshell.Io

Text {
    id: root
    property string barMon: ""   // monitor name, for per-monitor icon size
    text:  "󰂜"
    color: Colors.fgPrimary
    font.family:    Style.font
    font.pixelSize: VtlConfig.barIconSizeFor(root.barMon)

    Process { id: proc; command: ["bash", "-c", "$VELUMERON_DIR/bin/velumeron --panel-toggle"] }

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
