import ".."
import QtQuick

// Inline-expanding glyph palette for workspace names: a curated nerd-font set plus
// "clear". Sits full-width under the row that toggles it (house style expands inline,
// like Dropdown — no popups). Emits picked(glyph); "" clears the name.
Flow {
    id: gp
    property bool open: false
    signal picked(string glyph)

    visible: open
    width:   parent ? parent.width : 200
    spacing: 4

    readonly property var glyphs: [
        "", "󰖟", "", "", "󰭹", "󰇮", "󰝚", "󰕧", "󰊴", "󰋩",
        "", "󰠮", "󰃭", "󰅐", "󰒱", "󰍩", "󰒋", "󰢹", "󰆼", "󰖳",
        "󰎆", "󰎈", "󰕼", "󰊤", "󰈹", "󰇩", "", "󰨞", "", "󰙯"
    ]

    Repeater {
        model: gp.glyphs
        delegate: Rectangle {
            required property string modelData
            width: 30; height: 30; radius: Style.rTile
            color: gHov.containsMouse ? Style.controlHover : Style.controlFill
            border.width: Style.controlBorderW; border.color: Style.controlBorderColor
            Text { anchors.centerIn: parent; text: modelData
                   color: Colors.fgPrimary; font.pixelSize: 15; font.family: Style.font }
            MouseArea { id: gHov; anchors.fill: parent; hoverEnabled: true
                        onClicked: { gp.picked(modelData); gp.open = false } }
        }
    }
    Rectangle {
        width: 52; height: 30; radius: Style.rTile
        color: cHov.containsMouse ? Style.controlHover : Style.controlFill
        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
        Text { anchors.centerIn: parent; text: "clear"
               color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font }
        MouseArea { id: cHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: { gp.picked(""); gp.open = false } }
    }
}
