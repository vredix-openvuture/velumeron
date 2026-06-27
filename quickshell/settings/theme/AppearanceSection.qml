import "../.."
import QtQuick
import Quickshell

// Combined "Theme" section — mirrors the old GUI's Theme tab (WallpaperPage): a
// Wallpaper picker and a Colours (wallust) page, switched by a segmented control.
// Wallpaper is the default view, exactly like the old GUI.
Item {
    id: root
    property string sub: "wallpaper"   // "wallpaper" | "colors"

    // ── Segmented switcher ────────────────────────────────────────────────────
    Row {
        id: tabs
        anchors { top: parent.top; left: parent.left; topMargin: 16 }
        spacing: 6

        TabBtn { label: "Wallpaper"; key: "wallpaper" }
        TabBtn { label: "Settings";  key: "settings"  }
    }

    // ── Active sub-page ───────────────────────────────────────────────────────
    Loader {
        anchors { top: tabs.bottom; topMargin: 10
                  left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: root.sub === "settings" ? settingsComp : wallpaperComp
    }
    Component { id: wallpaperComp; WallpaperSection      {} }
    Component { id: settingsComp;  ThemeSettingsSection  {} }

    // ── Tab button ────────────────────────────────────────────────────────────
    component TabBtn: Rectangle {
        id: tb
        property string label: ""
        property string key:   ""
        readonly property bool active: root.sub === tb.key

        width: lbl.implicitWidth + 24; height: 28; radius: 8
        color: active ? Colors.bgActive
             : (tbHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                                    : Colors.bgElement)
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
            id: lbl; anchors.centerIn: parent; text: tb.label
            color: tb.active ? Colors.fgBright : Colors.fgPrimary
            font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
        }
        MouseArea { id: tbHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.sub = tb.key }
    }
}
