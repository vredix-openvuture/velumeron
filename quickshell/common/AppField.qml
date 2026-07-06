import ".."
import QtQuick
import Quickshell

// Command input with app suggestions from DesktopEntries: type to filter installed
// apps, pick one to insert its launch command, or keep free text. Emits committed(v)
// on Enter / focus loss / suggestion pick.
Column {
    id: af
    property string value: ""
    property string placeholder: "command…"
    property int maxSuggestions: 5
    signal committed(string v)

    width:   parent ? parent.width : 200
    spacing: 3

    onValueChanged: if (!input.activeFocus) input.text = value

    function _commit(v) {
        input.text = v
        af.value = v
        af.committed(v)
    }

    // Launch command for a desktop entry: execString minus %-field codes, falling
    // back to the entry id (repo QML otherwise only uses .execute(), see Launcher).
    readonly property var matches: {
        if (!input.activeFocus) return []
        var q = input.text.trim().toLowerCase()
        if (q === "") return []
        var apps = DesktopEntries.applications
        var list = (apps && apps.values !== undefined) ? apps.values : (apps || [])
        var out = []
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (!e || e.noDisplay) continue
            var n = e.name || ""
            var cmd = ("" + (e.execString || "")).replace(/ ?%[a-zA-Z]/g, "").trim()
            if (cmd === "") cmd = e.id || n
            if (n.toLowerCase().indexOf(q) >= 0 || cmd.toLowerCase().indexOf(q) >= 0)
                out.push({ name: n, cmd: cmd })
        }
        out.sort(function (a, b) { return a.name.localeCompare(b.name) })
        return out.slice(0, af.maxSuggestions)
    }

    StyledRect {
        width:        parent.width
        height:       34
        radius:       Style.rControl
        color:        Style.controlFill
        borderWidth:  input.activeFocus ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
        borderColor:  input.activeFocus ? Style.accent : Style.controlBorderColor

        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
            clip: true; selectByMouse: true
            text: af.value
            onEditingFinished: if (text !== af.value) { af.value = text; af.committed(text) }

            Text {
                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                visible: input.text === "" && !input.activeFocus
                text: af.placeholder; color: Colors.fgMuted; font: input.font; elide: Text.ElideRight
            }
        }
    }

    Column {
        visible: af.matches.length > 0
        width:   parent.width
        spacing: 2
        Repeater {
            model: af.matches
            delegate: StyledRect {
                required property var modelData
                width: af.width; height: 28; radius: Style.rTile
                color: sHov.containsMouse ? Style.controlHover : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Text {
                    anchors { left: parent.left; leftMargin: 12; right: cmdT.left; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    text: modelData.name; color: Colors.fgPrimary
                    font.pixelSize: 12; font.family: Style.font; elide: Text.ElideRight
                }
                Text {
                    id: cmdT
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: modelData.cmd; color: Colors.fgMuted
                    font.pixelSize: 10; font.family: Style.font
                    elide: Text.ElideMiddle; width: Math.min(implicitWidth, af.width * 0.45)
                }
                MouseArea {
                    id: sHov
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: { af._commit(modelData.cmd); input.focus = false }
                }
            }
        }
    }
}
