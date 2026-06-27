import "../.."
import QtQuick
import Quickshell.Services.UPower

Row {
    id: root
    spacing: 4
    visible: UPower.displayDevice !== null && UPower.displayDevice.isPresent

    readonly property UPowerDevice dev: UPower.displayDevice
    readonly property int pct: dev ? Math.round(dev.percentage) : 0
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging
                                        || dev.state === UPowerDeviceState.FullyCharged
                                        || dev.state === UPowerDeviceState.PendingCharge) : false

    Text {
        text:  {
            var icon
            if (root.charging) {
                icon = "󰂄"
            } else if (root.pct >= 90) {
                icon = "󰁹"
            } else if (root.pct >= 70) {
                icon = "󰂀"
            } else if (root.pct >= 50) {
                icon = "󰁾"
            } else if (root.pct >= 30) {
                icon = "󰁼"
            } else if (root.pct >= 15) {
                icon = "󰁺"
            } else {
                icon = "󰂎"
            }
            return root.pct + "% " + icon
        }
        color: {
            if (root.pct <= 10 && !root.charging) return Colors.fgUrgent
            if (root.pct <= 20 && !root.charging) return Colors.color11   // amber
            return Colors.fgMuted
        }
        font.family:    "FantasqueSansM Nerd Font"
        font.pointSize: 10
    }
}
