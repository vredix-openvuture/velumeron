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

    // Publish this module's anchor while it's on the focused monitor: it is the ONE place the
    // quick-menu grows from, however it gets opened (UiState.openWallpaperQuick) — clicking here,
    // Super+Alt+Space, a hot corner or a dashboard tile all land in the same spot.
    readonly property bool _onFocused: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name === root.barMon : false
    function _publish() { if (root._onFocused) root._publishNow() }
    function _publishNow() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.wpSwitcherMon = root.barMon; UiState.wpSwitcherEdge = root.barEdge
        UiState.wpSwitcherGroup = root.barGroup; UiState.wpSwitcherX = c.x; UiState.wpSwitcherY = c.y
    }
    on_OnFocusedChanged: _publish()
    Component.onCompleted: _publish()
    Connections { target: Hyprland; function onFocusedMonitorChanged() { root._publish() } }
    // Drop the claim when the module goes away (removed from the bar, monitor unplugged) — a stale
    // one would keep growing the menu out of a spot where nothing sits any more.
    Component.onDestruction: if (UiState.wpSwitcherMon === root.barMon) UiState.wpSwitcherMon = ""

    function _open() {
        // Unconditionally, not _publish(): clicking a module on a monitor that doesn't hold focus
        // must still grow the menu out of THIS module, not out of the fallback position.
        root._publishNow()
        UiState.openWallpaperQuick(root.barMon, Screen.width, Screen.height)
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
