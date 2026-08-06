import ".."
import QtQuick

// Text that scrolls itself when it doesn't fit, and sits still when it does. Two copies in a Row,
// translated by exactly one segment on an endless loop, so the tail flows into the head with no
// visible jump — the trick the bar's Mpris title has used all along, now a component so a narrow
// dashboard tile can show its full label instead of an ellipsis.
//
// Give it a width; it reports the height it needs.
Item {
    id: root

    property string text:      ""
    property color  color:     Colors.fgPrimary
    property int    pixelSize: 12
    property bool   bold:      false
    property string family:    Style.font
    property int    hAlign:    Text.AlignLeft
    // Gap between the two copies. At least half the visible box, so the tail has left before the
    // head arrives — with a fixed small gap a narrow tile showed two fragments of the same word at
    // once, which reads as garbage rather than as scrolling text.
    property int    gap:       Math.max(36, Math.round(root.width * 0.55))
    property bool   running:   true

    readonly property bool overflow: measure.implicitWidth > root.width + 0.5
    implicitHeight: measure.implicitHeight
    implicitWidth:  measure.implicitWidth
    clip: root.overflow

    // Unrendered yardstick: the natural width decides whether this has to move at all.
    Text {
        id: measure
        visible: false
        text: root.text
        font.pixelSize: root.pixelSize; font.bold: root.bold; font.family: root.family
    }

    Text {
        visible: !root.overflow
        width:   root.width
        horizontalAlignment: root.hAlign
        text:  root.text
        color: root.color
        font.pixelSize: root.pixelSize; font.bold: root.bold; font.family: root.family
    }

    Row {
        id: marquee
        visible: root.overflow
        spacing: root.gap
        readonly property real seg: measure.implicitWidth + spacing
        Repeater {
            model: 2
            delegate: Text {
                text:  root.text
                color: root.color
                font.pixelSize: root.pixelSize; font.bold: root.bold; font.family: root.family
            }
        }
        // Rest at the start, then travel. Speed scales with the distance, so a long title doesn't
        // crawl and a short one doesn't race. Without the rest the text is never still long enough
        // to actually be read.
        SequentialAnimation on x {
            running: root.overflow && root.running && root.visible
            loops:   Animation.Infinite
            PropertyAction  { value: 0 }
            PauseAnimation  { duration: 1600 }
            NumberAnimation { from: 0; to: -marquee.seg
                              duration: Math.max(2200, Math.round(marquee.seg * 16)) }
        }
    }
}
