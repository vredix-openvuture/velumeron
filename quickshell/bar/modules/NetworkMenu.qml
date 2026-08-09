import "../.."
import QtQuick

// Network flyout: grows out of the bar from the Network module (like the player / bluetooth
// menus). Content lives in NetworkMenuBody, shared with GroupMenu — loaded lazily while the
// panel is visible (per-screen instances of every menu add up in RAM otherwise).
Flyout {
    id: root
    flyoutId: "network"
    // Percent of the screen, not a pixel count. Wider than it was because four readings across a
    // 330px panel gave each of them 72px, and "126 kB/s" does not fit in 72px — it read "126…".
    panelW: Math.max(340, Math.round(root.sw * VtlConfig.moduleSetting("network", "menu_width_pct", 18) / 100))
    maxH:   Math.round(root.sh * VtlConfig.moduleSetting("network", "menu_height_pct", 50) / 100)

    Loader {
        active: root.visible
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: bodyComp
    }
    Component { id: bodyComp; NetworkMenuBody { active: root.isOpen } }
}
