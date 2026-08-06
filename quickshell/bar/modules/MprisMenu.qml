import "../.."
import QtQuick

// Mpris player flyout: grows out of the bar from the Mpris module on hover (see Mpris.qml +
// UiState.flyout). Content lives in MprisMenuBody, shared with GroupMenu — loaded lazily
// while the panel is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "mpris"
    // Sized from the module's own settings (Settings → Bar → Mpris, or double right-click
    // the module in the bar), as a PERCENTAGE of the monitor — a pixel size that looks
    // right on 1080p is a postage stamp on 4K and overflows a small laptop panel.
    // Flyout publishes this screen's dimensions as sw/sh.
    panelW:   Math.round(root.sw * VtlConfig.moduleSetting("mpris", "menu_width_pct",  16) / 100)
    maxH:     Math.round(root.sh * VtlConfig.moduleSetting("mpris", "menu_height_pct", 52) / 100)

    // The wave lives HERE and not in the body: the body is a Column, and an anchored child
    // inside a Column is not a background — it becomes a layout item and takes the panel's
    // height with it (which is exactly how the popout stopped opening once).
    CavaWave {
        anchors.fill: parent
        z: -1
        // Backdrop, not a visualiser: few wide bars, kept low and dim so the cover, the title
        // and the transport stay the subject of the popout.
        radius: Style.rCard
        bars: 10
        intensity: 0.35
        barGap: 4
        opacity: 0.35
        active: root.isOpen && (body.item?.player?.isPlaying ?? false)
    }

    Loader {
        id: body
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; MprisMenuBody { active: root.isOpen } }
}
