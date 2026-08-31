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
// It is a CROP at half scale, not the whole desktop shrunk. A 2560-wide desktop squeezed into a
// 250 px card turns a bar into a hairline and its type into grey mush; the top-left corner at 1:2
// holds the bar, its modules and the head of the menu panel, which is where a theme's signature
// actually lives. So `stage` is twice the card in every direction and everything on it is drawn at
// its REAL pixel size, then halved.
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

    readonly property var    urls:  prev.theme.urls || ({})
    readonly property string font:  (prev.theme.ui_font || "") !== "" ? prev.theme.ui_font : Style.font
    readonly property string pos:   prev.theme.bar_position || "top"
    readonly property bool   float_: (prev.theme.bar_mode || "frame") === "float"
    readonly property bool   pills: (prev.theme.bar_module_bg || "module") !== "none"
    readonly property int    barT:  prev.theme.bar_thickness || 36
    readonly property int    barR:  prev.theme.bar_inner_radius || 0

    function url(k) { return (prev.urls[k] || "") !== "" ? "file://" + prev.urls[k] : "" }

    Item {
        id: stage
        width:  prev.width  * 2
        height: prev.height * 2
        transform: Scale { xScale: 0.5; yScale: 0.5 }

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
        // shape belongs to the theme. Real thickness, real corner, real module treatment.
        Rectangle {
            id: bar
            anchors {
                left: parent.left; right: parent.right
                top:    prev.pos === "bottom" ? undefined : parent.top
                bottom: prev.pos === "bottom" ? parent.bottom : undefined
                margins: prev.float_ ? 10 : 0
            }
            height: prev.barT
            radius: prev.float_ ? prev.barR : Math.round(prev.barR * 0.5)
            color: Style.tint(Colors.bgElement, 0.92)
            border.width: prev.look.cardBorderW || 0
            border.color: prev.look.cardBorderColor || "transparent"

            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width:  index === 0 ? 46 : 22
                        height: 22
                        radius: prev.pills ? 11 : Math.max(0, prev.look.rTile || 0)
                        color: index === 0 ? (prev.look.selFill || Colors.bgActive)
                                           : Style.tint(Colors.bgActive, 0.5)
                        border.width: index === 0 ? (prev.look.selBorderW || 0) : 0
                        border.color: prev.look.selBorderColor || "transparent"
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: "12:34"
                color: Colors.fgBright
                font.family: prev.font; font.pixelSize: 15
            }
            Row {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14
                        radius: prev.pills ? 7 : Math.max(0, prev.look.rTile || 0)
                        color: Style.tint(Colors.fgMuted, 0.55)
                    }
                }
            }
        }

        // ── The menu, grown out of the bar ──────────────────────────────────────────────────────
        // The panel is where a theme differs most, so the crop is aimed at it. Its chrome is the
        // theme's own — corner, border, fill — and what is INSIDE it is the theme's own dashboard
        // component when it brings one. That is the whole point: Console's card shows Console's
        // actual dashboard, loaded from the same file the menu loads.
        Rectangle {
            id: panel
            anchors {
                left: parent.left; leftMargin: 12
                top:    prev.pos === "bottom" ? parent.top : bar.bottom
                topMargin: prev.pos === "bottom" ? 12 : 10
            }
            width:  Math.min(stage.width - 24, 470)
            height: Math.max(60, stage.height - bar.height - 22)
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
            // a picker card has no business starting those.
            Grid {
                visible: prev.url("dashboard") === ""
                anchors { fill: parent; margins: prev.look.cardPad || 14 }
                columns: 3
                rowSpacing: prev.look.cardGap || 10
                columnSpacing: prev.look.cardGap || 10
                Repeater {
                    model: 6
                    delegate: Rectangle {
                        required property int index
                        width:  Math.round((panel.width  - 2 * (prev.look.cardPad || 14)
                                            - 2 * (prev.look.cardGap || 10)) / 3)
                        height: Math.round((panel.height - 2 * (prev.look.cardPad || 14)
                                            - (prev.look.cardGap || 10)) / 2)
                        radius: prev.look.rTile || 0
                        color:  index === 0 ? (prev.look.selFill || Colors.bgActive)
                                            : Style.tint(Colors.bgActive, 0.45)
                        border.width: index === 0 ? (prev.look.selBorderW || 0) : 0
                        border.color: prev.look.selBorderColor || "transparent"
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; margins: 10 }
                            width: Math.round(parent.width * 0.42); height: 8
                            radius: Math.max(0, Math.round((prev.look.rControl || 0) * 0.5))
                            color: Style.tint(Colors.fgMuted, 0.75)
                        }
                    }
                }
            }
        }
    }
}
