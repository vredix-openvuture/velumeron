import ".."
import QtQuick

// A section of a popout: its own surface, its label riding the top edge, and a live figure on the
// right of that label — because a section that can say something about itself should.
//
// This exists because the hairline-plus-tiny-label divider never worked. A 1px rule is thinner than
// the rows it is meant to separate, so the list wins and the structure disappears; and a label
// floating BETWEEN two blocks belongs to neither. Here the label sits on the surface it names.
//
// The caption is declared FIRST and inside the very column the default alias points at, so a
// caller's children land after it no matter which way QML routes them — the caption can never end
// up under the content.
StyledRect {
    id: p
    default property alias content: col.data

    property string label:  ""
    property string value:  ""          // the section's own reading, right of the label
    property bool   accent: false       // that reading is a live/positive state
    property bool   warn:   false
    property int    pad:    14
    property real   gap:    9

    width:  parent ? parent.width : 0
    height: col.implicitHeight + p.pad * 2
    radius: Style.rCard
    // A cut panel takes its definition from the edge rather than the fill — see Style.plateFill.
    borderWidth: Style.plateBorderW
    borderColor: Style.plateBorderColor
    // A wash, not a fill — the same translucent bgElement every surface in this shell is made of,
    // one step lighter than the panel it sits on so the edge reads without a border.
    color:  Style.plateFill

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: p.pad; rightMargin: p.pad; topMargin: p.pad }
        spacing: p.gap

        Item {
            width: parent.width
            visible: p.label !== ""
            // From the FONT, not from the label's laid-out height. Reading a child's
            // implicitHeight here loops: the child's width comes from this item's width, which
            // comes from the plate, whose height comes from this row — Qt reports it and then
            // resolves it however it likes. A caption is one line of a known size; measuring it
            // was never necessary. (Verified against a standalone harness: 10px → 14.)
            height: visible ? Math.round(cap.font.pixelSize * 1.45) : 0
            Text {
                id: cap
                anchors { left: parent.left; top: parent.top }
                width: Math.max(0, parent.width - val.width - 10)
                elide: Text.ElideRight
                text: p.label
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 10; font.bold: true
                font.capitalization: Font.AllUppercase; font.letterSpacing: 0.7
            }
            Text {
                id: val
                anchors { right: parent.right; baseline: cap.baseline }
                text: p.value
                color: p.warn ? Colors.fgUrgent : p.accent ? Style.accent : Colors.fgMuted
                font.family: Style.font; font.pixelSize: 10
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
    }
}
