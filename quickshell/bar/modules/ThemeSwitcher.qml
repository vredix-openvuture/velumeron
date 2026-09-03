import "../.."
import QtQuick

// Theme switcher module: one glyph that opens the theme picker, grown out of the bar from this
// module's position. Which SHAPE opens is the user's setting, not this module's business — the
// popout grows here, the gallery takes the screen (Settings -> Style -> Picker); Popouts routes to
// whichever is configured.
Item {
    id: root
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"
    property bool   vertical: false
    // One glyph, so never turned on its side.
    readonly property bool rotateOnVertical: root._label !== ""

    readonly property string _icon:  "" + VtlConfig.moduleSetting("theme", "icon", "󰏘")
    // Off by default: the bar shows what the theme LOOKS like already; the name is for the people
    // who switch often enough to want to read which one is on.
    readonly property bool   _showName: VtlConfig.moduleSetting("theme", "show_name", false)
    readonly property string _label: root._showName ? Theme.name : ""
    readonly property string _font:  VtlConfig.moduleFontFor("theme")
    readonly property color  _col:   Colors[VtlConfig.moduleColorName("theme")] ?? Colors.fgPrimary

    readonly property bool hovered: mouse.containsMouse
    readonly property bool open:    Popouts.isOpen("theme", root.barMon)
                                    || (UiState.themePickerOpen && UiState.themePickerMon === root.barMon)

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: root._label !== "" ? 6 : 0
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root._icon
            color: (root.hovered || root.open) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleIconSizeFor("theme", root.barMon)
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:  root._label
            color: (root.hovered || root.open) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: VtlConfig.moduleFontSizeFor("theme", root.barMon)
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Popouts.openFor("theme", root, root.barEdge, root.barGroup, root.barMon)
    }
}
