import ".."
import QtQuick

// Inline-expanding dropdown. `options` = [{ label, key, on }]; emits picked(key).
// An option may carry `swatch: "<Colors role>"` (e.g. "bgActive") to show that palette colour as a
// chip before its label — for pickers whose choice IS a colour. Omit it and nothing is drawn.
Column {
    id: dd
    property var    options: []
    property string summary: ""
    property bool   open:    false
    // `multi: true` stays open after a pick, so several options can be toggled in one go (the
    // caller drives the checkmarks through each option's `on`). Single-select closes on pick.
    property bool   multi:   false
    signal picked(string key)
    width:   parent ? parent.width : 0
    spacing: 4

    StyledRect {
        width: parent.width; height: Style.ctrlH; radius: Style.rControl
        color: ddHov.containsMouse ? Style.controlHover : Style.controlFill
        borderWidth: dd.open ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
        borderColor: dd.open ? Style.accent : Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        Text {
            anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text: dd.summary; color: Colors.fgPrimary; elide: Text.ElideRight
            font.pixelSize: Style.fsLabel; font.family: Style.font
        }
        Text { id: chev
               anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
               text: dd.open ? "▴" : "▾"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
        MouseArea { id: ddHov; anchors.fill: parent; hoverEnabled: true; onClicked: dd.open = !dd.open }
    }

    Column {
        visible: dd.open
        width: parent.width; spacing: 3
        Repeater {
            model: dd.options
            delegate: StyledRect {
                required property var modelData
                width: dd.width; height: 30; radius: Style.rTile
                color: modelData.on ? Style.selFill
                     : (oHov.containsMouse ? Style.controlHover : Style.controlFill)
                borderWidth: modelData.on ? Style.selBorderW : Style.controlBorderW
                borderColor: modelData.on ? Style.selBorderColor : Style.controlBorderColor
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                Row {
                    anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 30
                              verticalCenter: parent.verticalCenter }
                    spacing: 8
                    readonly property string swatchRole: modelData.swatch !== undefined ? "" + modelData.swatch : ""
                    StyledRect {
                        visible: parent.swatchRole !== "" && Colors[parent.swatchRole] !== undefined
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14; height: 14; radius: Math.min(4, Style.rTile)
                        color: visible ? Colors[parent.swatchRole] : "transparent"
                        borderWidth: 1; borderColor: Style.tint(Colors.fgBright, 0.25)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label; color: modelData.on ? Style.selText : Colors.fgPrimary
                        font.pixelSize: 12; font.family: Style.font
                        elide: Text.ElideRight
                    }
                }
                Text { visible: modelData.on
                       anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                       text: "✓"; color: Style.selText; font.pixelSize: 12; font.family: Style.font }
                MouseArea { id: oHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: { dd.picked(modelData.key); if (!dd.multi) dd.open = false } }
            }
        }
    }
}
