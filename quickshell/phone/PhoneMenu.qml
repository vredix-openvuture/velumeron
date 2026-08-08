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

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

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
            delegate: StyledRect {
                id: card
                required property var modelData
                readonly property bool live: card.modelData.reachable && card.modelData.paired
                readonly property var  bat:  card.modelData.battery ?? ({})
                readonly property var  con:  card.modelData.connectivity ?? ({})

                width:  parent.width
                height: body.implicitHeight + 22
                radius: Style.rControl
                color:  cardHov.containsMouse ? Style.controlHover : Style.menuRowFill
                opacity: card.live ? 1.0 : 0.55
                Behavior on color { ColorAnimation { duration: 100 } }

                // Which device a drop lands on: whichever card the cursor is over.
                MouseArea {
                    id: cardHov
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: if (containsMouse && card.live) root.dropTarget = card.modelData.id
                }

                Column {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 12; rightMargin: 12; topMargin: 11 }
                    spacing: 9

                    Row {
                        width: parent.width
                        spacing: 9
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text:  PhoneService.icon(card.modelData)
                            color: card.live ? Style.accent : Colors.fgMuted
                            font.family: Style.font; font.pixelSize: 19
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 28 - batT.implicitWidth - 18
                            spacing: 1
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text:  card.modelData.name
                                color: Colors.fgBright
                                font.family: Style.font; font.pixelSize: 14; font.bold: true
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: !card.modelData.paired ? "not paired"
                                    : !card.modelData.reachable ? "offline"
                                    : (card.con.ok && card.con.type !== ""
                                       ? PhoneService.signalGlyph(card.con.strength) + "  " + card.con.type
                                       : "connected")
                                color: Colors.fgMuted
                                font.family: Style.font; font.pixelSize: 11
                            }
                        }
                        Text {
                            id: batT
                            anchors.verticalCenter: parent.verticalCenter
                            visible: card.bat.ok === true && card.bat.charge >= 0
                            text:  (card.bat.charging ? "󰂄 " : "󰁹 ") + card.bat.charge + "%"
                            color: card.bat.charging ? Style.accent
                                 : card.bat.charge <= 15 ? Colors.fgUrgent : Colors.fgPrimary
                            font.family: Style.font; font.pixelSize: 12
                        }
                    }

                    // Battery bar — a number alone reads slower than a line you can glance at.
                    Rectangle {
                        visible: card.bat.ok === true && card.bat.charge >= 0
                        width: parent.width; height: 5; radius: 2.5
                        color: Colors.bgPrimary
                        Rectangle {
                            width:  parent.width * Math.max(0, Math.min(1, card.bat.charge / 100))
                            height: parent.height; radius: parent.radius
                            color:  card.bat.charging ? Style.accent
                                  : card.bat.charge <= 15 ? Colors.fgUrgent : Colors.bgActive
                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6
                        visible: card.live
                        Act {
                            label: "󰅧  Send files…"
                            primary: true
                            enabled: PhoneService.hasPlugin(card.modelData, "share")
                            onTap: PhoneService.pickAndShare(card.modelData.id)
                        }
                        Act {
                            label: "󰄜  Ring"
                            enabled: PhoneService.hasPlugin(card.modelData, "findmyphone")
                            onTap: PhoneService.ring(card.modelData.id)
                        }
                        Act {
                            label: "󰎇  Ping"
                            enabled: PhoneService.hasPlugin(card.modelData, "ping")
                            onTap: PhoneService.ping(card.modelData.id)
                        }
                    }
                }
            }
        }

        Text {
            visible: PhoneService.hasDevices
            width: parent.width; wrapMode: Text.WordWrap
            text:  "Drop files onto a device to send them."
            color: Colors.fgMuted; font.pixelSize: 10; font.family: Style.font
        }
    }

    component Act: StyledRect {
        id: act
        property string label:   ""
        property bool   primary: false
        signal tap()
        // No `enabled` of its own: Item already has one, and setting it also stops the MouseArea
        // below from firing — so a device without the plugin is inert, not just faded.
        width:  actT.implicitWidth + 22
        height: 28
        radius: Style.rTile
        opacity: act.enabled ? 1.0 : 0.4
        color: act.primary ? (actHov.containsMouse ? Style.tint(Style.accent, 0.55) : Style.tint(Style.accent, 0.34))
                           : (actHov.containsMouse ? Style.controlHover : Style.controlFill)
        Behavior on color { ColorAnimation { duration: 90 } }
        Text {
            id: actT
            anchors.centerIn: parent
            text:  act.label
            color: act.primary ? Colors.fgBright : Colors.fgPrimary
            font.family: Style.font; font.pixelSize: 12
        }
        MouseArea {
            id: actHov
            anchors.fill: parent
            hoverEnabled: true
            onClicked: act.tap()
        }
    }
}
