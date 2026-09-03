import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Notifications settings: popup placement/behaviour, the notification-centre placement, the
// grouping toggle, and the full history (shared NotifList). Uses the shared common components.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // The width of ONE of the menu's columns. The page is handed the whole content
    // width and told how many columns it owns, so a card is the same width on every
    // page and a full-width band really does run wall to wall.
    readonly property real pageColW: (parent && parent.pageColW !== undefined) ? parent.pageColW : 0
    // How tall this page's first row came out, so the menu's preview card — which
    // stands in that row — can end on the same line as the cards beside it.
    readonly property real pageRowH: col.firstRowH
    // The first row is one column shorter when the menu's preview card stands in it; every row
    // below gets the full width, so no column-wide strip of nothing runs down the page.
    readonly property int pageFirstCols: (parent && parent.pageFirstCols !== undefined) ? parent.pageFirstCols : 0
    // What the menu sizes its grid from: a page with one card does not get three columns.
    readonly property int pageCards: col.cardCount
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    // Where this page's card grid starts inside it. Zero for a page that is nothing but
    // its grid; the ones with a header of their own say so, and the menu lines its
    // preview card up with the grid rather than with the top of the page.
    // Where the card grid starts inside this page. The menu puts its preview card on this line and
    // measures the height the grid has from it, so it has to be the REAL offset: a page whose grid
    // starts lower than it says gets a preview sitting too high and a grid too tall for the room it
    // has, which is then cut off at the bottom. The grid used to carry 4 px of air of its own that
    // this number did not know about — the air is gone instead.
    readonly property real pageGridY: 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
    function posLabel(p) { return p === "auto" ? "Auto (follow module)" : p === "center" ? "Standalone centre" : p.split("-").map(root.cap).join(" ") }

    function save(key, value) { SettingsStore.set(key, value) }

    readonly property var popupPositions:  ["top-left", "top-center", "top-right",
                                            "bottom-left", "bottom-center", "bottom-right"]
    readonly property var centrePositions: ["auto", "top-left", "top-center", "top-right",
                                            "center-left", "center-right",
                                            "bottom-left", "bottom-center", "bottom-right", "center"]

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        CardColumns {
            id: col
            forced: root.pageCols
            colW:  root.pageColW
            firstRowCols: root.pageFirstCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width

            // ── Popups ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "POPUPS" }
                FieldLabel { text: "Position" }
                Dropdown {
                    summary: root.posLabel(VtlConfig.notifyPosition)
                    options: root.popupPositions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.notifyPosition === p } })
                    onPicked: root.save("notify_position", key)
                }
                Toggle { label: "Dock to bar"; sub: "Flush to the edge (off = floating toasts)"
                         on: VtlConfig.notifyDock; onToggled: root.save("notify_dock", !VtlConfig.notifyDock) }
                Toggle { label: "Only on main monitor"; sub: "Always show popups on the primary monitor"
                         on: VtlConfig.notifyMainOnly; onToggled: root.save("notify_main_monitor_only", !VtlConfig.notifyMainOnly) }
            }

            // ── Centre ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "CENTRE" }
                FieldLabel { text: "Position"
                             hint: "Auto: dock to the notifications module, else the Velumeron icon, else top-left." }
                Dropdown {
                    summary: root.posLabel(VtlConfig.notifyCenterPos)
                    options: root.centrePositions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.notifyCenterPos === p } })
                    onPicked: root.save("notify_center_position", key)
                }
                FieldLabel { text: "Size"
                             hint: "0 = match the settings menu size." }
                Stepper { label: "Width"; unit: VtlConfig.notifyCenterWidth > 0 ? "px" : "auto"; step: 5; min: 0; max: 900
                          value: VtlConfig.notifyCenterWidth; onChanged: root.save("notify_center_width", v) }
                Stepper { label: "Height"; unit: VtlConfig.notifyCenterHeight > 0 ? "px" : "auto"; step: 5; min: 0; max: 2000
                          value: VtlConfig.notifyCenterHeight; onChanged: root.save("notify_center_height", v) }
            }

            // ── Behaviour ─────────────────────────────────────────────────────
            Card {
                CardLabel { text: "BEHAVIOUR" }
                Toggle { label: "Group by source"; sub: "Collapse same-app notifications into one stack"
                         on: VtlConfig.notifyGroup; onToggled: root.save("notify_group", !VtlConfig.notifyGroup) }
            }

            // ── History ───────────────────────────────────────────────────────
            CardLabel { text: "HISTORY" }
            NotifList { width: parent.width; height: 360 }
        }
    }
}
