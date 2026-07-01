import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// OSD settings — the system OSD (volume / brightness / workspace banner) and the
// notification-popup placement. Writes live to settings.json; the OSD/notifications follow via
// VtlConfig's poll. All controls come from quickshell/common (token-driven shared components).
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
            spacing: Style.cardGap

            // ── Wallpaper quick-menu ──────────────────────────────────────────
            Card {
                CardLabel { text: "WALLPAPER QUICK-MENU" }
                SubLabel {
                    width: parent.width
                    text: "Swaps the focused monitor's wallpaper, grown out of the bar (per-monitor folder). "
                        + "Bind it in Hyprland, e.g.:\n  bind = $mod, W, exec, qs -p ~/.config/velumeron/quickshell ipc call wallpaper toggle"
                }
            }

            // ── System OSD: placement ─────────────────────────────────────────
            Card {
                CardLabel { text: "SYSTEM OSD" }
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
            Card {
                CardLabel { text: "VOLUME" }
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
            Card {
                CardLabel { text: "BRIGHTNESS" }
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
            Card {
                CardLabel { text: "WORKSPACE" }
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
            Card {
                CardLabel { text: "APPEARANCE" }
                Stepper { label: "Duration"; unit: "ms"; step: 100; min: 400; max: 6000
                          value: VtlConfig.osdDuration; onChanged: root.save("osd_duration_ms", v) }
                Stepper { label: "Edge margin"; unit: "px"; step: 5; min: 0; max: 600
                          value: VtlConfig.osdMargin; onChanged: root.save("osd_margin_px", v) }
                Stepper { label: "Width"; unit: "px"; step: 5; min: 120; max: 900
                          value: VtlConfig.osdWidth; onChanged: root.save("osd_width_px", v) }
                Stepper { label: "Height"; unit: "px"; step: 5; min: 32; max: 200
                          value: VtlConfig.osdHeight; onChanged: root.save("osd_height_px", v) }
            }
        }
    }
}
