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
    readonly property bool   _showArt: VtlConfig.moduleSetting("mpris", "show_art", false)
    readonly property bool   _wave:    VtlConfig.moduleSetting("mpris", "cava_wave", false)
    readonly property string full:     root.player?.trackTitle ?? ""

    // ── Audio wave behind the module ─────────────────────────────────────────
    // Only while this module is actually on screen AND something is playing: cava reads the
    // audio device, and keeping it alive for a paused player would burn CPU for a flat line.
    readonly property bool _waveOn: root._wave && root.visible && (root.player?.isPlaying ?? false)

    CavaWave {
        anchors.fill: parent
        z: -1                              // behind the controls and the title
        // The quietest of the three: in the bar the wave sits DIRECTLY behind the title, with
        // no card between them, so anything more than a hint competes with the text.
        radius: VtlConfig.barModuleBgRadiusFor(root.barMon)
        bars: 14
        intensity: 0.4
        barGap: 2
        opacity: 0.35
        active: root._waveOn
    }

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

        // Album art as a little record: round, and it turns while the track plays. FIXED size on
        // purpose — it is a picture, not a glyph, so tying it to the module's icon size made it
        // shrink along with the transport arrows and turned the cover into a smudge. Shown
        // whenever art is switched on: with no art the component's own glyph stands in, so the
        // disc is there either way instead of the module changing width when a player ships no
        // cover.
        Item {
            id: disc
            // A little air to the module's edges — at 26 it sat flush against the bar's inner
            // edge and read as cramped.
            readonly property int size: 22
            visible: root._showArt
            anchors.verticalCenter: parent.verticalCenter
            width:  disc.size
            height: disc.size

            RoundedImage {
                id: art
                anchors.fill: parent
                radius: Math.round(parent.width / 2)     // a circle, whatever the icon size is
                // It spins, so it is rendered at 3× and scaled down — at 1× the rotation
                // resampling made the cover look smeared. Decode close to that size too: a
                // 128 px cover squeezed into 18 px is a five-step downscale for nothing.
                supersample: 3
                decode: 64
                source: root.player?.trackArtUrl ?? ""

                // The spindle hole — small, and only over real art (on the fallback glyph it
                // would just sit on top of the note).
                Rectangle {
                    visible: art.ready
                    anchors.centerIn: parent
                    width:  Math.max(3, Math.round(parent.width * 0.16))
                    height: width
                    radius: width / 2
                    color:  Colors.bgPrimary
                    border.width: 1
                    border.color: Style.tint(Colors.fgBright, 0.25)
                }
            }

            // Turntable behaviour: the animation runs for as long as the disc is on screen and is
            // PAUSED when playback is — pausing holds the current angle, so hitting play picks the
            // rotation up where it stopped instead of snapping back to zero.
            RotationAnimator on rotation {
                running: disc.visible
                paused:  !(root.player?.isPlaying ?? false)
                from: 0; to: 360
                duration: 6000
                loops: Animation.Infinite
            }
        }

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
                    // ~20 px/s: slow enough to read a long title while walking past the bar.
                    // (Was twice that, which read as "scrolling" rather than as text.)
                    duration: Math.max(6000, Math.round(marquee.seg * 50))
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
