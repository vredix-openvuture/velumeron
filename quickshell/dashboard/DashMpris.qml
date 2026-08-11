import ".."
import QtQuick

// Now playing. Two faces, picked from the module's OWN height instead of from what the other cards
// left over: a compact cover-row for short cells, a full player (big cover, centred info,
// transport) once the user drags it tall enough. With no player it holds a quiet placeholder so
// the grid keeps its shape rather than showing an empty card.
DashTile {
    id: root
    readonly property var  player: DashState.player
    // Big = the full player. Also whenever the cell is upright: a cover-row in a portrait cell
    // wastes the height it was given.
    readonly property bool big: root.height >= 260 || (root.tall && root.height >= 150)
    // The compact cover grows with whatever height the cell has, so a stretched-but-not-big
    // module shows a real picture instead of a thumbnail.
    // The compact record follows the cell it landed in. The floor was 52, which is bigger than a
    // 1x1 cell's inner height — the disc then hung out of its own tile.
    readonly property int  cover: Math.max(24, Math.min(128, Math.min(root.innerW, root.innerH)))

    // Same wave as the bar module and the popout, behind the tile's content while something
    // plays. Inset by the tile radius so it cannot paint over the rounded corners.
    CavaWave {
        anchors { fill: parent; margins: 1 }
        z: -1
        // A tile is small and already carries cover, title and transport: few wide bars, kept
        // low, so the wave stays a backdrop instead of a second subject fighting the artwork.
        // Clipped to the tile's own corner radius, so the outer bars end WITH the card
        // instead of poking over its rounded bottom corners.
        radius: Style.rCard
        bars: 10
        intensity: 0.45
        barGap: 3
        opacity: 0.6
        active: root.player !== null && (root.player?.isPlaying ?? false)
    }

    // ── No player ────────────────────────────────────────────────────────────
    Column {
        visible: root.player === null
        anchors.centerIn: parent
        spacing: 8
        // Sized from the tile, not from two hard-coded numbers: at 1x1 a 48px disc overflowed the
        // cell and at 4x3 a 96px one sat in the middle of a field of nothing. Take the short side
        // and leave room for the caption under it.
        VinylArt {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(28, Math.min(root.innerW, root.innerH - (root.tiny ? 0 : 26)))
            height: width
            source: ""; spinning: false
            opacity: 0.5
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter
               visible: !root.tiny
               text: "Nothing playing"; color: Colors.fgMuted
               font.pixelSize: 12; font.family: Style.font }
    }

    // ── Compact: cover row + slim progress ───────────────────────────────────
    Row {
        visible: !root.big && root.player !== null
        anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: -4
                  left: parent.left; leftMargin: root.pad
                  right: parent.right; rightMargin: root.pad }
        spacing: 12
        VinylArt {
            width: root.cover; height: root.cover
            anchors.verticalCenter: parent.verticalCenter
            source: root.player?.trackArtUrl ?? ""
            spinning: root.player?.isPlaying ?? false

            // Click goes to the player's own window (Settings → Bar → Media).
            MouseArea {
                anchors.fill: parent
                enabled: VtlConfig.moduleSetting("mpris", "jump_to_player", true)
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: Actions.focusPlayer(root.player)
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - root.cover - ctl.width - 2 * 12)
            spacing: 2
            MarqueeText { width: parent.width
                          text: root.player?.trackTitle ?? ""; color: Colors.fgBright
                          pixelSize: 13; bold: true }
            MarqueeText { width: parent.width
                          visible: (root.player?.trackArtist ?? "") !== ""
                          text: root.player?.trackArtist ?? ""; color: Colors.fgMuted
                          pixelSize: 11 }
        }
        Row {
            id: ctl
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            MediaBtn { icon: "󰒮"; onTrig: root.player?.previous() }
            MediaBtn { icon: root.player?.isPlaying ? "󰏤" : "󰐊"; onTrig: root.player?.togglePlaying() }
            MediaBtn { icon: "󰒭"; onTrig: root.player?.next() }
        }
    }
    Rectangle {
        visible: !root.big && root.player !== null
        anchors { bottom: parent.bottom; bottomMargin: root.pad
                  left: parent.left; leftMargin: root.pad
                  right: parent.right; rightMargin: root.pad }
        height: 4; radius: 2; color: Style.liftSolid(Colors.bgElement)
        Rectangle { width: Math.round(parent.width * DashState.progress)
                    height: parent.height; radius: parent.radius; color: Style.accent }
    }

    // ── Big: cover fills the flexible room, info + transport below ────────────
    Column {
        visible: root.big && root.player !== null
        anchors { fill: parent; margins: root.pad }
        spacing: 12
        Item {
            width: parent.width
            height: Math.max(0, parent.height - info.height - prog.height - bigCtl.height - 3 * parent.spacing)
            VinylArt {
                // Equal air on three sides. The record is a circle inside a box that is rarely
                // square itself, so whichever side is short decides its size and the other one
                // is left with the difference. Centring it horizontally splits that difference
                // into two side gaps — so the top gets exactly the same amount as a margin, and
                // left, right and top end up identical whatever the tile's proportions are.
                // Whatever remains falls below the disc, where the title follows anyway.
                anchors {
                    top: parent.top
                    topMargin: Math.round((parent.width - width) / 2)
                    horizontalCenter: parent.horizontalCenter
                }
                width: Math.max(52, Math.min(parent.width, parent.height))
                height: width
                decode: 512
                source: root.player?.trackArtUrl ?? ""
                spinning: root.player?.isPlaying ?? false

                // Click goes to the player's own window (Settings → Bar → Media).
                MouseArea {
                    anchors.fill: parent
                    enabled: VtlConfig.moduleSetting("mpris", "jump_to_player", true)
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Actions.focusPlayer(root.player)
                }
            }
        }
        Column {
            id: info
            width: parent.width
            spacing: 2
            MarqueeText { width: parent.width; hAlign: Text.AlignHCenter
                          text: root.player?.trackTitle ?? ""; color: Colors.fgBright
                          pixelSize: 15; bold: true }
            MarqueeText { width: parent.width; hAlign: Text.AlignHCenter
                          visible: (root.player?.trackArtist ?? "") !== ""
                          text: root.player?.trackArtist ?? ""; color: Colors.fgMuted
                          pixelSize: 12 }
        }
        Rectangle {
            id: prog
            width: parent.width; height: 5; radius: 2; color: Style.liftSolid(Colors.bgElement)
            Rectangle { width: Math.round(parent.width * DashState.progress)
                        height: parent.height; radius: parent.radius; color: Style.accent }
        }
        Row {
            id: bigCtl
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            MediaBtn { size: 42; icon: "󰒮"; onTrig: root.player?.previous() }
            MediaBtn { size: 48; icon: root.player?.isPlaying ? "󰏤" : "󰐊"; onTrig: root.player?.togglePlaying() }
            MediaBtn { size: 42; icon: "󰒭"; onTrig: root.player?.next() }
        }
    }

    // Round transport button (compact cousin of MprisMenuBody's Ctl).
    component MediaBtn: Rectangle {
        id: mb
        property string icon: ""
        property int    size: 34
        signal trig()
        width: size; height: size; radius: size / 2
        // Opaque: this was an accent tint at 18 % alpha, so the wave behind the tile shone
        // straight through the transport buttons.
        color: mbHov.containsMouse ? Style.accent : Style.liftSolid(Colors.bgElement)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { anchors.centerIn: parent; text: mb.icon
               color: mbHov.containsMouse ? Style.onAccent : Colors.fgPrimary
               font.pixelSize: Math.round(mb.size * 0.47); font.family: Style.iconFont }
        MouseArea { id: mbHov; anchors.fill: parent; hoverEnabled: true; onClicked: mb.trig() }
    }
}
