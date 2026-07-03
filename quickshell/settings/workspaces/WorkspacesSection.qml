import "../.."
import QtQuick

// Workspaces: names/icons, per-monitor assignment, persistence and the default (start)
// workspace — the WORKSPACES section of user_settings.lua. Edits stage locally in the
// shared WorkspaceRuleEditor; Apply writes via user-settings-io.py and reloads Hyprland.
Item {
    id: root

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
        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            Card {
                CardLabel { text: "WORKSPACES" }
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
