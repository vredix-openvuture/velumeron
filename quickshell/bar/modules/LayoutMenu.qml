pragma ComponentBehavior: Bound
import "../.."
import QtQuick
import Quickshell.Io

// Layout flyout: grows out of the bar from the LayoutSwitcher module. Lists the built-in
// tiling layouts (dwindle, master) plus every custom layout from Settings → Layouts, and
// switches live via hl.config. The choice is also persisted to settings.json
// (tiling_layout) so user_layouts.lua restores it across Hyprland reloads.
Flyout {
    id: root
    flyoutId: "layoutmenu"
    panelW:   250
    maxH:     480

    property string current: "dwindle"

    readonly property var entries: {
        var out = [
            { value: "dwindle", label: "Dwindle", icon: "󰕴", hint: "binary splits" },
            { value: "master",  label: "Master",  icon: "󰨑", hint: "master + stack" }
        ]
        var cs = VtlConfig.customLayouts
        for (var i = 0; i < cs.length; i++) {
            var kindIcon = ({ columns: "󰕭", rows: "󰕳", grid: "󰕰", main_stack: "󰨑" })[cs[i].kind] ?? "󰕸"
            var kindHint = ({ columns: "equal columns", rows: "stacked rows",
                              grid: "auto grid", main_stack: "main + stack" })[cs[i].kind] ?? "custom"
            out.push({ value: "lua:" + cs[i].name, label: cs[i].name, icon: kindIcon, hint: kindHint })
        }
        return out
    }

    onIsOpenChanged: if (isOpen) root.poll()

    Process {
        id: pollProc
        command: ["bash", "-c", "hyprctl getoption general:layout -j | tr -d '\\n'"]
        stdout: SplitParser {
            onRead: line => {
                try { root.current = JSON.parse(line).str ?? "dwindle" } catch (e) { /* keep */ }
            }
        }
    }
    function poll() { pollProc.running = false; pollProc.running = true }

    // Switch: persist the choice (settings.json → restored on reload by user_layouts.lua),
    // then apply it live via hl.config and re-poll every consumer.
    Process { id: setProc; onExited: { root.poll(); UiState.layoutPollSerial++ } }
    function setLayout(value) {
        root.current = value
        SettingsStore.set("tiling_layout", value)
        setProc.command = ["bash", "-c",
            "hyprctl eval \"hl.config({ general = { layout = [[$1]] } })\"", "vtl", value]
        setProc.running = false
        setProc.running = true
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 4

        Text {
            text: "TILING LAYOUT"
            color: Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
        }

        Repeater {
            model: root.entries
            delegate: StyledRect {
                id: entry
                required property var modelData
                readonly property bool on: root.current === modelData.value
                width: parent.width; height: 40
                radius: Style.rTile
                color: on ? Style.tint(Style.accent, 0.30)
                     : eHov.containsMouse ? Style.controlHover : Style.controlFill
                Behavior on color { ColorAnimation { duration: 90 } }

                Text {
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text:  entry.modelData.icon
                    color: entry.on ? Colors.fgBright : Colors.fgMuted
                    font.pixelSize: 16; font.family: Style.font
                }
                Column {
                    anchors { left: parent.left; leftMargin: 40; right: chk.left; rightMargin: 6
                              verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text:  entry.modelData.label
                        color: entry.on ? Colors.fgBright : Colors.fgPrimary
                        font.pixelSize: 12; font.family: Style.font; font.bold: entry.on
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text:  entry.modelData.hint
                        color: Colors.fgMuted; font.pixelSize: 9; font.family: Style.font
                    }
                }
                Text {
                    id: chk
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    visible: entry.on
                    text: "󰄬"; color: Style.accent
                    font.pixelSize: 13; font.family: Style.font
                }
                MouseArea {
                    id: eHov
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.setLayout(entry.modelData.value)
                }
            }
        }

        // Footer: jump to the layout builder.
        Item { width: 1; height: 2 }
        StyledRect {
            width: parent.width; height: 30
            radius: Style.rTile
            color: editHov.containsMouse ? Style.controlHover : "transparent"
            Row {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "󰒓"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.font }
                Text { text: "Edit layouts"; color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font }
            }
            MouseArea {
                id: editHov
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    UiState.flyout = ""
                    UiState.settingsRequestSection = "layouts"
                    UiState.menuMon = root.mon
                    UiState.openDropdown = "vuture-icon"
                }
            }
        }
    }
}
