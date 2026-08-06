import ".."
import QtQuick

// Empty room. Draws nothing and does nothing — it just occupies its cells.
//
// Two jobs. Air between modules, so a dashboard can breathe instead of being one solid mosaic. And
// paging: placement is forward-only, so the way to start a new page early is to fill the rest of
// this one — a spacer is that filler. In edit mode the grid's own outline makes it visible; in the
// live dashboard it is nothing at all.
DashTile {
    showBg: false
}
