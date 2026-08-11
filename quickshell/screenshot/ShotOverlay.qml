import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The screenshot picker. SUPER+SHIFT+S used to go straight into a region drag, which is the right
// default and the only option — you could not grab the focused window or a whole screen without
// remembering a second bind, and the mode was decided in a config file rather than at the moment
// you pressed the key.
//
// So: the key opens this, Selection is preselected, and Enter takes it. One keystroke more than
// before for the common case, and every other case becomes possible.
//
// The overlay must be GONE before the capture runs — it is a layer surface over the whole screen,
// and grim would photograph it (or slurp would fight it for the pointer). Hence the beat between
// closing and firing.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property bool onActiveMonitor: monitor !== null && monitor === Compositor.focusedMonitor
    readonly property bool open:   UiState.shotOpen
    readonly property bool active: root.open && root.onActiveMonitor

    // Selection is the default every time, deliberately: it is what the key meant before this
    // existed, and a picker that remembers "full screen" from last week ambushes you.
    property string mode: "region"
    readonly property var modes: [
        { key: "region", label: "Selection",   glyph: "󰩭", hint: "Drag a rectangle" },
        { key: "window", label: "Window",      glyph: "󰖯", hint: "The focused window" },
        { key: "output", label: "This screen", glyph: "󰍹", hint: "The monitor you are on" },
        { key: "all",    label: "All screens", glyph: "󰍺", hint: "Every monitor at once" }
    ]
    function modeIdx() {
        for (var i = 0; i < root.modes.length; i++) if (root.modes[i].key === root.mode) return i
        return 0
    }

    // These DO persist — they are how you work, not what you are grabbing right now.
    readonly property bool copyClip: VtlConfig.shotCopy
    readonly property bool saveFile: VtlConfig.shotSave
    readonly property bool cursor:   VtlConfig.shotCursor
    readonly property int  delay:    VtlConfig.shotDelay

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    // Its own namespace with blur off: the backdrop below covers the screen, and Hyprland's global
    // rule blurs any layer whose alpha clears ignore_alpha (0.1). Frosting the desktop you are
    // about to photograph would be a memorable bug.
    WlrLayershell.namespace:     "velumeron-screenshot"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // An explicit Region either way. `mask: null` is not "take everything" — every other surface in
    // this shell that wants input names the rectangle it wants (Flyout, Bar, HotCorners), and the
    // one that wanted none says `Region {}`. A null mask is undefined ground, and the picker's whole
    // job is to receive one click.
    Region { id: noInput }
    Region { id: allInput; x: 0; y: 0; width: root.width; height: root.height }
    mask: root.active ? allInput : noInput
    visible: root.active || card.reveal > 0.01

    // ── What was on screen when the key was pressed ────────────────────────────
    // Read at OPEN, never after. The picker is a keyboard-grabbing layer surface, so by the time it
    // has come and gone the compositor's idea of "the focused window" is a state this overlay
    // itself disturbed — and "the window" you meant is the one you were looking at when you
    // reached for the key.
    property string ctxGeom: ""
    property string ctxMon:  ""
    Process {
        id: ctxProc
        command: ["bash", "-c",
            "hyprctl activewindow -j 2>/dev/null | jq -r 'select(.at != null) | \"g \\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' 2>/dev/null; " +
            "hyprctl activeworkspace -j 2>/dev/null | jq -r '\"m \" + (.monitor // \"\")' 2>/dev/null"]
        stdout: SplitParser { onRead: line => {
            var t = ("" + line).trim()
            if (t.indexOf("g ") === 0)      root.ctxGeom = t.substring(2)
            else if (t.indexOf("m ") === 0) root.ctxMon  = t.substring(2)
        } }
    }
    onOpenChanged: if (root.open && root.onActiveMonitor) {
        root.ctxGeom = ""; root.ctxMon = ""
        root.mode = "region"                       // Selection every time — see `mode` above.
        ctxProc.running = false; ctxProc.running = true
    }

    function cancel() { root.pending = ""; UiState.shotOpen = false }

    // Arm, then close. The capture is fired by the surface actually GOING AWAY, not by a timer
    // guessing when that might be: the fade is 180 ms and the old timer was 140, so grim ran with
    // the picker still on screen — it photographed itself, and slurp never got the pointer because
    // this surface still held the keyboard. `visible` flips only once nothing is left to draw.
    property string pending: ""
    function shoot() {
        if (!root.active) return
        root.pending = root.mode
        UiState.shotOpen = false
    }
    onVisibleChanged: if (!root.visible && root.pending !== "") settle.restart()

    Timer {
        id: settle
        // One breath after the unmap, for the compositor to actually drop the surface.
        interval: 60
        onTriggered: {
            var m = root.pending
            root.pending = ""
            if (m === "") return
            var a = [Quickshell.env("VELUMERON_DIR") + "/assets/scripts/screenshot.sh", m]
            if (m === "window" && root.ctxGeom !== "") { a.push("--geom");   a.push(root.ctxGeom) }
            if (m === "output" && root.ctxMon  !== "") { a.push("--output"); a.push(root.ctxMon) }
            if (!root.copyClip) a.push("--no-copy")
            if (!root.saveFile) a.push("--no-save")
            if (root.cursor)    a.push("--cursor")
            if (root.delay > 0) { a.push("--delay"); a.push("" + root.delay) }
            // One line per capture. Not decoration: the last two rounds of "it does not work" were
            // guesses because nothing on this path left a trace, and a screenshot tool is the one
            // thing you cannot debug by taking a screenshot of it.
            console.warn("screenshot: " + a.slice(1).join(" "))
            shotProc.command = ["setsid", "bash"].concat(a)
            shotProc.running = false
            shotProc.running = true
        }
    }
    Process { id: shotProc }

    Shortcut { sequence: "Escape"; onActivated: if (root.active) root.cancel() }
    Shortcut { sequence: "Return"; onActivated: if (root.active) root.shoot() }
    Shortcut { sequence: "Enter";  onActivated: if (root.active) root.shoot() }
    Shortcut { sequence: "Right";  onActivated: if (root.active)
                   root.mode = root.modes[(root.modeIdx() + 1) % root.modes.length].key }
    Shortcut { sequence: "Left";   onActivated: if (root.active)
                   root.mode = root.modes[(root.modeIdx() + root.modes.length - 1) % root.modes.length].key }
    Shortcut { sequence: "1"; onActivated: if (root.active) root.mode = "region" }
    Shortcut { sequence: "2"; onActivated: if (root.active) root.mode = "window" }
    Shortcut { sequence: "3"; onActivated: if (root.active) root.mode = "output" }
    Shortcut { sequence: "4"; onActivated: if (root.active) root.mode = "all" }

    // Click anywhere outside the card to cancel.
    MouseArea { anchors.fill: parent; enabled: root.active; onClicked: root.cancel() }

    // A dim so the card reads as being in front of the desktop rather than drawn on it — the same
    // reasoning as the floating settings window, and derived from the scheme's own ground for the
    // same reason: black punches a hole through a wallust-tinted desktop.
    Rectangle {
        anchors.fill: parent
        color:   Style.tint(Qt.darker(Colors.bgPrimary, 1.8), 0.45)
        opacity: card.reveal
    }

    StyledRect {
        id: card
        property real reveal: root.active ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        anchors.centerIn: parent
        // Percent of the screen, not pixels: four tiles and their captions need a share of the
        // width, not a number that happened to fit one monitor.
        readonly property int uGap: Math.max(8, Math.round(width * 0.022))
        width:   Math.max(460, Math.round(root.width * 0.34))
        height:  body.implicitHeight + card.uGap * 2
        radius:  Style.rCard
        color:   Style.panelColor(VtlConfig.menuColorful)
        borderWidth: Style.chromeBorderWidth
        borderColor: Style.chromeBorder
        opacity: card.reveal
        scale:   0.94 + 0.06 * card.reveal

        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: card.uGap; rightMargin: card.uGap; topMargin: card.uGap }
            spacing: card.uGap

            Item {
                width: parent.width
                height: title.implicitHeight
                Text {
                    id: title
                    anchors.left: parent.left
                    text: "Screenshot"; color: Colors.fgBright
                    font.family: Style.font; font.pixelSize: 16; font.bold: true
                }
                Text {
                    anchors { right: parent.right; baseline: title.baseline }
                    text: "↵ capture   ·   esc cancel"
                    color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 10
                }
            }

            // ── What to capture.
            Row {
                id: tiles
                width: parent.width
                spacing: 7
                readonly property int cellW: Math.floor((width - 3 * spacing) / 4)
                Repeater {
                    model: root.modes
                    delegate: StyledRect {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool on: root.mode === tile.modelData.key
                        width: tiles.cellW
                        height: 84
                        radius: Style.rTile
                        color: tile.on ? Style.rowActive
                             : th.containsMouse ? Style.rowHover : Style.rowFill
                        borderWidth: tile.on ? 2 : 0
                        borderColor: Style.accent
                        Behavior on color { ColorAnimation { duration: 110 } }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 12
                            spacing: 5
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tile.modelData.glyph
                                color: tile.on ? Style.accent : Colors.fgPrimary
                                font.family: Style.font; font.pixelSize: 24
                            }
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.modelData.label
                                color: tile.on ? Colors.fgBright : Colors.fgPrimary
                                font.family: Style.font; font.pixelSize: 11; font.bold: tile.on
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (tile.index + 1) + ""
                                color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9
                            }
                        }
                        MouseArea {
                            id: th
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: { root.mode = tile.modelData.key; root.shoot() }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.modes[root.modeIdx()].hint
                color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 11
            }

            // ── How. These stick between sessions.
            Flow {
                width: parent.width
                spacing: 6
                DataChip {
                    label: "󰅍  Clipboard"; on: root.copyClip
                    onTap: SettingsStore.set("shot_copy", !root.copyClip)
                }
                DataChip {
                    label: "󰆓  Save file"; on: root.saveFile
                    onTap: SettingsStore.set("shot_save", !root.saveFile)
                }
                DataChip {
                    label: "󰆾  Cursor"; on: root.cursor
                    onTap: SettingsStore.set("shot_cursor", !root.cursor)
                }
                DataChip {
                    label: root.delay > 0 ? ("󰔛  " + root.delay + "s delay") : "󰔛  No delay"
                    on: root.delay > 0
                    // 0 → 3 → 5 → 10 → 0. A stepper for four values is three more widgets than the
                    // question deserves.
                    onTap: SettingsStore.set("shot_delay",
                                             root.delay === 0 ? 3 : root.delay === 3 ? 5
                                           : root.delay === 5 ? 10 : 0)
                }
            }

            MetaTag {
                width: parent.width; elide: Text.ElideRight
                text: !root.saveFile ? "Clipboard only — the file is removed after the copy."
                                     : "Saved to " + VtlConfig.shotDir
            }
        }
    }
}
