import "../.."
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// System-tray module. Two layouts (Settings → Bar → Tray → gear):
//   • inline (default): every tray icon shown in the bar
//   • collapsed: a single glyph; hovering it reveals the icons inline (they expand out of the glyph)
// Each icon: left-click → activate() (or menu, for menu-only items), middle → secondaryActivate(),
// right-click → the item's context menu (QsMenuAnchor), wheel → scroll(). Collapses to zero width
// while nothing is in the tray.
Item {
    id: root
    property string barEdge:  "top"   // set by Bar; drives which side the context menu opens toward
    property string barMon:   ""      // monitor name, for per-monitor sizing
    property bool   vertical: false

    readonly property bool   _collapse: VtlConfig.moduleSetting("tray", "collapse", false)
    readonly property string _glyph:    VtlConfig.moduleSetting("tray", "icon", "󰀻")
    readonly property string _font:     VtlConfig.moduleFontFor("tray")
    readonly property color  _col:      Colors[VtlConfig.moduleColorName("tray")] ?? Colors.fgPrimary
    readonly property int    _sz:       VtlConfig.moduleIconSizeFor("tray", root.barMon)
    readonly property bool   hasTray:   SystemTray.items.values.length > 0

    // Collapsed-mode hover-reveal state.
    property bool _expanded: false
    readonly property bool _showIcons: root.hasTray && (!root._collapse || root._expanded)
    readonly property bool _showGlyph: root.hasTray && root._collapse && !root._expanded

    implicitWidth:  !root.hasTray ? 0 : (root._showIcons ? layout.implicitWidth : glyph.implicitWidth)
    implicitHeight: Math.max(root._sz, root._showIcons ? layout.implicitHeight : glyph.implicitHeight)
    width:  implicitWidth
    height: implicitHeight
    Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Publish the item's menu handle + the icon's screen anchor; the per-screen TrayMenu overlay
    // renders it with the shell's own styling (see UiState.openTrayMenu / TrayMenu.qml).
    function openMenu(item, cell) {
        var c = cell.mapToItem(null, cell.width / 2, cell.height / 2)
        UiState.openTrayMenu(item.menu, c.x, c.y, root.barEdge, root.barMon)
    }

    // Collapsed-mode hover reveal, with a close grace so the glyph→icons swap doesn't flicker.
    HoverHandler { id: modHover; enabled: root._collapse }
    Connections {
        target: modHover
        enabled: root._collapse
        function onHoveredChanged() {
            if (modHover.hovered) { collapseTimer.stop(); root._expanded = true }
            else collapseTimer.restart()
        }
    }
    Timer { id: collapseTimer; interval: 240; onTriggered: root._expanded = false }

    // Collapsed glyph.
    Text {
        id: glyph
        visible: root._showGlyph
        anchors.centerIn: parent
        text:  root._glyph
        color: modHover.hovered ? Colors.fgBright : root._col
        font.family:    root._font
        font.pixelSize: root._sz
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    // Inline icon strip (always shown when not collapsed; revealed on hover when collapsed).
    Row {
        id: layout
        visible: root._showIcons
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: cell
                required property SystemTrayItem modelData
                width:  root._sz + 2
                height: root._sz + 2

                IconImage {
                    anchors.centerIn: parent
                    width:  root._sz; height: root._sz; implicitSize: root._sz
                    source: cell.modelData.icon
                    opacity: cellHov.containsMouse ? 1.0 : 0.85
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }

                MouseArea {
                    id: cellHov
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: e => {
                        if (e.button === Qt.LeftButton) {
                            if (cell.modelData.onlyMenu) root.openMenu(cell.modelData, cell)
                            else                         cell.modelData.activate()
                        } else if (e.button === Qt.MiddleButton) {
                            cell.modelData.secondaryActivate()
                        } else {
                            if (cell.modelData.hasMenu) root.openMenu(cell.modelData, cell)
                            else                        cell.modelData.secondaryActivate()
                        }
                    }
                    onWheel: e => cell.modelData.scroll(e.angleDelta.y, false)
                }
            }
        }
    }
}
