import "../.."
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// Microphone: mute state at a glance, mute with a click, and — on hover — the pill that names what
// is actually recording. The last part is the reason the module exists: "is something listening"
// is a question the shell could answer all along (PipeWire knows every capture stream) and did not.
//
// Left click mutes, middle click opens the panel. Swap them with the module's "Click" setting if
// the panel is what you reach for more often; either way the other one is on the middle button, so
// both are always one click away.
Item {
    id: root
    property bool vertical: false
    property string barMon:   ""
    property string barEdge:  "top"
    property string barGroup: "start"

    readonly property bool rotateOnVertical: root._showPct

    PwObjectTracker { objects: [Pipewire.defaultAudioSource] }

    readonly property bool muted:  Pipewire.defaultAudioSource?.audio?.muted ?? false
    readonly property int  volume: Math.round((Pipewire.defaultAudioSource?.audio?.volume ?? 0) * 100)

    // Streams the shell itself owns are not "an app listening to you" — same exclusion the sound
    // desk makes, kept in step with it by hand because a filter that lives in a menu body is not
    // reachable from here.
    readonly property var _ownStreams: ["cava", "quickshell", "noctalia-qs"]
    readonly property var recorders: {
        var out = []
        var ns = Pipewire.nodes.values
        for (var i = 0; i < ns.length; i++) {
            var n = ns[i]
            if (!n || !n.isStream || !n.audio || n.isSink) continue
            if (root._ownStreams.indexOf(("" + (n.name ?? "")).toLowerCase()) >= 0) continue
            out.push(n)
        }
        return out
    }
    readonly property int  recCount: root.recorders.length
    // The slot's own status dot (Bar.qml draws it): something is recording.
    readonly property bool  dotOn:   root.recCount > 0 && !root.muted
    readonly property color dotTone: Colors.fgUrgent

    readonly property string _font: VtlConfig.moduleFontFor("microphone")
    readonly property int    _fs:   VtlConfig.moduleFontSizeFor("microphone", root.barMon)
    readonly property int    _is:   VtlConfig.moduleIconSizeFor("microphone", root.barMon)
    readonly property bool   _showPct: VtlConfig.moduleSetting("microphone", "show_percent", false)
    readonly property string _click:   "" + VtlConfig.moduleSetting("microphone", "click", "mute")   // mute | popout
    readonly property bool   _hoverPill: VtlConfig.moduleSetting("microphone", "hover_list", true)

    // Muted is the loud state here, not the quiet one: a live microphone is the thing worth
    // colouring, so the accent goes to "open" and muted falls back to the muted foreground.
    readonly property color _col: root.muted ? Style.barDim(root.barMon)
                                : (root.recCount > 0 ? Colors.fgUrgent
                                                     : (Colors[VtlConfig.moduleColorName("microphone")] ?? Colors.fgPrimary))
    readonly property bool hovered: mouse.containsMouse

    implicitWidth:  row.implicitWidth
    implicitHeight: row.implicitHeight
    width:  implicitWidth
    height: implicitHeight

    function _publishGlide() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.micAnchorX = c.x; UiState.micAnchorY = c.y
        UiState.micEdge = root.barEdge; UiState.micMon = root.barMon
    }
    function _dropGlide() { if (UiState.micMon === root.barMon) UiState.micHover = false }
    Component.onDestruction: root._dropGlide()

    Row {
        id: row
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  root.muted ? "󰍭" : "󰍬"
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._is
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
        Text {
            visible: root._showPct
            anchors.verticalCenter: parent.verticalCenter
            text:  root.volume + "%"
            color: root.hovered ? Colors.fgBright : root._col
            font.family:    root._font
            font.pixelSize: root._fs
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onEntered: if (root._hoverPill) { root._publishGlide(); UiState.micHover = true }
        onExited:  root._dropGlide()
        onClicked: event => {
            var wantMute = (event.button === Qt.MiddleButton) !== (root._click === "mute")
            if (wantMute) { muteProc.running = false; muteProc.running = true; return }
            root._dropGlide()
            Popouts.openFor("microphone", root, root.barEdge, root.barGroup, root.barMon)
        }
        onWheel: event => {
            var s = Math.max(1, VtlConfig.moduleSetting("microphone", "scroll_step", 5))
            var target = event.angleDelta.y > 0 ? (Math.floor(root.volume / s) + 1) * s
                                                : (Math.ceil(root.volume / s) - 1) * s
            target = Math.max(0, Math.min(100, target))
            scrollProc.command = ["pactl", "set-source-volume", "@DEFAULT_SOURCE@", target + "%"]
            scrollProc.running = false
            scrollProc.running = true
        }
    }

    Process { id: muteProc; command: ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"] }
    Process { id: scrollProc }
}
