import "../.."
import QtQuick

// The power profile as a bar chip: which one is on, and a click to move to the next. Same backend
// as the dashboard tile and the system-monitor popout (DashState → powermode.sh), so all three
// always agree.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    readonly property bool rotateOnVertical: root._showName

    readonly property var modes: [
        { key: "power-saver", icon: "󰞀", label: "Saver" },
        { key: "balanced",    icon: "󰌪", label: "Balanced" },
        { key: "performance", icon: "󰡴", label: "Performance" }
    ]
    readonly property string current: DashState.profile
    readonly property int idx: {
        for (var i = 0; i < root.modes.length; i++) if (root.modes[i].key === root.current) return i
        return 1
    }

    readonly property bool   _showName: VtlConfig.moduleSetting("powerprofile", "show_name", false)
    readonly property string _font: VtlConfig.moduleFontFor("powerprofile")
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("powerprofile", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("powerprofile", root.barMon)
    // Only the two ENDS are worth colouring: balanced is the resting state and colouring it too
    // would make the chip shout all day.
    readonly property color  _col: root.current === "performance" ? Colors.fgUrgent
                                 : root.current === "power-saver" ? Style.accent
                                 : (Colors[VtlConfig.moduleColorName("powerprofile")] ?? Colors.fgPrimary)

    readonly property bool hovered: mouse.containsMouse

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: root._showName ? 6 : 0
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root.modes[root.idx].icon
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showName
            anchors.verticalCenter: parent.verticalCenter
            text:  root.modes[root.idx].label
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.MiddleButton) {
                Popouts.openFor("powerprofile", root, root.barEdge, root.barGroup, root.barMon)
                return
            }
            DashState.setProfile(root.modes[(root.idx + 1) % root.modes.length].key)
        }
    }
}
