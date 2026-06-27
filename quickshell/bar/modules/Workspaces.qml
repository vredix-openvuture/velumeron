import "../.."
import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    id: root
    spacing: 4
    required property HyprlandMonitor monitor

    // Set true by the sidebar Loader (which rotates the whole module -90°).
    // Used to counter-rotate the active-workspace number so it stays upright.
    property bool vertical: false

    // The sidebar's -90° rotation sends the row's tail end to the top. Reverse the
    // layout when vertical so workspaces still read low→high from top to bottom.
    layoutDirection: vertical ? Qt.RightToLeft : Qt.LeftToRight

    Repeater {
        model: Hyprland.workspaces
        delegate: Item {
            id: wsDot
            required property HyprlandWorkspace modelData

            // Captured once at creation — no closure capture bug, no Bound pragma needed
            readonly property var    ipc:     modelData.lastIpcObject
            readonly property int    wsId:    modelData.id
            // Resolve the owning monitor via lastIpcObject too: empty *persistent*
            // workspaces can report a null modelData.monitor, which would hide them.
            readonly property string wsMon:   modelData.monitor?.name ?? ipc?.monitor ?? ""
            readonly property bool   isMine:  wsMon === root.monitor?.name
            readonly property bool   isActive: root.monitor?.activeWorkspace?.id === modelData.id
            readonly property bool   show:    modelData.id > 0 && modelData.id <= 10
            readonly property bool   hovered: dotHover.containsMouse
            // Only the active workspace gets the full icon size; the rest sit a little smaller.
            readonly property int    dotD:    isActive ? VtlConfig.barIconSize : VtlConfig.barIconSize - 5

            // Persistent workspaces (this monitor) are always shown; plus the active one.
            visible: show && (isMine || isActive)
            width:   visible ? (isActive ? VtlConfig.barIconSize + 12 : dotD) : 0
            height:  VtlConfig.barIconSize + 10

            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.centerIn: parent
                width:  parent.width
                height: wsDot.dotD
                radius: height / 2
                color: {
                    if (wsDot.isActive) return Colors.boActive
                    if (wsDot.hovered)  return Colors.fgPrimary
                    return Colors.bgElement
                }
                Behavior on color { ColorAnimation { duration: 100 } }

                // Workspace number — only on the (widened) active pill
                Text {
                    anchors.centerIn: parent
                    // Counter the sidebar's -90° so the digit reads upright when vertical
                    rotation:       root.vertical ? 90 : 0
                    visible:        wsDot.isActive
                    text:           wsDot.wsId
                    color:          Colors.bgPrimary
                    font.pixelSize: 14
                    font.bold:      true
                    font.family:    "FantasqueSansM Nerd Font"
                }
            }

            MouseArea {
                id: dotHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    // hypr.lua wraps dispatch as: return hl.dispatch(<expr>)
                    // so we must pass valid Lua — hl.dsp.focus({workspace=N})
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsDot.wsId + " })")
                }
                onWheel: event => {
                    var dir = event.angleDelta.y > 0 ? "m-1" : "m+1"
                    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + dir + "\" })")
                }
            }
        }
    }
}
