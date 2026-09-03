import "../.."
import QtQuick

// A window onto the desktop a theme makes — not a diagram of one.
//
// Three tries at this card failed the same way: anything the shell DRAWS for a theme can only vary
// a corner radius and a typeface, so a terminal report and a card desktop came out as the same
// picture twice. The way out is to stop drawing and start SHOWING: the picture actually on the
// desk, the theme's own backdrop over it, the bar its arrangement asks for, and — where the theme
// brings one — its real dashboard component, the same file the menu loads.
//
// ── The stage is a FIXED logical desktop, not a multiple of the card ────────────────────────────
// It used to be "twice the card, drawn at real pixel size, then halved", which quietly made the
// picture depend on how big the card was: a 36 px bar is 7 % of a 250 px settings card and 1.8 % of
// a 1000 px picker card, so the same component showed a tight crop in one place and a wallpaper
// with a speck of shell in it in the other. Measured on both, and it is exactly why the full-screen
// picker read as "wallpaper with an empty panel on it".
//
// So the stage is `logicalW` wide whatever the card is, the card's own aspect gives its height, and
// ONE scale factor maps it onto the card. Small card and large card now show the same picture at
// two sizes — which is the only way a preview can be trusted at either.
//
// `logicalW` is a crop, not a desktop: it holds the bar, its modules and the head of the menu
// panel, which is where a theme's signature actually lives. A whole 2560 px desktop shrunk into a
// card is a hairline bar and grey mush.
Item {
    id: prev
    clip: true

    // The list entry from theme-list.py: arrangement, tokens, and the URLs of everything it brings.
    property var    theme:     ({})
    // The resolved token table for THIS theme (not the one being worn).
    property var    look:      ({})
    // The picture on the desk right now. A theme is chosen against your wallpaper, not against a
    // stock one, so the card shows yours.
    property string wallpaper: ""
    // What a theme's own component is handed. Built by the caller so every card shares one object.
    property var    ctx:       ({})
    // How wide the crop is in logical pixels. Everything on the stage is drawn at its real size in
    // these units, so this one number decides how much desktop a card shows — at any card size.
    property int    logicalW:  640
    // The bar as it will ACTUALLY be drawn when you wear this theme, resolved by the caller
    // (ThemeTile): your saved arrangement for that theme first, the package's second, the shell's
    // defaults last. The card used to read the package alone, so a theme that ships no bar keys —
    // which is both shipped themes, because the bar is yours and travels with the theme — was
    // previewed as a top frame with round module pills whatever your bar actually looked like.
    //   { mode, position, thickness, radius, moduleBg, moduleRadius, moduleOpacity, moduleSpacing }
    property var    bar:       ({})

    readonly property var    urls:  prev.theme.urls || ({})
    readonly property string font:  (prev.theme.ui_font || "") !== "" ? prev.theme.ui_font : Style.font
    readonly property string mode:  prev.bar.mode || "frame"
    readonly property string pos:   prev.bar.position || "top"
    readonly property bool   float_: prev.mode === "float"
    readonly property bool   noBar:  prev.mode === "none"
    readonly property bool   vert:   prev.pos === "left" || prev.pos === "right"
    // The pill BEHIND a module ("none" | "group" | "module"), its radius and its strength — the
    // three keys that decide whether a strip reads as round or as square.
    readonly property bool   pills: (prev.bar.moduleBg || "none") !== "none"
    // A module's corner is the THEME's, out of its own token table — not a settings key. It is the
    // difference you see from across the room: mirobo's controls are round, Console's are cut
    // square, and a card that draws both with the same chip is not showing you a theme.
    readonly property int    chipR: Math.max(0, Math.min(Math.round(prev.barT * 0.33),
                                                         prev.look.rModule ?? prev.look.rControl ?? 10))
    readonly property real   chipO: prev.bar.moduleOpacity ?? 0.22
    readonly property int    modGap: Math.max(4, prev.bar.moduleSpacing ?? 10)
    readonly property int    barT:  prev.bar.thickness || 36
    readonly property int    barR:  prev.bar.radius ?? 0

    readonly property real   scaleF: prev.width > 0 ? prev.width / prev.logicalW : 1

    function url(k) { return (prev.urls[k] || "") !== "" ? "file://" + prev.urls[k] : "" }

    Item {
        id: stage
        width:  prev.logicalW
        height: prev.scaleF > 0 ? Math.round(prev.height / prev.scaleF) : prev.height
        transform: Scale { xScale: prev.scaleF; yScale: prev.scaleF }

        // ── The desk ────────────────────────────────────────────────────────────────────────────
        Rectangle { anchors.fill: parent; color: Colors.bgPrimary }
        Image {
            anchors.fill: parent
            visible: prev.wallpaper !== ""
            source: prev.wallpaper !== "" ? "file://" + prev.wallpaper : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 640
            asynchronous: true
            cache: true
        }

        // The theme's own backdrop, if it brings one — the layer between your wallpaper and your
        // windows. Console pushes the picture down to a trace here and puts its brackets on it,
        // and that is half of what its desktop looks like.
        Loader {
            anchors.fill: parent
            active: prev.url("backdrop") !== ""
            source: prev.url("backdrop")
            onLoaded: item.ctx = Qt.binding(function () { return prev.ctx })
        }

        // ── The bar ─────────────────────────────────────────────────────────────────────────────
        // Drawn, because no theme brings a bar component: what it carries is yours, and only its
        // shape belongs to the theme. Real thickness, real corner, real MODULES — a strip of blank
        // pills with three dots at each end read as a macOS title bar rather than as our bar, and
        // round pills on a theme whose modules are square is the one mistake you see across the
        // room. Every treatment here comes from `prev.bar`, which is the arrangement that will
        // actually apply.
        //
        // ONE strip, on `position`, in the direction that position implies — a left bar is drawn
        // down the left, not as a top strip with the label "left". A frame with several edges is
        // drawn as its first edge: the crop is a corner of a desktop, and four strips around a card
        // this size is a picture frame.
        // Explicit geometry, NOT anchors. The card is built before the menu knows which monitor it
        // is on, so the bar starts horizontal (the global keys) and turns vertical a frame later
        // when the per-monitor block arrives — and an anchor set to `undefined` on that switch does
        // not let go: the strip stayed anchored left AND right AND top AND bottom and swallowed the
        // whole card. Four numbers cannot get stuck.
        Rectangle {
            id: bar
            visible: !prev.noBar
            readonly property int m: prev.float_ ? 10 : 0
            x: prev.pos === "right"  ? stage.width  - bar.width  - bar.m : bar.m
            y: prev.pos === "bottom" ? stage.height - bar.height - bar.m : bar.m
            width:  prev.noBar ? 0 : (prev.vert ? prev.barT : stage.width  - 2 * bar.m)
            height: prev.noBar ? 0 : (prev.vert ? stage.height - 2 * bar.m : prev.barT)
            radius: prev.float_ ? prev.barR : Math.round(prev.barR * 0.5)
            color: Style.tint(Colors.bgElement, 0.92)
            border.width: prev.look.cardBorderW || 0
            border.color: prev.look.cardBorderColor || "transparent"

            readonly property int chipH: Math.max(16, Math.round(prev.barT * 0.66))
            readonly property int fs:    Math.max(9,  Math.round(prev.barT * 0.34))

            // A module: the pill behind it (only where the arrangement asks for one) plus what it
            // says. Same three treatments the real strip has — none, group, module.
            component Mod: Rectangle {
                id: mod
                property string glyph: ""
                property string label: ""
                property bool   sel:   false
                width:  Math.max(bar.chipH, modRow.implicitWidth + (prev.pills ? 16 : 2))
                height: bar.chipH
                radius: prev.chipR
                // Against bgActive, not bgElement: the strip is already an bgElement tint, so a
                // module ground mixed from the same colour was invisible on the card and the
                // theme's module SHAPE — the round-versus-square that the card exists to show —
                // came down to the one selected chip.
                color: mod.sel ? (prev.look.selFill || Colors.bgActive)
                               : (prev.pills ? Style.tint(Colors.bgActive,
                                                          Math.min(0.85, 0.35 + prev.chipO))
                                             : "transparent")
                // The selected chip wears the theme's selection outline; every other chip wears its
                // module outline. Console draws its cells as bordered squares rather than as filled
                // pills, and a card that only ever fills would show that as "the same pill,
                // squarer" — which is not what is on the desk.
                border.width: mod.sel ? (prev.look.selBorderW || 0)
                                      : (prev.pills ? (prev.look.moduleBorderW || 0) : 0)
                border.color: mod.sel ? (prev.look.selBorderColor || "transparent")
                                      : (prev.look.moduleBorderColor || "transparent")
                Row {
                    id: modRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        visible: mod.glyph !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: mod.glyph
                        color: mod.sel ? (prev.look.selText || Colors.fgBright) : Colors.fgPrimary
                        font.family: Style.iconFont; font.pixelSize: bar.fs + 1
                    }
                    Text {
                        visible: mod.label !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: mod.label
                        color: mod.sel ? (prev.look.selText || Colors.fgBright) : Colors.fgPrimary
                        font.family: prev.font; font.pixelSize: bar.fs
                    }
                }
            }

            // The three groups the real strip has. A Grid rather than a Row/Column pair, so one
            // declaration serves a horizontal and a vertical bar.
            Grid {
                id: grpStart
                x: prev.vert ? Math.round((bar.width - width) / 2) : 12
                y: prev.vert ? 12 : Math.round((bar.height - height) / 2)
                columns: prev.vert ? 1 : 99
                spacing: prev.modGap
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment:   Grid.AlignVCenter
                Mod { glyph: ""; label: "1"; sel: true }
                Mod { glyph: ""; label: "2" }
                Mod { glyph: ""; label: "3" }
                Mod { glyph: "󰕾"; label: prev.vert ? "" : "72%" }
            }
            Mod {
                id: clock
                x: Math.round((bar.width  - clock.width)  / 2)
                y: Math.round((bar.height - clock.height) / 2)
                label: prev.vert ? "12" : "12:34"
            }
            Grid {
                id: grpEnd
                x: prev.vert ? Math.round((bar.width - width) / 2) : (bar.width - width - 12)
                y: prev.vert ? (bar.height - height - 12) : Math.round((bar.height - height) / 2)
                columns: prev.vert ? 1 : 99
                spacing: prev.modGap
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment:   Grid.AlignVCenter
                Mod { glyph: "󰤨" }
                Mod { glyph: "󰂚" }
                Mod { glyph: "󰁹" }
            }
        }

        // ── The menu, grown out of the bar ──────────────────────────────────────────────────────
        // The panel is where a theme differs most, so the crop is aimed at it. Its chrome is the
        // theme's own — corner, border, fill — and what is INSIDE it is the theme's own dashboard
        // component when it brings one. That is the whole point: Console's card shows Console's
        // actual dashboard, loaded from the same file the menu loads.
        Rectangle {
            id: panel
            // The menu grows out of the bar's inner face, whichever edge that is: it takes the rect
            // the strip leaves, inset. Numbers again, for the same reason the bar uses them.
            readonly property real freeL: (!prev.noBar && prev.pos === "left")   ? bar.x + bar.width  : 0
            readonly property real freeR: (!prev.noBar && prev.pos === "right")  ? bar.x              : stage.width
            readonly property real freeT: (!prev.noBar && prev.pos === "top")    ? bar.y + bar.height : 0
            readonly property real freeB: (!prev.noBar && prev.pos === "bottom") ? bar.y              : stage.height
            x: panel.freeL + 12
            y: panel.freeT + 10
            width:  Math.max(80, Math.min(panel.freeR - panel.freeL - 24, 470))
            height: Math.max(60, panel.freeB - panel.freeT - 22)
            radius: prev.look.rCard || 0
            // TWO layers, because the real menu is two: the panel's own ground, and the theme's
            // card fill on top of it. A card fill is usually translucent — drawn straight onto the
            // wallpaper it turns the panel into glass and the tiles into panes floating over a
            // landscape, which is not what the menu looks like on any theme.
            color:  Colors.bgPrimary
            border.width: prev.look.cardBorderW || 0
            border.color: prev.look.cardBorderColor || "transparent"
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: prev.look.cardFill || Colors.bgSecondary
            }

            Loader {
                anchors { fill: parent; margins: prev.look.cardPad || 14 }
                active: prev.url("dashboard") !== ""
                source: prev.url("dashboard")
                onLoaded: item.ctx = Qt.binding(function () { return prev.ctx })
            }

            // No dashboard of its own → the shipped raster, in this theme's tile shape. Drawn
            // rather than loaded: the real grid is wired to your modules and to live services, and
            // a picker card has no business starting those. Each tile carries what a real one
            // carries — a glyph, a name, a figure — because six empty rounded rectangles are the
            // one thing that reads as "unfinished" rather than as "a dashboard".
            Grid {
                id: raster
                visible: prev.url("dashboard") === ""
                anchors { fill: parent; margins: prev.look.cardPad || 14 }
                columns: 3
                rowSpacing: prev.look.cardGap || 10
                columnSpacing: prev.look.cardGap || 10
                readonly property var tiles: [
                    { "g": "󰕾", "l": "Volume",  "v": "72%" },
                    { "g": "󰃞", "l": "Bright",  "v": "80%" },
                    { "g": "󰤨", "l": "Network", "v": "on"  },
                    { "g": "󰂯", "l": "Bluetooth", "v": "2" },
                    { "g": "󰍛", "l": "CPU",     "v": "6%"  },
                    { "g": "󰋊", "l": "Disk",    "v": "81%" }
                ]
                Repeater {
                    model: raster.tiles
                    delegate: Rectangle {
                        id: tile
                        required property int index
                        required property var modelData
                        width:  Math.round((panel.width  - 2 * (prev.look.cardPad || 14)
                                            - 2 * (prev.look.cardGap || 10)) / 3)
                        height: Math.round((panel.height - 2 * (prev.look.cardPad || 14)
                                            - (prev.look.cardGap || 10)) / 2)
                        radius: prev.look.rTile || 0
                        color:  index === 0 ? (prev.look.selFill || Colors.bgActive)
                                            : Style.tint(Colors.bgActive, 0.45)
                        border.width: index === 0 ? (prev.look.selBorderW || 0) : 0
                        border.color: prev.look.selBorderColor || "transparent"
                        clip: true

                        readonly property color ink: tile.index === 0
                                                     ? (prev.look.selText || Colors.fgBright)
                                                     : Colors.fgBright
                        Column {
                            anchors { left: parent.left; top: parent.top; right: parent.right
                                      margins: 9 }
                            spacing: 3
                            Text {
                                text: tile.modelData.g
                                color: tile.ink
                                font.family: Style.iconFont; font.pixelSize: 17
                            }
                            Text {
                                width: parent.width
                                text: tile.modelData.l
                                color: tile.ink
                                opacity: 0.75
                                elide: Text.ElideRight
                                font.family: prev.font; font.pixelSize: 10
                            }
                        }
                        Text {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 9 }
                            text: tile.modelData.v
                            color: tile.ink
                            font.family: prev.font; font.pixelSize: 13; font.bold: true
                        }
                    }
                }
            }
        }
    }
}
