import "../.."
import QtQuick

// Group bar module — one icon standing in for several modules (e.g. bluetooth + volume + mpris).
// Clicking opens the shared GroupMenu flyout, a Control-Center-style stack of the members' menu
// bodies. Instances are dynamic: the module key in bar_modules_m is "group:<n>" and doubles as the
// flyout id; members/icon/label live under module_settings["group:<n>"]. ModSlot injects
// `instanceKey` one frame after creation, so every read guards against "".
Item {
    id: root
    property bool   vertical:    false
    // Turned 90 degrees on a vertical bar (see Bar.qml ModSlot): one glyph, and a glyph on its side is just wrong.
    readonly property bool rotateOnVertical: false
    property string barMon:      ""
    property string barEdge:     "top"
    property string barGroup:    "start"
    property string instanceKey: ""      // "group:g1" — injected by ModSlot (Bar.qml)

    implicitWidth:  label.implicitWidth
    implicitHeight: label.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool open:    instanceKey !== "" && UiState.flyout === root.instanceKey
                                    && UiState.flyoutMon === root.barMon

    readonly property string _icon: instanceKey !== "" ? VtlConfig.moduleSetting(instanceKey, "icon", "󰐱") : "󰐱"
    readonly property string _font: instanceKey !== "" ? VtlConfig.moduleFontFor(instanceKey) : Style.font
    readonly property color  _col:  instanceKey !== "" ? (Colors[VtlConfig.moduleColorName(instanceKey)] ?? Style.barDim(root.barMon))
                                                       : Style.barDim(root.barMon)

    Text {
        id: label
        text:  root._icon
        color: (root.hovered || root.open) ? Colors.fgBright : root._col
        font.family:    root._font
        font.pixelSize: root.instanceKey !== "" ? VtlConfig.moduleIconSizeFor(root.instanceKey, root.barMon)
                                                : VtlConfig.barIconSizeFor(root.barMon)
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (root.instanceKey === "") return
            Popouts.openFor(root.instanceKey, root, root.barEdge, root.barGroup, root.barMon)
        }
    }
}
