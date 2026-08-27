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
        color: Qt.rgba(0, 0, 0, 0.84)
    }
    // A wash of the scheme's own ground rather than more black: black punches a hole through the
    // wallust tint instead of dimming it, and the desktop should darken in its own colour.
    Rectangle {
        anchors.fill: parent
        color: root.pal.bgPrimary || "#06030a"
        opacity: 0.40
    }
}
