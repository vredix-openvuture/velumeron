import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// OSD settings — the system OSD (volume / brightness / workspace banner) and the
// notification-popup placement. Mirrors the old GTK GUI's OSD page. Writes live to
// settings.json; the OSD/notifications follow via VtlConfig's poll.
Item {
    id: root

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }
    function posLabel(p) { return p.split("-").map(root.cap).join(" ") }
    function dispLabel(k) {
        return ({ bar_and_value: "Bar + value", bar_only: "Bar only", value_only: "Value only",
                  dots_only: "Dots", number_only: "Number", dots_and_number: "Dots + number" })[k] ?? k
    }

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

    readonly property var notifyPositions: ["top-left", "top-center", "top-right",
                                            "bottom-left", "bottom-center", "bottom-right"]
    readonly property var sysDisplay: ["bar_and_value", "bar_only", "value_only"]
    readonly property var wsDisplay:  ["dots_only", "number_only", "dots_and_number"]

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

            // ── Wallpaper quick-menu ──────────────────────────────────────────
            Group {
                Text { text: "WALLPAPER QUICK-MENU"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Swaps the focused monitor's wallpaper, grown out of the bar (per-monitor folder). "
                        + "Bind it in Hyprland, e.g.:\n  bind = $mod, W, exec, qs -p ~/.config/velumeron/quickshell ipc call wallpaper toggle"
                    color: Colors.fgMuted; font.pixelSize: 11; font.family: "FantasqueSansM Nerd Font"
                }
            }

            // ── System OSD: placement ─────────────────────────────────────────
            Group {
                Text { text: "SYSTEM OSD"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                FieldLabel { text: "Position" }
                PosGrid { current: VtlConfig.osdPosition; onPicked: root.save("osd_position", key) }
                FieldLabel { text: "Style" }
                Dropdown {
                    summary: root.cap(VtlConfig.osdStyle)
                    options: [{ label: "Float", key: "float", on: VtlConfig.osdStyle === "float" },
                              { label: "Dock",  key: "dock",  on: VtlConfig.osdStyle === "dock"  }]
                    onPicked: root.save("osd_style", key)
                }
            }

            // ── Volume ────────────────────────────────────────────────────────
            Group {
                Text { text: "VOLUME"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Toggle { label: "Enable"; sub: "Show OSD on volume change"
                         on: VtlConfig.osdVolume; onToggled: root.save("osd_volume", !VtlConfig.osdVolume) }
                FieldLabel { text: "Display" }
                Dropdown {
                    summary: root.dispLabel(VtlConfig.osdVolumeDisplay)
                    options: root.sysDisplay.map(function (k) { return { label: root.dispLabel(k), key: k, on: VtlConfig.osdVolumeDisplay === k } })
                    onPicked: root.save("osd_volume_display", key)
                }
                Toggle { label: "Show device"; sub: "Audio output name under the bar"
                         on: VtlConfig.osdShowDevice; onToggled: root.save("osd_show_device", !VtlConfig.osdShowDevice) }
            }

            // ── Brightness ────────────────────────────────────────────────────
            Group {
                Text { text: "BRIGHTNESS"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Toggle { label: "Enable"; sub: "Show OSD on brightness change"
                         on: VtlConfig.osdBrightness; onToggled: root.save("osd_brightness", !VtlConfig.osdBrightness) }
                FieldLabel { text: "Display" }
                Dropdown {
                    summary: root.dispLabel(VtlConfig.osdBrightnessDisplay)
                    options: root.sysDisplay.map(function (k) { return { label: root.dispLabel(k), key: k, on: VtlConfig.osdBrightnessDisplay === k } })
                    onPicked: root.save("osd_brightness_display", key)
                }
            }

            // ── Workspace ─────────────────────────────────────────────────────
            Group {
                Text { text: "WORKSPACE"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Toggle { label: "Enable"; sub: "Show OSD when switching workspaces"
                         on: VtlConfig.osdWorkspace; onToggled: root.save("osd_workspace", !VtlConfig.osdWorkspace) }
                Toggle { label: "Same monitor only"; sub: "Only on the active monitor's change"
                         on: VtlConfig.osdWorkspaceLocalOnly; onToggled: root.save("osd_workspace_local_only", !VtlConfig.osdWorkspaceLocalOnly) }
                FieldLabel { text: "Display" }
                Dropdown {
                    summary: root.dispLabel(VtlConfig.osdWorkspaceDisplay)
                    options: root.wsDisplay.map(function (k) { return { label: root.dispLabel(k), key: k, on: VtlConfig.osdWorkspaceDisplay === k } })
                    onPicked: root.save("osd_workspace_display", key)
                }
            }

            // ── Appearance ────────────────────────────────────────────────────
            Group {
                Text { text: "APPEARANCE"; color: Colors.fgMuted; font.pixelSize: 10; font.bold: true
                       font.family: "FantasqueSansM Nerd Font" }
                Stepper { label: "Duration"; unit: "ms"; step: 100; min: 400; max: 6000
                          value: VtlConfig.osdDuration; onChanged: root.save("osd_duration_ms", v) }
                Stepper { label: "Edge margin"; unit: "px"; step: 5;min: 0; max: 600
                          value: VtlConfig.osdMargin; onChanged: root.save("osd_margin_px", v) }
                Stepper { label: "Width"; unit: "px"; step: 5; min: 120; max: 900
                          value: VtlConfig.osdWidth; onChanged: root.save("osd_width_px", v) }
                Stepper { label: "Height"; unit: "px"; step: 5;min: 32; max: 200
                          value: VtlConfig.osdHeight; onChanged: root.save("osd_height_px", v) }
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
        color: Colors.fgMuted; font.pixelSize: 11; font.bold: true
        font.letterSpacing: 0.5; font.family: "FantasqueSansM Nerd Font"
    }

    // Label + sliding switch.
    component Toggle: Rectangle {
        id: tg
        property string label: ""
        property string sub:   ""
        property bool   on:    false
        signal toggled()
        width:  parent ? parent.width : 0
        height: tg.sub !== "" ? 46 : 38
        radius: 10
        color:  Colors.bgElement
        Column {
            anchors { left: parent.left; leftMargin: 12; right: knob.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { text: tg.label; color: Colors.fgPrimary; font.pixelSize: 13
                   font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
            Text { visible: tg.sub !== ""; text: tg.sub; color: Colors.fgMuted; font.pixelSize: 10
                   font.family: "FantasqueSansM Nerd Font"; elide: Text.ElideRight; width: parent.width }
        }
        Rectangle {
            id: knob
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

    // Label + −/value/+ stepper.
    component Stepper: Row {
        id: st
        property string label: ""
        property string unit:  ""
        property int    value: 0
        property int    step:  5
        property int    min:   0
        property int    max:   9999
        signal changed(int v)
        width:   parent ? parent.width : 0
        spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: 92; text: st.label
               color: Colors.fgPrimary; font.pixelSize: 12; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: mh.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "−"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: mh; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.max(st.min, st.value - st.step)) }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; width: 60; horizontalAlignment: Text.AlignHCenter
               text: st.value + (st.unit !== "" ? " " + st.unit : ""); color: Colors.fgBright
               font.pixelSize: 13; font.family: "FantasqueSansM Nerd Font" }
        Rectangle {
            width: 26; height: 26; radius: 6; color: ph.containsMouse ? Colors.bgActive : Colors.bgElement
            Text { anchors.centerIn: parent; text: "+"; color: Colors.fgPrimary; font.pixelSize: 14 }
            MouseArea { id: ph; anchors.fill: parent; hoverEnabled: true
                        onClicked: st.changed(Math.min(st.max, st.value + st.step)) }
        }
    }

    // 3×3 placement grid (centre cell is a spacer).
    component PosGrid: Item {
        id: pg
        property string current: ""
        signal picked(string key)
        width:  parent ? parent.width : 0
        height: grid.height
        Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3; rowSpacing: 4; columnSpacing: 4
            Repeater {
                model: [{ k: "top-left", s: "↖" }, { k: "top-center", s: "↑" }, { k: "top-right", s: "↗" },
                        { k: "center-left", s: "←" }, { k: "", s: "" }, { k: "center-right", s: "→" },
                        { k: "bottom-left", s: "↙" }, { k: "bottom-center", s: "↓" }, { k: "bottom-right", s: "↘" }]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: pg.current === modelData.k && modelData.k !== ""
                    width: 58; height: 30; radius: 7
                    color: modelData.k === "" ? "transparent"
                         : sel ? Colors.bgActive
                         : (gh.containsMouse ? Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.20) : Colors.bgElement)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: modelData.s
                           color: parent.sel ? Colors.fgBright : Colors.fgPrimary
                           font.pixelSize: 14; font.family: "FantasqueSansM Nerd Font" }
                    MouseArea { id: gh; anchors.fill: parent; hoverEnabled: modelData.k !== ""
                                enabled: modelData.k !== ""; onClicked: pg.picked(modelData.k) }
                }
            }
        }
    }

    // Compact inline-expanding dropdown.
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
}
