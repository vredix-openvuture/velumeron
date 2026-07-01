import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Style settings: the global UI-style variant, the Colorful master + per-surface sub-toggles, the
// grow-from-bar transition style, and the wallust colour mode (automatic vs. fixed scheme).
// All controls come from quickshell/common (token-driven shared components).
Item {
    id: root

    // ── Colours (wallust mode) ──
    property bool   autoMode:    true
    property var    schemes:     []
    property string selected:    ""
    property string colorStatus: ""

    Component.onCompleted: reload()
    onVisibleChanged:      if (visible) reload()

    function displayName(f) { return ("" + f).replace(/\.json$/, "") }

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
        return ({ fillet: "Tapered (fillet)", straight: "Straight — all edges",
                  straight_origin: "Straight — origin edge" })[k] ?? k
    }
    function styleLabelG(k) { return k === "global" ? "Follow global" : styleLabel(k) }
    function styleOpts(current, withGlobal) {
        var base = withGlobal ? [{ key: "global", label: "Follow global" }] : []
        base.push({ key: "fillet",          label: "Tapered (fillet)" })
        base.push({ key: "straight",        label: "Straight — all edges" })
        base.push({ key: "straight_origin", label: "Straight — origin edge" })
        return base.map(function (o) { return { label: o.label, key: o.key, on: current === o.key } })
    }

    function reload() {
        colorStatus = ""
        schemes     = []
        loadProc.running = false; loadProc.running = true
    }

    // Persist one key into settings.json (VtlConfig picks it up on its poll).
    function save(key, value) {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
              "or os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = ["python3", "-c", py, key, JSON.stringify(value)]
        saveProc.running = false; saveProc.running = true
    }
    Process { id: saveProc }

    function applyColours() {
        if (autoMode) {
            applyColourProc.command = ["bash", "-c", "\"$VELUMERON_DIR/assets/scripts/apply-theme.sh\" auto"]
            colorStatus = "Saved — automatic colours active."
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
    Timer { id: colorClear; interval: 4000
            onTriggered: if (!root.colorStatus.endsWith("…")) root.colorStatus = "" }

    // ── Template (preset) editor state ──
    property string _tplEdit: ""   // "" | "new" | "rename"
    function _tplBeginNew()    { _tplEdit = "new";    tplNameInput.text = "";                    tplNameInput.forceActiveFocus() }
    function _tplBeginRename() { _tplEdit = "rename"; tplNameInput.text = Templates.activeName;  tplNameInput.forceActiveFocus() }
    function _tplCommit() {
        var n = ("" + tplNameInput.text).trim()
        if (n === "") { _tplEdit = ""; return }
        if      (_tplEdit === "new")    Templates.create(n)
        else if (_tplEdit === "rename") Templates.rename(Templates.activeId, n)
        _tplEdit = ""
    }

    // ── Content ──────────────────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Template (preset) ─────────────────────────────────────────────
            Card {
                CardLabel { text: "TEMPLATE" }
                SubLabel { width: parent.width
                           text: "Switch the whole look. Editing anything forks a private copy — the built-in presets stay untouched." }

                Text {
                    width:   parent.width
                    visible: Templates.activeName !== ""
                    text:    "Active: " + Templates.activeName + (Templates.activeIsBuiltin ? "  · built-in" : "  · your copy")
                    color:   Colors.fgMuted; font.pixelSize: Style.fsSub; font.family: Style.font
                    elide:   Text.ElideRight
                }

                // Available templates — built-ins first, then user copies.
                Column {
                    width: parent.width; spacing: 4
                    Repeater {
                        model: Templates.templates
                        delegate: SelectRow {
                            required property var modelData
                            label:    modelData.name + (modelData.builtin ? "  · built-in" : "")
                            selected: modelData.active
                            onClicked: Templates.activate(modelData.source, modelData.id)
                        }
                    }
                }

                // Inline name editor (New / Rename).
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

                // Actions.
                Flow {
                    width: parent.width; spacing: 8
                    TextButton { label: "New";       onClicked: root._tplBeginNew() }
                    TextButton { label: "Duplicate"; onClicked: Templates.duplicate(Templates.activeSource, Templates.activeId, "") }
                    TextButton { label: "Rename"; visible: !Templates.activeIsBuiltin && Templates.activeId !== ""
                                 onClicked: root._tplBeginRename() }
                    TextButton { label: "Delete"; visible: !Templates.activeIsBuiltin && Templates.activeId !== ""
                                 onClicked: Templates.remove(Templates.activeId) }
                }
            }

            // ── UI style variant ──────────────────────────────────────────────
            Card {
                CardLabel { text: "UI STYLE" }
                SubLabel { width: parent.width
                           text: "Look of every menu and the quick-panel. Switches live." }
                Segmented {
                    equal: true
                    current: VtlConfig.uiStyle
                    segments: [{ label: "Flat", key: "flat" }, { label: "Cards", key: "cards" },
                               { label: "Outlined", key: "outlined" }]
                    onPicked: { VtlConfig.applyLocal("ui_style", key); root.save("ui_style", key) }
                }
            }

            // ── Colorful ──────────────────────────────────────────────────────
            Card {
                CardLabel { text: "COLORFUL" }
                Toggle {
                    label: "Colorful"
                    sub:   "Blend a hint of the accent into surfaces"
                    on:    VtlConfig.colorfulEnabled
                    onToggled: root.save("colorful_enabled", !VtlConfig.colorfulEnabled)
                }
                // Per-surface sub-toggles — only while the master is on.
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
            }

            // ── Transition ────────────────────────────────────────────────────
            Card {
                CardLabel { text: "TRANSITION" }
                SubLabel {
                    width: parent.width
                    text: "How OSD, menus and notifications meet the bar (or bare monitor edge) they grow from — set per context."
                }

                FieldLabel { text: "Global — when on a bar" }
                Dropdown {
                    summary: root.styleLabel(VtlConfig.transitionGlobalRaw("bar"))
                    options: root.styleOpts(VtlConfig.transitionGlobalRaw("bar"), false)
                    onPicked: root.save("transition_style_bar", key)
                }
                FieldLabel { text: "Global — when on a monitor edge" }
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

            // ── Colours (wallust mode) ────────────────────────────────────────
            Card {
                CardLabel { text: "COLOURS" }
                Toggle {
                    label: "Automatic colours"
                    sub:   "Derive from the wallpaper on each change"
                    on:    root.autoMode
                    onToggled: root.autoMode = !root.autoMode
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
                        delegate: SelectRow {
                            required property string modelData
                            label:    root.displayName(modelData)
                            selected: root.selected === modelData
                            onClicked: root.selected = modelData
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
