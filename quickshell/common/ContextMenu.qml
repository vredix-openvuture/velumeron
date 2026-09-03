import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The shell's context menu — right-click on the empty desktop, or on the bare strip of the bar.
//
// One surface for both, because a context menu is one thing: a short list of what you can do to
// whatever you right-clicked. The KIND decides the list; everything else — where it opens, how it
// closes, how it looks — is the same either way.
//
// A surface of its own rather than something drawn on the desk or the bar, and on the OVERLAY
// layer: the desk lives UNDER the windows and the bar is a strip no menu would fit inside, so a
// menu drawn on either would be clipped by the first thing it touched. Opening at the pointer means
// the click point travels through UiState — the surface that was clicked catches the click, this
// draws the answer.
//
// One per screen; it shows on the monitor the click came from. Esc or a click anywhere outside
// closes it, exactly like the session menu.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool active: UiState.ctxMenuOpen && root.mon !== "" && root.mon === UiState.ctxMenuMon

    // What you right-clicked decides the list, and each list is deliberately short: a right-click
    // menu that needs reading is a menu you stop using.
    readonly property var entries: UiState.ctxMenuKind === "bar" ? root.barEntries : root.deskEntries
    readonly property var deskEntries: [
        { icon: "󰏫", label: "Edit homescreen",  act: "edit" },
        { icon: "󰸉", label: "Change wallpaper", act: "wallpaper" },
        { icon: "󰒓", label: "Settings",         act: "settings" }
    ]
    readonly property var barEntries: [
        { icon: "󰏫", label: "Edit bar",  act: "bar" },
        { icon: "󰒓", label: "Settings",  act: "settings" }
    ]
    property int sel: -1

    // A theme made of type gets a menu made of type (Style.glyphStyle): the marker moves to the
    // hovered row like the launcher's `▸`, and the pictogram column goes away rather than being
    // translated into a character that means nothing.
    readonly property bool typed: Style.typedGlyphs

    function activate(i) {
        var e = root.entries[i]
        if (!e) return
        UiState.ctxMenuOpen = false
        switch (e.act) {
        case "edit":
            UiState.openDashEdit(root.mon, "desk")
            break
        // The bar's own page, not the page list: you right-clicked the bar, so that is the thing
        // you asked to edit.
        case "bar":
            UiState.menuMon = root.mon
            UiState.settingsRequestSection = "bar"
            UiState.openDropdown = "vuture-icon"
            break
        // The FULL-SCREEN picker, not the bar popout the `wallpaper` action opens. Asked for from
        // the desktop, a wallpaper is the whole screen's business — and there is no bar module here
        // for a popout to grow out of.
        case "wallpaper":
            UiState.toggleWallpaperGallery(root.mon)
            break
        // Straight into the settings, not into the dashboard that happens to be the menu's Home:
        // you asked for the settings. In sidebar mode the rail IS the navigation, so the request
        // falls back to Home there (settings/Settings.qml).
        case "settings":
            UiState.menuMon = root.mon
            UiState.settingsRequestSection = "nav"
            UiState.openDropdown = "vuture-icon"
            break
        }
    }

    // A plain fade in place, deliberately NOT the shell's FREE motion. That one springs the scale
    // past 1 and settles back, and from a top-left origin the overshoot reads as the card swinging
    // in from the right — which is wrong twice over: a context menu is not an arrival, it is an
    // answer, and it has to be under the pointer on the first frame you look at it.
    property real reveal: 0
    onActiveChanged: {
        root.reveal = root.active ? 1 : 0
        root.sel = -1
        if (root.active) keyScope.forceActiveFocus()
    }
    Behavior on reveal { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    visible: root.active || root.reveal > 0.01

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-context-menu"
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // -1, like the desk itself: both span the whole monitor, so the click point the desk reports is
    // the click point this draws at. With 0 the bar's reservation would shift the surface out from
    // under those coordinates and the menu would open a bar's thickness away from the pointer.
    WlrLayershell.exclusiveZone: -1

    // No dim. A context menu is a small local answer, not a mode — veiling the screen for three
    // rows would read as something far more important than it is.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: UiState.ctxMenuOpen = false
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        Keys.onEscapePressed: UiState.ctxMenuOpen = false
        Keys.onDownPressed:   root.sel = (root.sel + 1) % root.entries.length
        Keys.onUpPressed:     root.sel = (root.sel - 1 + root.entries.length) % root.entries.length
        Keys.onReturnPressed: root.activate(root.sel)
        Keys.onEnterPressed:  root.activate(root.sel)

        StyledRect {
            id: card
            readonly property real pad: 6
            width:  Math.max(190, rows.implicitWidth + 2 * card.pad)
            height: rows.implicitHeight + 2 * card.pad
            // Grows away from the pointer, and folds back over it at the screen edge — a menu that
            // ran off the screen would be a menu with an unreachable last row.
            x: Math.max(8, Math.min(UiState.ctxMenuX, root.width  - card.width  - 8))
            y: Math.max(8, Math.min(UiState.ctxMenuY, root.height - card.height - 8))
            radius: Style.rCard
            color:  Colors.bgPrimary
            borderWidth: 1
            borderColor: Style.chromeBorder
            opacity: root.reveal
            MouseArea { anchors.fill: parent }          // the card is not the backdrop

            Column {
                id: rows
                anchors { fill: parent; margins: card.pad }
                spacing: 2

                Repeater {
                    model: root.entries
                    delegate: StyledRect {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool seld: root.sel === row.index
                        width:  rows.width
                        height: Style.ctrlH
                        radius: Style.rControl
                        color:  row.seld ? Style.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: Style.popColorMs } }

                        Row {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                // Fixed width in the typed style so the labels stay in one column
                                // whether or not the marker is on this row.
                                width: root.typed ? 10 : implicitWidth
                                text: root.typed ? (row.seld ? "▸" : "") : row.modelData.icon
                                color: row.seld ? Colors.fgBright : Colors.fgPrimary
                                font.pixelSize: root.typed ? 13 : 15
                                font.family: root.typed ? Style.font : Style.iconFont
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.typed ? row.modelData.label.toLowerCase() : row.modelData.label
                                color: row.seld ? Colors.fgBright : Colors.fgPrimary
                                font.pixelSize: 13; font.family: Style.font
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.sel = row.index
                            onExited:  if (root.sel === row.index) root.sel = -1
                            onClicked: root.activate(row.index)
                        }
                    }
                }
            }
        }
    }
}
