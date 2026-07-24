import ".."
import QtQuick
import Quickshell
import Quickshell.Widgets

// Windows-on-this-workspace preview gliding out of the bar on hover of a workspace dot (which
// publishes the hovered workspace id + anchor into UiState). Informational; keepOpenOnHover so the
// cursor can rest on the pill. One per screen.
BarGlide {
    id: g
    mine:            UiState.wsMon === g.mon && g.mon !== ""
    shown:           UiState.wsHover
    edge:            UiState.wsEdge
    anchorX:         UiState.wsAnchorX
    anchorY:         UiState.wsAnchorY
    keepOpenOnHover: true

    // Open windows living on the hovered workspace (Hyprland ids are global, so the id alone is
    // enough — no monitor filter needed).
    readonly property var _wins: {
        var out = []
        var ws = Hyprwindows.windows
        for (var i = 0; i < ws.length; i++)
            if (ws[i].workspace === UiState.wsPreviewId) out.push(ws[i])
        return out
    }

    Column {
        spacing: 6

        Text {
            text:           "Workspace " + UiState.wsPreviewId
            color:          Colors.fgMuted
            font.family:    Style.font
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
        }

        Text {
            visible:        g._wins.length === 0
            text:           "leer"
            color:          Colors.fgMuted
            font.family:    Style.font
            font.italic:    true
            font.pixelSize: 13
        }

        Repeater {
            model: g._wins.slice(0, 8)
            delegate: Row {
                id: winRow
                required property var modelData
                spacing: 8
                readonly property var _e: DesktopEntries.heuristicLookup(winRow.modelData.cls || "")

                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; implicitSize: 18
                    visible: source !== ""
                    source: (winRow._e && winRow._e.icon)
                            ? Quickshell.iconPath(winRow._e.icon, "application-x-executable") : ""
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text:           (winRow.modelData.title || winRow.modelData.cls || "Fenster").slice(0, 42)
                    color:          winRow.modelData.focused ? Colors.fgBright : Colors.fgPrimary
                    font.family:    Style.font
                    font.pixelSize: 13
                }
            }
        }

        Text {
            visible:        g._wins.length > 8
            text:           "+" + (g._wins.length - 8) + " weitere"
            color:          Colors.fgMuted
            font.family:    Style.font
            font.pixelSize: 11
        }
    }
}
