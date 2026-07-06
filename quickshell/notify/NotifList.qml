import ".."
import QtQuick
import Quickshell

// Reusable notification history list (used by the centre and the settings page). When `grouped`
// is on, notifications from the same app collapse into one card showing the latest + a count.
Item {
    id: root
    property bool grouped: VtlConfig.notifyGroup

    // Recompute display rows from the tracked history whenever it changes.
    readonly property var src: NotifService.model.values
    readonly property var rows: {
        var vs = root.src
        if (!root.grouped)
            return vs.map(function (n) { return { app: n.appName || "", latest: n, count: 1, items: [n] } })
        var byApp = {}, order = []
        for (var i = 0; i < vs.length; i++) {
            var a = vs[i].appName || ""
            if (!byApp[a]) { byApp[a] = { app: a, latest: vs[i], count: 0, items: [] }; order.push(a) }
            byApp[a].items.push(vs[i])
            byApp[a].count++
            byApp[a].latest = vs[i]   // last seen wins as the representative
        }
        return order.map(function (a) { return byApp[a] })
    }

    function dismissRow(row) { for (var i = 0; i < row.items.length; i++) row.items[i].dismiss() }

    // Which app groups are expanded (clicking a stacked card toggles it). Keyed by app name so
    // the state survives the rows recompute; reassigned as a copy to retrigger bindings.
    property var expandedApps: ({})
    function toggleExpand(app) {
        var m = Object.assign({}, expandedApps)
        m[app] = !m[app]
        expandedApps = m
    }

    Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        text:   "No notifications"
        color:  Colors.fgMuted; font.pixelSize: 13; font.family: Style.font
    }

    ListView {
        id: list
        anchors.fill: parent
        clip:    true
        spacing: 8
        model:   root.rows

        delegate: StyledRect {
            id: item
            required property var modelData
            readonly property var n: modelData.latest
            readonly property bool stacked:  modelData.count > 1
            readonly property bool expanded: stacked && root.expandedApps[modelData.app] === true
            width:  ListView.view.width
            radius: Style.rControl
            color:  cardMa.containsMouse && item.stacked ? Style.tint(Colors.bgElement, 0.06) : Colors.bgElement
            implicitHeight: item.expanded ? igroup.y + igroup.implicitHeight + 14
                                          : Math.max(54, ibody.y + ibody.implicitHeight + 14)

            // A stacked card expands/collapses on click (✕ sits on top and keeps priority).
            MouseArea {
                id: cardMa
                anchors.fill: parent
                enabled: item.stacked
                hoverEnabled: true
                onClicked: root.toggleExpand(item.modelData.app)
            }

            Text {
                id: iapp
                anchors { left: parent.left; right: badge.left; top: parent.top
                          leftMargin: 16; rightMargin: 8; topMargin: 14 }
                text: item.n ? item.n.appName : ""; color: Colors.fgMuted
                font.pixelSize: 10; font.family: Style.font; elide: Text.ElideRight
            }
            Text {
                id: isum
                visible: !item.expanded
                anchors { left: iapp.left; right: idel.left; rightMargin: 8; top: iapp.bottom; topMargin: 1 }
                text: item.n ? item.n.summary : ""; color: Colors.fgBright
                font.pixelSize: 13; font.bold: true; font.family: Style.font; elide: Text.ElideRight
            }
            Text {
                id: ibody
                anchors { left: iapp.left; right: parent.right; rightMargin: 16; top: isum.bottom; topMargin: 3 }
                visible: !item.expanded && text !== ""
                text: item.n ? item.n.body : ""; color: Colors.fgPrimary
                font.pixelSize: 12; font.family: Style.font
                wrapMode: Text.WordWrap; textFormat: Text.PlainText
                maximumLineCount: 5; elide: Text.ElideRight
            }
            // Expanded stack: every notification of the group, newest first.
            Column {
                id: igroup
                visible: item.expanded
                anchors { left: iapp.left; right: parent.right; rightMargin: 16; top: iapp.bottom; topMargin: 1 }
                spacing: 10
                Repeater {
                    model: item.expanded ? item.modelData.items.slice().reverse() : []
                    delegate: Column {
                        required property var modelData
                        width: igroup.width
                        spacing: 3
                        Text {
                            width: parent.width
                            text: modelData.summary; color: Colors.fgBright
                            font.pixelSize: 13; font.bold: true; font.family: Style.font; elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: modelData.body; color: Colors.fgPrimary
                            font.pixelSize: 12; font.family: Style.font
                            wrapMode: Text.WordWrap; textFormat: Text.PlainText
                            maximumLineCount: 5; elide: Text.ElideRight
                        }
                    }
                }
            }
            // Group count badge — doubles as the expand hint on stacked cards
            Rectangle {
                id: badge
                visible: item.stacked
                anchors { right: idel.left; rightMargin: 6; verticalCenter: iapp.verticalCenter }
                width: cnt.implicitWidth + 12; height: 16; radius: 8
                color: Colors.bgActive
                Text { id: cnt; anchors.centerIn: parent
                       text: item.modelData.count + (item.expanded ? " ▴" : " ▾")
                       color: Colors.fgBright; font.pixelSize: 9; font.bold: true; font.family: Style.font }
            }
            Rectangle {
                id: idel
                anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 8 }
                width: 20; height: 20; radius: 10
                color: dHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 10 }
                MouseArea { id: dHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.dismissRow(item.modelData) }
            }
        }
    }
}
