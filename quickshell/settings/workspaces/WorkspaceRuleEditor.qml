import "../.."
import QtQuick

// Shared workspace-rule editor — used by the Workspaces settings section AND the onboarding
// wizard. Pure view: renders `rules` grouped per monitor and emits changed(newRules) for
// every edit; the owner persists (and the python helper re-validates the invariants).
// System workspaces (10/90/99/111/112/1111) are never part of `rules` — the helper strips
// and preserves them.
Column {
    id: ed
    property var rules:    []   // [{workspace, monitor, persistent, default, default_name, layout}]
    property var monitors: []   // [{var, output}] from `get monitors`
    signal changed(var rules)

    width:   parent ? parent.width : 300
    spacing: 14

    // Which rule's glyph palette is open (workspace number, "" = none).
    property string glyphFor: ""

    function _copy(r) { return Object.assign({}, r) }
    function upd(ws, patch) {
        ed.changed(ed.rules.map(function (r) {
            return r.workspace === ws ? Object.assign(ed._copy(r), patch) : ed._copy(r)
        }))
    }
    // Default is a radio per monitor: setting one clears the others on that monitor.
    function setDefault(ws, mon) {
        ed.changed(ed.rules.map(function (r) {
            var c = ed._copy(r)
            if (c.monitor === mon) c["default"] = (c.workspace === ws)
            return c
        }))
    }
    function remove(ws) {
        ed.changed(ed.rules.filter(function (r) { return r.workspace !== ws })
                           .map(ed._copy))
    }
    function moveToNext(ws) {
        var vars = ed.monitors.map(function (m) { return m.var })
        if (vars.length < 2) return
        var r = ed.rules.find(function (x) { return x.workspace === ws })
        var next = vars[(vars.indexOf(r.monitor) + 1) % vars.length]
        ed.upd(ws, { monitor: next, "default": false })
    }
    function add(mon) {
        var used = {}
        ed.rules.forEach(function (r) { used[r.workspace] = true })
        var reserved = { "10": 1, "90": 1, "99": 1, "111": 1, "112": 1, "1111": 1 }
        var n = 1
        while (used[String(n)] || reserved[String(n)]) n++
        ed.changed(ed.rules.map(ed._copy).concat([{
            workspace: String(n), monitor: mon, persistent: true,
            "default": false, default_name: "", layout: ""
        }]))
    }
    function rulesFor(mon) {
        return ed.rules.filter(function (r) { return r.monitor === mon })
                       .sort(function (a, b) { return parseInt(a.workspace) - parseInt(b.workspace) })
    }

    Repeater {
        model: ed.monitors
        delegate: Column {
            id: monGroup
            required property var modelData
            width:   ed.width
            spacing: 6

            FieldLabel { text: modelData.var + "  —  " + modelData.output }

            Repeater {
                model: ed.rulesFor(monGroup.modelData.var)
                delegate: Column {
                    id: ruleRow
                    required property var modelData
                    width:   monGroup.width
                    spacing: 4

                    Row {
                        width:   parent.width
                        spacing: 6

                        // Workspace number
                        Rectangle {
                            width: 34; height: 34; radius: Style.rTile
                            color: Style.controlFill
                            border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                            Text { anchors.centerIn: parent; text: ruleRow.modelData.workspace
                                   color: Colors.fgBright; font.pixelSize: 13; font.bold: true
                                   font.family: Style.font }
                        }

                        // Name / icon
                        InputField {
                            width: parent.width - 34 - (34 * 4) - (6 * 5) - (ed.monitors.length > 1 ? 40 : 0)
                            text: ruleRow.modelData.default_name
                            placeholder: "name…"
                            onEdited: v => ed.upd(ruleRow.modelData.workspace, { default_name: v })
                        }
                        IconBtn {
                            glyph: "󰃀"; tip: "icon"
                            active: ed.glyphFor === ruleRow.modelData.workspace
                            onTap: ed.glyphFor = (ed.glyphFor === ruleRow.modelData.workspace
                                                  ? "" : ruleRow.modelData.workspace)
                        }

                        // Persistent pin
                        IconBtn {
                            glyph: "󰐃"; tip: "persistent"
                            active: ruleRow.modelData.persistent
                            onTap: ed.upd(ruleRow.modelData.workspace,
                                          { persistent: !ruleRow.modelData.persistent })
                        }
                        // Default radio (one per monitor)
                        IconBtn {
                            glyph: ruleRow.modelData["default"] ? "◉" : "○"; tip: "default"
                            active: ruleRow.modelData["default"]
                            onTap: ed.setDefault(ruleRow.modelData.workspace, ruleRow.modelData.monitor)
                        }
                        // Move to the other monitor
                        IconBtn {
                            visible: ed.monitors.length > 1
                            width: 34
                            glyph: "⇄"; tip: "move"
                            onTap: ed.moveToNext(ruleRow.modelData.workspace)
                        }
                        // Remove
                        IconBtn {
                            glyph: "✕"; tip: "remove"; danger: true
                            onTap: ed.remove(ruleRow.modelData.workspace)
                        }
                    }

                    IconGlyphPicker {
                        width: parent.width
                        open: ed.glyphFor === ruleRow.modelData.workspace
                        onPicked: g => {
                            ed.upd(ruleRow.modelData.workspace, { default_name: g })
                            ed.glyphFor = ""
                        }
                    }
                }
            }

            TextButton { label: "+ Add workspace"; onClicked: ed.add(monGroup.modelData.var) }
        }
    }

    SubLabel {
        width: parent.width
        text: "󰐃 keeps the workspace alive when empty · ◉ marks the monitor's start workspace. "
            + "Workspaces 10/90/99/111/112/1111 are managed by the system and stay hidden here."
    }

    component IconBtn: Rectangle {
        property string glyph:  ""
        property string tip:    ""
        property bool   active: false
        property bool   danger: false
        signal tap()
        width: 34; height: 34; radius: Style.rTile
        color: active ? Style.selFill
             : (ibHov.containsMouse ? (danger ? Style.tint(Colors.fgUrgent, 0.25) : Style.controlHover)
                                    : Style.controlFill)
        border.width: active ? Style.selBorderW : Style.controlBorderW
        border.color: active ? Style.selBorderColor : Style.controlBorderColor
        Text { anchors.centerIn: parent; text: glyph
               color: active ? Style.selText : Colors.fgMuted
               font.pixelSize: 14; font.family: Style.font }
        MouseArea { id: ibHov; anchors.fill: parent; hoverEnabled: true; onClicked: tap() }
    }
}
