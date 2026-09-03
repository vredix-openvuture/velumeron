import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Invisible surface that reserves space on one screen edge so tiled windows avoid the
// bar. One instance per (screen × edge); only active when the bar occupies that edge.
// Reserves the edge's effective thickness (half on module-less frame edges) plus the
// float gap when floating. mask: Region {} = no input.
PanelWindow {
    id: zone
    required property string edge   // "top" | "bottom" | "left" | "right"
    readonly property string mon: Hyprland.monitorFor(zone.screen)?.name ?? ""

    readonly property bool isActive:   VtlConfig.edgeActiveFor(edge, zone.mon)
    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property int  thickness:  VtlConfig.edgeThicknessFor(edge, zone.mon)
                                       + (VtlConfig.barFloatingFor(zone.mon) ? VtlConfig.barFloatGapFor(zone.mon) : 0)

    // ── A capsule reserves one window gap less ─────────────────────────────────────────────────
    // A normal bar is a strip: it ends where its thickness ends, the window keeps its own outer gap
    // beyond that, and the two read as a panel with air after it. A CAPSULE draws no strip, so the
    // only thing on the edge is the module row — and it is centred in a thickness nobody can see.
    // The screen side of a pill then shows its own inset, and the window side shows that same inset
    // PLUS the compositor's gap. Same module, two different amounts of nothing around it.
    //
    // So the capsule hands one window gap back: the window moves up to exactly where the strip's
    // outer face would have been, and the pill sits in the middle of the space again. Never more
    // than half the thickness, so the reserved area stays a meaningful number for everything else
    // that reads it (the desk takes its margins from it).
    //
    // Only the RESERVATION moves. Nothing that docks onto this bar reads it: a popout's geometry
    // comes from the strip's own inner face (UiState.barInnerFor / VtlConfig.barInsetFor, both
    // derived from the thickness), so the panels grow out of exactly the same line as before.
    readonly property bool capsule: VtlConfig.barChromeless(zone.mon)
    readonly property int  trim:    zone.capsule
                                    ? Math.min(Compositor.windowGap, Math.floor(zone.thickness / 2)) : 0
    readonly property int  reserve: Math.max(0, zone.thickness - zone.trim)

    // The gap is a compositor value the shell otherwise has no use for, so it is fetched on demand
    // — the first capsule edge asks for it, and a config reload re-asks (see Compositor).
    onCapsuleChanged:      if (zone.capsule && zone.isActive) Compositor.requestWindowGap()
    onIsActiveChanged:     if (zone.capsule && zone.isActive) Compositor.requestWindowGap()
    Component.onCompleted: if (zone.capsule && zone.isActive) Compositor.requestWindowGap()

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
