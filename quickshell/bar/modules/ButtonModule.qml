import "../.."
import QtQuick

// A button the user builds: their glyph, their text, their command. Instances are dynamic — the
// module key in bar_modules_m is "button:<n>" and the icon / label / action live under
// module_settings["button:<n>"], exactly like a group instance. ModSlot injects `instanceKey` one
// frame after creation, so every read guards against "".
//
// What a click does: it fires the configured action (the shell's shared vocabulary — a command, an
// app, a Hyprland dispatch, the launcher, the lock …). Leave the action on "None" and the button
// becomes a pure popout button instead: whatever panel it was pointed at grows out of it. One
// button is therefore either a doing button or an opening button, never a coin toss between them.
Item {
    id: root
    property bool   vertical:    false
    property string barMon:      ""
    property string barEdge:     "top"
    property string barGroup:    "start"
    property string instanceKey: ""

    // A glyph alone stays upright on a vertical bar; a glyph with a word beside it has to turn.
    readonly property bool rotateOnVertical: root._label !== ""

    readonly property string _icon:  root.instanceKey !== "" ? ("" + VtlConfig.moduleSetting(root.instanceKey, "icon", "󰐒")) : "󰐒"
    readonly property string _label: root.instanceKey !== "" ? ("" + VtlConfig.moduleSetting(root.instanceKey, "label", "")) : ""
    readonly property string _type:  root.instanceKey !== "" ? ("" + VtlConfig.moduleSetting(root.instanceKey, "action", "command")) : "none"
    readonly property string _value: root.instanceKey !== "" ? ("" + VtlConfig.moduleSetting(root.instanceKey, "value", "")) : ""
    readonly property string _font:  root.instanceKey !== "" ? VtlConfig.moduleFontFor(root.instanceKey) : Style.font
    readonly property color  _col:   root.instanceKey !== "" ? (Colors[VtlConfig.moduleColorName(root.instanceKey)] ?? Colors.fgPrimary)
                                                             : Colors.fgPrimary
    readonly property int    _fs:    root.instanceKey !== "" ? VtlConfig.moduleFontSizeFor(root.instanceKey, root.barMon)
                                                             : VtlConfig.barFontSizeFor(root.barMon)
    readonly property int    _is:    root.instanceKey !== "" ? VtlConfig.moduleIconSizeFor(root.instanceKey, root.barMon)
                                                             : VtlConfig.barIconSizeFor(root.barMon)

    readonly property bool hovered: mouse.containsMouse
    readonly property bool open:    root.instanceKey !== "" && Popouts.isOpen(root.instanceKey, root.barMon)

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: root._icon !== "" && root._label !== "" ? 6 : 0
        Text {
            visible: root._icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:  root._icon
            color: (root.hovered || root.open) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text:  root._label
            color: (root.hovered || root.open) ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.instanceKey === "") return
            if (root._type === "none" || root._type === "") {
                Popouts.openFor(root.instanceKey, root, root.barEdge, root.barGroup, root.barMon)
                return
            }
            Actions.fire({ "type": root._type, "value": root._value }, root.barMon)
        }
    }
}
