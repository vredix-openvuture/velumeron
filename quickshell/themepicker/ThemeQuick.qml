import ".."
import QtQuick

// The theme picker as a PANEL on the bar — the second shape of the same picker the full screen
// shows (themepicker/ThemeGallery.qml). Settings → Style → Picker → Style switches between them,
// and every way of asking for the picker (Super+Ctrl+Space, `ipc call theme toggle`, a hot corner)
// goes through UiState.openThemePicker(), so the two shapes cannot disagree about which one opens.
//
// A panel is for the swap you already decided on — back to mirobo, over to Console — where the
// gallery is for browsing. Same tiles either way (common/ThemeTile.qml), only smaller.
Flyout {
    id: root
    flyoutId: "theme"

    readonly property int _cols:    Math.max(1, VtlConfig.themePickerCols)
    readonly property int _cardW:   Math.max(120, VtlConfig.themePickerPreview)
    readonly property int _captionH: 40
    readonly property int _cardH:   Math.round((_cardW - 10) * 9 / 16) + _captionH
    panelW: root._cols * root._cardW + (root._cols - 1) * 8 + 28
    maxH:   560

    readonly property var entries: Theme.available.filter(function (t) { return !t.wip })
    // A theme is a FOLDER you drop in, so the list is re-scanned every time the panel opens —
    // there is no registry that would have told us about a new one.
    onIsOpenChanged: if (root.isOpen) Theme.refresh()

    // The picture on the desk right now, so a card is drawn against YOUR wallpaper. The feed is
    // reused rather than re-implemented and is never asked to list a folder, so it costs nothing.
    WallpaperFeed { id: feed }
    readonly property string deskWallpaper: {
        var p = feed.currentFor(root.mon)
        return feed.isVideo(p) ? "" : p
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        Text {
            width: parent.width
            text: "Wearing " + Theme.name
            color: Colors.fgMuted
            font.family: Style.font; font.pixelSize: Style.fsSub; font.bold: true
            elide: Text.ElideRight
        }

        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: root.entries
                delegate: ThemeTile {
                    id: tile
                    required property var modelData
                    width:  root._cardW
                    height: root._cardH
                    captionH: root._captionH
                    theme:     tile.modelData
                    monitor:   root.mon
                    wallpaper: root.deskWallpaper
                    // One click wears here, unlike the gallery: a panel has no cursor to centre
                    // first, so a second click would only be a tax on a decision already made.
                    onPicked: { Theme.wear(tile.modelData.id); UiState.flyout = "" }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.entries.length === 0
            text: "No themes found."
            color: Colors.fgMuted
            font.family: Style.font; font.pixelSize: Style.fsSub
        }
    }
}
