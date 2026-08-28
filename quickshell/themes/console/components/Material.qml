pragma ComponentBehavior: Bound
import QtQuick

// What makes Console a screen rather than a dark colour scheme: scanlines, a falloff toward the
// corners, and two registration brackets. It lies over the whole monitor, above the windows, and
// takes no input.
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
// carries only what is small — the lines and the two brackets — and the falloff moved to Backdrop,
// under the windows, where it cannot erase anything. That is the better place for it anyway: a
// falloff belongs to the picture, not over the applications.
// See .internal/debug/console-bar-no-text.md.
//
// Nothing here animates. This layer covers the entire screen, so one moving pixel is a full-screen
// repaint for as long as the session is up.
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
    readonly property int linePitch: 6
    readonly property int lineThick: 1
    Repeater {
        model: Math.ceil(root.h / root.linePitch)
        delegate: Rectangle {
            required property int index
            y: index * root.linePitch
            width: root.w
            height: root.lineThick
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.05)
        }
    }

    // Two registration brackets, not four. Four corners is a frame, and a frame is what the old
    // hairline HUD already was; two is a mark on a screen.
    readonly property real bm:   Math.round(Math.max(14, Math.min(root.w, root.h) * 0.022))
    readonly property real blen: Math.round(Math.min(root.w, root.h) * 0.075)
    readonly property real bth:  3

    Rectangle { x: root.bm; y: root.bm; width: root.blen; height: root.bth; color: root.accent }
    Rectangle { x: root.bm; y: root.bm; width: root.bth; height: root.blen; color: root.accent }
    Rectangle { x: root.w - root.bm - root.blen; y: root.h - root.bm - root.bth
                width: root.blen; height: root.bth; color: root.accent }
    Rectangle { x: root.w - root.bm - root.bth; y: root.h - root.bm - root.blen
                width: root.bth; height: root.blen; color: root.accent }
}
