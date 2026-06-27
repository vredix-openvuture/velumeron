import "../.."
import QtQuick
import Quickshell.Services.Mpris

Item {
    id: root
    property bool vertical: false   // set by ModSlot: rotate to read along a vertical sidebar

    readonly property MprisPlayer player: Mpris.players.values.length > 0
                                          ? Mpris.players.values[0] : null
    visible: player !== null

    readonly property bool hovered: mouseArea.containsMouse

    // Full title (no truncation); it scrolls when wider than `maxLen`.
    readonly property int    maxLen: 180
    readonly property string full:   (root.player?.isPlaying ? " " : " ") + (root.player?.trackTitle ?? "")

    // Measure the full title to decide static vs. marquee.
    TextMetrics {
        id: tm
        font.family:    "FantasqueSansM Nerd Font"
        font.pointSize: 10
        text:           root.full
    }
    readonly property bool overflow: tm.width > maxLen

    implicitWidth:  Math.min(tm.width, maxLen)
    implicitHeight: tm.height
    width:  implicitWidth
    height: implicitHeight
    clip:   overflow

    // Static — fits in full.
    Text {
        visible: !root.overflow
        text:    root.full
        color:   root.hovered ? Colors.fgBright : Colors.fgMuted
        font.family:    "FantasqueSansM Nerd Font"
        font.pointSize: 10
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    // Marquee — two identical copies scrolling left; looping one segment is seamless.
    Row {
        id: marquee
        visible: root.overflow
        spacing: 36
        readonly property real seg: tm.width + spacing
        Repeater {
            model: 2
            delegate: Text {
                text:  root.full
                color: root.hovered ? Colors.fgBright : Colors.fgMuted
                font.family:    "FantasqueSansM Nerd Font"
                font.pointSize: 10
                Behavior on color { ColorAnimation { duration: 100 } }
            }
        }
        NumberAnimation on x {
            running:  root.overflow && root.visible
            from:     0
            to:       -marquee.seg
            duration: Math.max(4000, Math.round(marquee.seg * 60))
            loops:    Animation.Infinite
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill:    parent
        hoverEnabled:    true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if      (event.button === Qt.LeftButton)   root.player?.togglePlaying()
            else if (event.button === Qt.RightButton)  root.player?.next()
            else if (event.button === Qt.MiddleButton) root.player?.previous()
        }
        onWheel: event => {
            if (event.angleDelta.y > 0) root.player?.previous()
            else                        root.player?.next()
        }
    }
}
