import "../.."
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Taskbar as a bar module: a strip of the open windows on this monitor; click focuses. Orientation
// follows the bar edge (row on top/bottom, column on left/right) — it has NO `vertical` property, so
// the bar never rotates it and the icons stay upright. Shares the Hyprwindows live list + the
// hl.dsp.focus dispatch used by the standalone taskbar OSD.
Item {
    id: root

    property var    monitor: null     // HyprlandMonitor, set by Bar.qml (like Workspaces)
    property string barEdge: "top"    // set by Bar.qml → orientation
    property string barMon:  ""
    readonly property bool horiz: barEdge === "top" || barEdge === "bottom"
    readonly property int  monId: monitor?.id ?? -1
    readonly property int  isz:   VtlConfig.barIconSizeFor(barMon)

    readonly property var items: {
        var all = Hyprwindows.windows
        if (root.monId < 0) return all
        return all.filter(function (w) { return w.monitorId === root.monId })
    }

    implicitWidth:  lay.implicitWidth
    implicitHeight: lay.implicitHeight

    Grid {
        id: lay
        rows:    root.horiz ? 1 : 0
        columns: root.horiz ? 0 : 1
        flow:    root.horiz ? Grid.LeftToRight : Grid.TopToBottom
        rowSpacing: 4; columnSpacing: 4

        Repeater {
            model: root.items
            delegate: Rectangle {
                id: it
                required property var modelData
                readonly property int sz: root.isz + 8
                width: sz; height: sz; radius: 6
                color: it.modelData.focused
                     ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.9)
                     : (h.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.22) : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }
                Image {
                    anchors.centerIn: parent
                    width: root.isz; height: root.isz
                    source: Quickshell.iconPath(it.modelData.cls, "application-x-executable")
                    sourceSize.width: 48; sourceSize.height: 48; asynchronous: true
                }
                MouseArea {
                    id: h; anchors.fill: parent; hoverEnabled: true
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + it.modelData.address + "\" })")
                }
            }
        }
    }
}
