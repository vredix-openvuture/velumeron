import "../.."
import QtQuick

// A chip whose whole job is to open one of the shell's panels. The calendar and the clipboard
// history had no way onto the bar at all — one lived behind the clock, the other behind a keybind —
// and both are things people reach for often enough to want a button.
//
// Deliberately generic: `mkey` is the catalogue key, the panel it opens is that key's entry in
// Popouts.defaults, and the glyph is a per-module setting. Anything else that turns out to be "an
// icon that opens a panel" becomes one more line in Bar.componentFor rather than one more file.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"
    property string mkey:       ""      // catalogue key — set by Bar.componentFor
    property string defaultIcon: "󰐱"
    property string label:       ""     // optional text beside the glyph (module setting wins)

    readonly property string _icon:  "" + VtlConfig.moduleSetting(root.mkey, "icon", root.defaultIcon)
    readonly property bool   _showLabel: VtlConfig.moduleSetting(root.mkey, "show_label", false)
    readonly property string _label: root._showLabel ? root.label : ""
    readonly property string _font:  root.mkey === "" ? Style.font : VtlConfig.moduleFontFor(root.mkey)
    readonly property color  _col:   root.mkey === "" ? Colors.fgPrimary
                                                      : (Colors[VtlConfig.moduleColorName(root.mkey)] ?? Colors.fgPrimary)

    readonly property bool rotateOnVertical: root._label !== ""
    readonly property bool hovered: mouse.containsMouse
    readonly property bool open:    root.mkey !== "" && Popouts.isOpen(root.mkey, root.barMon)

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
            font.pixelSize: root.mkey === "" ? VtlConfig.barIconSizeFor(root.barMon)
                                             : VtlConfig.moduleIconSizeFor(root.mkey, root.barMon)
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:  root._label
            color: (root.hovered || root.open) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root.mkey === "" ? VtlConfig.barFontSizeFor(root.barMon)
                                             : VtlConfig.moduleFontSizeFor(root.mkey, root.barMon)
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.mkey !== "") Popouts.openFor(root.mkey, root, root.barEdge, root.barGroup, root.barMon)
    }
}
