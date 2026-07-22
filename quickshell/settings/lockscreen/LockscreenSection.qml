import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Lockscreen & suspend. The lockscreen is the native quickshell lock (lock/Lock.qml). Its look is a
// PRESET — a named snapshot of the VtlConfig.lock* keys (LockPresets.qml / lockscreen-config.py),
// shipped default "mirobo" + user presets built in the LockEditor overlay ("Build your own"). Mirrors
// Settings → Style (templates + your palettes). The Timers card still writes hypr.lua/hypridle.conf.
Item {
    id: root

    property int lockMin:    6
    property int suspendMin: 14

    Component.onCompleted: { reload(); LockPresets.refresh() }
    onVisibleChanged: if (visible) { reload(); LockPresets.refresh() }
    function reload() { readProc.running = false; readProc.running = true }

    function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s }

    // Open the build-your-own editor on the monitor the settings menu is on (mirrors StyleSection's
    // "Build your own" → PaletteEditor). seed = a preset object to edit, or null = fresh from live.
    function openEditor(seed) {
        UiState.lockEditorSeed = seed || null
        UiState.lockEditorMon  = UiState.menuMon
        UiState.openDropdown   = ""
        UiState.lockEditorOpen = true
    }

    // ── Timers: parse the two hypridle.conf timeouts (lock, then suspend) ────────────────────────
    readonly property string _readPy: [
        "import os,re",
        "vd=os.environ.get('VELUMERON_DIR','')",
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.expanduser('~/.config/velumeron')",
        "cf=os.path.join(pu,'hypr.lua/hypridle.conf')",
        "cf=cf if os.path.exists(cf) else os.path.join(vd,'hypr.lua/hypridle.conf')",
        "c=open(cf).read() if os.path.exists(cf) else ''",
        "ts=[int(x) for x in re.findall(r'timeout\\s*=\\s*(\\d+)',c)]",
        "print('LOCK\\t%d'%(ts[0] if ts else 360))",
        "print('SUSPEND\\t%d'%(ts[1] if len(ts)>1 else 840))"
    ].join("\n")
    Process {
        id: readProc
        command: ["python3", "-c", root._readPy]
        stdout: SplitParser { onRead: line => root._ingest(("" + line).trim()) }
    }
    function _ingest(t) {
        var p = t.split("\t"); if (p.length < 2) return
        if      (p[0] === "LOCK")    root.lockMin    = Math.max(1, Math.round(parseInt(p[1]) / 60))
        else if (p[0] === "SUSPEND") root.suspendMin = Math.max(0, Math.round(parseInt(p[1]) / 60))
    }
    function commitTimes() {
        timeProc.command = ["bash", "-c",
            "\"$VELUMERON_DIR/assets/scripts/hypridle-set.sh\" "
            + (root.lockMin * 60) + " " + (root.suspendMin * 60)]
        timeProc.running = false; timeProc.running = true
    }
    Process { id: timeProc }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Presets (built-in) ────────────────────────────────────────────
            Card {
                CardLabel { text: "PRESETS" }
                Flow {
                    id: presetGrid
                    width: parent.width; spacing: 8
                    readonly property real cw: (width - spacing) / 2
                    Repeater {
                        model: LockPresets.presets.filter(function (p) { return p.source === "builtin" })
                        delegate: LockPresetCard {
                            required property var modelData
                            preset: modelData
                            width: presetGrid.cw
                        }
                    }
                }
                TextButton { width: parent.width; label: "󰏘  Build your own"; primary: true
                             onClicked: root.openEditor(null) }
            }

            // ── Your lockscreens (user presets) ───────────────────────────────
            Card {
                visible: root._userPresets.length > 0
                CardLabel { text: "YOUR LOCKSCREENS" }
                Repeater {
                    model: root._userPresets
                    delegate: StyledRect {
                        required property var modelData
                        width: parent.width; height: 40; radius: Style.rControl
                        readonly property bool active: modelData.active
                        color: active ? Style.selFill : (rHov.containsMouse ? Style.controlHover : Style.controlFill)
                        borderWidth: active ? Style.selBorderW : Style.controlBorderW
                        borderColor: active ? Style.selBorderColor : Style.controlBorderColor
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: modelData.name; color: active ? Style.selText : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 13
                        }
                        MouseArea { id: rHov; anchors.fill: parent; hoverEnabled: true
                                    onClicked: LockPresets.activate(modelData.source, modelData.id) }
                        Row {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Text { text: "󰏫"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 16
                                   MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                               onClicked: root.openEditor(modelData) } }
                            Text { text: "󰩹"; color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 16
                                   MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                               onClicked: LockPresets.remove(modelData.id) } }
                        }
                    }
                }
            }

            // ── Timers ────────────────────────────────────────────────────────
            Card {
                CardLabel { text: "TIMERS" }
                Stepper { label: "Lock after"; unit: "min"; min: 1; max: 120; labelWidth: 110
                          value: root.lockMin; onChanged: { root.lockMin = v; root.commitTimes() } }
                Stepper { label: "Suspend after"; unit: root.suspendMin > 0 ? "min" : "off"; min: 0; max: 240
                          labelWidth: 110
                          value: root.suspendMin; onChanged: { root.suspendMin = v; root.commitTimes() } }
                SubLabel { width: parent.width
                           text: "Idle time before the lockscreen appears, then before the system suspends." }
            }
        }
    }

    readonly property var _userPresets: LockPresets.presets.filter(function (p) { return p.source === "user" })

    // Mini lock-preview tile for a built-in preset (mirrors StyleSection's TemplateCard).
    component LockPresetCard: Item {
        id: lc
        property var preset
        readonly property bool active: preset.active
        height: 128
        StyledRect {
            anchors.fill: parent
            radius: Style.rCard
            color: lc.active ? Style.selFill : Style.controlFill
            borderWidth: lc.active ? Style.selBorderW : Style.controlBorderW
            borderColor: lc.active ? Style.selBorderColor : Style.controlBorderColor
            Column {
                anchors.fill: parent; anchors.margins: 10; spacing: 8
                // mini mock: dark blurred backdrop with a small centred card + dots
                Rectangle {
                    width: parent.width; height: parent.height - lblRow.height - parent.spacing
                    radius: Style.rControl; clip: true
                    color: Qt.rgba(0, 0, 0, 0.5)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(Colors.bgActive.r, Colors.bgActive.g, Colors.bgActive.b, 0.35) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
                    }
                    StyledRect {
                        anchors.centerIn: parent
                        width: parent.height * 0.62; height: width
                        radius: Style.rTile
                        color: Style.cardFill
                        borderWidth: 1; borderColor: Style.cardBorderColor
                        Column {
                            anchors.centerIn: parent; spacing: 4
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter
                                        width: 16; height: 16; radius: 8; color: Colors.bgElement }
                            Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 3
                                  Repeater { model: 3; delegate: Rectangle { width: 4; height: 4; radius: 2; color: Colors.fgBright } } }
                        }
                    }
                }
                Row {
                    id: lblRow
                    width: parent.width; spacing: 6
                    Text { text: root.cap(lc.preset.name); color: lc.active ? Style.selText : Colors.fgPrimary
                           font.family: Style.font; font.pixelSize: 13; elide: Text.ElideRight
                           width: parent.width - (lc.active ? checkT.width + parent.spacing : 0) }
                    Text { id: checkT; visible: lc.active; text: "✓"; color: Style.selText
                           font.family: Style.font; font.pixelSize: 13 }
                }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: lc.active ? root.openEditor(lc.preset)
                                     : LockPresets.activate(lc.preset.source, lc.preset.id)
            }
        }
    }
}
