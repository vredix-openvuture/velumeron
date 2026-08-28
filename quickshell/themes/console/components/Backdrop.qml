pragma ComponentBehavior: Bound
import QtQuick

// Console pushes the wallpaper down to a trace. It is not decoration to be looked at here; it is
// the faint thing behind the phosphor, and the screen is what you read.
//
// This sits on the BACKGROUND layer, over the wallpaper and under the windows, which is the whole
// reason it is a separate file from Material.qml. The same dim on the overlay would have dimmed
// every application window with it, and an app is not part of the theme.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})
    readonly property var pal: root.ctx.palette || ({})

    // Nearly opaque. What survives is the shape of the picture, not the picture.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.74)
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
}
