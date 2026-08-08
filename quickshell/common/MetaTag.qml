import ".."
import QtQuick

// A small factual label — a sample format, a codec, "default". Deliberately the quietest thing on
// a tile: it is there to be found, not read. Hides itself when empty so a caller can bind it to a
// value that may not exist without guarding every one.
Text {
    property bool good: false            // a positive fact (a negotiated codec, a live link)
    property bool warn: false
    visible: text !== ""
    color: warn ? Colors.fgUrgent : good ? Style.accent : Colors.fgMuted
    font.family: Style.font
    font.pixelSize: 10
}
