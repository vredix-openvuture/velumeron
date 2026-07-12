import "../.."
import QtQuick

// Window rules: which apps open floating / transparent. The user works with app chips —
// type a name or pick one of the currently open windows (matching runs on the window
// class); the `(.*[Kk]itty.*|…)` regex behind it is composed and parsed here and never
// shown. Fragments the parser doesn't recognize survive as raw chips, so hand-written
// patterns are kept intact. Apply writes the WINDOWRULES section and reloads Hyprland.
Item {
    id: root

    // Token: { label, raw } — label "" means an unrecognized raw fragment (shown as-is).
    property var    floatingTokens: []
    property var    opacityTokens:  []
    property bool   dirty:  false
    property string status: ""

    // ── regex ⇄ chips ─────────────────────────────────────────────────────────
    // Split "(a|b|c)" into fragments at paren-depth 0.
    function _fragments(pattern) {
        var p = ("" + pattern).trim()
        if (p === "") return []
        if (p.startsWith("(") && p.endsWith(")")) p = p.slice(1, -1)
        var out = [], depth = 0, cur = ""
        for (var i = 0; i < p.length; i++) {
            var ch = p[i]
            if (ch === "(") depth++
            if (ch === ")") depth--
            if (ch === "|" && depth === 0) { out.push(cur); cur = "" }
            else cur += ch
        }
        if (cur !== "") out.push(cur)
        return out.filter(function (f) { return f.trim() !== "" })
    }
    function _fragToToken(f) {
        var m = f.match(/^\.\*\[([A-Za-z])([A-Za-z])\]([A-Za-z0-9._ -]*)\.\*$/)
        if (m && m[1].toUpperCase() === m[2].toUpperCase())
            return { label: m[2].toLowerCase() + m[3], raw: f }
        m = f.match(/^\.\*([A-Za-z0-9._ -]+)\.\*$/)
        if (m) return { label: m[1], raw: f }
        return { label: "", raw: f }
    }
    function _nameToFrag(name) {
        var n = ("" + name).trim()
        if (/^[A-Za-z][A-Za-z0-9._ -]*$/.test(n))
            return ".*[" + n[0].toUpperCase() + n[0].toLowerCase() + "]" + n.slice(1) + ".*"
        return n   // anything regex-flavoured passes through verbatim
    }
    function parseTokens(pattern) { return root._fragments(pattern).map(root._fragToToken) }
    function compose(tokens) {
        if (tokens.length === 0) return ""
        return "(" + tokens.map(function (t) { return t.raw }).join("|") + ")"
    }

    // ── load / save ───────────────────────────────────────────────────────────
    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() {
        UserSettings.get("windowrules", function (d) {
            if (!d) return
            root.floatingTokens = root.parseTokens(d.floating_window || "")
            root.opacityTokens  = root.parseTokens(d.opacity_window || "")
            root.dirty = false
            root.status = ""
        })
    }
    function apply() {
        root.status = "Applying…"
        UserSettings.set("windowrules", {
            floating_window: root.compose(root.floatingTokens),
            opacity_window:  root.compose(root.opacityTokens)
        })
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "windowrules") return
            root.status = ok ? "Applied ✓" : ("" + (errors[0] || "Failed"))
            if (ok) root.dirty = false
        }
    }

    function addToken(group, name) {
        var n = ("" + name).trim()
        if (n === "") return
        var frag = root._nameToFrag(n)
        var list = (group === "floating" ? root.floatingTokens : root.opacityTokens)
        if (list.some(function (t) { return t.raw === frag })) return
        list = list.concat([root._fragToToken(frag)])
        if (group === "floating") root.floatingTokens = list
        else root.opacityTokens = list
        root.dirty = true
    }
    function removeToken(group, raw) {
        var list = (group === "floating" ? root.floatingTokens : root.opacityTokens)
                   .filter(function (t) { return t.raw !== raw })
        if (group === "floating") root.floatingTokens = list
        else root.opacityTokens = list
        root.dirty = true
    }

    // Suggestions = classes of the windows open right now (that's what rules match on).
    function classSuggestions(query, taken) {
        var q = ("" + query).trim().toLowerCase()
        if (q === "") return []
        var seen = {}, out = []
        var ws = Hyprwindows.windows || []
        for (var i = 0; i < ws.length; i++) {
            var c = ws[i].cls || ""
            if (c === "" || seen[c]) continue
            seen[c] = true
            if (!Fuzzy.match(q, c)) continue
            if (taken.some(function (t) { return t.label.toLowerCase() === c.toLowerCase() })) continue
            out.push({ cls: c, title: ws[i].title || "" })
        }
        return out.slice(0, 5)
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            Card {
                CardLabel { text: "FLOATING APPS" }
                SubLabel {
                    width: parent.width
                    text: "These apps always open as floating windows."
                }
                RuleGroup { group: "floating"; tokens: root.floatingTokens }
            }

            Card {
                CardLabel { text: "TRANSPARENT APPS" }
                SubLabel {
                    width: parent.width
                    text: "These apps get the see-through look."
                }
                RuleGroup { group: "opacity"; tokens: root.opacityTokens }
            }

            Card {
                Row {
                    spacing: 10
                    TextButton { label: "Apply & reload"; primary: root.dirty; onClicked: root.apply() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dirty ? "unsaved changes" : root.status
                        color: root.dirty ? Colors.fgUrgent : Colors.fgMuted
                        font.pixelSize: Style.fsSub; font.family: Style.font
                    }
                }
            }
        }
    }

    // ── One rule group: chips + add field with open-window suggestions ────────
    component RuleGroup: Column {
        id: rg
        property string group: ""
        property var tokens: []
        width: parent ? parent.width : 200
        spacing: 8

        Flow {
            width: parent.width
            spacing: 6
            visible: rg.tokens.length > 0
            Repeater {
                model: rg.tokens
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool custom: modelData.label === ""
                    width: chipRow.implicitWidth + 20
                    height: 28; radius: 14
                    color: Style.selFill
                    border.width: Style.selBorderW; border.color: Style.selBorderColor
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            // Custom fragments keep their raw pattern visible — rare, hand-written.
                            text: chip.custom ? chip.modelData.raw : chip.modelData.label
                            color: Style.selText
                            font.pixelSize: 12; font.family: Style.font
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✕"; color: xHov.containsMouse ? Colors.fgUrgent : Colors.fgMuted
                            font.pixelSize: 10; font.family: Style.font
                            MouseArea {
                                id: xHov
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true
                                onClicked: root.removeToken(rg.group, modelData.raw)
                            }
                        }
                    }
                }
            }
        }

        // Add field
        Rectangle {
            width: parent.width
            height: 34
            radius: Style.rControl
            color: Style.controlFill
            border.width: addInput.activeFocus ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
            border.color: addInput.activeFocus ? Style.accent : Style.controlBorderColor
            TextInput {
                id: addInput
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                clip: true; selectByMouse: true
                onAccepted: { root.addToken(rg.group, text); text = "" }
                Text {
                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                    visible: addInput.text === "" && !addInput.activeFocus
                    text: "add app…  (type, or pick an open window)"
                    color: Colors.fgMuted; font: addInput.font; elide: Text.ElideRight
                }
            }
        }
        Column {
            width: parent.width
            spacing: 2
            Repeater {
                model: addInput.activeFocus ? root.classSuggestions(addInput.text, rg.tokens) : []
                delegate: Rectangle {
                    required property var modelData
                    width: rg.width; height: 28; radius: Style.rTile
                    color: sgHov.containsMouse ? Style.controlHover : Style.controlFill
                    border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                    Text {
                        anchors { left: parent.left; leftMargin: 12; right: tHint.left; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        text: modelData.cls; color: Colors.fgPrimary
                        font.pixelSize: 12; font.family: Style.font; elide: Text.ElideRight
                    }
                    Text {
                        id: tHint
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.title; color: Colors.fgMuted
                        font.pixelSize: 10; font.family: Style.font
                        elide: Text.ElideMiddle; width: Math.min(implicitWidth, rg.width * 0.4)
                    }
                    MouseArea {
                        id: sgHov
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: { root.addToken(rg.group, modelData.cls); addInput.text = ""; addInput.focus = false }
                    }
                }
            }
        }
    }
}
