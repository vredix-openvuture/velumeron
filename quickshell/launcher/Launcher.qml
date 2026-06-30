import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Native application launcher (replaces the rofi `drun` launcher). A centred search card over a dim
// backdrop; types to filter Quickshell.DesktopEntries, ↑/↓ to move, Enter to launch, Esc / click-out to
// close. One per screen; shows on the focused monitor. Toggled via UiState.launcherOpen (the `launcher`
// IPC / Super+Space).
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool onActiveMonitor: monitor !== null && monitor === Hyprland.focusedMonitor
    readonly property bool isOpen: UiState.launcherOpen
    readonly property bool active: isOpen && onActiveMonitor

    visible: active
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0

    // ── App list + fuzzy filter ──────────────────────────────────────────────────────────────
    readonly property var allApps: {
        var m = DesktopEntries.applications
        var v = (m && m.values !== undefined) ? m.values : (m || [])
        return v.filter(function (a) { return a && !a.noDisplay })
    }
    function _match(a, q) {
        return ((a.name || "").toLowerCase().indexOf(q) >= 0)
            || ((a.genericName || "").toLowerCase().indexOf(q) >= 0)
            || ((a.comment || "").toLowerCase().indexOf(q) >= 0)
            || (("" + (a.keywords || "")).toLowerCase().indexOf(q) >= 0)
    }
    readonly property var filtered: {
        var q = search.text.trim().toLowerCase()
        var arr = root.allApps.slice()
        if (q === "") {
            arr.sort(function (a, b) { return (a.name || "").localeCompare(b.name || "") })
            return arr
        }
        arr = arr.filter(function (a) { return root._match(a, q) })
        arr.sort(function (a, b) {
            var as = (a.name || "").toLowerCase().indexOf(q) === 0 ? 0 : 1
            var bs = (b.name || "").toLowerCase().indexOf(q) === 0 ? 0 : 1
            if (as !== bs) return as - bs
            return (a.name || "").localeCompare(b.name || "")
        })
        return arr
    }
    onFilteredChanged: list.currentIndex = 0

    function launch(i) {
        var a = root.filtered[i]
        if (a) { a.execute(); UiState.launcherOpen = false }
    }

    onIsOpenChanged: if (isOpen) { search.text = ""; list.currentIndex = 0; search.forceActiveFocus() }

    // Dim backdrop — click outside the card closes.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        MouseArea { anchors.fill: parent; onClicked: UiState.launcherOpen = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width:  Math.min(640, root.width  - 80)
        height: Math.min(540, root.height - 120)
        radius: 16
        color:  Colors.bgPrimary
        border.width: 1
        border.color: Colors.boActive
        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Search field.
            Rectangle {
                width: parent.width; height: 46; radius: 11; color: Colors.bgElement
                Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                       text: "󰍉"; color: Colors.fgMuted; font.pixelSize: 18; font.family: "FantasqueSansM Nerd Font" }
                TextInput {
                    id: search
                    anchors { left: parent.left; leftMargin: 46; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: Colors.fgBright; font.pixelSize: 16; font.family: "FantasqueSansM Nerd Font"; clip: true
                    focus: true
                    Keys.onDownPressed:   if (list.currentIndex < root.filtered.length - 1) list.currentIndex++
                    Keys.onUpPressed:     if (list.currentIndex > 0) list.currentIndex--
                    Keys.onReturnPressed: root.launch(list.currentIndex)
                    Keys.onEnterPressed:  root.launch(list.currentIndex)
                    Keys.onEscapePressed: UiState.launcherOpen = false
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: search.text === ""
                           text: "Search apps…"; color: Colors.fgMuted; font: search.font }
                }
            }

            // Results.
            ListView {
                id: list
                width: parent.width; height: parent.height - 56
                clip: true
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 80
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width; height: 52; radius: 9
                    color: index === list.currentIndex ? Colors.bgActive
                         : (rHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.16) : "transparent")
                    Image {
                        id: ic
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 34; height: 34
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        sourceSize.width: 64; sourceSize.height: 64; asynchronous: true
                    }
                    Column {
                        anchors { left: ic.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Text { text: row.modelData.name || ""; color: Colors.fgBright; font.pixelSize: 14
                               font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
                        Text { visible: (row.modelData.comment || "") !== ""; text: row.modelData.comment || ""
                               color: Colors.fgMuted; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
                               elide: Text.ElideRight; width: parent.width }
                    }
                    MouseArea {
                        id: rHov; anchors.fill: parent; hoverEnabled: true
                        onPositionChanged: list.currentIndex = row.index
                        onClicked: { list.currentIndex = row.index; root.launch(row.index) }
                    }
                }
                Text { visible: root.filtered.length === 0; anchors.centerIn: parent
                       text: "No matches"; color: Colors.fgMuted; font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
            }
        }
    }
}
