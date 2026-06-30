import "../.."
import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
    id: root
    spacing: 4
    required property HyprlandMonitor monitor

    // Set true by the sidebar Loader (which rotates the whole module ±90°).
    // Used to counter-rotate the active-workspace number so it stays upright.
    property bool vertical: false
    // Which edge we live on — set by the bar. The rotation is -90° on the left edge but
    // +90° on the right, so the upright counter-rotation and the layout order both flip.
    property string barEdge: ""
    readonly property bool onRight: barEdge === "right"

    // The rotation sends one end of the row off-axis; reverse the layout when vertical so
    // workspaces still read low→high from top to bottom — left edge (-90°) needs RightToLeft,
    // right edge (+90°) needs LeftToRight.
    layoutDirection: vertical ? (onRight ? Qt.LeftToRight : Qt.RightToLeft) : Qt.LeftToRight

    // Per-module customization (Settings → Bar → Module → gear). Colour override = the active pill.
    readonly property int    _is:        VtlConfig.moduleIconSizeFor("workspaces", monitor?.name ?? "")
    readonly property int    _fs:        VtlConfig.moduleFontSizeFor("workspaces", monitor?.name ?? "")
    readonly property string _font:      VtlConfig.moduleFontFor("workspaces")
    readonly property color  _activeCol: Colors[VtlConfig.moduleColorName("workspaces")] ?? Colors.boActive
    readonly property int    _max:       VtlConfig.moduleSetting("workspaces", "max_workspaces", 10)
    readonly property bool   _showNum:   VtlConfig.moduleSetting("workspaces", "show_number", true)

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
            readonly property bool   show:    modelData.id > 0 && modelData.id <= root._max
            readonly property bool   hovered: dotHover.containsMouse
            // Only the active workspace gets the full icon size; the rest sit a little smaller.
            readonly property int    dotD:    isActive ? root._is : root._is - 5

            // Persistent workspaces (this monitor) are always shown; plus the active one.
            visible: show && (isMine || isActive)
            width:   visible ? (isActive ? root._is + 14 : dotD) : 0
            height:  root._is

            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Rectangle {
                anchors.centerIn: parent
                width:  parent.width
                height: wsDot.dotD
                radius: height / 2
                color: {
                    if (wsDot.isActive) return root._activeCol
                    if (wsDot.hovered)  return Colors.fgPrimary
                    return Colors.bgElement
                }
                Behavior on color { ColorAnimation { duration: 100 } }

                // Workspace number — only on the (widened) active pill
                Text {
                    anchors.centerIn: parent
                    // Counter the sidebar's rotation so the digit reads upright: +90° to undo the
                    // left edge's -90°, -90° to undo the right edge's +90°.
                    rotation:       root.vertical ? (root.onRight ? -90 : 90) : 0
                    visible:        wsDot.isActive && root._showNum
                    text:           wsDot.wsId
                    color:          Colors.bgPrimary
                    font.pixelSize: root._fs
                    font.bold:      true
                    font.family:    root._font
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
