import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Classic Alt-Tab window switcher (replaces `rofi -show window`). A horizontal MRU strip of open
// windows over a subtle dim backdrop. The overlay grabs the keyboard while open and handles the input
// itself: Tab cycles, Shift+Tab back, Super release / Enter / Space confirms, Esc cancels — then sends
// `hyprctl dispatch focuswindow`. The Super+Tab Hyprland bind just opens it. One per screen.
PanelWindow {
    id: root

    property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""
    readonly property bool isOpen: UiState.windowSwitcherOpen
    readonly property bool active: isOpen && root.mon !== "" && root.mon === UiState.windowSwitcherMon

    // What a theme's switcher is handed. Already ordered most-recently-used, so a theme never has
    // to know how this shell tracks focus history.
    readonly property var switcherContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        var out = []
        for (var i = 0; i < root.wins.length; i++) {
            var wi = root.wins[i]
            out.push({ "class": wi.cls || "", "title": wi.title || "", "address": wi.address || "" })
        }
        c.windows = out
        return c
    }

    property var wins: []     // [{ address, cls, title }], most-recently-used first
    property int sel: 0

    property real reveal: 0
    onActiveChanged: { reveal = active ? 1 : 0; if (active) { root.load(); kbd.forceActiveFocus() } }
    Behavior on reveal {
        id: revealB
        // Direction from the Behavior's own targetValue, NOT the surface's open flag:
        // the flag flips in the same signal that starts the animation, and the animation
        // latched the OLD spring — opening ran on the closing spring and vice versa.
        SpringAnimation {
            spring:  Style.springFor(revealB.targetValue > 0.5)
            damping: Style.dampingFor(revealB.targetValue > 0.5)
            epsilon: 0.003
        }
    }
    visible: active || root.reveal > 0.01

    // Fallback: if the grab doesn't suppress the Super+Tab bind, the bind re-fires `window open`, which
    // bumps this counter → advance either way.
    Connections {
        target: UiState
        function onWindowSwitcherNextChanged() { if (root.active) root.move(1) }
    }

    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "velumeron-window-switcher"
    // Grab the keyboard while open: the overlay handles Tab / Super-release itself and then sends the
    // focus command (like the launcher — no mask, so it also takes pointer input for click-out).
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusiveZone: 0

    // Fetch the window list once on open (newlines stripped → single JSON line), MRU-sorted.
    Process {
        id: clientsProc
        property string _acc: ""
        stdout: SplitParser { onRead: line => { clientsProc._acc += line } }
        onRunningChanged: if (!running) {
            var out = []
            try {
                var arr = JSON.parse(clientsProc._acc)
                arr = arr.filter(function (w) { return w && !w.hidden && w.mapped !== false && w.address })
                arr.sort(function (a, b) { return (a.focusHistoryID || 0) - (b.focusHistoryID || 0) })
                out = arr.map(function (w) {
                    return { address: w.address, cls: (w.class || ""), title: (w.title || w.class || "Window") }
                })
            } catch (e) { out = [] }
            clientsProc._acc = ""
            root.wins = out
            root.sel  = out.length > 1 ? 1 : 0     // preselect the previously-focused window
            strip.positionViewAtIndex(root.sel, ListView.Contain)
        }
    }
    function load() {
        clientsProc._acc = ""
        clientsProc.command = ["bash", "-c", "hyprctl clients -j | tr -d '\\n\\r'"]
        clientsProc.running = false; clientsProc.running = true
    }

    // Focus the chosen window a moment AFTER the overlay closes, so Hyprland's focus-restore (when the
    // keyboard grab drops) has settled and doesn't override us. hypr.lua wraps dispatch as Lua, so we
    // focus via hl.dsp.focus({ window = "address:…" }) — the raw `focuswindow address:…` string is
    // invalid Lua there and silently did nothing (that was the real bug all along).
    Timer {
        id: focusTimer
        interval: 130; repeat: false
        property string addr: ""
        onTriggered: if (addr !== "") Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
    }
    // Close the overlay, then (after the grab-drop focus-restore settles) focus wins[idx]. confirm →
    // the selection; cancel → wins[0] (the window focused at open) so Escape stays put even though
    // follow_mouse would otherwise pull focus to whatever is under the cursor when the overlay closes.
    function _finish(idx) {
        var w = root.wins[idx]
        Qt.callLater(function () {          // out of the key handler → dropping the grab can't re-enter/crash
            UiState.windowSwitcherOpen = false
            focusTimer.addr = (w && w.address) ? ("" + w.address) : ""
            if (focusTimer.addr !== "") focusTimer.restart()
        })
    }
    function confirm() { root._finish(root.sel) }
    function cancel()  { root._finish(0) }
    function move(d) {
        var n = root.wins.length; if (n === 0) return
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
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.confirm(); e.accepted = true }
            else if (e.key === Qt.Key_Escape)  { root.cancel(); e.accepted = true }
        }
        Keys.onReleased: e => {
            if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta) { root.confirm(); e.accepted = true }
        }

        // Subtle dim backdrop (NOT blurred — the layerrule opts this namespace out of the global blur).
        Rectangle {
            anchors.fill: parent
            color: Style.popDimColor(root.reveal)
            MouseArea { anchors.fill: parent; onClicked: root.cancel() }   // click outside → cancel
        }

        StyledRect {
            id: card
            anchors.centerIn: parent
            // The shipped strip sizes the card to its own content. A themed switcher draws a list
            // instead, and `strip` is not built then — so its contentWidth is 0 and the card
            // collapsed to a sliver. Give the theme a share of the screen to work in.
            width:  Theme.hasComponent("switcher") ? Math.round(Math.min(root.width - 120, 820))
                                                   : Math.min(root.width - 80, strip.contentWidth + 28)
            height: Theme.hasComponent("switcher")
                    ? Math.round(Math.min(root.height * 0.5,
                                          Math.max(120, ((root.wins.length || 1) * 30) + 40)))
                    : 150
            radius: Style.rCard; color: Colors.bgPrimary
            borderWidth: 1; borderColor: Style.chromeBorder
            opacity: Style.popFade(root.reveal)
            scale:   Style.popScale(root.reveal)

            // A theme that brings its own switcher draws the list. The shell keeps the keyboard, the
            // most-recently-used order and the raise on release.
            ThemeSurface {
                id: themedSwitcher
                anchors.fill: parent
                anchors.margins: 14
                visible: Theme.hasComponent("switcher")
                surface: Theme.hasComponent("switcher") ? "switcher" : ""
                ctx: root.switcherContext
                z: 2
            }
            // Bound on its own, not carried in `ctx`: see the launcher and the wallpaper picker —
            // a context rebuilt on every step hands the theme a new window list each time, and the
            // view drawing it resets to the top.
            Binding {
                target:   themedSwitcher.item
                property: "cursor"
                value:    root.sel
                when:     themedSwitcher.item !== null
            }

            ListView {
                id: strip
                visible: !Theme.hasComponent("switcher")
                anchors.fill: parent; anchors.margins: 14
                orientation: ListView.Horizontal
                spacing: 10; clip: true
                model: root.wins
                currentIndex: root.sel
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 90
                interactive: false

                delegate: StyledRect {
                    id: wcard
                    required property var modelData
                    required property int index
                    readonly property bool seld: root.sel === index
                    width: 112; height: strip.height; radius: Style.rControl
                    color: wcard.seld ? Style.accent : (wHov.containsMouse ? Style.controlHover : Style.controlFill)
                    borderWidth: wcard.seld ? 0 : Style.controlBorderW
                    borderColor: Style.controlBorderColor
                    Behavior on color { ColorAnimation { duration: Style.popColorMs } }
                    Column {
                        anchors.centerIn: parent; width: parent.width - 16; spacing: 8
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 52; height: 52
                            source: Quickshell.iconPath(wcard.modelData.cls, "application-x-executable")
                            sourceSize.width: 96; sourceSize.height: 96; asynchronous: true
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: wcard.modelData.title
                            color: wcard.seld ? Colors.fgBright : Colors.fgMuted
                            font.pixelSize: 11; font.family: Style.font; elide: Text.ElideRight; maximumLineCount: 1
                        }
                    }
                    MouseArea { id: wHov; anchors.fill: parent; hoverEnabled: true
                                onPositionChanged: root.sel = wcard.index
                                onClicked: { root.sel = wcard.index; root.confirm() } }
                }
                Text { visible: root.wins.length === 0; anchors.centerIn: parent
                       text: Wording.s("windows.none"); color: Colors.fgMuted; font.pixelSize: 13; font.family: Style.font }
            }
        }
    }
}
