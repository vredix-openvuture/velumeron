import ".."
import QtQuick

// Small-caps group header, e.g. "SYSTEM OSD". Deliberately prominent — brighter than the
// body text and letter-spaced — so each block reads as a distinct section, not fine print.
Text {
    color:              Colors.fgPrimary
    font.pixelSize:     Style.fsSection
    font.bold:          true
    font.letterSpacing: 1.2
    font.family:        Style.font
}
