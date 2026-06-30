import "../.."
import QtQuick
import Quickshell.Io

// VPN status indicator: WireGuard, Mullvad, OpenVPN.
// Shows the active tunnel name(s); hidden when no VPN is connected.
Item {
    id: root
    property string barMon: ""   // monitor name, for per-monitor icon/font size
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    property bool   _connected: false
    property string _label:     ""

    visible: _connected

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font: VtlConfig.moduleFontFor("vpn")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("vpn")] ?? Colors.boActive
    readonly property bool   _showName: VtlConfig.moduleSetting("vpn", "show_name", true)

    Row {
        id: label
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:           "󰌾"
            color:          root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleIconSizeFor("vpn", root.barMon)
        }
        Text {
            visible:        root._showName && root._label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:           root._label
            color:          root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleFontSizeFor("vpn", root.barMon)
        }
    }

    Process {
        id: pollProc
        command: ["bash", "-c", [
            "vpns=();",
            // WireGuard
            "wg_ifaces=$(wg show interfaces 2>/dev/null);",
            "[[ -n $wg_ifaces ]] && for i in $wg_ifaces; do vpns+=(\"$i\"); done;",
            // Mullvad
            "if command -v mullvad &>/dev/null; then",
            "  mullvad status 2>/dev/null | grep -qi connected && vpns+=(MVD);",
            "fi;",
            // OpenVPN
            "pgrep -x openvpn &>/dev/null && vpns+=(OVPN);",
            // Output
            "if [[ ${#vpns[@]} -gt 0 ]]; then",
            "  echo \"connected:${vpns[*]}\";",
            "else echo \"off\"; fi"
        ].join(" ")]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("connected:")) {
                    root._connected = true
                    root._label     = line.slice(10).trim()
                } else {
                    root._connected = false
                    root._label     = ""
                }
            }
        }
    }

    Timer {
        interval: 6000
        repeat:   true
        running:  true
        triggeredOnStart: true
        onTriggered: {
            pollProc.running = false
            pollProc.running = true
        }
    }
}
