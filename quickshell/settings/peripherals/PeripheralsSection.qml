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
                    summary: root.curTheme === "" ? "(default)" : root.curTheme
                    options: root.themes.map(function (t) {
                        return { label: t, key: t, on: t === root.curTheme }
                    })
                    onPicked: key => { root.curTheme = key; root.dirty = true }
                }
                Stepper {
                    label: "Size"; unit: "px"; min: 8; max: 64; step: 2; labelWidth: 110
                    value: root.curSize
                    onChanged: v => { root.curSize = v; root.dirty = true }
                }
            }

            Card {
                CardLabel { text: "FUNCTION KEYS" }
                SubLabel {
                    width: parent.width
                    text: "Stored for keyboards without dedicated media keys — the default keybinds "
                        + "use the XF86 media events directly, so these mappings are not consumed yet."
                }
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
