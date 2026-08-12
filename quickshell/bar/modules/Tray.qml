import "../.."
import QtQuick
import Quickshell.Services.SystemTray

// System-tray module. Two layouts (Settings → Bar → Tray → gear):
//   • inline (default): every tray icon shown in the bar
//   • collapsed: a single glyph; hovering it glides the icons OUT OF THE BAR (TrayGlide), the same
//     pill the other hover modules use — the module itself stays one glyph wide, so revealing the
//     tray no longer pushes the rest of the bar around.
// The icons and their click semantics live in TrayIcons (shared with the glide). Collapses to zero
// width while nothing is in the tray.
Item {
    id: root
    property string barEdge:  "top"   // set by Bar; drives glide direction + which side menus open toward
    property string barMon:   ""      // monitor name, for per-monitor sizing
    property bool   vertical: false

    readonly property bool   _collapse: VtlConfig.moduleSetting("tray", "collapse", false)
    readonly property string _glyph:    VtlConfig.moduleSetting("tray", "icon", "󰀻")
    readonly property string _font:     VtlConfig.moduleFontFor("tray")
    readonly property color  _col:      Colors[VtlConfig.moduleColorName("tray")] ?? Colors.fgPrimary
    readonly property int    _sz:       VtlConfig.moduleIconSizeFor("tray", root.barMon)
    readonly property bool   hasTray:   SystemTray.items.values.length > 0

    readonly property bool _showIcons: root.hasTray && !root._collapse
    readonly property bool _showGlyph: root.hasTray && root._collapse
    // The pill is ours while it shows for this monitor — keeps the glyph lit while it's out.
    readonly property bool _glideOpen: UiState.trayHover && UiState.trayMon === root.barMon

    implicitWidth:  !root.hasTray ? 0 : (root._showIcons ? layout.implicitWidth : glyph.implicitWidth)
    implicitHeight: Math.max(root._sz, root._showIcons ? layout.implicitHeight : glyph.implicitHeight)
    width:  implicitWidth
    height: implicitHeight
    Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.trayAnchorX = c.x; UiState.trayAnchorY = c.y
        UiState.trayEdge = root.barEdge; UiState.trayMon = root.barMon
    }
    // Nothing else can retract the pill once the glyph that opened it is gone — switching the layout
    // back to inline (from the settings panel, while hovering) or dropping the module from the bar
    // would otherwise leave it hanging out for good.
    function _dropGlide() { if (UiState.trayMon === root.barMon) UiState.trayHover = false }
    on_CollapseChanged: root._dropGlide()
    Component.onDestruction: root._dropGlide()

    // Collapsed glyph — hovering it hands the icons to the glide.
    Text {
        id: glyph
        visible: root._showGlyph
        anchors.centerIn: parent
        text:  root._glyph
        color: (glyphHov.containsMouse || root._glideOpen) ? Colors.fgBright : root._col
        font.family:    root._font
        font.pixelSize: root._sz
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

        MouseArea {
            id: glyphHov
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { if (root.hasTray) { root._publishGlide(); UiState.trayHover = true } }
            onExited:  { if (UiState.trayMon === root.barMon) UiState.trayHover = false }
        }
    }

    // Inline icon strip (the default layout).
    TrayIcons {
        id: layout
        visible:  root._showIcons
        anchors.centerIn: parent
        iconSize: root._sz
        barEdge:  root.barEdge
        barMon:   root.barMon
    }
}
