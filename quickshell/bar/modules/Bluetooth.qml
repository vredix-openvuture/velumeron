import "../.."
import QtQuick
import Quickshell.Io

// Bluetooth module: shows power/connection state. Hover glides the active connection out of the bar
// (BtGlide); click opens the Bluetooth menu (BluetoothMenu, grows from the bar). Hover is suppressed
// while the menu is open.
Item {
    id: root
    property string barMon:   ""    // monitor name, for per-monitor icon/font size
    property string barEdge:  "top" // set by Bar; drives glide / menu direction
    property string barGroup: "start"
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    property bool   _powered:   false
    property int    _connected: 0
    property string _names:     ""   // connected device names, "·"-joined (for the hover glide)

    readonly property string _icon: {
        if (!_powered)      return "󰂲"
        if (_connected > 0) return "󰂯"
        return "󰂰"
    }
    // Per-module customization (Settings → Bar → Module → gear). Colour override = the active state.
    readonly property string _font: VtlConfig.moduleFontFor("bluetooth")
    readonly property color _col: (root._powered && root._connected > 0)
                                  ? (Colors[VtlConfig.moduleColorName("bluetooth")] ?? Colors.boActive) : Colors.fgMuted
    readonly property bool menuOpen: UiState.flyout === "bluetooth" && UiState.flyoutMon === root.barMon

    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.btAnchorX = c.x; UiState.btAnchorY = c.y
        UiState.btEdge = root.barEdge; UiState.btMon = root.barMon
        UiState.btStatus = root._names !== "" ? root._names : (root._powered ? "No device connected" : "Bluetooth off")
    }
    function _toggleMenu() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.btHover = false
        UiState.toggleFlyout("bluetooth", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text:           root._icon
        color:          root._col
        font.family:    root._font
        font.pixelSize: VtlConfig.moduleIconSizeFor("bluetooth", root.barMon)

        MouseArea {
            anchors.fill:    parent
            hoverEnabled:    true
            acceptedButtons: Qt.LeftButton
            onClicked: root._toggleMenu()
            onEntered: { if (!root.menuOpen) { root._publishGlide(); UiState.btHover = true } }
            onExited:  { if (UiState.btMon === root.barMon) UiState.btHover = false }
        }
    }

    // Power + connected count + connected device names (for icon state and the hover glide).
    Process {
        id: pollProc
        command: ["bash", "-c",
            "echo power:$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2; exit}');" +
            "echo names:$(bluetoothctl devices Connected 2>/dev/null | cut -d' ' -f3- | paste -sd '·' -)"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("power:")) root._powered = line.slice(6).trim() === "yes"
                if (line.startsWith("names:")) {
                    var n = line.slice(6).trim()
                    root._names = n
                    root._connected = n === "" ? 0 : n.split("·").length
                    if (UiState.btMon === root.barMon && UiState.btHover) UiState.btStatus = root._names !== "" ? root._names : "No device connected"
                }
            }
        }
    }
    Timer {
        interval: 8000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { pollProc.running = false; pollProc.running = true }
    }
}
