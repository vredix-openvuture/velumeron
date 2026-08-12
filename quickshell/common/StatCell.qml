import ".."
import QtQuick

// One headline figure, on a light little card. The head strip of every popout is built from these:
// it answers "what is going on in here" before a single row is read, which is the difference
// between a settings page and a dashboard.
//
// The card is deliberately faint — lighter than the plate the active row wears, so a strip of them
// reads as a set of readings rather than a row of buttons. Set `card: false` for a bare figure.
StyledRect {
    id: s
    property string value:   ""
    property string caption: ""
    property string glyph:   ""          // optional, sits before the value
    property bool   good:    false       // a positive state — the accent
    property bool   warn:    false
    property bool   dim:     false       // present but not in play
    property bool   card:    true
    property int    pad:     9

    // From the NATURAL text widths, never from row.implicitWidth: a Row measures its children's
    // actual widths, and val's width is derived from this item's — that circle is a binding loop.
    // Item follows implicitWidth on its own when no width is assigned, so there is none here.
    implicitWidth:  Math.max(val.implicitWidth + (glyph.visible ? glyph.implicitWidth + row.spacing : 0),
                             cap.implicitWidth) + s.pad * 2
    implicitHeight: 44

    radius: Style.rTile
    // wellFill, not plateFill: this sits INSIDE a plate, and the same wash on both would make it
    // vanish into its container. A cut variant swaps the wash for a line instead.
    color:       s.card ? Style.wellFill : "transparent"
    borderWidth: s.card ? Style.wellBorderW : 0
    borderColor: Style.plateBorderColor

    readonly property color _c: s.warn ? Colors.fgUrgent
                              : s.dim  ? Colors.fgMuted
                              : s.good ? Style.accent : Colors.fgBright

    Row {
        id: row
        anchors { left: parent.left; top: parent.top; leftMargin: s.pad; topMargin: s.pad - 1 }
        spacing: 5
        Text {
            id: glyph
            anchors.baseline: val.baseline
            visible: s.glyph !== ""
            text: s.glyph; color: s._c
            font.family: Style.font; font.pixelSize: 13
        }
        Text {
            id: val
            // Elided against whatever the cell was given, because the value can be an SSID or a
            // device name — a headline figure that runs into the next cell is worse than a cut one.
            width: Math.max(0, s.width - s.pad * 2 - (glyph.visible ? glyph.width + row.spacing : 0))
            elide: Text.ElideRight
            text: s.value; color: s._c
            font.family: Style.font; font.pixelSize: 16; font.bold: true
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }
    Text {
        id: cap
        anchors { left: parent.left; right: parent.right; top: row.bottom; topMargin: 1
                  leftMargin: s.pad; rightMargin: s.pad }
        elide: Text.ElideRight
        text: s.caption; color: Colors.fgMuted
        font.family: Style.font; font.pixelSize: 9
        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
    }
}
