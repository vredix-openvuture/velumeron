import "../.."
import QtQuick

// VPN status indicator: WireGuard, Mullvad, OpenVPN.
// Shows the active tunnel name(s); hidden when no VPN is connected. State comes from the shared
// VpnService singleton (also read by the Network module for its inline lock glyph).
Item {
    id: root
    property string barMon: ""   // monitor name, for per-monitor icon/font size
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    // Turned 90 degrees on a vertical bar (see Bar.qml ModSlot): only with the name beside the glyph.
    readonly property bool rotateOnVertical: root._showName
    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight

    readonly property bool   _connected: VpnService.connected
    readonly property string _label:     VpnService.label

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
}
