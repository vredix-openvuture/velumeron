import "../.."
import QtQuick
import Quickshell.Io

// Shows Bluetooth power state and connected device count.
// Left-click opens the rofi bluetooth menu (or vtl_bluetooth_menu from config).
Item {
    id: root
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    property bool   _powered:   false
    property int    _connected: 0

    readonly property string _icon: {
        if (!_powered)     return "󰂲"
        if (_connected > 0) return "󰂯"
        return "󰂰"
    }

    Text {
        id: label
        text: {
            if (!root._powered) return root._icon
            if (root._connected > 0) return root._icon + " " + root._connected
            return root._icon
        }
        color: {
            if (!root._powered)      return Colors.fgMuted
            if (root._connected > 0) return Colors.boActive
            return Colors.fgMuted
        }
        font.family:    "FantasqueSansM Nerd Font"
        font.pointSize: 10
    }

    MouseArea {
        anchors.fill:    parent
        acceptedButtons: Qt.LeftButton
        onClicked: {
            btMenuProc.running = false
            btMenuProc.running = true
        }
    }

    Process {
        id: pollProc
        command: ["bash", "-c",
            "echo power:$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}');" +
            "echo conn:$(bluetoothctl devices Connected 2>/dev/null | wc -l)"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("power:")) root._powered = line.slice(6).trim() === "yes"
                if (line.startsWith("conn:"))  root._connected = parseInt(line.slice(5).trim()) || 0
            }
        }
    }

    Timer {
        interval: 8000
        repeat:   true
        running:  true
        triggeredOnStart: true
        onTriggered: {
            pollProc.running = false
            pollProc.running = true
        }
    }

    Process {
        id: btMenuProc
        command: ["bash", "-c",
            "$VUTURELAND_USER_DIR/rofi/assets/bluetooth.sh 2>/dev/null || true"]
    }
}
