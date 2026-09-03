import ".."
import QtQuick
import Quickshell
import Quickshell.Wayland

// The theme picker as a FULL-SCREEN row of desktops — the shape Super+Ctrl+Space opens by default.
// Its other shape is a panel on the bar (themepicker/ThemeQuick.qml); which one opens is a setting
// (Settings → Style → Picker), not a separate feature, exactly like the wallpaper picker.
//
// Why the screen and not a panel: a theme card is a WINDOW onto a whole desktop — the picture on
// your desk, that theme's backdrop over it, its bar, its real dashboard component. At panel size
// those become grey mush, and picking a desktop off mush is picking a name from a list with extra
// steps. So the cards are miniatures of this monitor, as big as they will go.
//
// It is a plain centred row rather than the wallpaper gallery's tilted coverflow, and that is
// deliberate: a wallpaper card is one picture that survives being turned away into depth, while a
// theme card is a live miniature desktop with two lines of caption under it. Tilted, the captions
// are the first thing to go — and the caption is half of what tells the themes apart.
//
// One instance per screen; only the one whose monitor was asked for opens (UiState.themePickerMon).
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.themePickerOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.themePickerMon

    // What is installed, minus the parked ones (`wip` in their theme.json) — the settings grid
    // hides those too, and a picker on a keybind is the last place to offer a theme that is not
    // finished. Themes are listed by theme-list.py; `refresh()` re-scans, because a theme is a
    // FOLDER you drop in and the shell has no other way to notice a new one.
    readonly property var entries: Theme.available.filter(function (t) { return !t.wip })
    property int cursor: 0
    readonly property var sel: root.entries[root.cursor] ?? ({})

    function indexOfCurrent() {
        for (var i = 0; i < root.entries.length; i++)
            if (root.entries[i].id === Theme.themeId) return i
        return 0
    }
    function move(d) {
        var n = root.entries.length; if (n === 0) return
        root.cursor = ((root.cursor + d) % n + n) % n
    }
    function close() { UiState.themePickerOpen = false }
    // Wearing is Theme.wear()'s whole job — id, arrangement, the compositor's window frames. The
    // picker only says which one, and then gets out of the way: wearing covers the screen with the
    // splash curtain while ~80 settings are rewritten, and watching that through a dimmed picker is
    // watching nothing.
    function wear(id) {
        if (!id) return
        Theme.wear("" + id)
        root.close()
    }

    // ── Motion: FREE (Style.qml) — it belongs to the screen, not to the bar ─────────────────────
    property real reveal: 0
    onActiveChanged: {
        reveal = active ? 1 : 0
        if (active) {
            Theme.refresh()
            root.cursor = root.indexOfCurrent()
            kbd.forceActiveFocus()
        }
    }
    // A theme dropped in while the picker is up must not move the cursor off what it is on.
    onEntriesChanged: if (root.active) root.cursor = Math.max(0, Math.min(root.entries.length - 1, root.cursor))
    Behavior on reveal {
        id: revealB
        // Direction from the Behavior's own targetValue, not the open flag: the flag flips in the
        // same signal that starts the animation, so reading it would latch the OLD spring.
        SpringAnimation {
            spring:  Style.springFor(revealB.targetValue > 0.5)
            damping: Style.dampingFor(revealB.targetValue > 0.5)
            epsilon: 0.003
        }
    }
    visible: active || root.reveal > 0.01

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-theme-picker"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // -1, not 0: at 0 the compositor hands this surface a rect with the bars already cut off, and a
    // picker meant to fill the screen would sit inside a frame of untouched desktop.
    WlrLayershell.exclusiveZone: -1
    // Blur is requested by PROTOCOL (ext-background-effect-v1), not by a compositor rule, so
    // nothing here depends on Hyprland — where the protocol is absent the surface is simply
    // translucent and unfrosted.
    BackgroundEffect.blurRegion: (root.active && VtlConfig.themePickerBlur) ? galBlur : null
    Region { id: galBlur; x: 0; y: 0; width: root.width; height: root.height }

    // The picture on the desk right now, so a theme is judged against YOUR wallpaper. The feed is
    // reused rather than re-implemented — its file watch is the same one the wallpaper surfaces
    // read — and it is never asked to list a folder, so it costs nothing here.
    WallpaperFeed { id: feed }
    readonly property string deskWallpaper: {
        var p = feed.currentFor(root.mon)
        return feed.isVideo(p) ? "" : p        // a video frame is not a still to draw a card on
    }

    // ── Card geometry ───────────────────────────────────────────────────────────────────────────
    // A card is a miniature of THIS monitor, so its height is a share of the screen and its width
    // follows from the aspect. Percent rather than pixels, because "42" means the same thing on a
    // 1080p laptop and a 4K desk screen.
    readonly property real cardAspect: (root.screen && root.screen.height > 0)
                                       ? (root.screen.width / root.screen.height) : (16 / 9)
    // The caption grows with the card (ThemeTile derives its type from this): at gallery size a
    // 46 px strip carries 12 px type across a 1000 px card, which reads as a footnote on a poster.
    readonly property int captionH: Math.max(46, Math.min(76, Math.round(root.cardH * 0.11)))
    readonly property int cardH: Math.max(120, Math.round(root.height
                                 * Math.max(15, Math.min(70, VtlConfig.themePickerSize)) / 100))
    readonly property int cardW: Math.max(160, Math.round(root.cardH * root.cardAspect))

    // ── Backdrop ────────────────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Style.popDimColor(root.reveal)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // Is a theme drawing the picker instead of the row? Asked once; everything in here that has to
    // step aside reads this one property. Console will bring its own — a wardrobe of desktops is a
    // very mirobo idea, and a terminal wants a listing with one preview beside it.
    readonly property bool themed: Theme.hasComponent("themepicker")

    ThemeSurface {
        id: themedPicker
        anchors.fill: parent
        visible: root.themed
        surface: root.themed ? "themepicker" : ""
        ctx: root.pickerContext
        opacity: Style.popFade(root.reveal)
        z: 4
    }
    // The cursor is handed over SEPARATELY from `ctx`: it moves on every key press, and a context
    // object rebuilt that often hands the picker a new `entries` array each time, which resets the
    // view drawing it. Same rule the wallpaper picker learned the hard way.
    Binding {
        target:   themedPicker.item
        property: "cursor"
        value:    root.cursor
        when:     themedPicker.item !== null
    }

    // What a theme's own picker is handed: the catalogue as plain rows, which one is worn, and the
    // three things it can do. It cannot see Theme or UiState — that is the contract, not an
    // oversight — so wearing and closing come through here.
    readonly property var pickerContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        c.monitor = root.mon
        c.wallpaper = root.deskWallpaper
        c.current = Theme.themeId
        c.entries = root.entries
        c.actions = {
            "wear":   function (id) { root.wear("" + id) },
            "close":  function ()   { root.close() },
            "select": function (i)  { root.cursor = Math.max(0, Math.min(root.entries.length - 1, i)) }
        }
        return c
    }

    // The keyboard is the SHELL's, always — a theme never owns input, so this scope stays alive
    // even when a theme draws the picker; only the shell's own visuals step aside.
    FocusScope {
        id: kbd
        anchors.fill: parent
        focus: true
        // NEVER `visible: false` when a theme draws instead: an invisible item cannot hold focus,
        // and the keyboard is the shell's job whoever is painting. The shell's own visuals step
        // aside inside (`chrome`), the scope itself stays.
        opacity: root.themed ? 0 : Style.popFade(root.reveal)
        enabled: !root.themed
        scale:   root.themed ? 1 : Style.popScale(root.reveal)

        Keys.onEscapePressed: root.close()
        Keys.onLeftPressed:   root.move(-1)
        Keys.onRightPressed:  root.move(1)
        Keys.onUpPressed:     root.move(-1)
        Keys.onDownPressed:   root.move(1)
        Keys.onReturnPressed: root.wear(root.sel.id)
        Keys.onEnterPressed:  root.wear(root.sel.id)
        Keys.onPressed: e => {
            // hjkl beside the arrows: the picker is a list you walk, and half the people who will
            // ever open it never take their hands off the home row.
            if      (e.key === Qt.Key_H || e.key === Qt.Key_K) { root.move(-1); e.accepted = true }
            else if (e.key === Qt.Key_L || e.key === Qt.Key_J) { root.move(1);  e.accepted = true }
            else if (e.key === Qt.Key_Home) { root.cursor = 0; e.accepted = true }
            else if (e.key === Qt.Key_End)  { root.cursor = Math.max(0, root.entries.length - 1); e.accepted = true }
        }

        // ── Head ────────────────────────────────────────────────────────────────────────────────
        Column {
            anchors { top: parent.top; topMargin: Math.round(root.height * 0.06)
                      horizontalCenter: parent.horizontalCenter }
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Themes"; color: Colors.fgBright
                font.family: Style.font; font.pixelSize: 24; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.entries.length + " installed  ·  wearing " + Theme.name
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: Style.fsSub
            }
        }

        // ── The row ─────────────────────────────────────────────────────────────────────────────
        // A ListView rather than a Row in a Flickable: it recycles, and every card here is a live
        // miniature desktop (a theme's real backdrop and dashboard components are loaded into it),
        // so the ones off screen are worth not building at all.
        ListView {
            id: row
            // Two themes shipped today, and a strip that always centres the CURSOR pushes the
            // other one half off the screen for no reason. So: while the whole set fits, the row
            // is exactly as wide as the set and sits in the middle of the screen with nothing to
            // scroll; past that it becomes the usual strip that keeps the cursor centred.
            readonly property int gap: 18
            readonly property int need: root.entries.length * root.cardW
                                        + Math.max(0, root.entries.length - 1) * row.gap
            readonly property bool fits: row.need <= root.width - 80
            width: row.fits ? row.need : root.width
            anchors { horizontalCenter: parent.horizontalCenter
                      verticalCenter: parent.verticalCenter
                      verticalCenterOffset: -Math.round(root.height * 0.02) }
            height: root.cardH + root.captionH + 24
            orientation: ListView.Horizontal
            model: root.entries
            spacing: row.gap
            clip: false
            currentIndex: root.cursor
            highlightRangeMode: row.fits ? ListView.NoHighlightRange : ListView.StrictlyEnforceRange
            preferredHighlightBegin: Math.round((root.width - root.cardW) / 2)
            preferredHighlightEnd:   Math.round((root.width - root.cardW) / 2) + root.cardW
            highlightMoveDuration: Math.round(240 * Style.motionSlow)
            // The pointer picks a card by clicking it (the tile's own signal below); dragging the
            // strip would fight the StrictlyEnforceRange snap for no gain.
            interactive: false

            delegate: ThemeTile {
                id: tile
                required property var modelData
                required property int index
                width:  root.cardW
                height: root.cardH + root.captionH
                captionH: root.captionH
                theme:     tile.modelData
                monitor:   root.mon
                wallpaper: root.deskWallpaper
                // The frame follows the CURSOR: it is what Return will wear. Which theme is
                // actually ON is a different question and keeps its own mark (the tick in the
                // caption), so the two never say the same thing twice.
                highlighted: tile.index === root.cursor
                // Off-cursor cards step back rather than tilt away, so their captions stay
                // readable — that caption is half of what tells two desktops apart.
                scale:   tile.index === root.cursor ? 1.0 : 0.9
                opacity: tile.index === root.cursor ? 1.0 : 0.72
                Behavior on scale   { NumberAnimation { duration: Style.ctrlMs } }
                Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
                // First click centres, second wears — the same rule the wallpaper coverflow uses.
                // One click can otherwise mean two different things depending on how well you aimed.
                onPicked: {
                    if (tile.index !== root.cursor) root.cursor = tile.index
                    else                            root.wear(tile.modelData.id)
                }
            }
        }

        // ── Caption: the theme the cursor is on ─────────────────────────────────────────────────
        // Under the CARDS, not at the bottom of the screen: the caption names what the cursor is
        // on, and a screen's worth of air between the two makes it read as a page footer instead.
        Column {
            anchors { top: row.bottom; topMargin: Math.round(root.height * 0.035)
                      horizontalCenter: parent.horizontalCenter }
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.sel.name || "") + (root.sel.source === "user" ? "  ·  yours" : "")
                color: Colors.fgBright
                font.family: Style.font; font.pixelSize: 20; font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: (root.sel.author || "") !== ""
                text: "by " + (root.sel.author || "")
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: Style.fsSub
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.sel.id === Theme.themeId
                      ? "Wearing this one — Enter puts its arrangement back"
                      : "Enter or click again wears it  ·  Esc closes"
                color: Colors.fgPrimary
                font.family: Style.font; font.pixelSize: Style.fsSub
            }
        }

        // Nothing installed is a state worth naming rather than an empty screen.
        Text {
            anchors.centerIn: parent
            visible: root.entries.length === 0
            text: "No themes found in quickshell/themes or ~/.config/velumeron/themes."
            color: Colors.fgMuted
            font.family: Style.font; font.pixelSize: Style.fsLabel
        }
    }
}
