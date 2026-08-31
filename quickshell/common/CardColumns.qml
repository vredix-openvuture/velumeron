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

    readonly property int  count: Math.max(1, Math.min(cols.maxCols,
                                  Math.floor((cols.width + cols.gap) / (cols.minColW + cols.gap))))
    readonly property real cardWidth: Math.floor((cols.width - cols.gap * (cols.count - 1)) / cols.count)

    // Every visible child's height, summed — a dependency the layout can watch. Card heights change
    // as their contents appear and disappear (a sub-group unfolding, a monitor list arriving), and
    // a layout that only ran on resize would leave the columns overlapping after any of that.
    readonly property real _heights: {
        var s = 0
        for (var i = 0; i < cols.children.length; i++) {
            var c = cols.children[i]
            if (c && c.visible) s += c.height + c.y * 0    // read height only; y is ours to set
        }
        return s
    }

    implicitHeight: cols._tallest
    property real _tallest: 0

    function relayout() {
        var n = cols.count
        var y = []
        for (var i = 0; i < n; i++) y.push(0)
        for (var j = 0; j < cols.children.length; j++) {
            var c = cols.children[j]
            // A Repeater is a child with no height; so is a card whose contents all hid themselves.
            // Placing those would open a column gap the size of the spacing for nothing.
            if (!c || !c.visible || c.height <= 0) continue
            // Something that has to have the whole width (a lead-in paragraph, a nested layout of
            // its own) takes a band across every column and the columns resume under it.
            if (c.spans === true) {
                var floor = 0
                for (var f = 0; f < n; f++) floor = Math.max(floor, y[f])
                c.x = 0
                c.y = floor
                for (var g = 0; g < n; g++) y[g] = floor + c.height + cols.gap
                continue
            }
            // shortest column wins; ties go left, so a single column stays in declared order
            var pick = 0
            for (var k = 1; k < n; k++) if (y[k] < y[pick] - 0.5) pick = k
            c.x = pick * (cols.cardWidth + cols.gap)
            c.y = y[pick]
            y[pick] += c.height + cols.gap
        }
        var tall = 0
        for (var m = 0; m < n; m++) tall = Math.max(tall, y[m])
        cols._tallest = Math.max(0, tall - cols.gap)
    }

    // Deferred, always: a relayout reads heights that the same frame is still settling, and running
    // it inside the change that triggered it is how a layout ends up one card behind.
    function _schedule() { relayoutTimer.restart() }
    Timer { id: relayoutTimer; interval: 0; onTriggered: cols.relayout() }

    onWidthChanged:     cols._schedule()
    onCountChanged:     cols._schedule()
    on_HeightsChanged:  cols._schedule()
    onChildrenChanged:  cols._schedule()
    Component.onCompleted: cols.relayout()
}
