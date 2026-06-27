import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// Invisible surface that reserves space on one screen edge so tiled windows avoid the
// bar. One instance per (screen × edge); only active when the bar occupies that edge.
// Reserves the edge's effective thickness (half on module-less frame edges) plus the
// float gap when floating. mask: Region {} = no input.
PanelWindow {
    id: zone
    required property string edge   // "top" | "bottom" | "left" | "right"

    readonly property bool isActive:   VtlConfig.edgeActive(edge)
    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property int  reserve:    VtlConfig.edgeThickness(edge)
                                       + (VtlConfig.barFloating ? VtlConfig.barFloatGap : 0)

    visible:             isActive
    color:               "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    mask: Region {}

    anchors {
        top:    edge !== "bottom"
        bottom: edge !== "top"
        left:   edge !== "right"
        right:  edge !== "left"
    }
    implicitWidth:  horizontal ? 0 : reserve
    implicitHeight: horizontal ? reserve : 0
    exclusiveZone:  reserve
}
