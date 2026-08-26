import ".."
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// The launcher's mode picker — the third of the card that is not results.
//
// Two jobs. It makes the launcher's modes VISIBLE: the modes used to be reachable only by typing a
// prefix (`!f`, `>`, `!v`, `!k`, `?`), so a button per mode is the difference between a feature you
// know about and one you don't. Each button carries the FUNCTION KEY that reaches it (F1 down the
// list), which is the shortcut users are told about now. And it carries a cut of the wallpaper,
// which is what keeps the card from being a grey box — see `imageMode`.
//
// One component, three shapes:
//   vertical + plate   the rail beside the results, when the launcher docks to a horizontal bar
//   horizontal + plate the band ABOVE the results, when it docks to a vertical bar — a rail down
//                      the side of a card that is already tall and narrow would leave no results
//   horizontal, plate off   the strip under the fullscreen search field (the desktop is the backdrop)
//
// Registered in quickshell/qmldir. Never `import "launcher"` — directory imports work under
// hot-reload and break a cold start.
Item {
    id: rail

    property string mon:       ""
    property bool   vertical:  true      // buttons in a column (side rail) vs a row (band / strip)
    property bool   plate:     true      // draw the panel + wallpaper behind the buttons
    property string mode:      "apps"    // the launcher's current mode key — the lit button
    property bool   fs:        false     // launcher currently fullscreen (flips the Fullscreen button)
    property bool   labels:    true      // names beside the icons (needs the plate)
    property bool   logo:      true      // the Velumeron wordmark (needs the plate)
    property string imageMode: "mini"    // mini | window | custom | off
    property string customPath: ""
    property real   dimAmt:    0.0       // 0…1 scrim over the image
    property real   blurAmt:   0.0       // 0…1 blur over the image
    property int    radius:    Style.rCard

    // Where this sits on the SCREEN, for `imageMode: "window"`: the image is drawn at screen size
    // and pushed back by exactly this, so the panel shows the piece of wallpaper it covers — the
    // card reads as a hole punched through to the desktop, and the piece pans while the drawer
    // rides out of the bar. Bound to the card's live position by the caller.
    property real originX: 0
    property real originY: 0
    property real screenW: 0
    property real screenH: 0

    signal picked(string key)

    readonly property string vtlDir: Quickshell.env("VELUMERON_DIR") ?? ""

    // ── Which buttons ───────────────────────────────────────────────────────────────────────────
    // Catalogue order, filtered by the user's set (VtlConfig.launcherSidebarModes) — so re-ordering
    // the catalogue re-orders every picker, and a key the user removed simply isn't drawn. The
    // order IS the F-key order, which is why it never depends on how the user picked them.
    readonly property var buttons: {
        var want = VtlConfig.launcherSidebarModes || []
        return VtlConfig.launcherModes.filter(function (m) { return want.indexOf(m.key) >= 0 })
    }
    // Names only where there is a plate to put them on; the bare fullscreen strip stays icons.
    readonly property bool showNames: rail.labels && rail.plate
    readonly property int  btnH:   rail.vertical ? 54 : (rail.plate ? 46 : 40)
    // Air between the buttons — the rail is allowed to need more room than it has and scroll; a
    // cramped column of seven chips is what it looked like when the gap was the settings-page 6.
    readonly property int  btnGap: rail.vertical ? 14 : 8
    readonly property int  pad:    10
    // The wordmark, not the bird alone — the same banner the splash and the setup wizard use, so
    // the launcher opens on the product's name. Its aspect is 1.9:1. It sits in a FIXED header: the
    // buttons scroll under it, the name does not scroll away.
    readonly property int  logoW:  rail.vertical ? Math.max(0, Math.round((rail.width - 2 * rail.pad) * 0.78))
                                                 : Math.round(rail.logoH * 1.9)
    readonly property int  logoH:  !rail.logo ? 0
                                 : rail.vertical ? Math.round((rail.width - 2 * rail.pad) * 0.78 / 1.9)
                                 : Math.max(0, Math.min(Math.round(rail.height * 0.30), 56))
    readonly property int  headerH: (rail.logo && rail.plate) ? rail.logoH + 2 * rail.pad : 0

    // ── The wallpaper behind it ─────────────────────────────────────────────────────────────────
    // Same file every wallpaper surface reads (quickshell/wallpapers.json), watched, so a change
    // made anywhere lands here too. Videos have no still to show, so their cached first frame (the
    // wallpaper picker's thumbnail, same path convention) stands in.
    property var _wallMap: ({})
    FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron"))
              + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      { try { rail._wallMap = JSON.parse(text()) } catch (e) { /* keep last good */ } }
        onFileChanged: reload()
    }
    readonly property string wallPath: {
        var e = rail.mon !== "" && rail._wallMap ? rail._wallMap[rail.mon] : null
        if (!e || !e.path) return ""
        if ((e.type || "image") === "image") return "" + e.path
        return (Quickshell.env("HOME") ?? "") + "/.cache/velumeron/wp-thumbs/" + Qt.md5("" + e.path) + ".jpg"
    }
    readonly property string imgSource:
          !rail.plate || rail.imageMode === "off" ? ""
        : rail.imageMode === "custom" ? (rail.customPath !== "" ? "file://" + rail.customPath : "")
        : (rail.wallPath !== "" ? "file://" + rail.wallPath : "")
    readonly property bool hasImage: rail.imgSource !== ""

    // Base plate — also what "off" and a missing wallpaper fall back to.
    StyledRect {
        anchors.fill: parent
        visible: rail.plate
        radius: rail.radius
        color: Style.controlFill
        borderWidth: Style.controlBorderW
        borderColor: Style.controlBorderColor
    }

    // The image, drawn only through the mask below (square corners inside a rounded card is exactly
    // the boxy look RoundedImage exists to avoid — same technique here, but the layouts differ per
    // mode, so it is spelled out rather than reused).
    Item {
        id: imgLayer
        anchors.fill: parent
        visible: false
        layer.enabled: rail.hasImage
        layer.smooth: true

        // "mini" / "custom": a CUT of the picture that fills the panel exactly — the wallpaper as a
        // tall strip (or a wide one for the band), not a fitted thumbnail with filler around it.
        // PreserveAspectCrop scales to cover and centres the overflow, so what shows is a piece of
        // the real image at the panel's own aspect.
        Image {
            anchors.fill: parent
            visible: rail.imageMode !== "window"
            source: rail.imageMode === "window" ? "" : rail.imgSource
            fillMode: Image.PreserveAspectCrop
            // Decode along the panel's LONG axis: constraining the short one would hand a 16:9
            // source back at a fraction of the pixels the crop needs, and it would come out mush.
            sourceSize.width:  rail.width >= rail.height ? Math.max(1, Math.round(rail.width  * 1.5)) : 0
            sourceSize.height: rail.width >= rail.height ? 0 : Math.max(1, Math.round(rail.height * 1.5))
            asynchronous: true; cache: true; smooth: true; mipmap: true
        }

        // "window": screen-sized, pushed back by the panel's own position on that screen.
        Image {
            visible: rail.imageMode === "window"
            width:  Math.max(1, rail.screenW)
            height: Math.max(1, rail.screenH)
            x: -rail.originX
            y: -rail.originY
            source: rail.imageMode === "window" ? rail.imgSource : ""
            fillMode: Image.PreserveAspectCrop        // matches WallpaperWindow, so the piece lines up
            sourceSize.width: Math.max(1, Math.round(rail.screenW))
            asynchronous: true; cache: true; smooth: true
        }
    }
    Rectangle {
        id: imgMask
        anchors.fill: parent
        radius: rail.radius
        color: "black"
        visible: false
        antialiasing: true
        layer.enabled: rail.hasImage
        layer.smooth: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: rail.plate && rail.hasImage
        source: imgLayer
        maskEnabled: true; maskSource: imgMask
        blurEnabled: rail.blurAmt > 0.001; blur: rail.blurAmt; blurMax: 64; autoPaddingEnabled: false
        brightness: -rail.dimAmt
    }
    // The border again, on TOP of the image — the mask stops at the rounded edge, so without this
    // the panel loses its outline wherever a picture is showing.
    StyledRect {
        anchors.fill: parent
        visible: rail.plate && rail.hasImage
        radius: rail.radius
        color: "transparent"
        borderWidth: Style.controlBorderW
        borderColor: Style.controlBorderColor
    }

    // ── Buttons ─────────────────────────────────────────────────────────────────────────────────
    Component {
        id: btn
        Item {
            id: b
            required property var modelData
            required property int index
            // The mode's key on the keyboard: F1 is the first button, F2 the second, and so on. The
            // chip shows it, so the shortcut is read off the button you just clicked.
            readonly property string fkey: "F" + (b.index + 1)
            readonly property bool isFsBtn: b.modelData.key === "fullscreen"
            readonly property bool lit: b.isFsBtn ? rail.fs : (rail.mode === b.modelData.key)
            readonly property string glyph: (b.isFsBtn && rail.fs) ? "󰊔" : b.modelData.icon
            readonly property string name:  (b.isFsBtn && rail.fs) ? "Windowed" : b.modelData.label
            readonly property int  padL: rail.showNames ? 10 : 0
            readonly property int  padR: rail.showNames ? 9  : 0

            // A column button spans the rail; a row button is as wide as what it holds (or square
            // when it holds only a glyph). Nothing here may read the button's own width — the row
            // shape derives it from the label.
            width: rail.vertical ? (rail.showNames ? rail.parentWidth - 2 * rail.pad : rail.btnH)
                 : rail.showNames ? Math.ceil(b.padL + 32 + 10 + lbl.implicitWidth + chipW + b.padR)
                 : b.height
            height: rail.btnH
            readonly property real chipW: chip.visible ? pfx.implicitWidth + 12 + 8 : 0

            StyledRect {
                anchors.fill: parent
                radius: Style.rControl
                // Over a photograph a plain "transparent" idle state is unreadable, so the resting
                // chip is a translucent plate — dark enough to sit on any wallpaper, light enough
                // that the picture still shows through it.
                color: b.lit ? Style.accent
                     : hov.containsMouse ? Style.tint(Colors.bgElement, 0.82)
                     : (rail.plate && rail.hasImage) ? Style.tint(Colors.bgPrimary, 0.46)
                                                     : Style.tint(Colors.bgElement, 0.30)
                borderWidth: Style.controlBorderW
                borderColor: b.lit ? Style.selBorderColor : Style.tint(Style.controlBorderColor, 0.6)

                Row {
                    id: brow
                    anchors { left: parent.left; right: parent.right
                              leftMargin: b.padL; rightMargin: b.padR
                              verticalCenter: parent.verticalCenter }
                    spacing: rail.showNames ? 10 : 0
                    // The glyph lives in a fixed square cell rather than sizing to itself, so every
                    // button's icon sits on the same line however wide its glyph draws.
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width:  rail.showNames ? 32 : brow.width
                        height: 32
                        Text {
                            anchors.centerIn: parent
                            text: b.glyph
                            color: b.lit ? Style.selText : Colors.fgBright
                            font.pixelSize: rail.vertical ? 23 : (rail.plate ? 21 : 17)
                            font.family: Style.font
                        }
                    }
                    Text {
                        id: lbl
                        visible: rail.showNames
                        anchors.verticalCenter: parent.verticalCenter
                        // Column buttons take the rail's width and elide; row buttons are sized BY
                        // this text, so there it must stay at its implicit width.
                        width: rail.vertical ? Math.max(0, brow.width - 32 - brow.spacing - b.chipW)
                                             : implicitWidth
                        text: b.name
                        color: b.lit ? Style.selText : Colors.fgBright
                        font.pixelSize: 14; font.family: Style.font
                        elide: Text.ElideRight
                    }
                }
                // The function key that reaches this mode, so the picker TEACHES the keyboard route
                // instead of replacing it. (The old prefixes still parse if you type them; nobody
                // has to know them any more.)
                StyledRect {
                    id: chip
                    visible: rail.showNames
                    anchors { right: parent.right; rightMargin: b.padR; verticalCenter: parent.verticalCenter }
                    width: pfx.implicitWidth + 12; height: 18
                    radius: Style.rControl
                    color: b.lit ? Style.tint(Style.selText, 0.18) : Style.tint(Colors.bgElement, 0.55)
                    Text {
                        id: pfx
                        anchors.centerIn: parent
                        text: b.fkey
                        color: b.lit ? Style.selText : Colors.fgMuted
                        font.pixelSize: 10; font.bold: true; font.family: Style.font
                    }
                }

                MouseArea {
                    id: hov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rail.picked(b.modelData.key)
                }
            }
        }
    }

    // Column buttons size themselves from the rail; row buttons from their own label.
    readonly property int parentWidth: rail.width

    // ── Fixed header: the wordmark, over a softly blurred patch of the picture ──────────────────
    // The blur is a SECOND pass over the same image layer, masked to the header strip: the
    // wallpaper stays sharp everywhere else and goes soft only where the name has to be readable.
    Rectangle {
        id: headerMask
        width: rail.width; height: rail.headerH
        topLeftRadius: rail.radius; topRightRadius: rail.radius
        bottomLeftRadius: 0; bottomRightRadius: 0
        color: "black"
        visible: false
        antialiasing: true
        layer.enabled: rail.hasImage && rail.headerH > 0
        layer.smooth: true
    }
    MultiEffect {
        anchors.fill: parent
        visible: rail.plate && rail.hasImage && rail.headerH > 0
        source: imgLayer
        maskEnabled: true; maskSource: headerMask
        blurEnabled: true; blur: 0.55; blurMax: 48; autoPaddingEnabled: false
        brightness: -Math.max(rail.dimAmt, 0.10)
    }
    Image {
        id: logoImg
        visible: rail.logo && rail.plate
        anchors { top: parent.top; topMargin: rail.pad; horizontalCenter: parent.horizontalCenter }
        width: rail.logoW; height: rail.logoH
        // Banner variant follows the palette, the same rule the splash and the wizard use:
        // light glyphs on a dark scheme, dark ones on a light scheme.
        readonly property real _lum: 0.299 * Colors.bgPrimary.r + 0.587 * Colors.bgPrimary.g
                                   + 0.114 * Colors.bgPrimary.b
        source: "file://" + rail.vtlDir + "/assets/icons/velumeron_banner-"
                + (_lum < 0.5 ? "white" : "black") + ".png"
        sourceSize.width: Math.max(1, 2 * rail.logoW)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true; mipmap: true; antialiasing: true
    }

    // ── Column shape (side rail) ────────────────────────────────────────────────────────────────
    // Scrollable: the rail is allowed to want more room than the card gives it (a long button set,
    // generous spacing). It clips and scrolls instead of forcing the card to grow to fit — the
    // results decide the card's height, not the rail.
    Flickable {
        visible: rail.vertical
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom
                  topMargin: rail.headerH > 0 ? rail.headerH : rail.pad
                  leftMargin: rail.pad; rightMargin: rail.pad; bottomMargin: rail.pad }
        clip: true
        contentWidth:  width
        contentHeight: railCol.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: railCol
            width: parent.width
            spacing: rail.btnGap

            Repeater { model: rail.buttons; delegate: btn }
        }
    }

    // ── Row shape (the band above the results, and the fullscreen strip) ────────────────────────
    // Centred while the buttons fit, scrollable when they do not — same deal as the column. The
    // header (if any) is above it and stays put.
    Flickable {
        id: rowScroll
        visible: !rail.vertical
        anchors { left: parent.left; right: parent.right
                  leftMargin: rail.pad; rightMargin: rail.pad
                  top: parent.top; topMargin: rail.headerH
                  bottom: parent.bottom; bottomMargin: rail.plate ? rail.pad : 0 }
        clip: true
        contentWidth:  btnRow.width
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        flickableDirection: Flickable.HorizontalFlick

        Row {
            id: btnRow
            x: Math.max(0, (rowScroll.width - width) / 2)
            y: Math.max(0, (rowScroll.height - height) / 2)
            spacing: rail.btnGap
            Repeater { model: rail.buttons; delegate: btn }
        }
    }
}
