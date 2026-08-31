pragma ComponentBehavior: Bound
import QtQuick

// Console pushes the wallpaper down to a trace. It is not decoration to be looked at here; it is
// the faint thing behind the phosphor, and the screen is what you read.
//
// This sits on the BACKGROUND layer, over the wallpaper and under the windows, which is the whole
// reason it is a separate file from Material.qml. The same dim on the overlay would have dimmed
// every application window with it, and an app is not part of the theme. The falloff and the
// registration brackets live here for that reason too: both were over the windows once, and both
// looked like something had gone wrong rather than like a theme.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})
    readonly property var pal: root.ctx.palette || ({})
    readonly property var set: root.ctx.settings || ({})

    // How far the picture is pushed down (Settings -> Console -> Screen). "half" is the design's
    // own answer; the other two exist because a wallpaper you chose is allowed to still be there.
    readonly property real dim: ({ "clear": 0.45, "half": 0.74, "solid": 0.92 })[root.set.desk_backdrop] ?? 0.74

    // Nearly opaque. What survives is the shape of the picture, not the picture.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dim)
    }
    // A wash of the scheme's own ground rather than more black: black punches a hole through the
    // wallust tint instead of dimming it, and the desktop should darken in its own colour.
    Rectangle {
        anchors.fill: parent
        color: root.pal.bgPrimary || "#06030a"
        opacity: 0.32
    }

    // The falloff toward the edges. It lives HERE rather than on the material layer because a
    // full-screen alpha ramp on the overlay erases the text of every surface under it — measured,
    // see .internal/debug/console-bar-no-text.md. Under the windows it can only darken the picture,
    // which is all it was ever meant to do.
    readonly property real fallDepth: Math.round(Math.min(root.width, root.height) * 0.34)
    readonly property real fallMax:   0.30

    Rectangle {
        width: parent.width; height: root.fallDepth
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.fallMax) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
        }
    }
    Rectangle {
        y: parent.height - root.fallDepth
        width: parent.width; height: root.fallDepth
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.fallMax) }
        }
    }
    Rectangle {
        width: root.fallDepth; height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.fallMax) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
        }
    }
    Rectangle {
        x: parent.width - root.fallDepth
        width: root.fallDepth; height: parent.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.fallMax) }
        }
    }

    // Two registration brackets, not four: four corners is a frame, and a frame is what the old
    // hairline HUD already was; two is a mark on a screen. They sit on THIS layer, under the
    // windows — on the material they were solid accent over whatever you were working in, and
    // straight across the bar.
    //
    // The margin is measured from the bar's inner face, not from the screen edge: `ctx.insets`
    // carries how much each edge is already spoken for. A bracket that ignores it draws one arm
    // behind the bar and starts the other on the bar's own rule, which reads as a rendering fault
    // rather than as a mark.
    readonly property color accent: root.pal.accent || "#b269e0"
    readonly property var  ins:  root.ctx.insets || ({})
    function inset(edge) { return root.ins[edge] || 0 }

    readonly property real bm:   Math.round(Math.max(14, Math.min(root.width, root.height) * 0.022))
    readonly property real blen: Math.round(Math.min(root.width, root.height) * 0.075)
    readonly property real bth:  3

    readonly property real bx0: root.inset("left") + root.bm
    readonly property real by0: root.inset("top") + root.bm
    readonly property real bx1: root.width  - root.inset("right")  - root.bm
    readonly property real by1: root.height - root.inset("bottom") - root.bm

    readonly property bool brackets: root.set.desk_brackets !== false

    Rectangle { visible: root.brackets
                x: root.bx0; y: root.by0; width: root.blen; height: root.bth; color: root.accent }
    Rectangle { visible: root.brackets
                x: root.bx0; y: root.by0; width: root.bth; height: root.blen; color: root.accent }
    Rectangle { visible: root.brackets
                x: root.bx1 - root.blen; y: root.by1 - root.bth
                width: root.blen; height: root.bth; color: root.accent }
    Rectangle { visible: root.brackets
                x: root.bx1 - root.bth; y: root.by1 - root.blen
                width: root.bth; height: root.blen; color: root.accent }
}
