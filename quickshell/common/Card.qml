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
    //
    // `spans` is the card saying it needs the whole row: the grid already places such a card at
    // x = 0 and resumes the columns under it, and this is the other half of that — without it the
    // card sat in a column's width at the full row's position.
    property bool spans: false
    // A width handed down by the grid: the last row of a page shares the columns it did not fill
    // between the cards it has, in WHOLE columns, so nothing is left as a column-shaped hole and
    // every card edge still sits on the same grid line as the rows above it. Zero = one column.
    property real rowWidth: 0
    width:        card.rowWidth > 0 ? card.rowWidth
                  : (parent && parent.cardWidth !== undefined)
                  ? (card.spans ? parent.width : parent.cardWidth)
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
    // As tall as its contents, or as tall as the row it was put in — never capped. A card that does
    // not fit the page is a card you scroll to; it does not scroll inside itself. (It did once: the
    // grid handed down a ceiling and the card scrolled its own rows so the page's fold could never
    // slice a frame. Two scrolls in one place, and the wheel went to whichever the pointer was
    // over — see the note in CardColumns.relayout.)
    height: Math.max(card.contentHeight, card.rowHeight)

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
    // A card given more height than its contents need holds them at the TOP and simply has room
    // under them. Centring was tried and thrown out: a heading floating in the middle of a tall
    // card reads as a mistake, and with several cards side by side their headings then no longer
    // line up with each other. Spreading the gaps was the other way and reads worse still — four
    // rows a finger apart stop looking like one group and start looking like four unrelated lines.
    Item {
        id: scroller
        anchors { fill: parent
                  leftMargin: Style.cardPad; rightMargin: Style.cardPad
                  topMargin: Style.cardPad;  bottomMargin: Style.cardPad }

        Column {
            id: inner
            width: scroller.width
            spacing: Style.rowGap
        }
    }
}
