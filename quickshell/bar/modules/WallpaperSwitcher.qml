import "../.."
import QtQuick
import Quickshell.Hyprland

// Wallpaper switcher module: a single icon that opens the wallpaper quick-menu, grown out of the bar
// from this module's position (like the Volume / Media flyouts). Icon configurable per-module.
Item {
    id: root
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"
    property bool   vertical: false

    readonly property string _icon: VtlConfig.moduleSetting("wallpaper-switcher", "icon", "󰸉")
    readonly property string _font: VtlConfig.moduleFontFor("wallpaper-switcher")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("wallpaper-switcher")] ?? Colors.fgPrimary

    implicitWidth:  glyph.implicitWidth
    implicitHeight: glyph.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    // Publish this module's anchor while it's on the focused monitor, so the Super+Alt+Space keybind can
    // grow the quick-menu from here (like a click), not from a fixed fallback position.
    readonly property bool _onFocused: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name === root.barMon : false
    function _publish() {
        if (!root._onFocused) return
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.wpSwitcherMon = root.barMon; UiState.wpSwitcherEdge = root.barEdge
        UiState.wpSwitcherGroup = root.barGroup; UiState.wpSwitcherX = c.x; UiState.wpSwitcherY = c.y
    }
    on_OnFocusedChanged: _publish()
    Component.onCompleted: _publish()
    Connections { target: Hyprland; function onFocusedMonitorChanged() { root._publish() } }

    function _open() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.toggleFlyout("wallpaper", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
    }

    Text {
        id: glyph
        text:  root._icon
        color: gHov.containsMouse ? Colors.fgBright : root._col
        font.family:    root._font
        font.pixelSize: VtlConfig.moduleIconSizeFor("wallpaper-switcher", root.barMon)
        Behavior on color { ColorAnimation { duration: 100 } }
        MouseArea { id: gHov; anchors.fill: parent; hoverEnabled: true; onClicked: root._open() }
    }
}
