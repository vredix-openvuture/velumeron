import "../.."
import QtQuick

// Phone module: the paired device's state at a glance, click for the popout (PhoneMenu).
//
// It stays in the bar whether or not anything is connected — the answer "no phone right now" is
// worth as much as the battery reading, and a module that vanishes takes its own click target with
// it, so there'd be no way back to the popout to find out why. Connected reads as the lit icon with
// a filled dot and the battery; disconnected as a muted icon with a hollow one.
Item {
    id: root
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"
    property bool   vertical: false

    // The device the module speaks for: the reachable one, else whatever is paired, so the icon
    // still reflects "phone" vs "tablet" while it's away.
    readonly property var dev: PhoneService.primary
                               ?? (PhoneService.devices.length > 0 ? PhoneService.devices[0] : null)
    readonly property bool connected: PhoneService.hasDevices
    readonly property var  bat: (root.connected && PhoneService.primary)
                                ? (PhoneService.primary.battery ?? ({})) : ({})
    readonly property bool showBattery: VtlConfig.moduleSetting("phone", "show_battery", true)
                                        && root.connected && root.bat.ok === true && root.bat.charge >= 0
    readonly property bool low: root.showBattery && root.bat.charge <= 15 && !root.bat.charging

    readonly property string _font: VtlConfig.moduleFontFor("phone")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("phone")] ?? Colors.fgPrimary
    readonly property bool   open:  UiState.flyout === "phone" && UiState.flyoutMon === root.barMon

    readonly property int _sz: VtlConfig.moduleIconSizeFor("phone", root.barMon)

    implicitWidth:  content.implicitWidth
    implicitHeight: content.implicitHeight
    width:  implicitWidth
    height: implicitHeight
    Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 5

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width:  glyph.implicitWidth
            height: glyph.implicitHeight

            Text {
                id: glyph
                text:  PhoneService.icon(root.dev)
                color: root.low ? Colors.fgUrgent
                     : (mouse.containsMouse || root.open) ? Colors.fgBright
                     : root.connected ? root._col : Colors.fgMuted
                font.family:    root._font
                font.pixelSize: root._sz
                opacity: root.connected ? 1.0 : 0.75
                Behavior on color   { ColorAnimation  { duration: 120 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            // Link state, so the two states differ by more than a shade of grey: filled while a
            // device is reachable, a hollow ring while none is.
            Rectangle {
                anchors { right: parent.right; top: parent.top; rightMargin: -1; topMargin: -1 }
                width: 6; height: 6; radius: 3
                color:        root.connected ? Style.accent : "transparent"
                border.width: root.connected ? 0 : 1
                border.color: Colors.fgMuted
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }

        Text {
            visible: root.showBattery
            anchors.verticalCenter: parent.verticalCenter
            text:  (root.bat.charging ? "󰂄" : "") + root.bat.charge + "%"
            color: root.bat.charging ? Style.accent : root.low ? Colors.fgUrgent : root._col
            font.family:    root._font
            font.pixelSize: Math.max(9, root._sz - 4)
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
