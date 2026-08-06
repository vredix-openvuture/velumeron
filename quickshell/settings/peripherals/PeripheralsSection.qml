import "../.."
import QtQuick
import Quickshell.Io

// Peripherals: cursor theme/size and the fn-key mapping variables from user_settings.lua.
// Apply writes the PERIPHERALS section (the helper also runs `hyprctl setcursor`) and reloads.
Item {
    id: root

    property string curTheme: ""
    property int    curSize:  24
    property var    fn:       ({})
    property var    themes:   []
    property bool   dirty:    false
    property string status:   ""
    property string previewPath: ""   // rendered PNG of the selected cursor (cursor-preview.sh)
    readonly property string dynTheme: "velumeron-dynamic"   // wallust-following cursor (cursor-build.py)

    readonly property var fnKeys: [
        { key: "brightness_up",   label: "Brightness up" },
        { key: "brightness_down", label: "Brightness down" },
        { key: "play_stop_play",  label: "Play / pause" },
        { key: "play_next",       label: "Next track" },
        { key: "play_prev",       label: "Previous track" },
        { key: "volume_up",       label: "Volume up" },
        { key: "volume_down",     label: "Volume down" },
        { key: "volume_mute",     label: "Mute" }
    ]

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    // Render a fresh preview whenever the chosen theme changes (from reload or a pick).
    onCurThemeChanged: root._preview(curTheme)
    function reload() {
        UserSettings.get("peripherals", function (d) {
            if (!d) return
            root.curTheme = d.cursor.theme || ""
            root.curSize = d.cursor.size || 24
            root.fn = d.fn || {}
            root.dirty = false
            root.status = ""
        })
        root.themes = []
        themeProc.running = false; themeProc.running = true
    }
    function setFn(key, val) {
        var f = Object.assign({}, root.fn)
        f[key] = val
        root.fn = f
        root.dirty = true
    }
    function apply() {
        root.status = "Applying…"
        UserSettings.set("peripherals", { cursor: { theme: root.curTheme, size: root.curSize }, fn: root.fn })
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "peripherals") return
            root.status = ok ? "Applied ✓" : ("" + (errors[0] || "Failed"))
            if (ok) root.dirty = false
        }
    }

    // Installed cursor themes = icon dirs that contain a cursors/ subdir.
    readonly property string _themesPy:
        "import os,glob;" +
        "seen=[];" +
        "bases=['/usr/share/icons',os.path.expanduser('~/.local/share/icons'),os.path.expanduser('~/.icons')];" +
        "[seen.append(os.path.basename(os.path.dirname(d))) for b in bases " +
          "for d in sorted(glob.glob(os.path.join(b,'*','cursors'))) " +
          "if os.path.basename(os.path.dirname(d)) not in seen];" +
        "print('\\n'.join(seen))"
    Process {
        id: themeProc
        command: ["python3", "-c", root._themesPy]
        stdout: SplitParser {
            onRead: line => {
                var t = ("" + line).trim()
                if (t !== "") root.themes = root.themes.concat([t])
            }
        }
    }

    // ── Preview: render the selected theme's pointer to a PNG (cached) ───────────
    Process {
        id: previewProc
        stdout: SplitParser { onRead: line => { var p = ("" + line).trim(); if (p.length) root.previewPath = p } }
    }
    function _preview(theme) {
        root.previewPath = ""
        if (!theme || theme === "") return
        previewProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/cursor-preview.sh\" " + JSON.stringify(theme)]
        previewProc.running = false; previewProc.running = true
    }
    // Live preview: apply the cursor for real so it changes ON SCREEN immediately (Apply persists it
    // to user_settings). setcursor alone only reloads the theme — the cursor that is currently ON the
    // menu surface doesn't re-render until the pointer re-enters a surface, so it looks like nothing
    // happened until the menu closes. Warping the cursor to its OWN position (no visible jump) forces
    // Hyprland to re-resolve the cursor image right away. hl.dsp.cursor.move is the hypr.lua form —
    // the raw `dispatch movecursor` keyword is dead in this config.
    // Picking the wallust-following theme (re)builds it from the current palette
    // first (it may not exist yet, or predate the latest wallpaper), then applies.
    Process {
        id: buildDynProc
        onExited: exitCode => {
            root.status = exitCode === 0 ? "" : "cursor build failed"
            root._preview(root.dynTheme)
            root._liveCursor(root.dynTheme, root.curSize)
        }
    }
    function _buildDynamic() {
        root.status = "Building cursor…"
        buildDynProc.command = ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/cursor-build.py\""]
        buildDynProc.running = false; buildDynProc.running = true
    }

    Process { id: setCursorProc }
    function _liveCursor(theme, size) {
        if (!theme || theme === "") return
        setCursorProc.command = ["bash", "-c",
            "hyprctl setcursor \"$1\" \"$2\" >/dev/null 2>&1; " +
            "p=$(hyprctl cursorpos 2>/dev/null); x=${p%,*}; y=${p#*, }; " +
            "[ -n \"$x\" ] && hyprctl dispatch \"hl.dsp.cursor.move({x=$x, y=$y})\" >/dev/null 2>&1",
            "_", theme, "" + size]
        setCursorProc.running = false; setCursorProc.running = true
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
                CardLabel { text: "CURSOR" }
                FieldLabel { text: "Theme" }
                Dropdown {
                    function _label(t) {
                        return t === root.dynTheme ? t + "   ·   follows wallpaper" : t
                    }
                    summary: root.curTheme === "" ? "(default)" : _label(root.curTheme)
                    // Pin the wallust-following theme to the top, always offered even
                    // before its first build (picking it builds it on demand).
                    options: {
                        var list = root.themes.filter(t => t !== root.dynTheme)
                        list.unshift(root.dynTheme)
                        return list.map(t => ({ label: _label(t), key: t, on: t === root.curTheme }))
                    }
                    onPicked: key => {
                        root.curTheme = key; root.dirty = true
                        if (key === root.dynTheme) root._buildDynamic()
                        else root._liveCursor(key, root.curSize)
                    }
                }

                // ── Preview: a rendered thumbnail of the chosen pointer ─────────
                Row {
                    width: parent.width; spacing: 12
                    Rectangle {
                        width: 72; height: 72; radius: Style.rControl
                        color: Colors.bgElement
                        border.width: Style.controlBorderW; border.color: Style.controlBorderColor
                        Image {
                            id: curImg
                            anchors.centerIn: parent
                            source: root.previewPath !== "" ? "file://" + root.previewPath : ""
                            sourceSize.width: 48; sourceSize.height: 48
                            width: 48; height: 48; fillMode: Image.PreserveAspectFit
                            smooth: true; cache: false
                            visible: status === Image.Ready
                        }
                        Text { anchors.centerIn: parent; visible: curImg.status !== Image.Ready
                               text: "󰇀"; color: Colors.fgMuted; font.pixelSize: 26; font.family: Style.iconFont }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 72 - 12
                        spacing: 3
                        Text { text: root.curTheme === "" ? "System default" : root.curTheme
                               color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.bold: true
                               font.family: Style.font; elide: Text.ElideRight; width: parent.width }
                        SubLabel { width: parent.width
                                   text: root.curTheme === root.dynTheme
                                         ? "Recolours itself from the wallpaper palette on every theme change."
                                         : "Live preview — the real cursor changes as you pick. Apply to keep it." }
                    }
                }

                Stepper {
                    label: "Size"; unit: "px"; min: 8; max: 64; step: 2; labelWidth: 110
                    value: root.curSize
                    onChanged: v => { root.curSize = v; root.dirty = true; root._liveCursor(root.curTheme, v) }
                }
            }

            Card {
                CardLabel { text: "FUNCTION KEYS"
                            hint: "Stored for keyboards without dedicated media keys — the default keybinds "
                                  + "use the XF86 media events directly, so these mappings are not consumed yet." }
                Repeater {
                    model: root.fnKeys
                    delegate: Dropdown {
                        required property var modelData
                        summary: modelData.label + "   —   " + (root.fn[modelData.key] || "unset")
                        options: {
                            var out = []
                            for (var i = 1; i <= 12; i++)
                                out.push({ label: "F" + i, key: "F" + i,
                                           on: root.fn[modelData.key] === ("F" + i) })
                            return out
                        }
                        onPicked: key => root.setFn(modelData.key, key)
                    }
                }
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
}
