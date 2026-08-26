import ".."
import QtQuick

// Small-caps group header, e.g. "SYSTEM OSD". Deliberately prominent — brighter than the
// body text and letter-spaced — so each block reads as a distinct section, not fine print.
//
// `hint` is the section's explanation. It is NOT drawn: the heading hands the text over on hover
// (HintTip), which is what keeps the settings pages from turning into walls of prose. Stays a Text,
// so every existing colour / font / width override keeps working and the hint never costs a row.
//
// The hairline under the heading is a HOVER effect, not a permanent mark. Standing there always, on
// every heading and every row that carries a hint, it turned a settings page into a list of
// markdown links — the page has to be calm at rest and only answer when asked.
Text {
    id: cl
    property string hint: ""

    color:              Colors.fgPrimary
    font.pixelSize:     Style.fsSection
    font.bold:          true
    font.letterSpacing: 1.2
    font.family:        Style.font

    // Under the glyphs only (contentWidth), so it tracks the heading instead of the row width.
    Rectangle {
        visible: cl.hint !== ""
        y:       cl.contentHeight + 1
        width:   cl.contentWidth
        height:  1
        color:   cl.color
        opacity: hintHover.containsMouse ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Style.ctrlMs } }
    }
    MouseArea {
        id: hintHover
        enabled: cl.hint !== ""
        width: cl.contentWidth; height: cl.contentHeight
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
    HintTip { target: cl; text: cl.hint; hovered: hintHover.containsMouse }
}
