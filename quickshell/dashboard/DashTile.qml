import ".."
import QtQuick

// Base surface every dashboard module sits on: the card look plus the two things the grid talks to
// it through — `opts` (this instance's options) and the size of the cell it landed in.
//
// Deliberately NO default-property alias to an inner content Item: that pattern makes the children
// declared inside the defining file part of the alias target too, which is a trap waiting for the
// first module that needs to draw outside the padding (a toggle's hit area covers the whole tile,
// the media progress bar sits on the bottom edge). Modules parent their content to the tile
// directly and inset it with `pad` where they want the inset.
StyledRect {
    id: tile
    // Per-instance options from the layout entry (sub-kind, action, …). The grid rebinds this.
    property var opts: ({})
    property int pad:  Style.cardPad
    // How many cells this module was given. The grid binds them; a module that is asked to behave
    // differently at 1x1 asks THESE, never its pixel size.
    property int cw: 1
    property int ch: 1
    readonly property bool tiny: tile.cw <= 1 && tile.ch <= 1
    // Own surface. Off when the module sits in a group that draws ONE card behind all its members —
    // then a per-module card would be a box inside a box.
    property bool showBg: true
    // Content box, for modules that just want "inside the padding".
    readonly property real innerW: Math.max(0, tile.width  - 2 * tile.pad)
    readonly property real innerH: Math.max(0, tile.height - 2 * tile.pad)

    // Shape of the cell the module landed in. Every module answers the same question the same way,
    // so a 1×3 column and a 3×1 strip both get a layout that was meant for them instead of a
    // squashed version of the other one.
    readonly property bool tall: tile.height > tile.width * 1.25
    readonly property bool wide: tile.width  > tile.height * 1.6

    radius:      Style.rCard
    color:       tile.showBg ? Style.cardFill : "transparent"
    borderWidth: tile.showBg ? Style.cardBorderW : 0
    borderColor: tile.showBg ? Style.cardBorderColor : "transparent"
}
