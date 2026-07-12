import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Style settings — deliberately minimal. The main page holds exactly three things:
//   1. STYLE     — preview cards for each shipped style. Only Mirobo is built out and selectable
//      right now (its own forks included); every other style is parked as a dimmed "SOON" card and
//      returns once it is finished. Clicking the active card re-opens the customiser.
//   2. APPEARANCE — the desktop-wide dark/light preference + GTK/Qt app theming
//   3. BUILD A THEME — opens the builder sub-page: name it, then assemble bar, menus, launcher,
//      font and colours. Every step edits the fresh template LIVE — copy-on-write persists it.
// The raw UI-style picker is parked with the other styles (it jumped straight into unfinished ones);
// the machinery all stays in the code for when the styles come back.
Item {
    id: root

    // "" = main page, "build" = the theme-builder sub-page.
    property string page: ""

    // ── Colours (wallust mode) ──
    property bool   autoMode:    true
    property var    schemes:     []
    property string selected:    ""
    property string colorStatus: ""

    // Key swatches shown in fixed-scheme rows: bg, the 8 "bright" accent colors, fg.
    readonly property var swatchKeys: ["background", "color1", "color2", "color3", "color4",
                                       "color5", "color6", "color9", "color10", "foreground"]
    // Map filename → flat color object { background, foreground, color0..15 }.
    property var schemeColors: ({})

    // ── Wallust auto-mode options ──
    // Saved to/from $VELUMERON_USER_DIR/wallust/options.json.
    property var wallustOpts: ({
        palette:        "saliencedarkdistributed",
        backend:        "wal",
        colorspace:     "lab",
        saturation:     20,
        check_contrast: true
    })

    readonly property var paletteOptions: [
        { key: "saliencedarkdistributed",  label: "Salience · Distributed (default)" },
        { key: "saliencedark",             label: "Salience · Default" },
        { key: "saliencedarkbalanced",     label: "Salience · Balanced" },
        { key: "saliencedarklow",          label: "Salience · Low (muted)" },
        { key: "dark",                     label: "Dark (classic)" },
        { key: "harddark",                 label: "Dark · Hard" },
        { key: "softdark",                 label: "Dark · Soft" },
        { key: "darkcomp",                 label: "Dark · Complementary" },
        { key: "dark16",                   label: "Dark 16" },
        { key: "saliencedarkdistributed16",label: "Salience · Distributed 16" },
    ]
    readonly property var backendOptions: [
        { key: "wal",        label: "Wal / ImageMagick (default)" },
        { key: "resized",    label: "Resized" },
        { key: "full",       label: "Full image (slower, precise)" },
        { key: "kmeans",     label: "K-Means (diverse)" },
        { key: "thumb",      label: "Thumb 512px (fastest)" },
        { key: "fastresize", label: "Fast resize (SIMD)" },
    ]
    readonly property var colorspaceOptions: [
        { key: "lab",      label: "L*a*b (default)" },
        { key: "salience", label: "Salience (visual pop)" },
        { key: "lch",      label: "LCH" },
        { key: "lchmixed", label: "LCH mixed" },
    ]

    function optLabel(arr, key) {
        for (var i = 0; i < arr.length; i++) if (arr[i].key === key) return arr[i].label
        return key
    }
    function setOpt(k, v) {
        var o = Object.assign({}, wallustOpts); o[k] = v; wallustOpts = o
        saveOptsProc.command = [
            "python3", "-c",
            "import json,os,sys; u=os.environ.get('VELUMERON_USER_DIR',os.path.expanduser('~/.config/velumeron')); d=os.path.join(u,'wallust','options.json'); os.makedirs(os.path.dirname(d),exist_ok=True); json.dump(json.loads(sys.argv[1]),open(d,'w'),indent=2)",
            JSON.stringify(wallustOpts)
        ]
        saveOptsProc.running = false; saveOptsProc.running = true
    }

    Component.onCompleted: reload()
    onVisibleChanged:      if (visible) { reload(); if (!visible) page = "" }

    function displayName(f) { return ("" + f).replace(/\.json$/, "").replace(/-/g, " ") }

    // ── Transition style helpers ──
    readonly property var menus: [
        { key: "menu",          label: "Settings menu" },
        { key: "osd",           label: "OSD" },
        { key: "notify_popup",  label: "Notification popups" },
        { key: "notify_center", label: "Notification center" },
        { key: "flyout",        label: "Bar flyouts" },
        { key: "taskbar",       label: "Taskbar" }
    ]
    function styleLabel(k) {
        return ({ auto: "Auto (follow UI style)", fillet: "Tapered (fillet)",
                  straight: "Straight — all edges",
                  straight_origin: "Straight — origin edge" })[k] ?? k
    }
    function styleLabelG(k) { return k === "global" ? "Follow global" : styleLabel(k) }
    function styleOpts(current, withGlobal) {
        var base = withGlobal ? [{ key: "global", label: "Follow global" }] : []
        base.push({ key: "auto",            label: "Auto (follow UI style)" })
        base.push({ key: "fillet",          label: "Tapered (fillet)" })
        base.push({ key: "straight",        label: "Straight — all edges" })
        base.push({ key: "straight_origin", label: "Straight — origin edge" })
        return base.map(function (o) { return { label: o.label, key: o.key, on: current === o.key } })
    }

    function reload() {
        colorStatus = ""
        schemes     = []
        loadProc.running = false; loadProc.running = true
        loadColorsProc.running = false; loadColorsProc.running = true
        loadOptsProc.running   = false; loadOptsProc.running   = true
        appThemeStatusProc.buf = ""
        appThemeStatusProc.running = false; appThemeStatusProc.running = true
    }

    // ── App theming (GTK / Qt / global dark-light) ──
    property bool   gtkTheming: false
    property bool   qtTheming:  false
    property string appMode:    "dark"
    Process {
        id: appThemeStatusProc
        property string buf: ""
        command: ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-app-theme.sh\" status"]
        stdout: SplitParser { onRead: line => appThemeStatusProc.buf += line }
        onExited: {
            try {
                var d = JSON.parse(appThemeStatusProc.buf)
                root.gtkTheming = d.gtk === true
                root.qtTheming  = d.qt === true
                root.appMode    = d.mode || "dark"
            } catch (e) {}
        }
    }
    // buf must be cleared before every status re-run: += accumulates across runs, and two
    // concatenated JSON objects make the parse throw forever.
    Process { id: appThemeProc; onExited: { appThemeStatusProc.buf = ""
                                            appThemeStatusProc.running = false; appThemeStatusProc.running = true } }
    function appTheme(args) {
        appThemeProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/apply-app-theme.sh\" " + args]
        appThemeProc.running = false; appThemeProc.running = true
    }

    // Persist one key into settings.json (VtlConfig picks it up on its poll).
    function save(key, value) { SettingsStore.set(key, value) }

    function pickStyle(key) {
        VtlConfig.applyLocal("ui_style", key)
        save("ui_style", key)
    }

    readonly property var fontOptions: [
        { key: "",           label: "Default · Fantasque Sans" },
        { key: "Chivo Mono", label: "Chivo Mono · strict mono" },
        { key: "Orbitron",   label: "Orbitron · futuristic" },
        { key: "Cinzel",     label: "Cinzel · medieval serif" },
        { key: "VT323",      label: "VT323 · retro terminal" },
        { key: "Shantell Sans", label: "Shantell Sans · handwritten" },
        { key: "Fredoka",    label: "Fredoka · rounded" }
    ]
    function fontLabel(k) {
        for (var i = 0; i < fontOptions.length; i++) if (fontOptions[i].key === k) return fontOptions[i].label
        return k !== "" ? k : "Default · Fantasque Sans"
    }
    function pickFont(key) {
        VtlConfig.applyLocal("ui_font", key)
        save("ui_font", key)
    }

    function applyColours() {
        if (autoMode) {
            applyColourProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-theme.sh\" auto"]
            colorStatus = "Re-deriving from current wallpaper."
        } else {
            if (!schemes.length) { colorStatus = "No schemes in fixed_colors/."; return }
            var s = selected || schemes[0]
            applyColourProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-theme.sh\" fixed " + JSON.stringify(s)]
            colorStatus = "Applying " + displayName(s) + "…"
        }
        applyColourProc.running = false; applyColourProc.running = true
        colorClear.restart()
    }

    Process {
        id: loadProc
        command: ["bash", "-c",
            "m=$(cat \"$VELUMERON_USER_DIR/wallust/color-mode\" 2>/dev/null || echo auto);" +
            "echo \"mode:$m\";" +
            "d=\"$VELUMERON_DIR/wallust/fixed_colors\";" +
            "if [ -d \"$d\" ]; then for f in \"$d\"/*.json; do " +
            "[ -e \"$f\" ] && echo \"scheme:$(basename \"$f\")\"; done; fi"]
        stdout: SplitParser {
            onRead: line => {
                var t = line.trim()
                if (t.startsWith("mode:")) {
                    var m = t.slice(5)
                    if (m.startsWith("fixed:")) { root.autoMode = false; root.selected = m.slice(6) }
                    else                          root.autoMode = true
                } else if (t.startsWith("scheme:")) {
                    var arr = root.schemes.slice(); arr.push(t.slice(7)); root.schemes = arr
                }
            }
        }
        onRunningChanged: {
            if (!running && !root.autoMode
                && (!root.selected || root.schemes.indexOf(root.selected) < 0))
                root.selected = root.schemes.length ? root.schemes[0] : ""
        }
    }
    Process { id: applyColourProc }
    Process { id: saveOptsProc }

    property string _colorsBuf: ""
    Process {
        id: loadColorsProc
        command: ["bash", "-c",
            "python3 - \"$VELUMERON_DIR\" <<'PY'\n" +
            "import json,os,glob,sys\n" +
            "base=os.path.join(sys.argv[1],'wallust','fixed_colors')\n" +
            "out={}\n" +
            "for f in glob.glob(os.path.join(base,'*.json')):\n" +
            "    try:\n" +
            "        d=json.load(open(f))\n" +
            "        out[os.path.basename(f)]={**d.get('special',{}),**d.get('colors',{})}\n" +
            "    except: pass\n" +
            "print(json.dumps(out))\n" +
            "PY"]
        stdout: SplitParser { onRead: line => { root._colorsBuf += line } }
        onRunningChanged: {
            if (running) { root._colorsBuf = ""; return }
            try { root.schemeColors = JSON.parse(root._colorsBuf.trim()) } catch(e) {}
        }
    }

    property string _optsBuf: ""
    Process {
        id: loadOptsProc
        command: ["bash", "-c",
            "f=\"$VELUMERON_USER_DIR/wallust/options.json\"; [ -f \"$f\" ] && cat \"$f\" || echo '{}'"]
        stdout: SplitParser { onRead: line => { root._optsBuf += line } }
        onRunningChanged: {
            if (running) { root._optsBuf = ""; return }
            try {
                var o = JSON.parse(root._optsBuf.trim())
                root.wallustOpts = Object.assign({}, root.wallustOpts, o)
            } catch(e) {}
        }
    }

    Timer { id: colorClear; interval: 4000
            onTriggered: if (!root.colorStatus.endsWith("…")) root.colorStatus = "" }

    // ── Template rename editor state (rename only — creation happens in the builder) ──
    property string _tplEdit: ""   // "" | "rename"
    function _tplBeginRename() { _tplEdit = "rename"; tplNameInput.text = Templates.activeName;  tplNameInput.forceActiveFocus() }
    function _tplCommit() {
        var n = ("" + tplNameInput.text).trim()
        if (n === "") { _tplEdit = ""; return }
        Templates.rename(Templates.activeId, n)
        _tplEdit = ""
    }

    // Mini-mock colours per ui_style: a hint of each style's mood for cards without a wallpaper.
    function styleTint(s) {
        return ({ futuristic: "#0d2236", grimoire: "#2b2015", nostalgic: "#0e4a45",
                  cupertino: "#26293c", sketch: "#31313b", wobbly: "#33283e",
                  straight: "#20242a", cards: "#252c38", outlined: "#22262e" })[s] ?? "#262b36"
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // MAIN PAGE — templates · appearance · build-a-theme
    // ════════════════════════════════════════════════════════════════════════════════
    Flickable {
        anchors.fill: parent
        visible: root.page === ""
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Template cards ────────────────────────────────────────────────
            Card {
                CardLabel { text: "STYLE" }
                SubLabel { width: parent.width
                           text: "Mirobo is the built-out style — click it to customise. The other styles are still in progress and will unlock over time. Editing anything forks a private copy, so the built-ins stay untouched." }

                Flow {
                    id: tplGrid
                    width: parent.width; spacing: 8
                    readonly property real cw: Math.floor((width - spacing) / 2)
                    Repeater {
                        // Parked "SOON" styles (built-ins other than mirobo) are hidden entirely for
                        // now — only mirobo and the user's own forks show. The TemplateCard's wip
                        // handling stays in the code for when they return; flip this filter to re-show.
                        model: Templates.templates.filter(function (t) {
                            return !(t.builtin && (t.id || "") !== "mirobo")
                        })
                        delegate: TemplateCard { required property var modelData; tpl: modelData; width: tplGrid.cw }
                    }
                }

                // Inline rename editor.
                Rectangle {
                    width: parent.width; height: 40; radius: Style.rControl
                    visible: root._tplEdit !== ""
                    color: Style.controlFill
                    border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                    Row {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                        spacing: 8
                        TextInput {
                            id: tplNameInput
                            width: parent.width - 128
                            anchors.verticalCenter: parent.verticalCenter
                            color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                            clip: true; selectByMouse: true
                            onAccepted: root._tplCommit()
                            Keys.onEscapePressed: root._tplEdit = ""
                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                   visible: tplNameInput.text === ""; text: "Template name…"
                                   color: Colors.fgMuted; font: tplNameInput.font }
                        }
                        TextButton { primary: true; label: "OK"; anchors.verticalCenter: parent.verticalCenter
                                     onClicked: root._tplCommit() }
                        TextButton { label: "Cancel"; anchors.verticalCenter: parent.verticalCenter
                                     onClicked: root._tplEdit = "" }
                    }
                }

                Flow {
                    width: parent.width; spacing: 8
                    TextButton { label: "Duplicate"; onClicked: Templates.duplicate(Templates.activeSource, Templates.activeId, "") }
                    TextButton { label: "Rename"; visible: !Templates.activeIsBuiltin && Templates.activeId !== ""
                                 onClicked: root._tplBeginRename() }
                    TextButton { label: "Delete"; visible: !Templates.activeIsBuiltin && Templates.activeId !== ""
                                 onClicked: Templates.remove(Templates.activeId) }
                }
            }

            // ── Appearance: desktop-wide dark/light + app theming ─────────────
            Card {
                CardLabel { text: "APPEARANCE" }
                Segmented {
                    equal: true
                    segments: [{ label: "󰖔  Dark", key: "dark" }, { label: "󰖨  Light", key: "light" }]
                    current: root.appMode
                    onPicked: key => root.appTheme("mode " + key)
                }
                SubLabel {
                    width: parent.width
                    text: "Desktop-wide dark/light preference (xdg color-scheme + GTK variant) for portal-aware apps and websites. Shell and terminal colours stay untouched."
                }
                Toggle {
                    label: "Theme GTK apps"
                    sub:   "adw-gtk3 + live wallust palette"
                    on:    root.gtkTheming
                    onToggled: root.appTheme("gtk " + (root.gtkTheming ? "off" : "on"))
                }
                Toggle {
                    label: "Theme Qt apps"
                    sub:   "qt5ct/qt6ct palette from the live colors"
                    on:    root.qtTheming
                    onToggled: root.appTheme("qt " + (root.qtTheming ? "off" : "on"))
                }
            }

            // ── Build a theme ─────────────────────────────────────────────────
            Card {
                CardLabel { text: "BUILD A THEME" }
                SubLabel { width: parent.width
                           text: "Assemble your own experience step by step — style, bar, menus, launcher, font, colours. Everything applies live." }
                Rectangle {
                    width: parent.width; height: 44; radius: Style.rControl
                    color: buildHov.containsMouse ? Style.accent : Style.tint(Style.accent, 0.22)
                    border.width: 1; border.color: Style.accent
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "󰏘   Build a theme"
                           color: buildHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                           font.pixelSize: 14; font.bold: true; font.family: Style.font }
                    MouseArea { id: buildHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: { root.page = "build"; buildName.text = "" } }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════
    // BUILDER SUB-PAGE — name it, then assemble the theme top to bottom
    // ════════════════════════════════════════════════════════════════════════════════
    Item {
        anchors.fill: parent
        visible: root.page === "build"

        Row {
            id: buildBack
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 2 }
            height: 34; spacing: 8
            Rectangle {
                width: 34; height: 34; radius: 8
                color: bbHov.containsMouse ? Style.accent : Style.controlFill
                Behavior on color { ColorAnimation { duration: 100 } }
                Text { anchors.centerIn: parent; text: "󰁍"; color: Colors.fgBright
                       font.pixelSize: 16; font.family: Style.font }
                MouseArea { id: bbHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.page = "" }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "Build a theme"; color: Colors.fgBright
                       font.pixelSize: 15; font.bold: true; font.family: Style.font }
                Text { text: "Editing: " + (Templates.activeName || "—"); color: Colors.fgMuted
                       font.pixelSize: 10; font.family: Style.font }
            }
        }

        Flickable {
            anchors { top: buildBack.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
            contentHeight: buildCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            Column {
                id: buildCol
                width: parent.width
                spacing: Style.cardGap

                // 1 · Name — snapshot the current settings as a fresh user template and edit that.
                Card {
                    CardLabel { text: "1 · NAME" }
                    SubLabel { width: parent.width
                               text: "Start from what you see now: a new template snapshots the current settings and every step below edits it live. Skip this to keep editing the active one." }
                    Rectangle {
                        width: parent.width; height: 40; radius: Style.rControl
                        color: Style.controlFill
                        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                        Row {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                            spacing: 8
                            TextInput {
                                id: buildName
                                width: parent.width - 108
                                anchors.verticalCenter: parent.verticalCenter
                                color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
                                clip: true; selectByMouse: true
                                onAccepted: if (text.trim() !== "") { Templates.createAndBuild(text.trim()) }
                                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                       visible: buildName.text === ""; text: "My theme…"
                                       color: Colors.fgMuted; font: buildName.font }
                            }
                            TextButton { primary: true; label: "Create"; anchors.verticalCenter: parent.verticalCenter
                                         onClicked: if (buildName.text.trim() !== "") Templates.createAndBuild(buildName.text.trim()) }
                        }
                    }
                }

                // UI-style switching is parked while only mirobo is built out — the other styles
                // return as their own cards on the Style page, each carrying its own ui_style, so the
                // builder no longer offers a raw style picker (it would jump into unfinished styles).

                // 2 · Bar basics — placement lives here, the module arrangement in Settings → Bar.
                Card {
                    CardLabel { text: "2 · BAR" }
                    FieldLabel { text: "Mode" }
                    Segmented {
                        equal: true
                        current: VtlConfig.barModeFor("")
                        segments: [{ label: "Dock", key: "dock" }, { label: "Float", key: "float" },
                                   { label: "Frame", key: "frame" }, { label: "None", key: "none" }]
                        onPicked: root.save("bar_mode", key)
                    }
                    FieldLabel { text: "Position" }
                    Segmented {
                        equal: true
                        current: VtlConfig.barPositionFor("")
                        segments: [{ label: "Top", key: "top" }, { label: "Bottom", key: "bottom" },
                                   { label: "Left", key: "left" }, { label: "Right", key: "right" }]
                        // Frame reads bar_edges, not bar_position — mirror the pick into the
                        // edge list so the choice takes effect there too (multi-edge frames
                        // stay a Settings → Bar affair).
                        onPicked: { root.save("bar_position", key)
                                    if (VtlConfig.barModeFor("") === "frame") root.save("bar_edges", [key]) }
                    }
                    Stepper { label: "Thickness"; unit: "px"; min: 16; max: 80; step: 2; labelWidth: 110
                              value: VtlConfig.barThicknessFor("")
                              onChanged: root.save("bar_thickness", v) }
                    SubLabel { width: parent.width
                               text: "Modules, per-edge arrangement and sizing: Settings → Bar." }
                }

                // 4 · Menus & transitions
                Card {
                    CardLabel { text: "3 · MENUS" }
                    Toggle {
                        label: "Colorful"
                        sub:   "Blend a hint of the accent into surfaces"
                        on:    VtlConfig.colorfulEnabled
                        onToggled: root.save("colorful_enabled", !VtlConfig.colorfulEnabled)
                    }
                    Column {
                        width:   parent.width
                        spacing: 6
                        visible: VtlConfig.colorfulEnabled
                        Toggle { indent: true; label: "Bar";   on: VtlConfig.colorfulBarSub
                                 onToggled: root.save("colorful_bar",   !VtlConfig.colorfulBarSub) }
                        Toggle { indent: true; label: "Menus"; on: VtlConfig.colorfulMenusSub
                                 onToggled: root.save("colorful_menus", !VtlConfig.colorfulMenusSub) }
                        Toggle { indent: true; label: "OSD";   on: VtlConfig.colorfulOsdSub
                                 onToggled: root.save("colorful_osd",   !VtlConfig.colorfulOsdSub) }
                    }

                    FieldLabel { text: "Transition — on a bar" }
                    Dropdown {
                        summary: root.styleLabel(VtlConfig.transitionGlobalRaw("bar"))
                        options: root.styleOpts(VtlConfig.transitionGlobalRaw("bar"), false)
                        onPicked: root.save("transition_style_bar", key)
                    }
                    FieldLabel { text: "Transition — on a monitor edge" }
                    Dropdown {
                        summary: root.styleLabel(VtlConfig.transitionGlobalRaw("edge"))
                        options: root.styleOpts(VtlConfig.transitionGlobalRaw("edge"), false)
                        onPicked: root.save("transition_style_edge", key)
                    }

                    // Per-menu overrides — collapsed until opened.
                    Rectangle {
                        id: perMenuHead
                        property bool open: false
                        width: parent.width; height: 34; radius: Style.rControl
                        color: phHov.containsMouse ? Style.controlHover : Style.controlFill
                        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: "Per-menu overrides"; color: Colors.fgPrimary
                            font.pixelSize: Style.fsLabel; font.family: Style.font
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            text: perMenuHead.open ? "▴" : "▾"; color: Colors.fgMuted
                            font.pixelSize: 12; font.family: Style.font
                        }
                        MouseArea { id: phHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: perMenuHead.open = !perMenuHead.open }
                    }
                    Column {
                        width: parent.width; spacing: 10
                        visible: perMenuHead.open
                        Repeater {
                            model: root.menus
                            delegate: Column {
                                required property var modelData
                                width: parent ? parent.width : 0
                                spacing: 3
                                FieldLabel { text: modelData.label }
                                SubLabel { text: "On a bar" }
                                Dropdown {
                                    summary: root.styleLabelG(VtlConfig.transitionMenuRaw(modelData.key, "bar"))
                                    options: root.styleOpts(VtlConfig.transitionMenuRaw(modelData.key, "bar"), true)
                                    onPicked: root.save("transition_style_" + modelData.key + "_bar", key)
                                }
                                SubLabel { text: "On a monitor edge" }
                                Dropdown {
                                    summary: root.styleLabelG(VtlConfig.transitionMenuRaw(modelData.key, "edge"))
                                    options: root.styleOpts(VtlConfig.transitionMenuRaw(modelData.key, "edge"), true)
                                    onPicked: root.save("transition_style_" + modelData.key + "_edge", key)
                                }
                            }
                        }
                    }
                }

                // 5 · Launcher
                Card {
                    CardLabel { text: "4 · LAUNCHER" }
                    FieldLabel { text: "Position" }
                    Dropdown {
                        summary: VtlConfig.launcherPosition
                        options: ["top-center", "center", "bottom-center", "top-left", "top-right",
                                  "bottom-left", "bottom-right"].map(function (k) {
                            return { key: k, label: k, on: VtlConfig.launcherPosition === k }
                        })
                        onPicked: root.save("launcher_position", key)
                    }
                    Toggle { label: "Dock against the bar"; on: VtlConfig.launcherDock
                             onToggled: root.save("launcher_dock", !VtlConfig.launcherDock) }
                    Toggle { label: "Blur behind"; on: VtlConfig.launcherBlur
                             onToggled: root.save("launcher_blur", !VtlConfig.launcherBlur) }
                }

                // 6 · Font
                Card {
                    CardLabel { text: "5 · FONT" }
                    Dropdown {
                        summary: root.fontLabel(VtlConfig.uiFont)
                        options: root.fontOptions.map(function (o) {
                            return { key: o.key, label: o.label, on: VtlConfig.uiFont === o.key }
                        })
                        onPicked: root.pickFont(key)
                    }
                }

                // 7 · Colours (wallust)
                Card {
                    CardLabel { text: "6 · COLOURS" }
                    Toggle {
                        label: "Automatic colours"
                        sub:   "Derive from the wallpaper on each change"
                        on:    root.autoMode
                        onToggled: { root.autoMode = !root.autoMode; root.applyColours() }
                    }

                    Column {
                        width: parent.width; spacing: Style.rowGap
                        visible: root.autoMode

                        FieldLabel { text: "Palette" }
                        Dropdown {
                            summary: root.optLabel(root.paletteOptions, root.wallustOpts.palette ?? "saliencedarkdistributed")
                            options: root.paletteOptions.map(function(o) {
                                return { key: o.key, label: o.label,
                                         on: (root.wallustOpts.palette ?? "saliencedarkdistributed") === o.key }
                            })
                            onPicked: root.setOpt("palette", key)
                        }

                        FieldLabel { text: "Backend" }
                        Dropdown {
                            summary: root.optLabel(root.backendOptions, root.wallustOpts.backend ?? "wal")
                            options: root.backendOptions.map(function(o) {
                                return { key: o.key, label: o.label,
                                         on: (root.wallustOpts.backend ?? "wal") === o.key }
                            })
                            onPicked: root.setOpt("backend", key)
                        }

                        FieldLabel { text: "Colorspace" }
                        Dropdown {
                            summary: root.optLabel(root.colorspaceOptions, root.wallustOpts.colorspace ?? "lab")
                            options: root.colorspaceOptions.map(function(o) {
                                return { key: o.key, label: o.label,
                                         on: (root.wallustOpts.colorspace ?? "lab") === o.key }
                            })
                            onPicked: root.setOpt("colorspace", key)
                        }

                        Stepper {
                            label: "Saturation boost"
                            value: root.wallustOpts.saturation ?? 20
                            min:   0; max: 100; step: 5
                            onChanged: root.setOpt("saturation", v)
                        }

                        Toggle {
                            label: "Check contrast"
                            sub:   "Ensure readable contrast vs background"
                            on:    !!(root.wallustOpts.check_contrast)
                            onToggled: root.setOpt("check_contrast", !(root.wallustOpts.check_contrast))
                        }

                        SubLabel {
                            width: parent.width
                            text: "Options apply on the next wallpaper change. Use “Apply” to re-derive now."
                        }
                    }

                    CardLabel {
                        visible: !root.autoMode
                        text: root.schemes.length ? "FIXED SCHEME" : "No schemes in fixed_colors/"
                    }
                    Column {
                        width: parent.width; spacing: 4
                        visible: !root.autoMode
                        Repeater {
                            model: root.schemes
                            delegate: Item {
                                required property string modelData
                                readonly property bool   sel:    root.selected === modelData
                                readonly property var    cmap:   root.schemeColors[modelData] ?? {}
                                width: parent ? parent.width : 0
                                height: 50

                                StyledRect {
                                    anchors.fill: parent
                                    radius:       Style.rControl
                                    color:        sel ? Style.selFill : (hov.containsMouse ? Style.controlHover : Style.controlFill)
                                    borderWidth:  sel ? Style.selBorderW : Style.controlBorderW
                                    borderColor:  sel ? Style.selBorderColor : Style.controlBorderColor
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                }
                                Text {
                                    anchors { left: parent.left; leftMargin: 12
                                              verticalCenter: parent.verticalCenter }
                                    text:  root.displayName(modelData)
                                    color: sel ? Style.selText : Colors.fgPrimary
                                    font.pixelSize: Style.fsLabel; font.family: Style.font
                                    font.capitalization: Font.Capitalize
                                }
                                Row {
                                    anchors { right: checkMark.left; rightMargin: 8
                                              verticalCenter: parent.verticalCenter }
                                    spacing: 3
                                    Repeater {
                                        model: root.swatchKeys
                                        delegate: Rectangle {
                                            required property string modelData
                                            width: 14; height: 14; radius: 3
                                            color: cmap[modelData] ?? "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(0,0,0,0.25)
                                        }
                                    }
                                }
                                Text {
                                    id: checkMark
                                    visible: sel
                                    anchors { right: parent.right; rightMargin: 10
                                              verticalCenter: parent.verticalCenter }
                                    text: "✓"; color: Style.selText
                                    font.pixelSize: 12; font.family: Style.font
                                }
                                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
                                            onClicked: { root.selected = modelData; root.applyColours() } }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        Text {
                            width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                            text: root.colorStatus; color: Colors.fgMuted; font.pixelSize: 11
                            elide: Text.ElideRight; font.family: Style.font
                        }
                        TextButton { primary: true; label: "Apply"; onClicked: root.applyColours() }
                    }
                }
            }
        }
    }

    // ── Template preview card: mini-mock of bar position/mode over the template's wallpaper
    //    (or a per-style tint), name + built-in tag, active ring. Click activates. ──────────
    component TemplateCard: Item {
        id: tc
        property var tpl: ({})
        readonly property bool  active: !!tpl.active
        readonly property string pos:  tpl.bar_position || "top"
        readonly property string mode: tpl.bar_mode || "frame"
        // Only mirobo (and the user's own forks of it) is a real, selectable style for now; every
        // other shipped style is parked as a dimmed "SOON" preview until it is fully built out.
        readonly property bool  wip:  !!tpl.builtin && (tpl.id || "") !== "mirobo"
        height: 150

        StyledRect {
            anchors.fill: parent
            radius: Style.rControl
            color: tc.active ? Style.tint(Style.accent, 0.14)
                             : (!tc.wip && tcHov.containsMouse ? Style.controlHover : Style.controlFill)
            borderWidth: tc.active ? 2 : Style.controlBorderW
            borderColor: tc.active ? Style.accent : Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: 90 } }
        }

        // Mock viewport.
        Item {
            id: mock
            opacity: tc.wip ? 0.4 : 1
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 5 }
            height: parent.height - 34
            clip: true

            // ── Mini desktop mock — a shrunken real UI, not just a font sample: it reads the LIVE
            //    palette (Colors) + style tokens (Style) + the template's font, so the card shows the
            //    theme's colours, chrome and bar shape at a glance. ────────────────────────────────
            readonly property string tcFont: (tc.tpl.ui_font || "") !== "" ? tc.tpl.ui_font : Style.font
            // Palette-tinted backdrop (subtle accent wash) + an optional wallpaper the template carries.
            Rectangle {
                anchors.fill: parent; radius: 5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.bgPrimary }
                    GradientStop { position: 1.0; color: Style.tint(Colors.bgActive, 0.12) }
                }
            }
            Image {
                anchors.fill: parent; visible: (tc.tpl.wallpaper || "") !== ""
                source: (tc.tpl.wallpaper || "") !== "" ? "file://" + tc.tpl.wallpaper : ""
                fillMode: Image.PreserveAspectCrop; sourceSize.width: 200; asynchronous: true; opacity: 0.5
            }
            // Mini bar: workspace pill (accent) + dots · clock in the theme font · status dots.
            Rectangle {
                id: miniBar
                anchors { left: parent.left; right: parent.right; top: parent.top
                          margins: tc.mode === "float" ? 6 : 0 }
                height: 20; radius: tc.mode === "float" ? 6 : 0
                color: Style.tint(Colors.bgElement, 0.9)
                Row {
                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Rectangle { width: 13; height: 8; radius: 4; color: Colors.bgActive; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 6; height: 6; radius: 3; color: Style.tint(Colors.fgMuted, 0.6); anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 6; height: 6; radius: 3; color: Style.tint(Colors.fgMuted, 0.6); anchors.verticalCenter: parent.verticalCenter }
                }
                Text {
                    anchors.centerIn: parent; text: "12:34"; color: Colors.fgBright
                    font.family: tc.tcFont; font.pixelSize: 11; font.bold: true
                }
                Row {
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Rectangle { width: 6; height: 6; radius: 3; color: Colors.fgMuted; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 6; height: 6; radius: 3; color: Colors.fgMuted; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            // Mini menu card — shows the style's chrome (radius / border / fill) + an accent header.
            Rectangle {
                anchors { left: parent.left; leftMargin: 10; top: miniBar.bottom; topMargin: 10 }
                width: Math.round(parent.width * 0.48)
                height: parent.height - miniBar.height - 30
                radius: Math.max(3, Math.round(Style.rCard * 0.55))
                color: Style.tint(Colors.bgElement, 0.7)
                border.width: 1; border.color: Style.tint(Colors.boNormal, 0.5)
                Column {
                    anchors { left: parent.left; top: parent.top; leftMargin: 6; topMargin: 6; right: parent.right; rightMargin: 6 }
                    spacing: 5
                    Rectangle { width: 24; height: 5; radius: 2.5; color: Colors.bgActive }
                    Rectangle { width: parent.width; height: 3; radius: 1.5; color: Style.tint(Colors.fgMuted, 0.7) }
                    Rectangle { width: Math.round(parent.width * 0.75); height: 3; radius: 1.5; color: Style.tint(Colors.fgMuted, 0.7) }
                }
            }
            // Palette swatches — a peek at the actual wallust colours.
            Row {
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 9; bottomMargin: 9 }
                spacing: 3
                Repeater {
                    model: [Colors.bgActive, Colors.color2, Colors.color5, Colors.color9, Colors.fgBright]
                    delegate: Rectangle {
                        required property var modelData
                        width: 10; height: 10; radius: 2; color: modelData
                        border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                    }
                }
            }
        }

        // "SOON" badge on the parked styles.
        Rectangle {
            visible: tc.wip
            anchors { top: mock.top; right: mock.right; topMargin: 4; rightMargin: 4 }
            width: soonLbl.implicitWidth + 12; height: 17; radius: 8
            color: Style.tint(Colors.bgActive, 0.9)
            Text { id: soonLbl; anchors.centerIn: parent; text: "SOON"; color: Colors.bgPrimary
                   font.pixelSize: 9; font.bold: true; font.family: Style.font; font.letterSpacing: 0.5 }
        }

        Row {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: 9; rightMargin: 9; bottomMargin: 7 }
            spacing: 6
            Text {
                width: parent.width - (tc.active ? 30 : 0)
                text: (tc.tpl.name || "") + (tc.tpl.builtin ? "" : "  · yours")
                color: tc.wip ? Colors.fgMuted : (tc.active ? Colors.fgBright : Colors.fgPrimary)
                font.pixelSize: 12; font.bold: tc.active; font.family: Style.font
                elide: Text.ElideRight
            }
            Text { visible: tc.active; text: "󰄬"; color: Style.accent
                   font.pixelSize: 13; font.family: Style.font }
        }

        // mirobo (and its forks) activate on click; the active card re-opens the customiser.
        // Parked "SOON" styles are inert until they are built out.
        MouseArea {
            id: tcHov; anchors.fill: parent; hoverEnabled: !tc.wip
            cursorShape: tc.wip ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                if (tc.wip) return
                if (tc.active) root.page = "build"
                else           Templates.activate(tc.tpl.source, tc.tpl.id)
            }
        }
    }
}
