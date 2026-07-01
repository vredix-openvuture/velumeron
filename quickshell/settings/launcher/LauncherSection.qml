import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Launcher settings — the Super+Space app launcher (quickshell/launcher/Launcher.qml). Placement,
// size and list-vs-grid layout. Writes live to settings.json; the launcher follows via VtlConfig's
// poll. Uses the shared common components.
Item {
    id: root

    function posLabel(p) {
        return ({ "top-left": "Top left", "top-center": "Top", "top-right": "Top right",
                  "center-left": "Left", "center": "Centre", "center-right": "Right",
                  "bottom-left": "Bottom left", "bottom-center": "Bottom", "bottom-right": "Bottom right" })[p] ?? p
    }
    readonly property var positions: ["top-left", "top-center", "top-right",
                                      "center-left", "center", "center-right",
                                      "bottom-left", "bottom-center", "bottom-right"]

    function save(key, value) {
        VtlConfig.applyLocal(key, value)   // instant feedback; the write below persists it
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

            // ── Mode ──────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "MODE" }
                Toggle {
                    label: "Fullscreen"
                    sub:   "Cover the screen with a large app grid"
                    on:    VtlConfig.launcherFullscreen
                    onToggled: root.save("launcher_fullscreen", !VtlConfig.launcherFullscreen)
                }
                Toggle {
                    label: "Blur backdrop"
                    sub:   "Blur what's behind the launcher"
                    on:    VtlConfig.launcherBlur
                    onToggled: root.save("launcher_blur", !VtlConfig.launcherBlur)
                }
            }

            // ── Window (windowed mode only) ───────────────────────────────────
            Card {
                visible: !VtlConfig.launcherFullscreen
                CardLabel { text: "WINDOW" }
                FieldLabel { text: "Position" }
                Dropdown {
                    summary: root.posLabel(VtlConfig.launcherPosition)
                    options: root.positions.map(function (p) { return { label: root.posLabel(p), key: p, on: VtlConfig.launcherPosition === p } })
                    onPicked: root.save("launcher_position", key)
                }
                Toggle {
                    label: "Dock to edge"
                    sub:   "Snap flush against the bar/edge instead of floating"
                    on:    VtlConfig.launcherDock
                    onToggled: root.save("launcher_dock", !VtlConfig.launcherDock)
                }
                Stepper { label: "Width"; unit: "px"; step: 20; min: 320; max: 1200; labelWidth: 96
                          value: VtlConfig.launcherWidth; onChanged: root.save("launcher_width", v) }
                Stepper { label: "Visible rows"; step: 1; min: 3; max: 16; labelWidth: 96
                          value: VtlConfig.launcherRows; onChanged: root.save("launcher_rows", v) }
                Stepper { label: "Columns"; step: 1; min: 1; max: 6; labelWidth: 96
                          value: VtlConfig.launcherCols; onChanged: root.save("launcher_cols", v) }
                SubLabel { width: parent.width; text: "Columns: 1 = list · more = grid." }
            }

            // ── Fullscreen grid ───────────────────────────────────────────────
            Card {
                visible: VtlConfig.launcherFullscreen
                CardLabel { text: "FULLSCREEN GRID" }
                Stepper { label: "Columns"; step: 1; min: 3; max: 12; labelWidth: 96
                          value: VtlConfig.launcherFsCols; onChanged: root.save("launcher_fs_cols", v) }
                SubLabel { width: parent.width
                           text: "Number of app columns in the fullscreen grid." }
            }
        }
    }
}
