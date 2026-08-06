import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Window rules: which apps open floating, and which stay fully opaque. The user works with app chips —
// type a name or pick one of the currently open windows (matching runs on the window
// class); the `(.*[Kk]itty.*|…)` regex behind it is composed and parsed here and never
// shown. Fragments the parser doesn't recognize survive as raw chips, so hand-written
// patterns are kept intact. Apply writes the WINDOWRULES section and reloads Hyprland.
Item {
    id: root

    // Token: { label, raw } — label "" means an unrecognized raw fragment (shown as-is).
    property var    floatingTokens: []
    property var    opacityTokens:  []

    // ── Global window decoration (the top card) ──────────────────────────────
    // Persist to gui/settings.json (VtlConfig reads it) AND run apply-decoration.sh, which
    // writes the hypr.lua include + pushes the change to the running compositor live. The
    // apply is debounced so dragging a slider doesn't spam hyprctl / the lua write.
    Process { id: decoProc }
    Timer {
        id: decoDebounce
        interval: 120
        onTriggered: {
            decoProc.command = ["bash",
                Quickshell.env("VELUMERON_DIR") + "/assets/scripts/apply-decoration.sh",
                "" + VtlConfig.windowOpacity,
                VtlConfig.windowBlur ? "1" : "0",
                "" + VtlConfig.windowVibrancy,
                VtlConfig.windowXray ? "1" : "0",
                "" + VtlConfig.windowBlurSize,
                "" + VtlConfig.windowBlurPasses,
                "" + VtlConfig.windowBlurNoise]
            decoProc.running = false
            decoProc.running = true
        }
    }
    function saveDecoration(key, value) {
        SettingsStore.set(key, value)   // updates VtlConfig immediately; the debounce reads it back
        decoDebounce.restart()
    }
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

            // Global window decoration — applies to every window at once, live + persisted.
            Card {
                CardLabel { text: "GLOBAL WINDOW LOOK"
                            hint: "Transparency and blur for every window at once. Blur, vibrancy and X-ray are Hyprland decoration features." }
                Slider {
                    label: "Opacity"; from: 0.5; to: 1.0; decimals: 2; step: 0.01
                    value: VtlConfig.windowOpacity
                    onMoved: root.saveDecoration("window_opacity", v)
                }
                Toggle {
                    label: "Blur"; sub: "Blur what shows through translucent windows"
                    on:    VtlConfig.windowBlur
                    onToggled: root.saveDecoration("window_blur", !VtlConfig.windowBlur)
                }
                Stepper {
                    label: "Blur size"; unit: "px"; step: 1; min: 1; max: 20; labelWidth: 110
                    visible: VtlConfig.windowBlur; value: VtlConfig.windowBlurSize
                    onChanged: root.saveDecoration("window_blur_size", v)
                }
                Stepper {
                    label: "Blur passes"; step: 1; min: 1; max: 6; labelWidth: 110
                    visible: VtlConfig.windowBlur; value: VtlConfig.windowBlurPasses
                    onChanged: root.saveDecoration("window_blur_passes", v)
                }
                Slider {
                    label: "Vibrancy"; from: 0; to: 1; decimals: 2; step: 0.01
                    visible: VtlConfig.windowBlur; value: VtlConfig.windowVibrancy
                    onMoved: root.saveDecoration("window_vibrancy", v)
                }
                Slider {
                    label: "Noise"; from: 0; to: 0.1; decimals: 3; step: 0.005
                    visible: VtlConfig.windowBlur; value: VtlConfig.windowBlurNoise
                    onMoved: root.saveDecoration("window_blur_noise", v)
                }
                Toggle {
                    label: "X-ray"; sub: "Blur sees through to the wallpaper, not the windows behind"
                    visible: VtlConfig.windowBlur; on: VtlConfig.windowXray
                    onToggled: root.saveDecoration("window_xray", !VtlConfig.windowXray)
                }
            }

            Card {
                CardLabel { text: "FLOATING APPS"
                            hint: "These apps always open as floating windows." }
                RuleGroup { group: "floating"; tokens: root.floatingTokens }
            }

            Card {
                CardLabel { text: "OPAQUE APPS"
                            hint: "These apps stay fully opaque — excluded from the global window transparency (handy for video players, image viewers, anything where you never want see-through)." }
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
