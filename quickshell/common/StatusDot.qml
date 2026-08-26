import ".."
import QtQuick

// The bar's status dot — the one "there is something here" mark every module shares.
//
// Every module used to draw its own: 5, 6 and 7 px, one with a ring and two without, one appearing
// instantly and one fading, in three different palette colours, each hung off whatever glyph the
// module happened to draw. Side by side in one bar that does not read as one indicator shown three
// times, it reads as three unrelated marks.
//
//   on   — is there something to report right now (animates in and out; not `visible`)
//   tone — the meaning; Style.dotTone by default, Style.danger when something is wrong
//
// There is deliberately no hollow / outline / small variant, and no placement knob. The dot is ONE
// shape at ONE size in ONE corner, and colour is the only thing allowed to differ — the moment a
// module gets its own geometry, the bar has two indicators again.
//
// It is instantiated by Bar.qml's ModSlot, not by the modules: the slot is the module's BOX, so the
// dot lands in the same top-right corner whatever the module draws inside. Modules only declare
// `dotOn` / `dotTone`. Size comes from the bar's icon size, never from the glyph next to it, so it
// stays identical across modules that render at different font and icon sizes (Style.dotSize).
Rectangle {
    id: root

    property string barMon: ""       // monitor, for the per-monitor bar icon size
    property color  tone:   Style.dotTone
    property bool   on:     true

    implicitWidth:  Style.dotSize(root.barMon)
    implicitHeight: implicitWidth
    width:  implicitWidth
    height: implicitHeight
    radius: Style.chromeR(width / 2)   // the strict/retro variants square everything else off too
    antialiasing: true

    // The tone, punched out of whatever it sits on by a ring in the bar's own colour — that ring is
    // what keeps it a dot rather than a blob welded to the glyph underneath.
    color:        root.tone
    border.width: Style.dotRing
    border.color: Colors.bgPrimary

    // The dot pops rather than blinks: same control curve as every other small state change in the
    // shell. Kept off `visible` so a module can bind `on` straight to its count.
    opacity: root.on ? 1 : 0
    scale:   root.on ? 1 : 0.4
    visible: opacity > 0.01
    transformOrigin: Item.Center

    Behavior on opacity      { NumberAnimation { duration: Style.ctrlMs; easing.type: Easing.OutCubic } }
    Behavior on scale        { NumberAnimation { duration: Style.ctrlMs; easing.type: Easing.OutCubic } }
    Behavior on color        { ColorAnimation  { duration: Style.ctrlMs } }
    Behavior on border.color { ColorAnimation  { duration: Style.ctrlMs } }
}
