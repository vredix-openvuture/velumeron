import "../.."
import QtQuick
import Quickshell.Hyprland

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar
    property string barMon: ""      // monitor name, for per-monitor font size
    property string activeSubmap: ""
    visible: activeSubmap !== "" && activeSubmap !== "normal"
    implicitWidth:  visible ? label.implicitWidth + 12 : 0
    implicitHeight: label.implicitHeight + 4
    width:  implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        color:  Colors.bgActive
        radius: 4
    }

    Text {
        id: label
        anchors.centerIn: parent
        text:  root.activeSubmap
        color: Colors[VtlConfig.moduleColorName("submap")] ?? Colors.fgBright
        font.family:    VtlConfig.moduleFontFor("submap")
        font.pixelSize: VtlConfig.moduleFontSizeFor("submap", root.barMon)
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") {
                root.activeSubmap = event.data
            }
        }
    }
}
