import "../.."
import QtQuick
import Quickshell.Services.Mpris

// Media module: inline prev / play-pause / next controls followed by the scrolling track title.
// The buttons let the user control playback without opening anything; clicking the title opens
// the player menu (TODO: fluid player menu — for now it toggles playback).
Item {
    id: root
    property bool vertical: false   // set by ModSlot (rotated to read along a vertical sidebar)
    property string barMon:   ""    // monitor name, for per-monitor icon/font size
    property string barEdge:  "top" // set by Bar; drives the flyout grow direction
    property string barGroup: "start" // set by Bar; start/end → menu merges into the corner

    // Prefer a player that's actually playing, then one with a track title, else the first —
    // so an idle proxy (e.g. kdeconnect) doesn't win over the real player.
    function _hasTitle(p) { return ((p.trackTitle ?? "") + "").trim() !== "" }
    readonly property MprisPlayer player: {
        var vs = Mpris.players.values
        if (vs.length === 0) return null
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying && root._hasTitle(vs[i])) return vs[i]
        for (var j = 0; j < vs.length; j++) if (root._hasTitle(vs[j]))                    return vs[j]
        return null
    }
    visible: player !== null

    // Per-module customization (Settings → Bar → Module → gear).
    readonly property string _font:    VtlConfig.moduleFontFor("mpris")
    readonly property color  _col:     Colors[VtlConfig.moduleColorName("mpris")] ?? Colors.fgMuted
    readonly property bool   _showCtl: VtlConfig.moduleSetting("mpris", "show_controls", true)
    readonly property int    fontSize: VtlConfig.moduleFontSizeFor("mpris", root.barMon)
    readonly property int    iconSize: VtlConfig.moduleIconSizeFor("mpris", root.barMon)
    readonly property int    maxLen:   VtlConfig.moduleSetting("mpris", "max_title", 180)
    readonly property string full:     root.player?.trackTitle ?? ""

    TextMetrics { id: tm; font.family: root._font; font.pixelSize: root.fontSize; text: root.full }
    readonly property bool overflow: tm.width > maxLen

    implicitWidth:  visible ? lay.implicitWidth  : 0
    implicitHeight: visible ? lay.implicitHeight : 0
    width:  implicitWidth
    height: implicitHeight

    // Click on the title opens the player flyout (docked out of the bar); IPC can also open it.
    function _toggleMenu() {
        var c = root.mapToItem(null, root.width / 2, root.height / 2)
        UiState.toggleFlyout("mpris", c.x, c.y, root.barEdge, root.barGroup, root.barMon)
    }

    Row {
        id: lay
        anchors.centerIn: parent
        spacing: 8

        Ctl { visible: root._showCtl; icon: "󰒮"; onTrig: root.player?.previous() }
        Ctl { visible: root._showCtl; icon: root.player?.isPlaying ? "󰏤" : "󰐊"; onTrig: root.player?.togglePlaying() }
        Ctl { visible: root._showCtl; icon: "󰒭"; onTrig: root.player?.next() }

        // Title (scrolls when wider than maxLen). Click opens the player menu.
        Item {
            id: titleArea
            anchors.verticalCenter: parent.verticalCenter
            width:  Math.min(tm.width, root.maxLen)
            height: tm.height
            clip:   root.overflow

            Text {
                visible: !root.overflow
                text:    root.full
                color:   titleHover.containsMouse ? Colors.fgBright : root._col
                font.family: root._font; font.pixelSize: root.fontSize
                Behavior on color { ColorAnimation { duration: 100 } }
            }
            Row {
                id: marquee
                visible: root.overflow
                spacing: 36
                readonly property real seg: tm.width + spacing
                Repeater {
                    model: 2
                    delegate: Text {
                        text:  root.full
                        color: titleHover.containsMouse ? Colors.fgBright : root._col
                        font.family: root._font; font.pixelSize: root.fontSize
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                }
                NumberAnimation on x {
                    running:  root.overflow && root.visible
                    from:     0
                    to:       -marquee.seg
                    duration: Math.max(3000, Math.round(marquee.seg * 20))
                    loops:    Animation.Infinite
                }
            }
            MouseArea {
                id: titleHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root._toggleMenu()
                onWheel: event => { if (event.angleDelta.y > 0) root.player?.previous(); else root.player?.next() }
            }
        }
    }

    // Inline control button.
    component Ctl: Text {
        property string icon: ""
        signal trig()
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        text:  icon
        color: ctlHover.containsMouse ? Colors.fgBright : root._col
        font.family: root._font; font.pixelSize: root.iconSize
        Behavior on color { ColorAnimation { duration: 100 } }
        MouseArea { id: ctlHover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.trig() }
    }
}
