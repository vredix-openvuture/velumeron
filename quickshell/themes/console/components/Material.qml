pragma ComponentBehavior: Bound
import QtQuick

// What makes Console a screen rather than a dark colour scheme. It lies over the whole monitor,
// above the windows, and takes no input — which is why the ONLY thing left on it is the scanline
// grid: a 5 % veil reads as phosphor over anything, while anything solid reads as damage.
//
// NO Canvas and NO Shape in this file, and both are scars rather than preferences. A full-screen
// overlay is the one place where "it rasterises to a texture" stops being an implementation detail:
// this layer sits above every surface in the shell, so anything that composites wrongly erases the
// shell instead of decorating it. Measured, with a green probe glyph under the layer:
//
//   no material at all                          1086 px
//   scanlines only, plain Rectangles             896 px
//   + a falloff as a Shape/RadialGradient          0 px
//   + a falloff as four edge-gradient Rectangles   0 px
//   both drawn into one Canvas                    76 px
//
// The pattern is not the drawing primitive, it is the SIZE: many small opaque rectangles composite
// fine, and any full-screen surface carrying an alpha ramp erases what is under it. So this layer
// carries only the lines, and the falloff moved to Backdrop, under the windows, where it cannot
// erase anything. That is the better place for it anyway: a falloff belongs to the picture, not
// over the applications.
// See .internal/debug/console-bar-no-text.md.
//
// Nothing here animates except the one dim that fades in when a menu opens. This layer covers the
// entire screen, so a moving pixel is a full-screen repaint for as long as it moves.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})
    readonly property var pal: root.ctx.palette || ({})
    readonly property color accent: root.pal.accent || "#b269e0"
    readonly property real w: root.ctx.w || root.width
    readonly property real h: root.ctx.h || root.height

    // Scanlines as plain rectangles: ~240 static nodes on a 1440 px screen, none of them bound to
    // anything that changes. Cheaper than it looks and, unlike a raster step, it cannot come out
    // as something other than what it says.
    readonly property var  set: root.ctx.settings || ({})
    readonly property bool scanlines: root.set.desk_scanlines !== false

    // Nothing is drawn here when a menu opens. Dimming the desktop belongs to the shell's own
    // modal backdrop (settings/SettingsDim.qml), which is a surface UNDER the panel rather than
    // over everything — a second dim on this layer stacked with it and crushed the windows to
    // black. The phosphor that does belong to a menu is on the panels themselves (ThemeSkin).

    // The same pitch the panels' grid uses (components/Skin.qml). Two different line spacings on one
    // screen do not read as two surfaces, they read as one surface rendered wrong.
    readonly property int linePitch: 4
    readonly property int lineThick: 1
    Repeater {
        model: root.scanlines ? Math.ceil(root.h / root.linePitch) : 0
        delegate: Rectangle {
            required property int index
            y: index * root.linePitch
            width: root.w
            height: root.lineThick
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.05)
        }
    }

    // The registration brackets used to be here and are in Backdrop.qml now. Two solid accent marks
    // over every window and across the bar are not a mark on a screen, they are graffiti on the
    // work — and they landed on top of the bar, which is the one surface that must look like it
    // belongs to the shell. Under the windows they still frame the desktop and never cover it.
}
