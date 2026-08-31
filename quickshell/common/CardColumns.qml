import ".."
import QtQuick

// Settings cards in as many columns as the panel can carry.
//
// A settings page is a stack of cards, and a stack laid out down a panel 1870 px wide gives every
// row the full width: a four-way switch runs wall to wall, a stepper puts its label at one end and
// its value at the other, and a card with two short rows in it is mostly air. Nothing on the page
// is sized to itself — that is what reads as "stretched".
//
// This lays the same cards into columns of a READABLE width instead. Docked at 420 px it is one
// column and behaves exactly as the plain Column it replaces; floating it is three or four, and no
// row is ever longer than a card. The panel stays as wide as you set it and the page fills it.
//
// It positions its children rather than reparenting them: a card keeps the parent it was declared
// under, so `parent.width` bindings inside a page do not silently retarget. Card.qml asks this
// container for `cardWidth`, so the width still arrives as a binding and nothing is overwritten.
//
// Cards are filled into the SHORTEST column each time, which keeps the bottom edge roughly level.
// The order down a column is therefore not strictly the declared order — for a settings page that
// is a set of independent groups, which is what these are.
Item {
    id: cols

    // A column narrower than this is not worth having: the widest control on these pages (a
    // segmented switch with four labels, a monitor chip row) needs about this much before it starts
    // wrapping into something worse than a long row. Measured against the real controls, not
    // guessed — "Dock / Float / Frame / None" at label size is about 340.
    property int minColW: 360
    // …and a ceiling, because the failure at the other end is real too: five 370 px columns on a
    // wide panel is a page you read like a newspaper, and these are settings, not an article.
    property int maxCols: 3
    property int gap:     Style.cardGap

    // A page inside the settings menu does not get to pick its own column count: the menu lays ONE
    // grid across the whole content area — the feature switch, the page's cards and the preview all
    // sit on it — and hands each part the number of columns it owns. Left at 0 this works it out
    // from its own width, which is what a CardColumns outside that grid does.
    property int forced: 0
    // A floor for the FIRST row. The menu puts its preview card beside the page rather than inside
    // it, and a preview that is taller than the row it stands next to leaves one card sticking out
    // below the others — which is the thing this grid exists to stop. The menu passes the preview's
    // height down and the first row matches it.
    property real firstRowMin: 0
    // The height the page has to fill. Rows grow into it proportionally when there is more room
    // than content — a page of two cards in a panel twice their height leaves half the screen
    // empty otherwise, which is the complaint this grid keeps coming back to.
    property real fillHeight: 0
    readonly property int  count: cols.forced > 0
                                  ? cols.forced
                                  : Math.max(1, Math.min(cols.maxCols,
                                    Math.floor((cols.width + cols.gap) / (cols.minColW + cols.gap))))
    readonly property real cardWidth: Math.floor((cols.width - cols.gap * (cols.count - 1)) / cols.count)

    // Every visible child's height, summed — a dependency the layout can watch. Card heights change
    // as their contents appear and disappear (a sub-group unfolding, a monitor list arriving), and
    // a layout that only ran on resize would leave the columns overlapping after any of that.
    readonly property real _heights: {
        var s = 0
        for (var i = 0; i < cols.children.length; i++) {
            var c = cols.children[i]
            if (c && c.visible) s += (c.contentHeight !== undefined ? c.contentHeight : c.height)
        }
        return s
    }

    implicitHeight: cols._tallest
    property real _tallest: 0

    // ROWS of equal height, in the order the page declared them.
    //
    // The first version filled the shortest column, which packs tighter — and looked assembled
    // rather than laid out: three cards of three different heights beside each other, their bottom
    // edges landing wherever the contents happened to end. A settings page is read across as much
    // as down, so the grid is rows: every card in a row is as tall as the tallest one in it, every
    // row starts on one line, and the reading order is the one the page wrote.
    function relayout() {
        var n = cols.count
        var row = []          // the cards on the row being filled
        var y = 0
        // Two passes: measure the rows, then place them. The stretch cannot be worked out until
        // every row's natural height is known.
        var rows = []
        var firstRow = true
        function flush() {
            if (!row.length) return
            var h = firstRow ? cols.firstRowMin : 0
            firstRow = false
            for (var a = 0; a < row.length; a++) h = Math.max(h, row[a].contentHeight !== undefined
                                                                 ? row[a].contentHeight : row[a].height)
            rows.push({ "items": row, "h": h, "span": false })
            row = []
        }
        for (var j = 0; j < cols.children.length; j++) {
            var c = cols.children[j]
            // A Repeater is a child with no height; so is a card whose contents all hid themselves.
            if (!c || !c.visible || (c.height <= 0 && c.contentHeight === undefined)) continue
            // Something that has to have the whole width (a lead-in paragraph, a nested layout of
            // its own) closes the row it is in and takes a band of its own.
            if (c.spans === true) {
                flush()
                if (c.rowHeight !== undefined) c.rowHeight = 0
                // A full-width CARD still grows with the rest — it is a row like any other, just
                // one column wide times all of them. Only a bare band (a lead-in line, a nested
                // layout with a height of its own) keeps what it is.
                rows.push({ "items": [c], "h": c.contentHeight !== undefined ? c.contentHeight : c.height,
                            "span": true, "fixed": c.rowHeight === undefined })
                continue
            }
            row.push(c)
            if (row.length === n) flush()
        }
        flush()

        // How much room is left over, and who may take it. A full-width band (a lead-in line, a
        // nested layout) keeps its own height; the card rows share the surplus in proportion to
        // what they already are, so a tall row stays taller than a short one.
        var natural = 0, stretchable = 0
        for (var r = 0; r < rows.length; r++) {
            natural += rows[r].h
            if (!rows[r].fixed) stretchable += rows[r].h
        }
        natural += Math.max(0, rows.length - 1) * cols.gap
        var surplus = (cols.fillHeight > 0 && stretchable > 0)
                      ? Math.max(0, cols.fillHeight - natural) : 0

        for (var q = 0; q < rows.length; q++) {
            var rw = rows[q]
            var h2 = rw.fixed ? rw.h : rw.h + surplus * (rw.h / stretchable)
            for (var b = 0; b < rw.items.length; b++) {
                var it = rw.items[b]
                if (it.rowHeight !== undefined) it.rowHeight = h2
                it.x = rw.span ? 0 : b * (cols.cardWidth + cols.gap)
                it.y = y
            }
            y += h2 + cols.gap
        }
        cols._tallest = Math.max(0, y - cols.gap)
    }

    // Deferred, always: a relayout reads heights that the same frame is still settling, and running
    // it inside the change that triggered it is how a layout ends up one card behind.
    function _schedule() { relayoutTimer.restart() }
    Timer { id: relayoutTimer; interval: 0; onTriggered: cols.relayout() }

    onWidthChanged:       cols._schedule()
    onFirstRowMinChanged: cols._schedule()
    onFillHeightChanged:  cols._schedule()
    onCountChanged:     cols._schedule()
    on_HeightsChanged:  cols._schedule()
    onChildrenChanged:  cols._schedule()
    Component.onCompleted: cols.relayout()
}
