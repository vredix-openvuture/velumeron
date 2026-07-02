import "../.."
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris

// Mpris player flyout: square hi-res cover, track info, progress + transport controls.
// Grows out of the bar from the Mpris module on hover (see Mpris.qml + UiState.flyout).
Flyout {
    id: root
    flyoutId: "mpris"
    panelW:   300
    maxH:     560

    function _hasTitle(p) { return ((p.trackTitle ?? "") + "").trim() !== "" }

    // All players worth showing (have a title). The switcher row appears when there's more than one.
    readonly property var _players: {
        var vs = Mpris.players.values, out = []
        for (var i = 0; i < vs.length; i++) if (root._hasTitle(vs[i])) out.push(vs[i])
        return out
    }
    // The user can pin a specific player via the switcher; otherwise auto = playing, else first.
    property var selected: null
    readonly property MprisPlayer player: {
        var ps = root._players
        if (ps.length === 0) return null
        if (root.selected) for (var i = 0; i < ps.length; i++) if (ps[i] === root.selected) return ps[i]
        for (var j = 0; j < ps.length; j++) if (ps[j].isPlaying) return ps[j]
        return ps[0]
    }
    // Reset to the auto pick each time the menu opens.
    onIsOpenChanged: if (isOpen) root.selected = null

    // Switch to a player: pin it, start it, and pause every other one.
    function selectPlayer(p) {
        root.selected = p
        var vs = Mpris.players.values
        for (var i = 0; i < vs.length; i++) {
            var pl = vs[i]
            if (pl === p) { if (!pl.isPlaying) pl.togglePlaying() }
            else          { if (pl.isPlaying)  pl.togglePlaying() }
        }
    }
    // A glyph per player, guessed from its MPRIS identity (falls back to a music note).
    function iconFor(p) {
        var id = ((p.identity ?? "") + "").toLowerCase()
        if (id.indexOf("spotify") >= 0)                               return "󰓇"
        if (id.indexOf("firefox") >= 0 || id.indexOf("mozilla") >= 0) return "󰈹"
        if (id.indexOf("chrom") >= 0)                                 return "󰊯"
        if (id.indexOf("vlc") >= 0)                                   return "󰕼"
        if (id.indexOf("mpv") >= 0)                                   return "󰐹"
        if (id.indexOf("youtube") >= 0)                               return "󰗃"
        if (id.indexOf("netflix") >= 0)                               return "󰝆"
        return "󰝚"
    }

    // Nudge the progress binding so it advances while playing (MPRIS position is polled).
    property int _tick: 0
    Timer { interval: 1000; repeat: true; running: root.player?.isPlaying ?? false; onTriggered: root._tick++ }
    readonly property real progress: {
        root._tick
        var p = root.player
        return (p && p.length > 0) ? Math.max(0, Math.min(1, p.position / p.length)) : 0
    }
    function _fmt(s) {
        if (!s || s < 0) return "0:00"
        var m = Math.floor(s / 60), sec = Math.floor(s % 60)
        return m + ":" + (sec < 10 ? "0" : "") + sec
    }
    Process { id: seekProc }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 12

        // ── Player switcher — one icon per active player, above the cover ──────
        Flow {
            width: parent.width; spacing: 8
            visible: root._players.length > 1
            Repeater {
                model: root._players
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool cur: modelData === root.player
                    width: 38; height: 38; radius: 10
                    color: cur ? Colors.bgActive
                         : (pHov.containsMouse ? Style.tint(Colors.bgActive, 0.20) : Colors.bgElement)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent; text: root.iconFor(modelData)
                        color: cur ? Colors.fgBright : (modelData.isPlaying ? Colors.fgPrimary : Colors.fgMuted)
                        font.family: Style.font; font.pixelSize: 18
                    }
                    // Small dot marks players that are currently playing.
                    Rectangle {
                        visible: modelData.isPlaying
                        width: 6; height: 6; radius: 3; color: Colors.fgBright
                        anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 4 }
                    }
                    MouseArea { id: pHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.selectPlayer(modelData) }
                }
            }
        }

        // ── Square hi-res cover ───────────────────────────────────────────────
        Rectangle {
            width:  parent.width
            height: parent.width
            radius: 14
            clip:   true
            color:  Colors.bgElement
            Image {
                anchors.fill: parent
                source:   root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width:  512
                sourceSize.height: 512
                smooth: true; mipmap: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !root.player || (root.player.trackArtUrl ?? "") === ""
                text:  "󰝚"
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 64
            }
        }

        // ── Title + artist ────────────────────────────────────────────────────
        Column {
            width: parent.width; spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text:  root.player?.trackTitle ?? "Nothing playing"
                color: Colors.fgBright
                font.family: Style.font; font.pixelSize: 14; font.bold: true
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                visible: (root.player?.trackArtist ?? "") !== ""
                text:  root.player?.trackArtist ?? ""
                color: Colors.fgMuted
                font.family: Style.font; font.pixelSize: 12
            }
        }

        // ── Progress ──────────────────────────────────────────────────────────
        Column {
            width: parent.width; spacing: 4
            Rectangle {
                width: parent.width; height: 6; radius: 3; color: Colors.bgElement
                Rectangle {
                    width:  parent.width * root.progress
                    height: parent.height; radius: parent.radius; color: Colors.bgActive
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: (root.player?.length ?? 0) > 0
                    onClicked: e => {
                        var sec = Math.max(0, Math.min(1, e.x / width)) * root.player.length
                        seekProc.command = ["playerctl", "position", ("" + Math.floor(sec))]
                        seekProc.running = false; seekProc.running = true
                    }
                }
            }
            Row {
                width: parent.width
                Text { text: root._fmt(root.player?.position ?? 0); color: Colors.fgMuted
                       font.family: Style.font; font.pixelSize: 10 }
                Item { width: parent.width - 2 * 36; height: 1 }
                Text { width: 36; horizontalAlignment: Text.AlignRight
                       text: root._fmt(root.player?.length ?? 0); color: Colors.fgMuted
                       font.family: Style.font; font.pixelSize: 10 }
            }
        }

        // ── Transport ─────────────────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18
            Ctl { icon: "󰒮"; onTrig: root.player?.previous() }
            Ctl { icon: root.player?.isPlaying ? "󰏤" : "󰐊"; big: true; onTrig: root.player?.togglePlaying() }
            Ctl { icon: "󰒭"; onTrig: root.player?.next() }
        }
    }

    component Ctl: Rectangle {
        property string icon: ""
        property bool   big:  false
        signal trig()
        width:  big ? 48 : 40
        height: big ? 48 : 40
        radius: width / 2
        color:  ch.containsMouse ? Colors.bgActive
              : Style.tint(Colors.bgActive, 0.18)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors.centerIn: parent
            text:  parent.icon
            color: ch.containsMouse ? Colors.fgBright : Colors.fgPrimary
            font.family: Style.font; font.pixelSize: parent.big ? 22 : 18
        }
        MouseArea { id: ch; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
}
