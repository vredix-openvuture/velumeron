import ".."
import QtQuick

// One theme, drawn as a shrunken desktop rather than as a name in a list.
//
// It draws with THAT THEME's tokens, not the shell's current ones: every card looked identical
// apart from where the bar sat, because they all read the active Style. The tile resolves the
// theme's own table (Theme.tableFor → Style.resolveTable) — its radii, its fills, its borders —
// against the LIVE wallust palette. So the shape on the card is the shape you will get, and the
// colours are still yours, which is the one thing a theme never decides.
//
// Two places show themes and they must not drift apart: Settings → Style picks one from a grid, and
// the theme picker (Super+Ctrl+Space) offers the same themes full-screen or on the bar. Same tile,
// same context, same badges — the caller only says how big it is and what a click means.
Item {
    id: tile

    // The list entry from theme-list.py (Theme.available).
    property var theme: ({})
    // The picture on the desk right now. A theme is judged against your wallpaper, not a stock one.
    property string wallpaper: ""
    // Are we wearing this one? Overridable so a preview can pretend otherwise.
    property bool active: Theme.themeId === (tile.theme.id || "")
    // Parked: shipped but not built out. Dimmed, badged, and inert until it is finished.
    readonly property bool wip: !!tile.theme.wip
    // The two caption lines under the picture. Zero drops them entirely (the popout draws its own).
    // Everything in the caption is derived from this one number: the same tile carries a 250 px
    // card in the settings grid and a 1000 px one in the full-screen picker, and a caption fixed at
    // 12 px reads as a label on the first and as a whisper on the second.
    property int captionH: 46
    readonly property int capName: Math.max(11, Math.round(tile.captionH * 0.27))
    readonly property int capSub:  Math.max(9,  Math.round(tile.captionH * 0.22))
    readonly property int capPad:  Math.max(7,  Math.round(tile.captionH * 0.20))
    // Hover/selection chrome. The picker drives it from the CURSOR instead of the pointer, so it
    // is a property rather than a MouseArea read.
    property bool highlighted: tileHov.containsMouse
    // Which screen the card is drawn for. Bars are per-monitor, so a card that ignored this would
    // show the global strip on a machine whose screens each carry their own.
    property string monitor: ""

    // ── The bar on the card: YOUR placement, the THEME's shape ──────────────────────────────────
    // The split is the whole point, and getting it wrong is what made the two cards identical.
    //
    //   WHERE the strip is — mode, edge, thickness, module spacing — is yours. The bar keys travel
    //   with the theme (Theme.themeScopedKeys), so your saved arrangement for THIS theme is what
    //   wearing it will actually put on screen: per-monitor block first, then the arrangement,
    //   then the package, then the shell's defaults.
    //
    //   WHAT it looks like — corner of the strip, corner of a module, whether a module has a
    //   ground at all — is the THEME's, always. It is read from the package and from the theme's
    //   own token table, never from your desk. Both shipped themes have the same bar arrangement
    //   on this machine, and taking the shape from it drew mirobo and Console as one picture: same
    //   strip, same rounded chips, twice. A card that cannot tell a round desktop from a hard one
    //   is not a preview.
    readonly property var barCfg: {
        var pkg  = tile.theme || ({})
        var mine = Theme.arrangementFor(pkg.id || "") || ({})
        var blk  = ({})
        if (mine.bar_per_monitor === true && mine.bar_monitors && tile.monitor !== "")
            blk = mine.bar_monitors[tile.monitor] || ({})
        // Placement: yours first.
        function mineFirst(k, d) {
            if (blk[k]  !== undefined && blk[k]  !== null) return blk[k]
            if (mine[k] !== undefined && mine[k] !== null) return mine[k]
            if (pkg[k]  !== undefined && pkg[k]  !== null) return pkg[k]
            return d
        }
        // Shape: the theme's only.
        function themeOnly(k, d) { return (pkg[k] !== undefined && pkg[k] !== null) ? pkg[k] : d }
        return {
            "mode":          mineFirst("bar_mode", "frame"),
            "position":      mineFirst("bar_position", "top"),
            "thickness":     mineFirst("bar_thickness", 36),
            "moduleSpacing": mineFirst("bar_module_spacing", 10),
            "radius":        themeOnly("bar_inner_radius", 0),
            "moduleBg":      themeOnly("bar_module_bg", "module"),
            "moduleOpacity": themeOnly("bar_module_bg_opacity", 0.22)
        }
    }

    signal picked()

    // The theme's own look, resolved against the live palette.
    readonly property var look: Style.resolveTable(Theme.tableFor(tile.theme.base || "flat",
                                                                 tile.theme.tokens || ({})))

    // A screen's proportions plus the caption. Fixed at 150 the card stretched into a letterbox the
    // moment the panel got wide, and a desktop drawn in a letterbox stops reading as a desktop.
    implicitHeight: Math.round((tile.width - 10) * 9 / 16) + tile.captionH
    height: tile.implicitHeight

    StyledRect {
        anchors.fill: parent
        radius: Style.rControl
        color: tile.active ? Style.tint(Style.accent, 0.14)
                           : (!tile.wip && tile.highlighted ? Style.controlHover : Style.controlFill)
        borderWidth: (tile.active || tile.highlighted) ? 2 : Style.controlBorderW
        borderColor: tile.active ? Style.accent
                                 : (tile.highlighted ? Style.tint(Style.accent, 0.7) : Style.controlBorderColor)
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
    }

    // ── The preview: a window onto the desktop this theme makes ─────────────────────────────────
    // Not a drawing of one. Three attempts at a drawn card all failed the same way — the shell can
    // only vary a corner radius and a typeface for a theme it does not know, so a terminal report
    // and a card desktop came out as the same picture twice. ThemePreview shows instead: the
    // picture actually on your desk, the theme's own backdrop over it, the bar its arrangement asks
    // for, and its real dashboard component where it brings one.
    //
    // What those components are handed: the shared context (live palette — colours belong to the
    // wallpaper, not to the theme) with the THEME's font and resolved tokens written over it, plus
    // enough plausible facts to draw with. Fixed figures on purpose: a picker card is not a
    // monitor, and wiring one to the live services would start them per card.
    readonly property var cardCtx: {
        var c = Style.themeContext()
        c.font   = (tile.theme.ui_font || "") !== "" ? tile.theme.ui_font : Style.font
        c.tokens = tile.look
        c.name   = tile.theme.name || tile.theme.id || ""
        c.worn   = tile.active
        c.surfaces = (tile.theme.components || []).length
        c.insets = ({ "top": 0, "bottom": 0, "left": 0, "right": 0 })
        c.settings = ({})
        c.host = "velumeron"; c.kernel = "7.1.8"; c.uptime = "1d 23h"; c.user = "vredix"
        c.load = ({ "cpu": 6, "mem": 38, "disk": 81 })
        c.battery = ({ "present": false })
        c.media = ({ "title": "", "playing": false })
        c.notifications = ({ "count": 0, "dnd": false })
        c.workspaces = [{ "slot": 1, "focused": true }]
        c.state = ({ "volume": 0.7, "brightness": 1.0, "profile": "balanced" })
        c.actions = ({})
        return c
    }

    ThemePreview {
        id: mock
        opacity: tile.wip ? 0.4 : 1
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 5 }
        height: parent.height - tile.captionH
        theme:     tile.theme
        look:      tile.look
        bar:       tile.barCfg
        wallpaper: tile.wallpaper
        ctx:       tile.cardCtx
    }

    // What the theme replaces, as a fact rather than as a picture that cannot hold it: a theme
    // taking over fourteen surfaces is a different desktop, and no thumbnail says that.
    Text {
        visible: tile.captionH > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: tile.capPad + 2; rightMargin: tile.capPad + 2
                  bottomMargin: Math.round(tile.captionH * 0.52) }
        text: ((tile.theme.components || []).length > 0
               ? ((tile.theme.components || []).length + " own surfaces")
               : "shipped surfaces")
              + "  ·  " + ((tile.theme.ui_font || "") !== "" ? tile.theme.ui_font : "shell font")
        color: Colors.fgMuted
        font.pixelSize: tile.capSub; font.family: Style.font
        elide: Text.ElideRight
    }

    // "SOON" badge on the parked themes.
    Rectangle {
        visible: tile.wip
        anchors { top: mock.top; right: mock.right; topMargin: 4; rightMargin: 4 }
        width: soonLbl.implicitWidth + 12; height: 17; radius: 8
        color: Style.tint(Colors.bgActive, 0.9)
        Text { id: soonLbl; anchors.centerIn: parent; text: "SOON"; color: Colors.bgPrimary
               font.pixelSize: 9; font.bold: true; font.family: Style.font; font.letterSpacing: 0.5 }
    }

    Row {
        visible: tile.captionH > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: tile.capPad + 2; rightMargin: tile.capPad + 2
                  bottomMargin: Math.round(tile.captionH * 0.15) }
        spacing: 6
        Text {
            width: parent.width - (tile.active ? 30 : 0)
            text: (tile.theme.name || "") + (tile.theme.source === "user" ? "  · yours" : "")
            color: tile.wip ? Colors.fgMuted : (tile.active ? Colors.fgBright : Colors.fgPrimary)
            font.pixelSize: tile.capName; font.bold: tile.active; font.family: Style.font
            elide: Text.ElideRight
        }
        Text { visible: tile.active; text: "󰄬"; color: Style.accent
               font.pixelSize: tile.capName + 1; font.family: Style.font }
    }

    MouseArea {
        id: tileHov
        anchors.fill: parent
        hoverEnabled: !tile.wip
        cursorShape: tile.wip ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: if (!tile.wip) tile.picked()
    }
}
