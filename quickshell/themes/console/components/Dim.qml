pragma ComponentBehavior: Bound
import QtQuick

// Console's window veil: while the shell has the screen — a menu, a flyout, a switcher, the
// launcher — your windows go a little quieter, and nothing else happens to them.
//
// It is its own surface on the Top layer, mapped before the bar, so it covers the windows and
// nothing the shell draws. That is not a detail: the first version of this was a rectangle on the
// full-screen material (Overlay), which dimmed the shell's own panels as well and stacked with the
// menu's own backdrop until the whole desktop read as black.
//
// Gentle on purpose. "A bit darker" is the brief; anything past that turns a popout into a modal.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    // Inset by the bar. Both this and the bar sit on the Top layer and the bar maps first, so it
    // ends up UNDER this veil — and a dimmed bar is exactly what "only the windows" is not. The
    // shell hands the thickness of every edge in `ctx.insets`, so the strip simply stays uncovered.
    readonly property var ins: root.ctx.insets || ({})
    function inset(edge) { return root.ins[edge] || 0 }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin:    root.inset("top")
        anchors.bottomMargin: root.inset("bottom")
        anchors.leftMargin:   root.inset("left")
        anchors.rightMargin:  root.inset("right")
        color: "black"
        opacity: root.ctx.busy === true ? 0.18 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
}
