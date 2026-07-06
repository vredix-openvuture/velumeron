import ".."
import QtQuick

// Titled settings group. Replaces the per-page `component Group` copies. Child controls are declared
// directly inside it (default content alias) and stacked in a padded column.
StyledRect {
    id: card
    default property alias content: inner.data
    width:        parent ? parent.width : 0
    radius:       Style.rCard
    color:        Style.cardFill
    borderWidth:  Style.cardBorderW
    borderColor:  Style.cardBorderColor
    height:       inner.implicitHeight + Style.cardPad * 2

    Column {
        id: inner
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: Style.cardPad; leftMargin: Style.cardPad; rightMargin: Style.cardPad }
        spacing: Style.rowGap
    }
}
