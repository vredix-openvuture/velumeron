import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Layout quick-switcher (Super+Alt+Tab) — the window switcher's sibling for tiling layouts. A
// horizontal strip of layout modes over a dim backdrop: Tab cycles, Shift+Tab back, Super release /
// Enter confirms, Esc cancels. Confirming switches the GLOBAL layout (tiling_layout) — the same
// thing the bar module and Settings → Layouts set — so the choice follows you across every
// workspace instead of applying only where you happened to stand. The one exception is "Endless",
// which is inherently per-monitor and toggles this monitor's strip. Applied live via
// VTL_layouts_apply(). Per-workspace pins stay a deliberate Settings-only feature. One per screen.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.layoutSwitcherOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.layoutSwitcherMon

    // The global layouts + one entry per custom layout; endless last (it acts on the monitor).
    readonly property var entries: {
        var out = [
            { key: "dwindle", label: "Dwindle", icon: "󰕴" },
            { key: "master",  label: "Master",  icon: "󰨑" },
            { key: "monocle", label: "Monocle", icon: "󰖲" },
            { key: "float",   label: "Float",   icon: "󰖯" }
        ]
        var cs = VtlConfig.customLayouts
        for (var i = 0; i < cs.length; i++) {
            var kindIcon = ({ columns: "󰕭", rows: "󰕳", grid: "󰕰", main_stack: "󰨑" })[cs[i].kind] ?? "󰕸"
            out.push({ key: "lua:" + cs[i].name, label: cs[i].name, icon: kindIcon })
        }
        out.push({ key: "endless", label: "Endless · Monitor", icon: "󰛤" })
        return out
    }
    // What is in force right now: this monitor's strip wins the marker, else the global layout.
    readonly property string currentKey: VtlConfig.layoutMonitors[root.mon] === "endless"
                                         ? "endless" : VtlConfig.tilingLayout
    property int sel: 0

    property real reveal: 0
    onActiveChanged: { reveal = active ? 1 : 0; if (active) { root.load(); kbd.forceActiveFocus() } }
    Behavior on reveal { SpringAnimation { spring: Style.elSpring; damping: Style.elDamping; epsilon: 0.003 } }
    visible: active || root.reveal > 0.01

    // Fallback: if the grab doesn't suppress the Super+Alt+Tab bind, the bind re-fires
    // `layoutswitch open`, which bumps this counter → advance either way.
    Connections {
        target: UiState
        function onLayoutSwitcherNextChanged() { if (root.active) root.move(1) }
    }

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-layout-switcher"
    // Grab the keyboard while open: the overlay handles Tab / Super-release itself and then writes
    // the assignment (like the window switcher — no mask, so it also takes pointer input for click-out).
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0

    // Open on whatever is in force, so a plain Tab-and-release moves you exactly one layout on.
    function load() {
        var idx = 0
        for (var i = 0; i < root.entries.length; i++)
            if (root.entries[i].key === root.currentKey) { idx = i; break }
        root.sel = idx
        strip.positionViewAtIndex(root.sel, ListView.Contain)
    }

    // Re-apply the override maps live after a write (layout_manager.lua), then re-poll every consumer.
    Process { id: applyProc; onExited: UiState.layoutPollSerial++ }
    function _commit(key) {
        if (key === root.currentKey) return   // nothing to do — don't churn the tunnel of windows
        // Leaving the strip means clearing this monitor's endless flag, whichever layout you pick.
        var m = {}
        var curM = VtlConfig.layoutMonitors
        for (var k in curM) m[k] = curM[k]
        var wasEndless = m[root.mon] === "endless"
        // The chosen value is handed to Lua directly — the settings write below is async and
        // re-reading it there applied the PREVIOUS choice (see layout_manager.lua).
        if (key === "endless") {
            m[root.mon] = "endless"
            SettingsStore.set("layout_monitors", m)
            applyProc.command = ["bash", "-c",
                "hyprctl eval \"VTL_layouts_set_monitor([[$1]], [[endless]])\"", "vtl", root.mon]
        } else {
            if (wasEndless) { delete m[root.mon]; SettingsStore.set("layout_monitors", m) }
            // The global layout — applies on every workspace that has no deliberate pin.
            SettingsStore.set("tiling_layout", key)
            applyProc.command = wasEndless
                ? ["bash", "-c",
                   "hyprctl eval \"VTL_layouts_set_monitor([[$1]], [[]])\"; "
                 + "hyprctl eval \"VTL_layouts_set([[$2]])\"", "vtl", root.mon, key]
                : ["bash", "-c", "hyprctl eval \"VTL_layouts_set([[$1]])\"", "vtl", key]
        }
        applyProc.running = false; applyProc.running = true
    }
    // Close the overlay, then (deferred — dropping the grab inside the key handler crashed the window
    // switcher) commit the selection. No focus dispatch here, so no settle timer is needed.
    function _finish(commit) {
        var key = root.entries[root.sel]?.key ?? root.currentKey
        Qt.callLater(function () {
            UiState.layoutSwitcherOpen = false
            if (commit) root._commit(key)
        })
    }
    function confirm() { root._finish(true) }
    function cancel()  { root._finish(false) }
    function move(d) {
        var n = root.entries.length; if (n === 0) return
        root.sel = (root.sel + d + n) % n
        strip.positionViewAtIndex(root.sel, ListView.Contain)
    }

    // A FocusScope holds active focus and captures the keys (a plain Item didn't reliably get keyboard
    // focus in the layer surface). onShortcutOverride claims Tab/Backtab so Qt's focus navigation
    // doesn't eat them before Keys.onPressed. confirm/cancel are deferred (Qt.callLater) so dropping the
    // grab isn't re-entered inside the key handler (that crashed). No mask → the mouse works too.
    FocusScope {
        id: kbd
        anchors.fill: parent
        focus: true
        Keys.onShortcutOverride: e => { if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) e.accepted = true }
        Keys.onPressed: e => {
            if      (e.key === Qt.Key_Tab)     { root.move((e.modifiers & Qt.ShiftModifier) ? -1 : 1); e.accepted = true }
            else if (e.key === Qt.Key_Backtab) { root.move(-1); e.accepted = true }
            else if (e.key === Qt.Key_Right)   { root.move(1);  e.accepted = true }
            else if (e.key === Qt.Key_Left)    { root.move(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.confirm(); e.accepted = true }
            else if (e.key === Qt.Key_Escape)  { root.cancel(); e.accepted = true }
        }
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta) { root.confirm(); e.accepted = true }
        }

        // Subtle dim backdrop (NOT blurred — the layerrule opts this namespace out of the global blur).
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35 * root.reveal)
            MouseArea { anchors.fill: parent; onClicked: root.cancel() }   // click outside → cancel
        }

        StyledRect {
            id: card
            anchors.centerIn: parent
            width:  Math.min(root.width - 80, strip.contentWidth + 28)
            height: 150
            radius: Style.rCard; color: Colors.bgPrimary
            borderWidth: 1; borderColor: Style.chromeBorder
            opacity: Style.elG01(root.reveal)
            scale:   0.97 + 0.03 * Style.elG01(root.reveal)

            ListView {
                id: strip
                anchors.fill: parent; anchors.margins: 14
                orientation: ListView.Horizontal
                spacing: 10; clip: true
                model: root.entries
                currentIndex: root.sel
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 90
                interactive: false

                delegate: StyledRect {
                    id: lcard
                    required property var modelData
                    required property int index
                    readonly property bool seld: root.sel === index
                    readonly property bool cur:  root.currentKey === lcard.modelData.key
                    width: 104; height: strip.height; radius: Style.rControl
                    color: lcard.seld ? Style.accent : (lHov.containsMouse ? Style.controlHover : Style.controlFill)
                    borderWidth: lcard.seld ? 0 : Style.controlBorderW
                    borderColor: Style.controlBorderColor
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Column {
                        anchors.centerIn: parent; width: parent.width - 12; spacing: 8
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: lcard.modelData.icon
                            color: lcard.seld ? Colors.fgBright : Colors.fgMuted
                            font.pixelSize: 26; font.family: Style.font
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: lcard.modelData.label
                            color: lcard.seld ? Colors.fgBright : Colors.fgMuted
                            font.pixelSize: 11; font.family: Style.font; elide: Text.ElideRight; maximumLineCount: 1
                        }
                    }
                    // Small dot marking the workspace's current assignment.
                    Rectangle {
                        visible: lcard.cur
                        anchors { top: parent.top; right: parent.right; margins: 6 }
                        width: 6; height: 6; radius: 3
                        color: lcard.seld ? Colors.fgBright : Style.accent
                    }
                    MouseArea { id: lHov; anchors.fill: parent; hoverEnabled: true
                                onPositionChanged: root.sel = lcard.index
                                onClicked: { root.sel = lcard.index; root.confirm() } }
                }
            }
        }
    }
}
