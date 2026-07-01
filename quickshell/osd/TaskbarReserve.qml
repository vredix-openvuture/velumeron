import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Invisible space-reserving surface for the taskbar's "like bar" layer: it reserves an exclusive zone
// on the taskbar's docked edge so windows are pushed away (instead of the taskbar being drawn over
// them). Active only when the taskbar is enabled, layer = reserve, always-visible, and this monitor
// actually shows windows. The visual taskbar (osd/Taskbar.qml) stays a separate overlay. One per screen.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon:   monitor?.name ?? ""
    readonly property int    monId: monitor?.id   ?? -1

    readonly property var    _pp:  VtlConfig.taskbarPosition.split("-")
    readonly property string edge: (_pp[0] !== "center") ? _pp[0] : (_pp[1] ?? "bottom")   // top|bottom|left|right
    // Cross-axis thickness the taskbar occupies (icon + item/card padding + float margin).
    readonly property int    thk:  VtlConfig.taskbarIconSize + 24 + (VtlConfig.taskbarStyle === "float" ? VtlConfig.taskbarMargin : 0) + 2

    readonly property bool hasWins: {
        var all = Hyprwindows.windows
        var scope = VtlConfig.taskbarScope
        if (scope === "all" || root.monId < 0) return all.length > 0
        if (scope === "workspace") { var w = root.monitor?.activeWorkspace?.id ?? -2; return all.some(function (x) { return x.workspace === w }) }
        return all.some(function (x) { return x.monitorId === root.monId })
    }
    readonly property bool on: VtlConfig.taskbarEnabledFor(root.mon) && VtlConfig.taskbarReserve && root.hasWins

    color: "transparent"
    mask: Region {}                 // invisible + no input
    WlrLayershell.layer: WlrLayer.Bottom
    // Anchor to the docked edge (+ the two perpendicular edges to span it fully).
    anchors {
        top:    root.edge === "top"    || root.edge === "left" || root.edge === "right"
        bottom: root.edge === "bottom" || root.edge === "left" || root.edge === "right"
        left:   root.edge === "left"   || root.edge === "top"  || root.edge === "bottom"
        right:  root.edge === "right"  || root.edge === "top"  || root.edge === "bottom"
    }
    implicitWidth:  (root.edge === "left" || root.edge === "right") ? root.thk : 0
    implicitHeight: (root.edge === "top"  || root.edge === "bottom") ? root.thk : 0
    exclusiveZone:  root.on ? root.thk : 0
}
