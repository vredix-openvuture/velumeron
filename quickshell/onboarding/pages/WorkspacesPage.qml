import "../.."
import QtQuick

// Wizard page 2: workspace setup — the shared WorkspaceRuleEditor on the rules the
// --autostart bootstrap seeded (1–5 on the primary monitor). Persisted on Next via
// commit(); the final wizard page performs the one batched reload.
Item {
    id: root

    property var  rules:    []
    property var  monitors: []
    property bool dirty:    false

    Component.onCompleted: {
        UserSettings.get("monitors", function (d) {
            if (d) root.monitors = (d.monitors || []).map(function (m) {
                return { var: m.var, output: m.output }
            })
        })
        UserSettings.get("workspaces", function (d) {
            if (d) root.rules = d.rules || []
        })
    }

    // Called by the wizard footer before advancing.
    function commit() {
        if (root.dirty) UserSettings.set("workspaces", { rules: root.rules }, { noReload: true })
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            spacing: 14

            Text {
                text: "Workspaces"
                color: Colors.fgBright; font.pixelSize: 18; font.bold: true; font.family: Style.font
            }
            SubLabel {
                width: parent.width
                text: "Distribute workspaces across your monitors, give them names or icons, and pick "
                    + "each monitor's start workspace."
            }

            WorkspaceRuleEditor {
                width: parent.width
                rules: root.rules
                monitors: root.monitors
                onChanged: r => { root.rules = r; root.dirty = true }
            }
        }
    }
}
