pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Phone popout — one card per paired device: name, battery, cellular, and the actions, all served
// by PhoneService (KDE Connect's daemon over D-Bus). Sending files is the point of it: drop them
// anywhere on the panel, or press "Send files…" for a chooser. No KDE window is involved at any
// step, which is the whole reason this exists instead of the KDE indicator.
Flyout {
    id: root
    flyoutId: "phone"
    panelW:   380
    maxH:     560

    // Keep the service on its brisk refresh only while this is up.
    onIsOpenChanged: {
        PhoneService.watchers = Math.max(0, PhoneService.watchers + (root.isOpen ? 1 : -1))
        if (root.isOpen) PhoneService.refresh()
    }

    // Drop files anywhere on the panel → they go to the device under the cursor, or to the only
    // reachable one when there is just the one.
    property string dropTarget: ""
    readonly property string _dropDev: root.dropTarget !== "" ? root.dropTarget
                                     : (PhoneService.reachable.length === 1 ? PhoneService.reachable[0].id : "")

    DropArea {
        anchors.fill: parent
        onEntered: drag => { if (root._dropDev === "") drag.accepted = false }
        onDropped: drop => {
            var paths = []
            var us = drop.urls ?? []
            for (var i = 0; i < us.length; i++) paths.push("" + us[i])
            if (paths.length > 0 && root._dropDev !== "") PhoneService.share(root._dropDev, paths)
            drop.accept()
        }
    }

    // Lowest charge across the reachable devices — the one figure worth putting in the head,
    // because what you want from a glance is "is anything about to die", not each in turn.
    readonly property int _lowBat: {
        var ds = PhoneService.reachable, m = -1
        for (var i = 0; i < ds.length; i++) {
            var b = ds[i].battery ?? ({})
            if (b.ok === true && b.charge >= 0 && (m < 0 || b.charge < m)) m = b.charge
        }
        return m
    }
    readonly property bool _anyCharging: {
        var ds = PhoneService.reachable
        for (var i = 0; i < ds.length; i++) if ((ds[i].battery ?? ({})).charging === true) return true
        return false
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        // ── Head: the fleet as figures, before any device card ─────────────────
        Row {
            id: phStats
            visible: PhoneService.available && PhoneService.devices.length > 0
            width: parent.width
            height: 34
            readonly property int cellW: Math.floor((width - 2 * 10) / 3)
            spacing: 10
            StatCell {
                width: phStats.cellW
                glyph: "󰄜"
                value: PhoneService.reachable.length + "/" + PhoneService.devices.length
                caption: "Online"
                good: PhoneService.hasDevices; dim: !PhoneService.hasDevices
            }
            StatCell {
                width: phStats.cellW
                glyph: root._anyCharging ? "󰂄" : root._lowBat >= 0 ? "󰁹" : ""
                value: root._lowBat >= 0 ? (root._lowBat + "%") : "—"
                caption: "Lowest"
                warn: root._lowBat >= 0 && root._lowBat <= 15 && !root._anyCharging
                good: root._anyCharging
                dim:  root._lowBat < 0
            }
            StatCell {
                width: phStats.cellW
                value: PhoneService.primary && (PhoneService.primary.connectivity ?? ({})).ok === true
                       && PhoneService.primary.connectivity.type !== ""
                       ? PhoneService.primary.connectivity.type : "—"
                caption: "Cellular"
                dim: !PhoneService.hasDevices
            }
        }
        SectionRule {
            visible: PhoneService.available && PhoneService.devices.length > 0
            height: visible ? 16 : 0
            text: "Devices"
            trailing: "drop files to send"
        }

        // Nothing paired / no daemon → say which, and don't pretend there are actions.
        StyledRect {
            visible: !PhoneService.available || PhoneService.devices.length === 0
            width:   parent.width
            height:  hintCol.implicitHeight + 20
            radius:  Style.rControl
            color:   Style.tint(Style.accent, 0.10)
            Column {
                id: hintCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: 12; rightMargin: 12 }
                spacing: 6
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: !PhoneService.available
                          ? "KDE Connect's daemon isn't running — install the kdeconnect package and it starts on demand."
                          : "No paired device yet. Pair from the KDE Connect app on your phone; it will show up here."
                    color: Colors.fgPrimary; font.pixelSize: 12; font.family: Style.font
                }
                Text {
                    visible: PhoneService.data.error !== ""
                    width: parent.width; elide: Text.ElideRight
                    text:  PhoneService.data.error
                    color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font
                }
            }
        }

        Repeater {
            model: PhoneService.devices
            delegate: DataTile {
                id: card
                required property var modelData
                readonly property bool live: card.modelData.reachable && card.modelData.paired
                readonly property var  bat:  card.modelData.battery ?? ({})
                readonly property var  con:  card.modelData.connectivity ?? ({})
                readonly property bool low:  card.bat.ok === true && card.bat.charge >= 0
                                             && card.bat.charge <= 15 && !card.bat.charging

                interactive: true
                active:  card.live
                opacity: card.live ? 1.0 : 0.55
                // A drop lands on whichever card the cursor is over.
                onHoveredChanged: if (card.hovered && card.live) root.dropTarget = card.modelData.id

                Row {
                    width: parent.width
                    spacing: 12

                    // Charge as a ring — the same shape a volume puck uses, so a device and a
                    // stream read as the same kind of thing across the two panels.
                    ValueRing {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 46
                        visible: card.bat.ok === true && card.bat.charge >= 0
                        value: Math.max(0, Math.min(1, (card.bat.charge ?? 0) / 100))
                        halo:  card.bat.charging ? 0.55 : 0
                        dim:   !card.live
                        ringColor: card.low ? Colors.fgUrgent : Style.accent
                        Text {
                            anchors.centerIn: parent
                            text: card.bat.charge + ""
                            color: card.low ? Colors.fgUrgent : Colors.fgBright
                            font.family: Style.font; font.pixelSize: 13; font.bold: true
                        }
                    }
                    // No battery plugin → the device icon keeps the slot, so the row never jumps.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !(card.bat.ok === true && card.bat.charge >= 0)
                        width: 46; horizontalAlignment: Text.AlignHCenter
                        text: PhoneService.icon(card.modelData)
                        color: card.live ? Style.accent : Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 22
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - 58 - sig.width - 12)
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: card.modelData.name
                            color: Colors.fgBright
                            font.family: Style.font; font.pixelSize: 14; font.bold: true
                        }
                        Row {
                            spacing: 8
                            MetaTag {
                                text: !card.modelData.paired ? "not paired"
                                    : !card.modelData.reachable ? "offline"
                                    : (card.con.ok && card.con.type !== "" ? card.con.type : "connected")
                                good: card.live
                            }
                            MetaTag { text: card.bat.charging ? "charging" : ""; good: true }
                        }
                    }

                    SignalArc {
                        id: sig
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30
                        visible: card.con.ok === true && card.con.strength >= 0
                        value: Math.max(0, Math.min(1, (card.con.strength ?? 0) / 4))
                        dim: !card.live
                        arcColor: Style.accent
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 5
                    visible: card.live
                    DataChip {
                        label: "󰅧  Send files"; on: true
                        enabled: PhoneService.hasPlugin(card.modelData, "share")
                        opacity: enabled ? 1 : 0.4
                        onTap: PhoneService.pickAndShare(card.modelData.id)
                    }
                    DataChip {
                        label: "󰄜  Ring"
                        enabled: PhoneService.hasPlugin(card.modelData, "findmyphone")
                        opacity: enabled ? 1 : 0.4
                        onTap: PhoneService.ring(card.modelData.id)
                    }
                    DataChip {
                        label: "󰎇  Ping"
                        enabled: PhoneService.hasPlugin(card.modelData, "ping")
                        opacity: enabled ? 1 : 0.4
                        onTap: PhoneService.ping(card.modelData.id)
                    }
                }
            }
        }

    }
}
