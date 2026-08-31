pragma ComponentBehavior: Bound
import QtQuick

// Console's OSD is a readout, not a slider.
//
//   VOL  ██████████░░░░░░░░░░  48 %
//
// The bar is drawn out of block characters rather than as a rectangle, for the same reason the
// dashboard has no meters: on a screen made of type, a graphic next to a number is a second voice
// saying the same thing. The cell count is MEASURED against the card rather than fixed at twenty:
// the card is as wide as the user's OSD width setting, and a meter that assumed its own width ran
// straight off the edge of a narrow one.
//
// It also has to answer for the workspace banner. The shell hides its own OSD content the moment a
// theme brings one, so a theme that only knows volume and brightness turns every workspace change
// into "VOL 0 %".
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent    || "#b269e0"
    readonly property color ink:    root.pal.fgBright  || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted   || "#6b5480"

    readonly property int px: Math.round(Math.max(11, Math.min(15, root.height * 0.30)))
    readonly property int pad: Math.round(root.px * 1.2)
    readonly property bool isWorkspace: root.ctx.kind === "workspace"

    readonly property string label: root.ctx.kind === "brightness" ? "LUM"
                                  : root.ctx.muted ? "MUTE" : "VOL"

    // One cell of the meter, measured in the face actually being drawn — a block glyph is not
    // reliably 0.6 em, and guessing is what put the meter over the edge of a narrow card.
    TextMetrics {
        id: cell
        font.family: root.font
        font.pixelSize: root.px
        text: "█"
    }
    readonly property real meterSpace: Math.max(0, root.width - root.pad * 2
                                                - labelT.width - percentT.width
                                                - Math.round(root.px * 0.9) * 2)
    readonly property int cells: Math.max(4, Math.min(20,
        cell.advanceWidth > 0 ? Math.floor(root.meterSpace / cell.advanceWidth) : 20))
    readonly property int filled: Math.round(Math.max(0, Math.min(1, root.ctx.level || 0)) * root.cells)

    Row {
        visible: !root.isWorkspace
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: root.pad; rightMargin: root.pad }
        spacing: Math.round(root.px * 0.9)

        Text {
            id: labelT
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(root.px * 3.2)
            text: root.label
            color: root.ctx.muted ? root.faint : root.accent
            font.family: root.font; font.pixelSize: root.px
            font.letterSpacing: root.px * 0.12
        }
        Text {
            id: meter
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var on = "", off = ""
                for (var i = 0; i < root.filled; i++) on += "█"
                for (var j = root.filled; j < root.cells; j++) off += "░"
                return on + off
            }
            color: root.ctx.muted ? root.faint : root.ink
            font.family: root.font; font.pixelSize: root.px
        }
        Text {
            id: percentT
            anchors.verticalCenter: parent.verticalCenter
            text: (root.ctx.percent !== undefined ? root.ctx.percent : 0) + " %"
            color: root.ink
            font.family: root.font; font.pixelSize: root.px
            horizontalAlignment: Text.AlignRight
        }
    }

    // The workspace banner: every slot THIS monitor has, the one you are on inverted, and its name
    // beside them. One number alone in the middle of a 300 px card is a lot of empty screen saying
    // very little; the row says where you are among where you could be, which is what a workspace
    // switch is about — and it is the same block the bar draws, so a switch reads the same in both
    // places.
    Row {
        visible: root.isWorkspace
        anchors.centerIn: parent
        spacing: Math.round(root.px * 0.55)

        Repeater {
            model: root.ctx.workspaces || []
            delegate: Rectangle {
                id: slot
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(root.px * 1.5, slotT.implicitWidth + root.px * 0.8)
                height: Math.round(root.px * 1.8)
                color: slot.modelData.focused ? root.accent : "transparent"
                Text {
                    id: slotT
                    anchors.centerIn: parent
                    text: "" + slot.modelData.slot
                    color: slot.modelData.focused ? (root.pal.bgPrimary || "#040207")
                         : slot.modelData.occupied ? root.ink : root.faint
                    font.family: root.font; font.pixelSize: root.px
                    font.bold: slot.modelData.focused
                }
            }
        }
        Item { width: Math.round(root.px * 0.6); height: 1 }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: (root.ctx.workspace && root.ctx.workspace.name
                   && root.ctx.workspace.name !== ("" + root.ctx.workspace.slot)
                   && root.ctx.workspace.name !== ("" + root.ctx.workspace.id))
                  ? root.ctx.workspace.name : ""
            color: root.ink
            // A workspace name is whatever hyprland.lua called it, and here they are Nerd Font
            // glyphs — which a mono face does not have, so a name like that drew the missing-glyph
            // box. Anything outside plain ASCII is therefore set in the glyph font. (`font.families`
            // would be the tidy answer and does not exist on Text in this Qt.)
            font.family: /^[\x20-\x7e]*$/.test(text) ? root.font
                                                      : (root.ctx.iconFont || root.font)
            font.pixelSize: root.px
            font.letterSpacing: root.px * 0.08
        }
    }

    // The active sink, when the shell says to show it. One line, no second card.
    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom
                  bottomMargin: Math.round(root.px * 0.4) }
        visible: !root.isWorkspace && (root.ctx.device || "") !== ""
        width: parent.width - root.px * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.ctx.device || ""
        color: root.faint
        font.family: root.font; font.pixelSize: Math.round(root.px * 0.82)
    }
}
