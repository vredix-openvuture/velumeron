import ".."
import QtQuick
import Quickshell.Widgets

// The cava spectrum as a backdrop — behind the bar module, inside the mpris popout and on the
// dashboard tile. One component, because three copies would drift in colour and, worse, each
// would have to get CavaService's acquire/release bookkeeping right on its own (the process
// only runs while someone is watching; a missed release leaves it running forever).
//
// Set `active` to "this surface is on screen AND something is playing". Everything else — the
// reference counting, the teardown on destruction — happens here.
//
// Colour: deliberately NOT the accent. The wave sits behind text, and an accent-bright spectrum
// turned titles into something you had to read twice. A muted, low-alpha wash reads as motion
// and texture without competing with the words on top of it.
// Clipped to a ROUNDED shape, not a rectangle: the wave sits at the bottom of a card, and a
// rectangular clip let the outer bars poke past the card's rounded corners. `radius` should be
// whatever the surface behind it uses (Style.rCard on a tile, the bar's module radius, …).
ClippingRectangle {
    id: wave
    color: "transparent"

    property bool  active:    false
    // A SURFACE colour, not a foreground one: fgMuted is what body text is painted with, so a
    // wave in it reads as more text. bgSecondary belongs to the background family — it shows as
    // texture behind the words instead of competing with them.
    property color barColor:  Style.tint(Colors.bgSecondary, 0.75)
    property int   barGap:    1
    property real  minHeight: 2      // a floor, so the wave never vanishes between beats
    // How many bars to draw. 0 = whatever cava delivers (24). Small surfaces want fewer and
    // wider ones; 24 needles on a dashboard tile is noise, not decoration.
    property int   bars:      0
    // Height scale. Below 1 the wave stays low and calm instead of filling the surface.
    property real  intensity: 1.0

    // cava's levels, bucketed down to `bars`. Peak per bucket rather than average — averaging
    // flattens the beat into a gentle hill and the wave stops looking like music.
    readonly property var levels: {
        var src = CavaService.levels
        if (wave.bars <= 0 || wave.bars >= src.length) return src
        var out = [], step = src.length / wave.bars
        for (var i = 0; i < wave.bars; i++) {
            var a = Math.floor(i * step)
            var b = Math.max(a + 1, Math.floor((i + 1) * step))
            var m = 0
            for (var j = a; j < b && j < src.length; j++) m = Math.max(m, src[j] ?? 0)
            out.push(m)
        }
        return out
    }

    visible: wave.active && wave.levels.length > 0

    onActiveChanged: {
        if (wave.active) CavaService.acquire()
        else             CavaService.release()
    }
    Component.onDestruction: if (wave.active) CavaService.release()

    Row {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height
        spacing: wave.barGap
        Repeater {
            model: wave.levels.length
            delegate: Rectangle {
                required property int index
                width: Math.max(1, (wave.width - (wave.levels.length - 1) * wave.barGap)
                                   / Math.max(1, wave.levels.length))
                height: Math.max(wave.minHeight,
                                 (wave.levels[index] ?? 0) * parent.height * wave.intensity)
                anchors.bottom: parent.bottom
                // Softened tops, not lozenges: a full pill radius turned the spectrum into a row
                // of blobs. Capped by the height too, so a bar near the floor keeps its shape.
                radius: Math.min(3, width / 2, height / 2)
                color: wave.barColor
                Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
            }
        }
    }
}
