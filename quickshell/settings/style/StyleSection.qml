import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Style settings: the Colorful master + per-surface sub-toggles, and the wallust colour mode
// (automatic vs. fixed scheme) moved here from the old wallpaper settings.
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
        { key: "flyout",        label: "Bar flyouts" }
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
            spacing: 18

            // ── Colorful ──────────────────────────────────────────────────────
            Group {
                Text { text: "COLORFUL"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }

                Toggle {
                    title:    "Colorful"
                    subtitle: "Blend a hint of the accent into surfaces"
                    on:       VtlConfig.colorfulEnabled
                    onToggled: root.save("colorful_enabled", !VtlConfig.colorfulEnabled)
                }
                // Per-surface sub-toggles — only while the master is on.
                Column {
                    width:   parent.width
                    spacing: 6
                    visible: VtlConfig.colorfulEnabled
                    Toggle { indent: true; title: "Bar";   on: VtlConfig.colorfulBarSub
                             onToggled: root.save("colorful_bar",   !VtlConfig.colorfulBarSub) }
                    Toggle { indent: true; title: "Menus"; on: VtlConfig.colorfulMenusSub
                             onToggled: root.save("colorful_menus", !VtlConfig.colorfulMenusSub) }
                    Toggle { indent: true; title: "OSD";   on: VtlConfig.colorfulOsdSub
                             onToggled: root.save("colorful_osd",   !VtlConfig.colorfulOsdSub) }
                }
            }

            // ── Transition ────────────────────────────────────────────────────
            Group {
                Text { text: "TRANSITION"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "How OSD, menus and notifications meet the bar (or bare monitor edge) they grow from — set per context."
                    color: Colors.fgMuted; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
                }

                SubLabel { text: "Global — when on a bar" }
                Dropdown {
                    summary: root.styleLabel(VtlConfig.transitionGlobalRaw("bar"))
                    options: root.styleOpts(VtlConfig.transitionGlobalRaw("bar"), false)
                    onPicked: root.save("transition_style_bar", key)
                }
                SubLabel { text: "Global — when on a monitor edge" }
                Dropdown {
                    summary: root.styleLabel(VtlConfig.transitionGlobalRaw("edge"))
                    options: root.styleOpts(VtlConfig.transitionGlobalRaw("edge"), false)
                    onPicked: root.save("transition_style_edge", key)
                }

                // Per-menu overrides — collapsed until opened.
                Rectangle {
                    id: perMenuHead
                    property bool open: false
                    width: parent.width; height: 34; radius: 8
                    color: phHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20)
                                               : Colors.bgElement
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: "Per-menu overrides"; color: Colors.fgPrimary
                        font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: perMenuHead.open ? "▴" : "▾"; color: Colors.fgMuted
                        font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
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
            Group {
                Text { text: "COLOURS"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }

                Toggle {
                    title:    "Automatic colours"
                    subtitle: "Derive from the wallpaper on each change"
                    on:       root.autoMode
                    onToggled: root.autoMode = !root.autoMode
                }

                Text {
                    visible: !root.autoMode
                    text: root.schemes.length ? "FIXED SCHEME" : "No schemes in fixed_colors/"
                    color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                    font.family: "FantasqueSansM Nerd Font"
                }
                Column {
                    width: parent.width; spacing: 4
                    visible: !root.autoMode
                    Repeater {
                        model: root.schemes
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool sel: root.selected === modelData
                            width: parent.width; height: 34; radius: 8
                            color: sel ? Colors.bgActive
                                 : (rHov.containsMouse
                                    ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.18)
                                    : Colors.bgElement)
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Text {
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: root.displayName(parent.modelData)
                                color: parent.sel ? Colors.fgBright : Colors.fgPrimary
                                font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
                            }
                            MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.selected = parent.modelData }
                        }
                    }
                }

                Row {
                    width: parent.width
                    Text {
                        width: parent.width - 72; anchors.verticalCenter: parent.verticalCenter
                        text: root.colorStatus; color: Colors.fgMuted; font.pixelSize: 11
                        elide: Text.ElideRight; font.family: "FantasqueSansM Nerd Font"
                    }
                    Rectangle {
                        width: 64; height: 28; radius: 6
                        color: acHov.containsMouse ? Colors.boActive : Colors.bgActive
                        Text { anchors.centerIn: parent; text: "Apply"; color: Colors.fgBright; font.bold: true
                               font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font" }
                        MouseArea { id: acHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: root.applyColours() }
                    }
                }
            }
        }
    }

    // ── Reusable bits ──────────────────────────────────────────────────────────────
    component Group: Rectangle {
        default property alias content: inner.data
        width:  parent ? parent.width : 0
        radius: 12
        color:  Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.08)
        height: inner.implicitHeight + 24
        Column {
            id: inner
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 12; leftMargin: 12; rightMargin: 12 }
            spacing: 8
        }
    }

    component FieldLabel: Text {
        color: Colors.fgBright; font.pixelSize: 12; font.bold: true
        font.letterSpacing: 0.5; font.family: "FantasqueSansM Nerd Font"
    }
    component SubLabel: Text {
        color: Colors.fgMuted; font.pixelSize: 10
        font.family: "FantasqueSansM Nerd Font"
    }

    // Compact inline-expanding dropdown (mirrors the OSD / Notifications settings pages).
    component Dropdown: Column {
        id: dd
        property var    options: []
        property string summary: ""
        property bool   open:    false
        signal picked(string key)
        width:   parent ? parent.width : 0
        spacing: 4

        Rectangle {
            width: parent.width; height: 34; radius: 8
            color: ddHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                       : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20)
            border.width: dd.open ? 2 : 1
            border.color: Colors.bgActive
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors { left: parent.left; leftMargin: 12; right: chev.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                text: dd.summary; color: Colors.fgPrimary; elide: Text.ElideRight
                font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font"
            }
            Text { id: chev; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                   text: dd.open ? "▴" : "▾"; color: Colors.fgMuted; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
            MouseArea { id: ddHov; anchors.fill: parent; hoverEnabled: true; onClicked: dd.open = !dd.open }
        }
        Column {
            visible: dd.open
            width: parent.width; spacing: 3
            Repeater {
                model: dd.options
                delegate: Rectangle {
                    required property var modelData
                    width: dd.width; height: 30; radius: 7
                    color: modelData.on ? Colors.bgActive
                         : (oHov.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.34)
                                               : Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20))
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: modelData.label; color: modelData.on ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font"
                    }
                    Text { visible: modelData.on; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                           text: "✓"; color: Colors.fgBright; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
                    MouseArea { anchors.fill: parent; hoverEnabled: true; id: oHov
                                onClicked: { dd.picked(modelData.key); dd.open = false } }
                }
            }
        }
    }

    component Toggle: Rectangle {
        id: tg
        property string title:    ""
        property string subtitle: ""
        property bool   on:       false
        property bool   indent:   false
        signal toggled()
        width:  parent ? parent.width - (indent ? 12 : 0) : 0
        x:      indent ? 12 : 0
        height: tg.subtitle !== "" ? 46 : 38
        radius: 10
        color:  indent ? Qt.rgba(Colors.bgElement.r, Colors.bgElement.g, Colors.bgElement.b, 0.5) : Colors.bgElement
        Column {
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { text: tg.title; color: Colors.fgPrimary
                   font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
            Text { visible: tg.subtitle !== ""; text: tg.subtitle; color: Colors.fgMuted
                   font.pixelSize: 10; font.family: "FantasqueSansM Nerd Font" }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 42; height: 22; radius: 11
            color: tg.on ? Colors.bgActive : Colors.bgPrimary
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8; color: Colors.fgBright
                anchors.verticalCenter: parent.verticalCenter
                x: tg.on ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
            MouseArea { anchors.fill: parent; onClicked: tg.toggled() }
        }
    }
}
