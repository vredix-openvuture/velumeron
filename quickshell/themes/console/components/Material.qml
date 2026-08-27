pragma ComponentBehavior: Bound
import QtQuick

// What makes Console a screen rather than a dark colour scheme: scanlines, a falloff toward the
// corners, and two registration brackets. It lies over the whole monitor, above the windows, and
// takes no input.
//
// Everything is drawn, nothing is an image: a full-screen texture per monitor would cost real
// memory for a pattern that is four numbers, and it would have to be regenerated on every palette
// change. Nothing here animates either — this layer covers the entire screen, so a single moving
// pixel is a full-screen repaint.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})
    readonly property var pal: root.ctx.palette || ({})
    readonly property color accent: root.pal.accent || "#b269e0"
    readonly property real w: root.ctx.w || root.width
    readonly property real h: root.ctx.h || root.height

    // Scanlines, painted once into a Canvas. A Repeater would be ~240 Rectangles per monitor for a
    // pattern that is two numbers, and a ShaderEffect would need a compiled .qsb for the same. The
    // canvas is rasterised on the first frame and then only composited; it repaints only when the
    // accent or the geometry actually changes.
    Canvas {
        id: lines
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            var g = getContext("2d")
            g.clearRect(0, 0, width, height)
            g.fillStyle = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            for (var y = 0; y < height; y += 6) g.fillRect(0, y, width, 2)

            // The falloff, radial and in the same pass. Two crossed linear gradients were tried
            // first and they meet in an octagon with visible corners, which reads as a shape drawn
            // on the screen rather than as the edge of the light.
            var cx = width / 2, cy = height / 2
            var r = Math.sqrt(cx * cx + cy * cy)
            var v = g.createRadialGradient(cx, cy, r * 0.15, cx, cy, r)
            v.addColorStop(0.0, "rgba(0,0,0,0)")
            v.addColorStop(0.7, "rgba(0,0,0,0.08)")
            v.addColorStop(1.0, "rgba(0,0,0,0.22)")
            g.fillStyle = v
            g.fillRect(0, 0, width, height)
        }
        Connections {
            target: root
            function onAccentChanged() { lines.requestPaint() }
        }
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }

    // Two registration brackets, not four. Four corners is a frame, and a frame is what the old
    // hairline HUD already was; two is a mark on a screen.
    readonly property real bm:  Math.round(Math.max(14, Math.min(root.w, root.h) * 0.022))
    readonly property real blen: Math.round(Math.min(root.w, root.h) * 0.075)
    readonly property real bth: 3

    Rectangle { x: root.bm; y: root.bm; width: root.blen; height: root.bth; color: root.accent }
    Rectangle { x: root.bm; y: root.bm; width: root.bth; height: root.blen; color: root.accent }
    Rectangle { x: root.w - root.bm - root.blen; y: root.h - root.bm - root.bth
                width: root.blen; height: root.bth; color: root.accent }
    Rectangle { x: root.w - root.bm - root.bth; y: root.h - root.bm - root.blen
                width: root.bth; height: root.blen; color: root.accent }
}
