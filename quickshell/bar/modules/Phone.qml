import "../.."
import QtQuick

// Phone module: the paired device's state at a glance, click for the popout (PhoneMenu). Shows the
// battery of the primary reachable device, so the bar answers "is my phone about to die" without
// being opened. Collapses to zero width when nothing is paired or the daemon isn't there — the
// module is meant to disappear rather than sit in the bar as a dead icon.
Item {
    id: root
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"
    property bool   vertical: false

    readonly property var  dev:  PhoneService.primary
    readonly property bool live: root.dev !== null
    readonly property var  bat:  root.live ? (root.dev.battery ?? ({})) : ({})
    readonly property bool showBattery: VtlConfig.moduleSetting("phone", "show_battery", true)
                                        && root.bat.ok === true && root.bat.charge >= 0

    readonly property string _font: VtlConfig.moduleFontFor("phone")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("phone")] ?? Colors.fgPrimary
    readonly property bool   open:  UiState.flyout === "phone" && UiState.flyoutMon === root.barMon

    implicitWidth:  root.live ? content.implicitWidth : 0
    implicitHeight: content.implicitHeight
    width:  implicitWidth
    height: implicitHeight
    visible: root.live
    Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  PhoneService.icon(root.dev)
            color: (mouse.containsMouse || root.open) ? Colors.fgBright
                 : (root.bat.charge >= 0 && root.bat.charge <= 15 && !root.bat.charging)
                   ? Colors.fgUrgent : root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleIconSizeFor("phone", root.barMon)
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Text {
            visible: root.showBattery
            anchors.verticalCenter: parent.verticalCenter
            text:  (root.bat.charging ? "󰂄" : "") + root.bat.charge + "%"
            color: root.bat.charging ? Style.accent
                 : root.bat.charge <= 15 ? Colors.fgUrgent : root._col
            font.family:    root._font
            font.pixelSize: Math.max(9, VtlConfig.moduleIconSizeFor("phone", root.barMon) - 4)
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            var c = root.mapToItem(null, root.width / 2, root.height / 2)
            UiState.toggleFlyout("phone", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
        }
    }
}
