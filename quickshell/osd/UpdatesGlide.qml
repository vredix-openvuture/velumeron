import ".."
import QtQuick

// Available-package list gliding out of the bar on hover of the Updates module (which publishes the
// list + total into UiState). Scrollable, laid out as an aligned three-column table
// (name · current · new) with no separators. keepOpenOnHover so the cursor can rest on and scroll the
// pill. One per screen.
BarGlide {
    glideId: "updates"
    id: g
    mine:            UiState.updMon === g.mon && g.mon !== ""
    shown:           UiState.updHover
    edge:            UiState.updEdge
    anchorX:         UiState.updAnchorX
    anchorY:         UiState.updAnchorY
    keepOpenOnHover: true

    readonly property int _maxH: 360

    // Flatten "name old -> new" lines into grid cells [name, old, new, name, old, new, …]. Lines
    // without a "->" (e.g. flatpak ids) fall back to name-only.
    readonly property var _cells: {
        var out = [], l = UiState.updList
        for (var i = 0; i < l.length; i++) {
            var s = "" + l[i]
            var m = s.match(/^(\S+)\s+(.*?)\s+->\s+(.*)$/)
            if (m) out.push(m[1], m[2], m[3])
            else   out.push(s, "", "")
        }
        return out
    }
    readonly property int _rows: Math.round(_cells.length / 3)

    Column {
        spacing: 8

        Text {
            text:           "Verfügbare Updates · " + UiState.updTotal
            color:          Colors.fgMuted
            font.family:    Style.font
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
        }

        Flickable {
            id: flick
            width:  grid.implicitWidth
            height: Math.min(grid.implicitHeight, g._maxH)
            contentWidth:  grid.implicitWidth
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // Mouse wheel → scroll (Flickable only flicks on drag by default).
            WheelHandler {
                onWheel: e => {
                    var max = Math.max(0, flick.contentHeight - flick.height)
                    flick.contentY = Math.max(0, Math.min(max, flick.contentY - e.angleDelta.y))
                }
            }

            Grid {
                id: grid
                columns: 3
                rowSpacing: 4
                columnSpacing: 18
                Repeater {
                    model: g._cells
                    delegate: Text {
                        required property var modelData
                        required property int index
                        text:  "" + modelData
                        color: (index % 3 === 0) ? Colors.fgPrimary       // name
                             : (index % 3 === 1) ? Colors.fgMuted         // current version
                                                 : Colors.boActive        // new version
                        font.family:    Style.font
                        font.pixelSize: 12
                        font.weight:    (index % 3 === 0) ? Font.Medium : Font.Normal
                    }
                }
            }
        }

        Text {
            visible:        UiState.updTotal > g._rows
            text:           "+" + (UiState.updTotal - g._rows) + " weitere"
            color:          Colors.fgMuted
            font.family:    Style.font
            font.pixelSize: 11
        }
    }
}
