pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// The SNI icon strip with its full interaction set — left-click → activate() (or the menu, for
// menu-only items), middle → secondaryActivate(), right-click → the item's context menu, wheel →
// scroll(). Lives on its own because it is rendered in TWO places: inline in the bar (Tray.qml) and
// inside the hover glide when the module is collapsed to a single glyph (TrayGlide.qml). Keeping one
// copy is the point — the click semantics are the fiddly part and must not drift between them.
//
// A Grid rather than a Row because of the VERTICAL bar: the strip has to stack there, and it cannot
// get there by being rotated — rotating the strip rotates every tray icon with it, and a sideways
// application icon is not a smaller version of the upright one. So the module never rotates (Tray's
// rotateOnVertical is false) and the icons re-flow into a column instead.
Grid {
    id: strip
    property int    iconSize: 16
    property string barEdge:  "top"     // which side the context menu opens toward
    property string barMon:   ""
    property bool   column:   false     // stack instead of running along
    signal menuOpened()                 // the glide listens, to stay up while the menu covers it

    rows:    strip.column ? 0 : 1
    columns: strip.column ? 1 : 0
    flow:    strip.column ? Grid.TopToBottom : Grid.LeftToRight
    rowSpacing: 2; columnSpacing: 2

    // Publish the item's menu handle + the icon's anchor; the per-screen TrayMenu overlay renders it
    // with the shell's own styling. Both hosts are full-width surfaces, so scene x == screen x.
    function openMenu(item, cell) {
        var c = cell.mapToItem(null, cell.width / 2, cell.height / 2)
        UiState.openTrayMenu(item.menu, c.x, c.y, strip.barEdge, strip.barMon)
        strip.menuOpened()
    }

    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: cell
            required property SystemTrayItem modelData
            width:  strip.iconSize + 2
            height: strip.iconSize + 2

            IconImage {
                anchors.centerIn: parent
                width:  strip.iconSize; height: strip.iconSize; implicitSize: strip.iconSize
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
                        if (cell.modelData.onlyMenu) strip.openMenu(cell.modelData, cell)
                        else                         cell.modelData.activate()
                    } else if (e.button === Qt.MiddleButton) {
                        cell.modelData.secondaryActivate()
                    } else {
                        if (cell.modelData.hasMenu) strip.openMenu(cell.modelData, cell)
                        else                        cell.modelData.secondaryActivate()
                    }
                }
                onWheel: e => cell.modelData.scroll(e.angleDelta.y, false)
            }
        }
    }
}
