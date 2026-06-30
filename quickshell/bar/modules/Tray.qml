import "../.."
import QtQuick
import Quickshell.Services.SystemTray

// System-tray module: a single icon (glyph configurable in Settings → Bar → Module → gear); on hover
// the system-tray items glide out of the bar (TrayGlide). Replaces the inline tray that used to live
// on the notification module.
Item {
    id: root
    property string barEdge:  "top"   // set by Bar; drives the hover-glide direction
    property string barMon:   ""      // monitor name, for per-monitor sizing
    property bool   vertical: false

    readonly property string _icon: VtlConfig.moduleSetting("tray", "icon", "󰀻")
    readonly property string _font: VtlConfig.moduleFontFor("tray")
    readonly property color  _col:  Colors[VtlConfig.moduleColorName("tray")] ?? Colors.fgPrimary
    readonly property bool   hasTray: SystemTray.items.values.length > 0

    implicitWidth:  glyph.implicitWidth
    implicitHeight: glyph.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    function publishTrayGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.trayAnchorX = c.x; UiState.trayAnchorY = c.y
        UiState.trayEdge = root.barEdge; UiState.trayMon = root.barMon
    }

    Text {
        id: glyph
        text:  root._icon
        color: trayHov.containsMouse ? Colors.fgBright : root._col
        font.family:    root._font
        font.pixelSize: VtlConfig.moduleIconSizeFor("tray", root.barMon)
        Behavior on color { ColorAnimation { duration: 100 } }

        MouseArea {
            id: trayHov
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { if (root.hasTray) { root.publishTrayGlide(); UiState.trayHover = true } }
            onExited:  { if (UiState.trayMon === root.barMon) UiState.trayHover = false }
        }
    }
}
