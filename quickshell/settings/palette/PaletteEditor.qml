import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Build-your-own palette editor — a centred overlay window (opened from Settings → Style → Colours →
// "Build your own", which closes Settings first). The user sets three SEED colours (Background,
// Accent, Text); everything else — surfaces, borders, muted text, hover, bright text — is DERIVED
// with guaranteed separation/contrast (same idea as fixed-scheme-colors.py, in JS so the mock updates
// instantly). A live mini-shell mock on the left shows the result; Apply writes it straight to the
// shell's colors.json (recolours live), Save keeps it as a reusable palette. One per screen.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.paletteEditorOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.paletteEditorMon

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-palette-editor"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0
    visible: active

    function close() { UiState.paletteEditorOpen = false }

    // ── Seeds + which one the shared picker edits ──────────────────────────────────
    property color bgSeed:     "#12131a"
    property color accentSeed: "#7aa2f7"
    property color textSeed:   "#e6e6ea"
    property string activeRole: "bg"
    property string saveName:  ""
    // Per-role overrides (roleKey → hex). Only derived roles live here; the 3 seeds are direct.
    property var    over:      ({})

    // On open: load a saved palette if one was requested for editing (UiState.paletteEditorSeed),
    // otherwise start fresh from the live palette.
    onActiveChanged: if (active) {
        var s = UiState.paletteEditorSeed
        if (s && s.colors) root._loadPalette(s.colors, s.name || "")
        else {
            root.bgSeed = Colors.color0; root.accentSeed = Colors.bgActive; root.textSeed = Colors.fgBright
            root.over = ({}); nameInput.text = ""
        }
        UiState.paletteEditorSeed = null
        root.activeRole = "bg"
        kbd.forceActiveFocus()
    }
    // Load a saved flat palette for editing: seeds from bg/accent/text, every derived role pinned as
    // an override so it reproduces exactly (each can then be reset to "auto" or tweaked). Name is
    // pre-filled so Save overwrites the same palette.
    function _loadPalette(c, name) {
        root.bgSeed     = c.color0 || Colors.color0
        root.accentSeed = c.color3 || Colors.bgActive
        root.textSeed   = c.color7 || Colors.fgBright
        var o = ({})
        if (c.color1)  o.surface  = c.color1
        if (c.color2)  o.elevated = c.color2
        if (c.color4)  o.hover    = c.color4
        if (c.color5)  o.border   = c.color5
        if (c.color8)  o.muted    = c.color8
        if (c.color15) o.bright   = c.color15
        if (c.color13) o.urgent   = c.color13
        root.over = o
        nameInput.text = name || ""
    }

    // ── Derivation: 3 seeds → full flat palette (hex strings, exactly the colors.json the shell reads).
    function _clamp(x) { return Math.max(0, Math.min(1, x)) }
    function _hsl(c) {
        var r = c.r, g = c.g, b = c.b, mx = Math.max(r, g, b), mn = Math.min(r, g, b)
        var l = (mx + mn) / 2, s = 0, h = 0, d = mx - mn
        if (d !== 0) {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if (mx === r) h = ((g - b) / d) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4
            h /= 6; if (h < 0) h += 1
        }
        return { h: h, s: s, l: l }
    }
    function _mix(a, b, t) { return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, 1) }
    function _h2(x) { return ("0" + Math.round(root._clamp(x) * 255).toString(16)).slice(-2) }
    function _hex(c) { return "#" + root._h2(c.r) + root._h2(c.g) + root._h2(c.b) }
    function _derive(bg, ac, tx) {
        var B = root._hsl(bg), T = root._hsl(tx)
        var dark = B.l < 0.5, sgn = dark ? 1.0 : -1.0
        var kf = 1.0 + Math.max(0.0, 0.22 - Math.min(B.l, 1.0 - B.l)) * 3.2   // lift more on very dark bases
        var ss = Math.min(B.s, 0.28)
        function surf(dl) { return Qt.hsla(B.h, ss, root._clamp(B.l + sgn * dl * kf), 1) }
        var c1 = surf(0.13), c2 = surf(0.20), c5 = surf(0.30)
        var muted  = Qt.hsla(T.h, Math.min(T.s, 0.20), root._clamp(B.l + sgn * 0.42), 1)
        var bright = Qt.hsla(T.h, T.s, dark ? Math.min(0.97, T.l + 0.10) : Math.max(0.05, T.l - 0.10), 1)
        return {
            background: root._hex(bg), foreground: root._hex(tx),
            color0: root._hex(bg),  color1: root._hex(c1),  color2: root._hex(c2),  color3: root._hex(ac),
            color4: root._hex(root._mix(c2, ac, 0.32)),     color5: root._hex(c5),  color6: root._hex(ac),
            color7: root._hex(tx),  color8: root._hex(muted),
            color9: root._hex(ac),  color10: root._hex(c2), color11: root._hex(ac),
            color12: root._hex(root._mix(ac, tx, 0.3)),     color13: "#e06c75",     color14: root._hex(ac),
            color15: root._hex(bright)
        }
    }
    // ── Roles: the 3 seeds drive the derivation; every derived role can be individually overridden. ──
    readonly property var roleDefs: [
        { key: "bg",       label: "Background",        slot: "color0",  seed: true },
        { key: "surface",  label: "Surface / module", slot: "color1" },
        { key: "elevated", label: "Elevated surface", slot: "color2" },
        { key: "accent",   label: "Accent",           slot: "color3",  seed: true },
        { key: "hover",    label: "Hover / active",   slot: "color4" },
        { key: "border",   label: "Border",           slot: "color5" },
        { key: "text",     label: "Text",             slot: "color7",  seed: true },
        { key: "muted",    label: "Muted text",       slot: "color8" },
        { key: "bright",   label: "Bright text",      slot: "color15" },
        { key: "urgent",   label: "Urgent",           slot: "color13" }
    ]
    // The colour slots each OVERRIDE role writes into (accent/text are seeds, handled in _derive).
    readonly property var _roleSlots: ({
        surface: ["color1"], elevated: ["color2", "color10"], hover: ["color4"],
        border: ["color5"], muted: ["color8"], bright: ["color15"], urgent: ["color13"]
    })
    function _resolved() {
        var p = root._derive(root.bgSeed, root.accentSeed, root.textSeed)
        var o = root.over || ({})
        for (var k in o) {
            var slots = root._roleSlots[k]
            if (slots) for (var i = 0; i < slots.length; i++) p[slots[i]] = o[k]
        }
        return p
    }
    readonly property var pal: root._resolved()

    function _isSeed(key)   { return key === "bg" || key === "accent" || key === "text" }
    function _slotOf(key)   { for (var i = 0; i < roleDefs.length; i++) if (roleDefs[i].key === key) return roleDefs[i].slot; return "color0" }
    function roleColor(key)      { return root.pal[root._slotOf(key)] }
    function roleOverridden(key) { return !root._isSeed(key) && root.over[key] !== undefined }
    function setRole(key, c) {
        if (key === "bg")          root.bgSeed = c
        else if (key === "accent") root.accentSeed = c
        else if (key === "text")   root.textSeed = c
        else { var o = Object.assign({}, root.over); o[key] = root._hex(c); root.over = o }
    }
    function resetRole(key) { var o = Object.assign({}, root.over); delete o[key]; root.over = o }
    // Readable text/glyph on the accent (mirrors Style.onColor, but from the LOCAL palette).
    readonly property color palOnAccent: Style.onColor(root.pal.color3)

    // ── Apply (write colors.json live) + Save (also keep as a reusable palette) ─────
    readonly property string _pyHead:
        "import json,os,sys,re;u=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') or os.path.expanduser('~/.config'),'velumeron');"
    Process { id: applyProc }
    function _apply() {
        applyProc.command = ["python3", "-c",
            root._pyHead +
            "p=os.path.join(u,'quickshell','colors.json');os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "json.dump(json.loads(sys.argv[1]),open(p,'w'),indent=2);" +
            "cm=os.path.join(u,'wallust','color-mode');os.makedirs(os.path.dirname(cm),exist_ok=True);open(cm,'w').write('custom\\n')",
            JSON.stringify(root.pal)]
        applyProc.running = false; applyProc.running = true
    }
    Process { id: saveProc }
    function _save() {
        var n = ("" + root.saveName).trim(); if (n === "") return
        saveProc.command = ["python3", "-c",
            root._pyHead +
            "name=re.sub(r'[^A-Za-z0-9]+','-',sys.argv[2].strip().lower()).strip('-') or 'palette';" +
            "d=os.path.join(u,'palettes');os.makedirs(d,exist_ok=True);" +
            "json.dump(json.loads(sys.argv[1]),open(os.path.join(d,name+'.json'),'w'),indent=2)",
            JSON.stringify(root.pal), n]
        saveProc.running = false; saveProc.running = true
        root._apply()
    }

    // ── Keyboard (Esc) + dim backdrop (click-out closes) ───────────────────────────
    Item { id: kbd; anchors.fill: parent; focus: root.active; Keys.onEscapePressed: root.close() }
    Rectangle {
        anchors.fill: parent; color: "#000000"; opacity: 0.55
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // ── The editor card ────────────────────────────────────────────────────────────
    Rectangle {
        id: cardW
        anchors.centerIn: parent
        width: Math.min(880, root.width - 80); height: Math.min(600, root.height - 80)
        radius: Style.rCard
        color: Colors.bgPrimary
        border.width: 1; border.color: Colors.boNormal
        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close

        Column {
            anchors { fill: parent; margins: 18 }
            spacing: 14

            Text { text: "Build your own palette"; color: Colors.fgBright
                   font.pixelSize: 17; font.bold: true; font.family: Style.font }

            Row {
                width: parent.width
                height: parent.height - 84
                spacing: 18

                // ── LEFT: live mini-shell mock, rendered from the derived `pal` ─────
                Rectangle {
                    id: mock
                    width: Math.round((parent.width - 18) * 0.52); height: parent.height
                    radius: Style.rCard; clip: true
                    color: root.pal.color0
                    border.width: 1; border.color: root.pal.color5

                    // bar strip (a module chip on it shows module-bg vs base separation)
                    Rectangle {
                        id: mbar
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        height: 34; radius: 8; color: root.pal.color1
                        Row {
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Rectangle { width: 26; height: 16; radius: 8; color: root.pal.color3
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { anchors.centerIn: parent; text: "1"; color: root.palOnAccent
                                               font.pixelSize: 10; font.bold: true; font.family: Style.font } }
                            Text { text: "12:34"; color: root.pal.color15; anchors.verticalCenter: parent.verticalCenter
                                   font.pixelSize: 12; font.bold: true; font.family: Style.font }
                        }
                        // a "module" chip — its bg is color2 (nested surface), clearly above the bar
                        Rectangle {
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 62; height: 20; radius: 6; color: root.pal.color2
                            Text { anchors.centerIn: parent; text: "󰕾  42%"; color: root.pal.color7
                                   font.pixelSize: 10; font.family: Style.font }
                        }
                    }

                    // a menu card sitting on the desktop base — the key bg-vs-surface contrast
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: mbar.bottom; margins: 8; topMargin: 12 }
                        height: parent.height - mbar.height - 32
                        radius: 10; color: root.pal.color1
                        border.width: 1; border.color: root.pal.color5
                        Column {
                            anchors { fill: parent; margins: 12 }
                            spacing: 10
                            Text { text: "Menu"; color: root.pal.color15
                                   font.pixelSize: 14; font.bold: true; font.family: Style.font }
                            Text { text: "Main text on the surface"; color: root.pal.color7
                                   font.pixelSize: 12; font.family: Style.font }
                            Text { text: "Muted secondary text"; color: root.pal.color8
                                   font.pixelSize: 11; font.family: Style.font }
                            // a nested row (color2) to show a second surface step
                            Rectangle { width: parent.width; height: 30; radius: 7; color: root.pal.color2
                                        Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                               text: "A list row"; color: root.pal.color7
                                               font.pixelSize: 11; font.family: Style.font } }
                            // accent button with auto on-accent text
                            Rectangle {
                                width: 128; height: 34; radius: 8; color: root.pal.color3
                                Text { anchors.centerIn: parent; text: "Accent button"; color: root.palOnAccent
                                       font.pixelSize: 12; font.bold: true; font.family: Style.font }
                            }
                        }
                    }
                }

                // ── RIGHT: every role — 3 seeds drive the rest, any derived role is overridable ─────
                Item {
                    width: parent.width - mock.width - 18; height: parent.height

                    Text {
                        id: rInfo
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        text: "Set Background, Accent and Text — the rest derives automatically. Click any role to fine-tune it; overridden ones show a reset."
                        color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font; wrapMode: Text.WordWrap
                    }
                    ColorPicker {
                        id: picker
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        color: root.roleColor(root.activeRole)
                        onPicked: c => root.setRole(root.activeRole, c)
                    }
                    Flickable {
                        anchors { top: rInfo.bottom; topMargin: 8; left: parent.left; right: parent.right
                                  bottom: picker.top; bottomMargin: 10 }
                        contentHeight: rolesCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                        Column {
                            id: rolesCol
                            width: parent.width; spacing: 5
                            Repeater {
                                model: root.roleDefs
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: root.activeRole === modelData.key
                                    readonly property bool ov:  root.roleOverridden(modelData.key)
                                    width: parent ? parent.width : 0; height: 36; radius: Style.rControl
                                    color: sel ? Style.tint(Style.accent, 0.16)
                                               : (rh.containsMouse ? Style.controlHover : Style.controlFill)
                                    border.width: sel ? 1 : Style.controlBorderW
                                    border.color: sel ? Style.accent : Style.controlBorderColor

                                    MouseArea { id: rh; anchors.fill: parent; hoverEnabled: true
                                                onClicked: root.activeRole = modelData.key }

                                    Rectangle {
                                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: 20; height: 20; radius: 5; color: root.roleColor(modelData.key)
                                        border.width: 1; border.color: "#00000050"
                                    }
                                    Text { anchors { left: parent.left; leftMargin: 40; verticalCenter: parent.verticalCenter }
                                           text: modelData.label; color: Colors.fgPrimary
                                           font.pixelSize: Style.fsLabel; font.family: Style.font }
                                    Text {
                                        anchors { right: resetBtn.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        visible: !modelData.seed
                                        text: parent.ov ? "custom" : "auto"
                                        color: parent.ov ? Style.accent : Colors.fgMuted
                                        font.pixelSize: 9; font.bold: parent.ov === true; font.family: Style.font
                                    }
                                    Rectangle {
                                        id: resetBtn
                                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        visible: parent.ov; width: 24; height: 24; radius: 6
                                        color: rbHov.containsMouse ? Style.controlHover : "transparent"
                                        Text { anchors.centerIn: parent; text: "󰑐"; color: Colors.fgMuted
                                               font.pixelSize: 12; font.family: Style.font }
                                        MouseArea { id: rbHov; anchors.fill: parent; hoverEnabled: true
                                                    onClicked: root.resetRole(modelData.key) }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer: name + Save · Apply · Close ────────────────────────────────
            Row {
                width: parent.width; height: 40; spacing: 10
                Rectangle {
                    width: parent.width - 320; height: 40; radius: Style.rControl
                    color: Style.controlFill; border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                    TextInput {
                        id: nameInput
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: Text.AlignVCenter
                        color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                        clip: true; selectByMouse: true
                        onTextChanged: root.saveName = text
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                               visible: nameInput.text === ""; text: "Palette name…"
                               color: Colors.fgMuted; font: nameInput.font }
                    }
                }
                TextButton { label: "Save"; anchors.verticalCenter: parent.verticalCenter
                             onClicked: root._save() }
                TextButton { primary: true; label: "Apply"; anchors.verticalCenter: parent.verticalCenter
                             onClicked: root._apply() }
                TextButton { label: "Close"; anchors.verticalCenter: parent.verticalCenter
                             onClicked: root.close() }
            }
        }
    }
}
