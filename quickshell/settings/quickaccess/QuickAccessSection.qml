import "../.."
import QtQuick

// Quick access: the SUPER+F1–F12 app slots (quick_app in user_settings.lua). Edits stage
// locally; Apply writes the QUICKACCESS section and reloads Hyprland so the binds update.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // The width of ONE of the menu's columns. The page is handed the whole content
    // width and told how many columns it owns, so a card is the same width on every
    // page and a full-width band really does run wall to wall.
    // Page-level action: it belongs in the menu's head bar, in view, not on a card at the bottom
    // of a page you have to scroll to reach.
    readonly property var pageActions: [{ key: "apply", label: "Apply & reload", primary: root.dirty }]
    // Never empty: the head bar reads as a strip with a button dropped in it when the only thing on
    // that line is the button. This is the other half of the pair.
    readonly property string pageStatus: root.dirty ? "unsaved changes"
                                       : (root.status !== "" ? root.status : "nothing to apply")
    readonly property bool pageStatusUrgent: root.dirty
    function pageAct(key) { if (key === "apply") root.apply() }
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

    property var    apps:   ["", "", "", "", "", "", "", "", "", "", "", ""]
    property bool   dirty:  false
    property string status: ""

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() {
        UserSettings.get("quickaccess", function (d) {
            if (!d || !d.apps) return
            root.apps = d.apps
            root.dirty = false
            root.status = ""
        })
    }
    function setSlot(i, v) {
        if (root.apps[i] === v) return
        var a = root.apps.slice()
        a[i] = v
        root.apps = a
        root.dirty = true
    }
    function apply() {
        root.status = "Applying…"
        UserSettings.set("quickaccess", { apps: root.apps })
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "quickaccess") return
            root.status = ok ? "Applied ✓" : ("" + (errors[0] || "Failed"))
            if (ok) root.dirty = false
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        CardColumns {
            id: col
            forced: root.pageCols
            colW:  root.pageColW
            firstRowCols: root.pageFirstCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width

            Card {
                CardLabel { text: "QUICK ACCESS APPS"
                            hint: "Launched with SUPER + F1–F12. Type to search installed apps or enter any command." }

                Repeater {
                    model: 12
                    delegate: Row {
                        required property int index
                        width: parent.width
                        spacing: 8
                        Text {
                            width: 34
                            anchors.top: parent.top; anchors.topMargin: 9
                            text: "F" + (index + 1)
                            color: Colors.fgMuted; font.pixelSize: 12; font.bold: true
                            font.family: Style.font
                        }
                        AppField {
                            width: parent.width - 42
                            value: root.apps[index] || ""
                            placeholder: "empty — key does nothing"
                            onCommitted: v => root.setSlot(index, v)
                        }
                    }
                }

            }
        }
    }
}
