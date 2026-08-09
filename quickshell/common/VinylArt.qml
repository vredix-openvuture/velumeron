import ".."
import QtQuick
import Quickshell.Widgets

// Album art as a record: the cover is the LABEL in the middle of a grooved disc, and the disc turns
// while something is playing.
//
// The grooves do not show the motion — a circle looks the same at every angle — the label does.
// They are there to make a dark circle read as a record instead of a hole punched in the card.
//
// The spin is paused, never stopped: an animation restarted from `from` would snap back to zero
// every time you hit play, and a record picks up where the needle left it.
Item {
    id: v
    property string source:    ""
    property bool   spinning:  false
    property string fallback:  "󰝚"
    property real   labelFrac: 0.60          // label diameter as a fraction of the disc
    property int    decode:    512

    readonly property real d: Math.min(v.width, v.height)
    // Near-black whatever the scheme is — a record is not a palette surface. Derived from the
    // scheme's darkest tone rather than hard-coded, so a warm wallust run gets a warm black.
    readonly property color discColor: Qt.darker(Colors.bgPrimary, 1.55)

    Item {
        id: disc
        anchors.centerIn: parent
        width: v.d; height: v.d

        RotationAnimator on rotation {
            from: 0; to: 360
            duration: 4200
            loops: Animation.Infinite
            running: true
            paused:  !v.spinning              // holds the angle; a paused animator costs no frames
        }

        Rectangle {
            id: plate
            anchors.fill: parent
            radius: width / 2
            color: v.discColor

            // Grooves live in the band OUTSIDE the label, so they move with it: a bigger label
            // does not swallow them, it just leaves them a narrower rim to sit in.
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    readonly property real gap: (0.985 - v.labelFrac) / 5
                    anchors.centerIn: parent
                    width: plate.width * (v.labelFrac + gap * (index + 0.6)); height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Style.tint(Colors.fgBright, index % 2 === 0 ? 0.07 : 0.04)
                }
            }
        }

        RoundedImage {
            id: label
            anchors.centerIn: parent
            width: Math.round(v.d * v.labelFrac); height: width
            radius: width / 2
            decode: v.decode
            // THE reason RoundedImage has this knob (its own comment says so): the layer is built
            // once at item size and then resampled every single frame while the disc turns, which
            // is what made every cover look chewed. Rendered at 3× and scaled down by the GPU it
            // stays crisp all the way round.
            supersample: 3
            source: v.source
            fallback: v.fallback
        }

        // The spindle hole. Small, and the disc's own colour rather than black, so it reads as a
        // hole in this record instead of a dot drawn on it.
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(3, Math.round(v.d * 0.045)); height: width
            radius: width / 2
            color: v.discColor
            border.width: 1
            border.color: Style.tint(Colors.fgBright, 0.10)
        }
    }

    // A sheen falling across the disc. Outside the rotating item on purpose: light does not turn
    // with the record, and one that did would read as a smear ON the vinyl.
    ClippingRectangle {
        anchors.fill: disc
        radius: width / 2
        color: "transparent"
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 1.6; height: parent.height * 1.6
            rotation: -28
            gradient: Gradient {
                GradientStop { position: 0.30; color: "transparent" }
                GradientStop { position: 0.46; color: Style.tint(Colors.fgBright, 0.07) }
                GradientStop { position: 0.54; color: Style.tint(Colors.fgBright, 0.07) }
                GradientStop { position: 0.70; color: "transparent" }
            }
        }
    }
}
