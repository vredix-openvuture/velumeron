import ".."
import QtQuick
import Quickshell
import Quickshell.Widgets

// Reusable notification history list (used by the centre and the settings page). When `grouped`
// is on, notifications from the same app collapse into one card showing the latest + a count.
Item {
    id: root
    property bool grouped: VtlConfig.notifyGroup

    // Recompute display rows from the tracked history whenever it changes.
    readonly property var src: NotifService.model ? NotifService.model.values : []
    readonly property var rows: {
        var vs = root.src, out
        if (!root.grouped) {
            out = vs.map(function (n) { return { app: n.appName || "", latest: n, count: 1, items: [n] } })
        } else {
            var byApp = {}, order = []
            for (var i = 0; i < vs.length; i++) {
                var a = vs[i].appName || ""
                if (!byApp[a]) { byApp[a] = { app: a, latest: vs[i], count: 0, items: [] }; order.push(a) }
                byApp[a].items.push(vs[i])
                byApp[a].count++
                byApp[a].latest = vs[i]   // last seen wins as the representative
            }
            out = order.map(function (a) { return byApp[a] })
        }
        // Pinned rows float to the top (stable order within each partition). Touch
        // NotifService.pinned so this rebinds the moment a pin is toggled.
        var _pins = NotifService.pinned
        out.forEach(function (r) { r.pinned = NotifService.isPinned(r.latest) })
        return out.filter(function (r) { return r.pinned })
             .concat(out.filter(function (r) { return !r.pinned }))
    }
    // Count of leading pinned rows → the index where the pinned/others divider is drawn.
    readonly property int pinnedCount: {
        var c = 0
        for (var i = 0; i < root.rows.length; i++) if (root.rows[i].pinned) c++
        return c
    }

    function dismissRow(row) { for (var i = 0; i < row.items.length; i++) row.items[i].dismiss() }

    // Go to whatever wants attention: the app's default action if it published one, plus focus on
    // its window (NotifService.activate). Closing the centre is part of the job, not a courtesy —
    // it is an overlay, so leaving it up would cover the very window we just brought forward.
    // Dismisses the entry afterwards, matching how clicking a toast behaves.
    function openNotif(n) {
        if (!NotifService.activate(n)) return
        UiState.notifCenterOpen = false
        if (n.dismiss) n.dismiss()
    }

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
        text:   Wording.s("notif.empty")
        color:  Colors.fgMuted; font.pixelSize: 13; font.family: Style.font
    }

    ListView {
        id: list
        anchors.fill: parent
        clip:    true
        spacing: 8
        model:   root.rows

        delegate: Column {
            id: rowWrap
            required property var modelData
            required property int index
            width: ListView.view.width
            spacing: 8

            // Divider between the pinned block and the rest — drawn above the first
            // un-pinned row, only when there actually are pinned rows above it.
            Item {
                width: parent.width
                visible: rowWrap.index === root.pinnedCount && root.pinnedCount > 0
                height: visible ? 15 : 0
                Rectangle {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: 1; color: Style.tint(Colors.boNormal, 0.6)
                }
            }

            StyledRect {
            id: item
            readonly property var modelData: rowWrap.modelData
            readonly property var n: modelData.latest
            readonly property bool stacked:  modelData.count > 1
            readonly property bool expanded: stacked && root.expandedApps[modelData.app] === true
            readonly property bool pinnedRow: item.modelData.pinned === true
            width:  parent.width
            radius:      Style.rControl
            clip:        true
            // The module-pill fill, translucent like the bar. A PINNED card wears the plate — it is
            // the one row here that is deliberately kept, so it is the one that gets a surface,
            // the way the active strip does on the sound desk and the connected row does in the
            // network list. Everything else is a lighter card.
            // Lighter than they were: these sit ON a plate now, and a card at full module opacity
            // inside a surface reads as a box in a box. Pinned still wears the full plate — it is
            // the one row here you deliberately kept.
            color:       item.pinnedRow ? Style.rowActive
                       : cardMa.containsMouse ? Style.rowHover
                       : Style.rowFill
            borderWidth: 0
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }

            // A row is wide, so its mark is a bar down the left rather than a rule across the top.
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                          topMargin: 8; bottomMargin: 8 }
                width: 3; radius: 2
                color: Style.accent
                opacity: item.pinnedRow ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130 } }
            }
            implicitHeight: item.expanded ? igroup.y + igroup.implicitHeight + 14
                                          : Math.max(54, ibody.y + ibody.implicitHeight + 14)

            // Whole-card click: a stacked card expands/collapses; a single card opens its default
            // action (✕ sits on top and keeps priority for dismiss).
            MouseArea {
                id: cardMa
                anchors.fill: parent
                hoverEnabled: true
                // Clickable whenever there is a card: a single one now goes to the sender's window
                // even without a default action, so keying the cursor on `actions` under-sold it.
                cursorShape: Qt.PointingHandCursor
                onClicked: item.stacked ? root.toggleExpand(item.modelData.app)
                                        : root.openNotif(item.n)
            }

            // App icon — the notification's own image/icon hint, else the sending app's desktop-entry
            // icon (NotifService.iconFor); a generic bell glyph when nothing resolves. Mirrors the toast.
            Item {
                id: iico
                anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 13 }
                width: 24; height: 24
                IconImage {
                    id: iicoImg
                    anchors.fill: parent
                    visible: source != ""
                    source: NotifService.iconFor(item.n)
                }
                Text {
                    anchors.centerIn: parent; visible: !iicoImg.visible
                    text: "󰂚"; color: Colors.fgMuted; font.pixelSize: 18; font.family: Style.iconFont
                }
            }

            // Source header — accent-coloured upper-cased label + a soft rule, so the service the
            // notification came from reads as a distinct heading above the message (matches the popup).
            Text {
                id: iapp
                anchors { left: iico.right; right: badge.left; top: parent.top
                          leftMargin: 10; rightMargin: 8; topMargin: 14 }
                text: item.n ? item.n.appName : ""; color: Colors.bgActive
                font.pixelSize: 10; font.family: Style.font; elide: Text.ElideRight
                font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
            }
            Rectangle {
                id: iappRule
                visible: iapp.text !== ""
                anchors { left: iapp.left; right: parent.right; rightMargin: 18
                          top: iapp.bottom; topMargin: 5 }
                height: 1
                color: Style.tint(Colors.boNormal, 0.55)
            }
            Text {
                id: isum
                visible: !item.expanded
                anchors { left: iapp.left; right: idel.left; rightMargin: 8
                          top: iappRule.visible ? iappRule.bottom : iapp.bottom; topMargin: iappRule.visible ? 6 : 1 }
                text: item.n ? item.n.summary : ""; color: Colors.fgBright
                font.pixelSize: 13; font.bold: true; font.family: Style.font; elide: Text.ElideRight
            }
            Text {
                id: ibody
                anchors { left: iapp.left; right: parent.right; rightMargin: 16; top: isum.bottom; topMargin: 3 }
                visible: !item.expanded && text !== ""
                text: item.n ? item.n.body : ""; color: Colors.fgPrimary
                font.pixelSize: 12; font.family: Style.font
                // StyledText, not PlainText: the notification spec lets a body carry a small markup
                // subset (<b> <i> <u> <a>), and PlainText printed the tags themselves — the
                // screenshot notification read "saved in <i>/home/…</i>". Rendering it is what the
                // sender asked for.
                wrapMode: Text.WordWrap; textFormat: Text.StyledText
                maximumLineCount: 5; elide: Text.ElideRight
            }
            // Expanded stack: every notification of the group, newest first.
            Column {
                id: igroup
                visible: item.expanded
                anchors { left: iapp.left; right: parent.right; rightMargin: 16
                          top: iappRule.visible ? iappRule.bottom : iapp.bottom; topMargin: iappRule.visible ? 6 : 1 }
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
                            wrapMode: Text.WordWrap; textFormat: Text.StyledText
                            maximumLineCount: 5; elide: Text.ElideRight
                        }
                    }
                }
            }
            // Group count badge — doubles as the expand hint on stacked cards
            StyledRect {
                id: badge
                visible: item.stacked
                anchors { right: ipin.left; rightMargin: 6; verticalCenter: iapp.verticalCenter }
                width: cnt.implicitWidth + 12; height: 16; radius: 8
                color: Colors.bgActive
                Text { id: cnt; anchors.centerIn: parent
                       text: item.modelData.count + (item.expanded ? " ▴" : " ▾")
                       color: Colors.fgBright; font.pixelSize: 9; font.bold: true; font.family: Style.font }
            }
            // Pin toggle — pinned rows float to the top and survive "clear all".
            StyledRect {
                id: ipin
                readonly property bool on: item.n ? NotifService.isPinned(item.n) : false
                anchors { right: idel.left; top: parent.top; rightMargin: 6; topMargin: 10 }
                width: 20; height: 20; radius: 10
                color: pHov.containsMouse ? Style.tint(Colors.bgActive, 0.25)
                     : (ipin.on ? Style.tint(Colors.bgActive, 0.18) : "transparent")
                Text { anchors.centerIn: parent; text: "󰐃"
                       color: ipin.on ? Colors.bgActive : Colors.fgMuted
                       font.pixelSize: 11; font.family: Style.iconFont }
                MouseArea { id: pHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: NotifService.togglePin(item.n) }
            }
            StyledRect {
                id: idel
                anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 10 }
                width: 20; height: 20; radius: 10
                color: dHov.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted; font.pixelSize: 10 }
                MouseArea { id: dHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.dismissRow(item.modelData) }
            }
            }
        }
    }
}
