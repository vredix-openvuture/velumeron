import ".."
import QtQuick

// Secondary caption line — for text the user must SEE without hunting for it: live status, empty
// states, a lead-in above a row of buttons, a command to copy.
//
// Explanations do NOT belong here any more. They live on the label they belong to (CardLabel /
// FieldLabel `hint`, Toggle `sub`), which underlines itself and shows the text on hover — that way
// a description never costs a row and never sits on a line of its own.
Text {
    color:          Colors.fgMuted
    font.pixelSize: Style.fsSub
    font.family:    Style.font
    wrapMode:       Text.WordWrap
}
