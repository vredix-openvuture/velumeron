import ".."
import QtQuick

// The one surface every popout row sits on. Depth comes from layering — panel, tile, track — not
// from borders: an outlined row is what makes a popout read as a form instead of a dashboard.
//
// It sizes to its content, so a tile that gains a curve or a row of app icons grows on its own
// rather than needing its height recomputed by hand (which is how the mixing desk ended up with a
// one-pixel overlap between the fader and the foot).
StyledRect {
    id: t
    default property alias content: col.data
    property bool  active:      false      // the current / default one
    property bool  interactive: false      // hovers, because clicking it does something
    property bool  highlight:   false      // a live drop target
    property int   pad:         13
    property real  spacing:     7
    readonly property alias hovered: hov.containsMouse

    width:  parent ? parent.width : 0
    height: col.implicitHeight + t.pad * 2
    radius: Style.rCard
    // Translucent, never a solid fill — the bar and the settings menu let the panel through, and
    // one solid slab inside a frosted popout reads as a foreign object glued on top of it. The
    // active tile wears the plate; everything else gets a wash faint enough to be an edge, not a
    // box. Same rule the sound desk settled on.
    color:  t.active ? Style.rowActive
          : (t.interactive && hov.containsMouse) ? Style.knobFill
          : Style.rowFill
    borderWidth: t.highlight ? 1 : 0
    borderColor: Style.accent
    Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: t.pad; rightMargin: t.pad; topMargin: t.pad }
        spacing: t.spacing
    }
}
