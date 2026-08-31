import ".."
import QtQuick

// Titled settings group. Replaces the per-page `component Group` copies. Child controls are declared
// directly inside it (default content alias) and stacked in a padded column.
StyledRect {
    id: card
    default property alias content: inner.data
    // A card fills its parent, unless the parent is laying cards into COLUMNS — then it takes the
    // column width it is told. Asked for as a property rather than assigned by the container, so
    // the width stays a binding and a page that overrides it still wins.
    width:        (parent && parent.cardWidth !== undefined) ? parent.cardWidth
                                                             : (parent ? parent.width : 0)
    radius:       Style.rCard
    color:        Style.cardFill
    borderWidth:  Style.cardBorderW
    borderColor:  Style.cardBorderColor
    // A card is as tall as its contents — unless the grid it sits in has told it to match the row
    // it is in. Cards of three different heights side by side is what makes a page look assembled
    // rather than laid out, and no amount of matching WIDTHS fixes that.
    property real rowHeight: 0
    readonly property real contentHeight: card._naturalH + Style.cardPad * 2
    height:       Math.max(card.contentHeight, card.rowHeight)

    // Grimoire flourish: an inner hairline frame echoing the scalloped outline, plus corner
    // bosses — the diamond fittings on medieval book covers. Pure decoration under the content
    // (cardPad keeps rows clear of it); every other variant skips the whole layer.
    Loader {
        anchors.fill: parent
        active: Style.isGrimoire
        sourceComponent: Item {
            StyledRect {
                anchors { fill: parent; margins: 5 }
                radius:      Math.max(4, Style.rCard - 5)
                color:       "transparent"
                borderWidth: 1
                borderColor: Style.tint(Style.accent, 0.28)
            }
            Repeater {
                model: [{ cx: 0, cy: 0 }, { cx: 1, cy: 0 }, { cx: 0, cy: 1 }, { cx: 1, cy: 1 }]
                delegate: Rectangle {
                    required property var modelData
                    width: 7; height: 7; rotation: 45
                    x: modelData.cx * (parent.width  - width)
                    y: modelData.cy * (parent.height - height)
                    color: Style.tint(Style.accent, 0.85)
                }
            }
        }
    }

    // When the grid gives a card more height than its contents need, the rows SPREAD into it
    // rather than sitting at the top of an empty box — up to a point. Past twice the normal gap
    // the page starts reading as a list of unrelated lines, so the rest of the slack stays at the
    // bottom and the card is simply taller.
    //
    // The spread is computed from the natural height (`_naturalH`, measured at the base gap), never
    // from `inner.implicitHeight` — spacing feeding back into the height it is derived from is a
    // binding loop.
    readonly property real _naturalH: {
        var n = 0, h = 0
        for (var i = 0; i < inner.children.length; i++) {
            var c = inner.children[i]
            if (c && c.visible) { h += c.height; n++ }
        }
        return h + Math.max(0, n - 1) * Style.rowGap
    }
    readonly property int _rows: {
        var n = 0
        for (var i = 0; i < inner.children.length; i++)
            if (inner.children[i] && inner.children[i].visible) n++
        return n
    }
    readonly property real _slack: Math.max(0, card.height - 2 * Style.cardPad - card._naturalH)

    Column {
        id: inner
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: Style.cardPad; leftMargin: Style.cardPad; rightMargin: Style.cardPad }
        spacing: Style.rowGap + (card._rows > 1
                 ? Math.min(card._slack / (card._rows - 1), Style.rowGap * 2) : 0)
    }
}
