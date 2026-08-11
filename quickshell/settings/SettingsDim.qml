import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The backdrop behind the floating settings window.
//
// It is a surface of its OWN, and that is the whole point of the file. Hyprland blurs every layer
// whose alpha clears ignore_alpha (0.1, globally), so a dim painted inside the settings window turns
// the entire screen frosted — the same trap the clipboard history, the window switcher and the
// window-tag overlay each had to climb out of, and their fix is this one: a namespace with blur off.
// The settings panel keeps its own frost, because it stays on its own surface.
//
// Top, not Overlay: the settings panel is on Overlay, so this is guaranteed to sit under it without
// depending on which surface happened to map first. That puts it over the bar as well, which is
// right — a modal that leaves the bar lit is not modal.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool onMenuMonitor: root.mon !== "" && root.mon === UiState.menuMon
    readonly property bool shown: UiState.menuFloating && root.onMenuMonitor

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "velumeron-settings-dim"
    WlrLayershell.exclusiveZone: -1
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    // Never take input: the settings window already grabs the screen and dismisses on a click
    // outside its panel. Two grabs would just argue about which one saw the click.
    mask: Region {}
    visible: root.shown || shade.opacity > 0.001

    Rectangle {
        id: shade
        anchors.fill: parent
        // Derived from the scheme's own ground rather than pure black, so a warm wallust run dims
        // warm instead of punching a grey hole through it.
        color:   Style.tint(Qt.darker(Colors.bgPrimary, 1.8), 0.55)
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
}
