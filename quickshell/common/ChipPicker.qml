import ".."
import QtQuick

// One chip that names the current choice and unfolds the rest beneath it.
//
// This exists because the first sound dashboard laid a card's profiles out as chips and a single
// device produced thirteen of them across four rows — the tile stopped being readable and the panel
// stopped looking designed. A long list of alternatives is a picker, not a row of buttons; only a
// short, meaningful set (a device's two or three ports) belongs on the surface.
Column {
    id: p
    property var    options: []          // [{ label, key, on }]
    property string placeholder: "—"
    property bool   open: false
    signal picked(string key)

    readonly property string summary: {
        var o = p.options
        for (var i = 0; i < o.length; i++) if (o[i].on) return "" + o[i].label
        return p.placeholder
    }

    width: parent ? parent.width : 0
    spacing: 4

    DataChip {
        ghost: true
        label: p.summary
        trailing: p.open ? "󰅃" : "󰅀"
        onTap: p.open = !p.open
    }

    Column {
        width: parent.width
        spacing: 2
        visible: p.open
        Repeater {
            model: p.open ? p.options : []
            delegate: StyledRect {
                id: opt
                required property var modelData
                width: parent.width
                height: 26
                radius: Style.rTile
                color: opt.modelData.on ? Style.tint(Colors.bgActive, 0.28)
                     : oh.containsMouse ? Style.controlHover : "transparent"
                Behavior on color { ColorAnimation { duration: 90 } }
                Text {
                    anchors { left: parent.left; leftMargin: 9; right: parent.right
                              rightMargin: 9; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: (opt.modelData.on ? "󰄬  " : "") + opt.modelData.label
                    color: opt.modelData.on ? Colors.fgBright : Colors.fgPrimary
                    font.family: Style.font; font.pixelSize: 11
                }
                MouseArea {
                    id: oh
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: { p.picked("" + opt.modelData.key); p.open = false }
                }
            }
        }
    }
}
