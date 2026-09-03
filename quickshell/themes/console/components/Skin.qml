pragma ComponentBehavior: Bound
import QtQuick

// The phosphor, on ONE panel. The shell drops this into the bar strip and into every panel that
// grows out of it, so the scanlines live where Console's own chrome is and nowhere else — over your
// windows they read as damage, over the shell they read as the machine.
//
// Still while the desktop is idle, running while a menu is open (`ctx.busy`): the grid comes up and
// a short band rolls down the panel, which is the moment the desktop is supposed to feel like a
// screen you are operating. It is bounded by the panel, so an animating skin costs a panel-sized
// repaint rather than a monitor-sized one.
//
// Plain rectangles, never a gradient: a full-screen alpha ramp on a shell surface erases the text
// under it (measured — see components/Material.qml). Small solid rects composite fine.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal: root.ctx.palette || ({})
    readonly property color accent: root.pal.accent || "#b269e0"
    readonly property bool busy: root.ctx.busy === true

    // ONE grid for every surface: same pitch, same weight, whether it is the bar or a panel you
    // just opened. It used to give the bar a lighter grid on the theory that a surface which is
    // always up should be quieter — but the bar and a popout are inches apart on the same screen,
    // and two different phosphors side by side read as a mistake rather than as emphasis.
    readonly property int  pitch: 4
    readonly property real idleAlpha: 0.06
    readonly property real liveAlpha: 0.11

    Repeater {
        // Clamped at zero. A panel this sits in reports a NEGATIVE height for a frame or two while
        // its spring settles (Style.elDockH overshoots through the collapsed size), and a Repeater
        // handed a negative model logs "Model size of -45 is less than 0" and draws nothing —
        // five of them on every cold start, before any of this was on screen.
        model: Math.max(0, Math.ceil(root.height / root.pitch))
        delegate: Rectangle {
            required property int index
            y: index * root.pitch
            width: root.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                           root.busy ? root.liveAlpha : root.idleAlpha)
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // The roll: the frame seam of a tube that is actually running. Only while a menu is open, and
    // only ever inside this panel.
    Item {
        id: roll
        width: root.width
        height: Math.max(root.pitch * 4, Math.min(root.pitch * 10, Math.round(root.height * 0.35)))
        visible: root.busy && root.height >= root.pitch * 6
        y: -height
        NumberAnimation on y {
            running: roll.visible
            loops: Animation.Infinite
            from: -roll.height; to: root.height
            duration: 2200
        }
        readonly property int lines: Math.max(2, Math.round(roll.height / root.pitch))
        Repeater {
            model: roll.lines
            delegate: Rectangle {
                required property int index
                y: index * root.pitch
                width: root.width
                height: 1
                // Brightest in the middle of the band, so it reads as one sweep rather than as a
                // stack of lines that happen to move together.
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                               0.14 * (1 - Math.abs(index - (roll.lines - 1) / 2)
                                           / Math.max(1, roll.lines / 2)))
            }
        }
    }
}
