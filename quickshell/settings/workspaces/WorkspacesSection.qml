import "../.."
import QtQuick

// Workspaces: names/icons, per-monitor assignment, persistence and the default (start)
// workspace — the WORKSPACES section of user_settings.lua. Edits stage locally in the
// shared WorkspaceRuleEditor; Apply writes via user-settings-io.py and reloads Hyprland.
Item {
    id: root

    // How many columns the menu has given this page. It lays one grid across the whole
    // content area — switch, cards, preview — and every page sits on it.
    readonly property int pageCols: (parent && parent.pageCols !== undefined) ? parent.pageCols : 0
    // How tall this page's content is, so the menu can be the size of its page rather than
    // a fixed box with half of it empty.
    readonly property real pageContentH: col.visible ? col.implicitHeight : 0
    readonly property real pageFillH: (parent && parent.pageFillH !== undefined) ? parent.pageFillH : 0
    readonly property real pageRowMin: (parent && parent.pageRowMin !== undefined) ? parent.pageRowMin : 0

    property var    rules:    []
    property var    monitors: []
    property bool   dirty:    false
    property string status:   ""

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() {
        UserSettings.get("monitors", function (d) {
            if (d) root.monitors = (d.monitors || []).map(function (m) {
                return { var: m.var, output: m.output }
            })
        })
        UserSettings.get("workspaces", function (d) {
            if (!d) return
            root.rules = d.rules || []
            root.dirty = false
            root.status = ""
        })
    }
    function apply() {
        root.status = "Applying…"
        UserSettings.set("workspaces", { rules: root.rules })
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "workspaces") return
            root.status = ok ? "Applied ✓" : ("" + (errors[0] || "Failed"))
            if (ok) root.reload()
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        CardColumns {
            id: col
            forced: root.pageCols
            firstRowMin: root.pageRowMin
            fillHeight: root.pageFillH
            width: parent.width
            y: 4

            Card {
                CardLabel { text: "WORKSPACES"
                            hint: "Each monitor owns one hundred workspace ids: the first 1-99, the "
                                + "second 101-199, and so on. The big number on a row is the SLOT — "
                                + "SUPER+1…0 always reaches slots 1-10 of the monitor you are on, "
                                + "and SUPER+ALT+<n> aims the same keys at monitor n. Pin a slot "
                                + "(󰐃) to keep it alive when it is empty." }
                WorkspaceRuleEditor {
                    width: parent.width
                    rules: root.rules
                    monitors: root.monitors
                    onChanged: r => { root.rules = r; root.dirty = true }
                }
            }

            Card {
                Row {
                    spacing: 10
                    TextButton { label: "Apply & reload"; primary: root.dirty; onClicked: root.apply() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dirty ? "unsaved changes" : root.status
                        color: root.dirty ? Colors.fgUrgent : Colors.fgMuted
                        font.pixelSize: Style.fsSub; font.family: Style.font
                    }
                }
            }
        }
    }
}
