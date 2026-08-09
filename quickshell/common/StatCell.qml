import ".."
import QtQuick

// One headline figure in a popout's header strip. The strip is what turns a list of rows into a
// dashboard: it answers "what is going on in here" before you read a single row, the way the sound
// desk's tabs say Output 3 / Input 2 / Sources 1 without you opening anything.
//
// No surface of its own. The header reads as figures floating on the panel, and the only thing that
// wears a plate anywhere in these menus is the row you are actually on.
Item {
    id: s
    property string value:   ""
    property string caption: ""
    property string glyph:   ""          // optional, sits before the value
    property bool   good:    false       // a positive state — the accent
    property bool   warn:    false
    property bool   dim:     false       // present but not in play

    // From the NATURAL text widths, never from row.implicitWidth: a Row measures its children's
    // actual widths, and val's width is derived from this item's — that circle is a binding loop.
    // Item follows implicitWidth on its own when no width is assigned, so there is none here.
    implicitWidth:  Math.max(val.implicitWidth + (glyph.visible ? glyph.implicitWidth + row.spacing : 0),
                             cap.implicitWidth)
    implicitHeight: 34

    readonly property color _c: s.warn ? Colors.fgUrgent
                              : s.dim  ? Colors.fgMuted
                              : s.good ? Style.accent : Colors.fgBright

    Row {
        id: row
        anchors { left: parent.left; top: parent.top }
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
            width: Math.max(0, s.width - (glyph.visible ? glyph.width + row.spacing : 0))
            elide: Text.ElideRight
            text: s.value; color: s._c
            font.family: Style.font; font.pixelSize: 17; font.bold: true
            Behavior on color { ColorAnimation { duration: 140 } }
        }
    }
    Text {
        id: cap
        anchors { left: parent.left; right: parent.right; top: row.bottom; topMargin: 1 }
        elide: Text.ElideRight
        text: s.caption; color: Colors.fgMuted
        font.family: Style.font; font.pixelSize: 9
        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
    }
}
