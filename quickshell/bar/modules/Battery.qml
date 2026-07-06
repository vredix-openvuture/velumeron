import "../.."
import QtQuick
import Quickshell.Services.UPower

Row {
    id: root
    spacing: 6
    visible: UPower.displayDevice !== null && UPower.displayDevice.isPresent
    property string barMon: ""   // monitor name, for per-monitor icon/font size

    readonly property UPowerDevice dev: UPower.displayDevice
    // UPowerDevice.percentage is a 0.0–1.0 fraction, not 0–100.
    readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging
                                        || dev.state === UPowerDeviceState.FullyCharged
                                        || dev.state === UPowerDeviceState.PendingCharge) : false
    readonly property string _icon: {
        if (root.charging)   return "󰂄"
        if (root.pct >= 90)  return "󰁹"
        if (root.pct >= 70)  return "󰂀"
        if (root.pct >= 50)  return "󰁾"
        if (root.pct >= 30)  return "󰁼"
        if (root.pct >= 15)  return "󰁺"
        return "󰂎"
    }
    // Per-module customization (Settings → Bar → Module → gear). The colour override applies to the
    // normal state; low/critical keep their semantic warning colours. `low_threshold` is the % at
    // which it turns urgent (amber at 2×).
    readonly property string _font: VtlConfig.moduleFontFor("battery")
    readonly property int    _low:  VtlConfig.moduleSetting("battery", "low_threshold", 10)
    readonly property bool   _showPct: VtlConfig.moduleSetting("battery", "show_percent", true)
    readonly property color  _normCol: Colors[VtlConfig.moduleColorName("battery")] ?? Colors.fgMuted
    readonly property color _col: {
        if (root.pct <= root._low     && !root.charging) return Colors.fgUrgent
        if (root.pct <= root._low * 2 && !root.charging) return Colors.color11   // amber
        return root._normCol
    }

    // % text (font size) + battery icon (icon size), centred on one line.
    Text {
        visible:        root._showPct
        anchors.verticalCenter: parent.verticalCenter
        text:           root.pct + "%"
        color:          root._col
        font.family:    root._font
        font.pixelSize: VtlConfig.moduleFontSizeFor("battery", root.barMon)
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text:           root._icon
        color:          root._col
        font.family:    root._font
        font.pixelSize: VtlConfig.moduleIconSizeFor("battery", root.barMon)
    }
}
