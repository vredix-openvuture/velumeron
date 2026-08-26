import "../.."
import QtQuick

// Shared workspace editor — used by the Workspaces settings section AND the onboarding wizard.
// Pure view: renders `rules` grouped per monitor and emits changed(newRules) for every edit;
// the owner persists (and the python helper re-validates the invariants).
//
// There is nothing to lay out here. Every monitor already owns one hundred workspaces by the
// block scheme (hypr.lua/modules/workspaces.lua): mon1 1-99, mon2 101-199, and SUPER+1…0 always
// means "slot n on the monitor I am looking at". So the only real decisions are HOW MANY of the
// slots stay alive when empty, WHICH one the session starts on, and what they are called. That
// is what this asks for — a count, a start slot and one name row each — instead of the old
// add/remove/pin/move list that made a fixed scheme look like free-form bookkeeping.
//
// System workspaces (10/90/99/111/112/1111) are never part of `rules` — the helper strips and
// preserves them.
Column {
    id: ed
    property var rules:    []   // [{workspace, monitor, persistent, default, default_name, layout}]
    property var monitors: []   // [{var, output}] from `get monitors`
    signal changed(var rules)

    width:   parent ? parent.width : 300
    spacing: 14

    // Slots 1-10 are the ones SUPER+1…0 can reach; a persistent workspace no key opens is a
    // workspace nobody visits.
    readonly property int maxSlots: 10

    // Which slot's glyph palette is open ("<monVar>:<slot>", "" = none).
    property string glyphFor: ""

    function baseOf(monVar) {
        var n = parseInt(("" + monVar).slice(3))
        return (isNaN(n) || n < 1) ? 0 : (n - 1) * 100
    }
    function slotOf(rule) { return parseInt(rule.workspace) - ed.baseOf(rule.monitor) }
    function _copy(r) { return Object.assign({}, r) }

    function rulesFor(mon) {
        return ed.rules.filter(function (r) { return r.monitor === mon })
    }
    // The count IS the highest configured slot, not the number of rules: a user who came from the
    // old free-form editor may have gaps (1, 3, 7), and reading that as "three" would silently
    // renumber their named workspaces.
    function countFor(mon) {
        var top = 0
        ed.rulesFor(mon).forEach(function (r) {
            var s = ed.slotOf(r)
            if (s > top && s <= ed.maxSlots) top = s
        })
        return Math.max(1, top)
    }
    function startFor(mon) {
        var found = 0
        ed.rulesFor(mon).forEach(function (r) { if (r["default"]) found = ed.slotOf(r) })
        return found > 0 ? found : 1
    }
    function ruleAt(mon, slot) {
        var id = String(ed.baseOf(mon) + slot)
        return ed.rules.find(function (r) { return r.monitor === mon && r.workspace === id }) || null
    }
    function nameAt(mon, slot) {
        var r = ed.ruleAt(mon, slot)
        return r ? (r.default_name || "") : ""
    }

    // Every edit rebuilds one monitor's block from (count, start, names) and leaves the other
    // monitors untouched. Names and per-workspace layouts survive a count change, so shrinking
    // and growing again is not destructive.
    function _rebuild(mon, count, start, nameOverride, nameSlot) {
        var base = ed.baseOf(mon)
        var kept = ed.rules.filter(function (r) { return r.monitor !== mon }).map(ed._copy)
        var out  = []
        for (var slot = 1; slot <= count; slot++) {
            var old = ed.ruleAt(mon, slot)
            var nm  = (nameSlot === slot) ? nameOverride : (old ? (old.default_name || "") : "")
            out.push({
                workspace:    String(base + slot),
                monitor:      mon,
                persistent:   true,
                "default":    slot === start,
                default_name: nm,
                layout:       old ? (old.layout || "") : ""
            })
        }
        ed.changed(kept.concat(out))
    }
    function setCount(mon, n) {
        var count = Math.max(1, Math.min(ed.maxSlots, n))
        ed._rebuild(mon, count, Math.min(ed.startFor(mon), count), "", -1)
    }
    function setStart(mon, slot) {
        var count = ed.countFor(mon)
        ed._rebuild(mon, count, Math.max(1, Math.min(count, slot)), "", -1)
    }
    function setName(mon, slot, value) {
        ed._rebuild(mon, ed.countFor(mon), ed.startFor(mon), value, slot)
    }

    Repeater {
        model: ed.monitors
        delegate: Column {
            id: monGroup
            required property var modelData
            readonly property string monVar: modelData.var
            readonly property int    count:  ed.countFor(monVar)
            readonly property int    start:  ed.startFor(monVar)
            width:   ed.width
            spacing: 8

            FieldLabel {
                text: monGroup.modelData.var + "  —  " + monGroup.modelData.output
                hint: "Each monitor owns one hundred workspaces: the first 1-99, the second "
                    + "101-199, and so on. SUPER+1…0 always means this monitor's slots, so the "
                    + "numbers below are slots, not ids. Persistent ones stay in the bar when "
                    + "empty; the rest appear as you use them."
            }

            Stepper {
                label: "Persistent workspaces"
                hint:  "How many workspaces stay alive on this monitor when nothing is open on them."
                value: monGroup.count
                min:   1
                max:   ed.maxSlots
                step:  1
                labelWidth: 150
                onChanged: v => ed.setCount(monGroup.monVar, v)
            }
            Stepper {
                label: "Start workspace"
                hint:  "The workspace this monitor shows right after login."
                value: monGroup.start
                min:   1
                max:   monGroup.count
                step:  1
                labelWidth: 150
                onChanged: v => ed.setStart(monGroup.monVar, v)
            }

            // One row per persistent slot: its number, a name, and the glyph palette behind the
            // icon button. Nothing else — the count above decides how many rows there are.
            Repeater {
                model: monGroup.count
                delegate: Column {
                    id: slotRow
                    required property int index
                    readonly property int slot: index + 1
                    readonly property string key: monGroup.monVar + ":" + slot
                    width:   monGroup.width
                    spacing: 4

                    Row {
                        width:   parent.width
                        spacing: 6

                        // The slot is what SUPER+n presses; the real id only matters to anyone
                        // reading `hyprctl workspaces`, so it stays small print.
                        Rectangle {
                            width: 34; height: 34; radius: Style.rTile
                            color: slotRow.slot === monGroup.start ? Style.selFill : Style.controlFill
                            border.width: slotRow.slot === monGroup.start ? Style.selBorderW
                                                                          : Style.controlBorderW
                            border.color: slotRow.slot === monGroup.start ? Style.selBorderColor
                                                                          : Style.controlBorderColor
                            Column {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: slotRow.slot
                                    color: slotRow.slot === monGroup.start ? Style.selText
                                                                           : Colors.fgBright
                                    font.pixelSize: 13; font.bold: true; font.family: Style.font
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: ed.baseOf(monGroup.monVar) > 0
                                    text: ed.baseOf(monGroup.monVar) + slotRow.slot
                                    color: Colors.fgMuted; font.pixelSize: 8; font.family: Style.font
                                }
                            }
                        }

                        InputField {
                            width: parent.width - 34 - 34 - (6 * 2)
                            text: ed.nameAt(monGroup.monVar, slotRow.slot)
                            placeholder: "name…"
                            onEdited: v => ed.setName(monGroup.monVar, slotRow.slot, v)
                        }
                        IconBtn {
                            glyph: "󰃀"; tip: "icon"
                            active: ed.glyphFor === slotRow.key
                            onTap: ed.glyphFor = (ed.glyphFor === slotRow.key ? "" : slotRow.key)
                        }
                    }

                    IconGlyphPicker {
                        width: parent.width
                        open: ed.glyphFor === slotRow.key
                        onPicked: g => {
                            ed.setName(monGroup.monVar, slotRow.slot, g)
                            ed.glyphFor = ""
                        }
                    }
                }
            }
        }
    }

    component IconBtn: Rectangle {
        property string glyph:  ""
        property string tip:    ""
        property bool   active: false
        signal tap()
        width: 34; height: 34; radius: Style.rTile
        color: active ? Style.selFill : (ibHov.containsMouse ? Style.controlHover : Style.controlFill)
        border.width: active ? Style.selBorderW : Style.controlBorderW
        border.color: active ? Style.selBorderColor : Style.controlBorderColor
        Text { anchors.centerIn: parent; text: glyph
               color: active ? Style.selText : Colors.fgMuted
               font.pixelSize: 14; font.family: Style.font }
        MouseArea { id: ibHov; anchors.fill: parent; hoverEnabled: true; onClicked: tap() }
    }
}
