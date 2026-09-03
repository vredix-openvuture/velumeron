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
    // The width of ONE column, handed down by the menu. A page is given the whole content width and
    // told how many of the menu's columns it owns, so a card here is exactly as wide as a card on
    // any other page and a full-width band (`spans`) really does run wall to wall — including past
    // the preview column, which is the only way "the strip goes all the way across" is true.
    // Zero = work it out from our own width (a CardColumns used outside the menu).
    property real colW: 0
    // How many cards the FIRST row may hold. The menu's preview card stands in the last column of
    // that row and nowhere else, so the page gets one column fewer up there and every column from
    // the second row down — otherwise a page of six cards leaves a column-wide strip of nothing
    // running down the whole page under the preview. 0 = the same as every other row.
    property int firstRowCols: 0
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
    readonly property real cardWidth: cols.colW > 0 ? cols.colW
                                     : Math.floor((cols.width - cols.gap * (cols.count - 1)) / cols.count)
    // How tall the first row came out. The menu's preview card stands in that row, in the column
    // this page does not own, and takes its height from here — that is what puts the preview and
    // the cards beside it on ONE bottom edge without either sizing the other.
    property real firstRowH: 0
    // How many cards this page actually has. The menu takes the column count from it, so a page
    // with one card does not get laid on three columns with two of them empty.
    readonly property int cardCount: {
        var n = 0
        for (var i = 0; i < cols.children.length; i++) {
            var c = cols.children[i]
            if (c && c.visible && (c.contentHeight !== undefined || c.height > 0)) n++
        }
        return n
    }

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
        var n1 = cols.firstRowCols > 0 ? Math.min(cols.firstRowCols, n) : n
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
            if (row.length === (rows.length === 0 ? n1 : n)) flush()
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

        // PLAIN SCROLLING. Every card is as tall as its contents and the PAGE is what scrolls —
        // one surface, one wheel, the whole way down.
        //
        // This used to be clever about the fold: a row that started inside the viewport but did not
        // fit was cut to the room it had and its cards scrolled INSIDE their own frames, so the
        // page's own scroll never sliced a card. It kept the frames intact and cost more than it
        // was worth — a row of cards each with its own little scroll, next to a page that also
        // scrolls, is two scrolls in one place and the wheel lands on whichever one the pointer
        // happens to be over. A card cut by the fold is only a card you have not scrolled to yet.
        for (var q = 0; q < rows.length; q++) {
            var rw = rows[q]
            var h2 = rw.fixed ? rw.h : rw.h + surplus * (rw.h / stretchable)
            // The LAST row shares whatever columns it did not fill, in whole columns: one card
            // left over takes the width of all of them, two cards on three columns take two and
            // one. Every edge stays on a grid line, and the page ends without a hole in it.
            var k    = rw.items.length
            var cap  = (q === 0 && n1 < n) ? n1 : n
            var last = (q === rows.length - 1) && !rw.span && k > 0 && k < cap
            var xr   = 0
            for (var b = 0; b < rw.items.length; b++) {
                var it = rw.items[b]
                if (it.rowHeight !== undefined) it.rowHeight = h2
                var span = last ? Math.floor(cap / k) + (b < (cap % k) ? 1 : 0) : 1
                if (it.rowWidth !== undefined)
                    it.rowWidth = last ? span * cols.cardWidth + (span - 1) * cols.gap : 0
                it.x = rw.span ? 0 : xr
                it.y = y
                xr += span * (cols.cardWidth + cols.gap)
            }
            if (q === 0) cols.firstRowH = h2
            y += h2 + cols.gap
        }
        cols._tallest = Math.max(0, y - cols.gap)
        if (!rows.length) cols.firstRowH = 0
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
