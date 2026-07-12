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

    // Forensics for the cold-start mis-association (ws1 pinned on the wrong bar,
    // 2026-07-11): silent unless the live monitor OBJECT disagrees with the raw
    // IPC json — the signature of the stale event-graph state.
    Timer {
        interval: 8000; running: true
        onTriggered: {
            var vs = Hyprland.workspaces.values
            for (var i = 0; i < vs.length; i++) {
                var om = vs[i].monitor?.name ?? "", im = vs[i].lastIpcObject?.monitor ?? ""
                if (om !== "" && im !== "" && om !== im)
                    console.warn("[workspaces] ws", vs[i].id, "monitor object says", om,
                                 "but IPC json says", im, "— stale Hyprland event graph")
            }
        }
    }

    Repeater {
        model: Hyprland.workspaces
        delegate: Item {
            id: wsDot
            required property HyprlandWorkspace modelData

            readonly property int    wsId:    modelData.id
            // Owning monitor: PREFER the raw IPC json — it is re-fetched by the
            // startup refreshWorkspaces() calls (shell.qml) and carries proper
            // notifies, while the linked monitor OBJECT can latch a stale
            // association when the shell cold-starts mid-event-stream (that
            // painted ws1 as a foreign active pill on the other bar). The object
            // name stays as fallback for empty persistent workspaces whose json
            // hasn't arrived yet.
            readonly property string wsMon:   modelData.lastIpcObject?.monitor ?? modelData.monitor?.name ?? ""
            readonly property bool   isMine:  wsMon === root.monitor?.name
            // Active pill = the monitor's own active workspace. READ IT FROM THE IPC JSON, never the
            // linked objects: when a secondary monitor gains focus, Quickshell.Hyprland latches its
            // monitor→activeWorkspace pointer to the wrong workspace (seen 2026-07-11: DP-3 focused
            // on ws6, but monitor.activeWorkspace.id said 1 and ws6.active flipped false — so no pill
            // lit at all), and a refreshMonitors() only re-fills lastIpcObject, not that object link.
            // lastIpcObject.activeWorkspace.id stays correct through it. Matching the monitor's one
            // active id (gated by isMine) also means exactly one pill per monitor — never two.
            readonly property int    monActiveId: root.monitor?.lastIpcObject?.activeWorkspace?.id
                                                  ?? root.monitor?.activeWorkspace?.id ?? -1
            readonly property bool   isActive: isMine && monActiveId === modelData.id
            readonly property bool   show:    modelData.id > 0 && modelData.id <= root._max
            readonly property bool   hovered: dotHover.containsMouse
            // Only the active workspace gets the full icon size; the rest sit a little smaller.
            readonly property int    dotD:    isActive ? root._is : root._is - 5

            // Persistent workspaces (this monitor) are always shown; a foreign workspace
            // that becomes active here flips its monitor association first, so isMine
            // already covers it.
            visible: show && isMine
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
