import ".."
import QtQuick
import Quickshell.Widgets

// Recent-notifications peek gliding out of the bar on hover of the notification bell (which publishes
// its anchor into UiState). Hover preview only — clicking the bell opens the full notification centre,
// which supersedes this. keepOpenOnHover so the cursor can rest on the pill. One per screen.
BarGlide {
    id: g
    mine:            UiState.npkMon === g.mon && g.mon !== ""
    shown:           UiState.npkHover && !UiState.notifCenterOpen
    edge:            UiState.npkEdge
    anchorX:         UiState.npkAnchorX
    anchorY:         UiState.npkAnchorY
    keepOpenOnHover: true

    // Most recent first — trackedNotifications appends chronologically, so reverse the tail.
    readonly property var _recent: {
        var m = NotifService.model ? NotifService.model.values : []
        return m.slice().reverse().slice(0, 4)
    }

    Column {
        spacing: 8

        Text {
            text:           "Benachrichtigungen"
            color:          Colors.fgMuted
            font.family:    Style.font
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
        }

        Text {
            visible:        g._recent.length === 0
            text:           "Keine Benachrichtigungen"
            color:          Colors.fgMuted
            font.italic:    true
            font.family:    Style.font
            font.pixelSize: 13
        }

        Repeater {
            model: g._recent
            delegate: Row {
                id: nRow
                required property var modelData
                spacing: 10
                readonly property string _icon: NotifService.iconFor(nRow.modelData)

                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; implicitSize: 26
                    visible: source !== ""
                    source: nRow._icon
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: 260; elide: Text.ElideRight
                        text:           nRow.modelData.summary || nRow.modelData.appName || "Benachrichtigung"
                        color:          Colors.fgBright
                        font.family:    Style.font
                        font.pixelSize: 13
                        font.weight:    Font.Medium
                    }
                    Text {
                        visible:        text !== ""
                        width: 260; elide: Text.ElideRight
                        text:           (nRow.modelData.body || "").replace(/\n/g, " ")
                        color:          Colors.fgPrimary
                        font.family:    Style.font
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
