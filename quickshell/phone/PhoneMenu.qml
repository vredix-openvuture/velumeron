pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Phone popout. One device is the MAIN one and gets tracked at the top with everything it can do —
// charge, cellular, what it is playing, what is on its screen — and the rest are one line each,
// there to be promoted. A strip of numbers averaged over every paired device answered a question
// nobody has ("what is the lowest battery in the house"); one device you chose answers the one
// everybody has.
//
// Served by PhoneService (KDE Connect's daemon over D-Bus). Sending files is still the point of it:
// drop them anywhere on the panel, or press "Send files…". No KDE window is involved at any step.
Flyout {
    id: root
    flyoutId: "phone"
    panelW:   400
    maxH:     680

    // Keep the service on its brisk refresh only while this is up.
    onIsOpenChanged: {
        PhoneService.watchers = Math.max(0, PhoneService.watchers + (root.isOpen ? 1 : -1))
        if (root.isOpen) PhoneService.refresh()
    }

    readonly property var main: PhoneService.mainDevice
    readonly property string mainId: root.main ? root.main.id : ""
    readonly property var others: PhoneService.devices.filter(d => d.id !== root.mainId)

    // Drop files anywhere on the panel → they go to the device under the cursor, else the main one.
    property string dropTarget: ""
    readonly property string _dropDev: root.dropTarget !== "" ? root.dropTarget : root.mainId

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

        // ══ The main device ═══════════════════════════════════════════════════════════════════
        DataTile {
            id: hero
            visible: root.main !== null
            active:  true
            pad:     14
            spacing: 11

            readonly property var  d:      root.main ?? ({})
            readonly property bool live:   hero.d.reachable === true && hero.d.paired === true
            readonly property var  bat:    hero.d.battery ?? ({})
            readonly property var  con:    hero.d.connectivity ?? ({})
            readonly property var  med:    hero.d.media ?? ({})
            readonly property var  ntf:    hero.d.notifs ?? ({})
            readonly property bool hasBat: hero.bat.ok === true && hero.bat.charge >= 0
            readonly property bool low:    hero.hasBat && hero.bat.charge <= 15 && !hero.bat.charging

            // ── Identity. The device's own glyph, big, wearing its charge as the ring around it.
            Row {
                width: parent.width
                spacing: 14
                Item {
                    id: idn
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76; height: 76
                    ValueRing {
                        anchors.fill: parent
                        visible: hero.hasBat
                        value: Math.max(0, Math.min(1, (hero.bat.charge ?? 0) / 100))
                        halo:  hero.bat.charging ? 0.55 : 0
                        thickness: 4
                        dim:   !hero.live
                        ringColor: hero.low ? Colors.fgUrgent : Style.accent
                    }
                    // No battery plugin → the bare track keeps the slot, so nothing jumps.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: !hero.hasBat
                        width: 70; height: 70; radius: 35
                        color: "transparent"
                        border.width: 4
                        border.color: Style.tint(Colors.bgElement, Style.lift(0.34))
                    }
                    Text {
                        anchors.centerIn: parent
                        text: PhoneService.icon(hero.d)
                        color: hero.live ? Colors.fgBright : Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 34
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - idn.width - parent.spacing)
                    spacing: 4
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: hero.d.name ?? ""
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 18; font.bold: true
                    }
                    Row {
                        spacing: 8
                        MetaTag {
                            text: hero.d.paired !== true ? "not paired"
                                : !hero.live ? "offline" : "connected"
                            good: hero.live; warn: !hero.live
                        }
                        MetaTag { text: hero.bat.charging ? "charging" : ""; good: true }
                        MetaTag { text: hero.med.ok === true && hero.med.playing ? "playing" : ""; good: true }
                    }
                    MetaTag {
                        width: parent.width; elide: Text.ElideRight
                        text: PhoneService.devices.length > 1 ? "main device" : ""
                    }
                }
            }

            // ── The readings.
            Row {
                id: facts
                width: parent.width
                spacing: 7
                readonly property int cellW: Math.floor((width - 2 * spacing) / 3)
                StatCell {
                    width: facts.cellW
                    glyph:   hero.bat.charging ? "󰂄" : hero.hasBat ? "󰁹" : ""
                    value:   hero.hasBat ? (hero.bat.charge + "%") : "—"
                    caption: hero.bat.charging ? "Charging" : "Battery"
                    warn: hero.low; good: hero.bat.charging === true; dim: !hero.hasBat
                }
                StatCell {
                    width: facts.cellW
                    glyph:   PhoneService.signalGlyph(hero.con.strength)
                    value:   hero.con.ok === true && hero.con.type !== "" ? hero.con.type : "—"
                    caption: "Cellular"
                    good: hero.con.ok === true && (hero.con.strength ?? 0) >= 3
                    dim:  hero.con.ok !== true
                }
                StatCell {
                    width: facts.cellW
                    glyph:   "󰂚"
                    value:   hero.ntf.ok === true ? (hero.ntf.total + "") : "—"
                    caption: "On screen"
                    good: hero.ntf.ok === true && hero.ntf.total > 0
                    dim:  hero.ntf.ok !== true || hero.ntf.total === 0
                }
            }

            // ── What the phone is playing, and the transport for it. The cover is a real file the
            //    daemon already cached, so there is nothing to fetch here.
            StyledRect {
                id: np
                width: parent.width
                height: 62
                radius: Style.rTile
                visible: hero.med.ok === true
                color: Style.tint(Colors.bgElement, Style.lift(0.14))

                // Between refreshes (5 s) the position is stepped locally, so a playing track gets a
                // bar that moves rather than one that lurches once every five seconds.
                property real pos: 0
                onVisibleChanged: np.pos = hero.med.position ?? 0
                Connections {
                    target: hero
                    function onMedChanged() { np.pos = hero.med.position ?? 0 }
                }
                Timer {
                    interval: 1000; repeat: true
                    running: root.isOpen && hero.med.playing === true
                    onTriggered: np.pos = Math.min(hero.med.length ?? 0, np.pos + 1000)
                }

                RoundedImage {
                    id: art
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 8 }
                    width: 46; height: 46
                    radius: Style.rTile
                    source: hero.med.art ?? ""
                    fallback: "󰝚"
                }
                Column {
                    anchors { left: art.right; right: transport.left; verticalCenter: parent.verticalCenter
                              leftMargin: 10; rightMargin: 10 }
                    spacing: 2
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: hero.med.title ?? ""
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 12; font.bold: true
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        visible: text !== ""
                        text: hero.med.artist ?? ""
                        color: Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 10
                    }
                    // A progress bar when the track has a length; otherwise the player's name, since
                    // the phone can have several and which one you are driving matters.
                    Item {
                        width: parent.width; height: 9
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                            height: 3; radius: 2
                            visible: (hero.med.length ?? 0) > 0
                            color: Style.tint(Colors.bgElement, Style.lift(0.34))
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * Math.max(0, Math.min(1, np.pos / Math.max(1, hero.med.length ?? 1)))
                                radius: 2
                                color: Style.accent
                            }
                        }
                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            visible: (hero.med.length ?? 0) <= 0
                            text: hero.med.player ?? ""
                            color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9
                        }
                    }
                }
                Row {
                    id: transport
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                    spacing: 5
                    RoundBtn { icon: "󰒮"; onTrig: PhoneService.media(hero.d.id, "Previous") }
                    RoundBtn {
                        big: true
                        icon: hero.med.playing === true ? "󰏤" : "󰐊"
                        onTrig: PhoneService.media(hero.d.id, "PlayPause")
                    }
                    RoundBtn { icon: "󰒭"; onTrig: PhoneService.media(hero.d.id, "Next") }
                }
            }

            // ── Everything it can be asked to do.
            Flow {
                width: parent.width
                spacing: 5
                visible: hero.live
                DataChip {
                    label: "󰅧  Send files"; on: true
                    enabled: PhoneService.hasPlugin(hero.d, "share")
                    opacity: enabled ? 1 : 0.4
                    onTap: PhoneService.pickAndShare(hero.d.id)
                }
                DataChip {
                    label: "󰅎  Clipboard"
                    enabled: PhoneService.hasPlugin(hero.d, "clipboard")
                    opacity: enabled ? 1 : 0.4
                    onTap: PhoneService.pushClipboard(hero.d.id)
                }
                DataChip {
                    label: "󰄜  Ring"
                    enabled: PhoneService.hasPlugin(hero.d, "findmyphone")
                    opacity: enabled ? 1 : 0.4
                    onTap: PhoneService.ring(hero.d.id)
                }
                DataChip {
                    label: "󰎇  Ping"
                    enabled: PhoneService.hasPlugin(hero.d, "ping")
                    opacity: enabled ? 1 : 0.4
                    onTap: PhoneService.ping(hero.d.id)
                }
            }
        }

        // ══ What is on the phone's screen ═════════════════════════════════════════════════════
        // Only devices that MIRROR their notifications to the desktop expose these; one set up the
        // other way round (it receives ours) has no such object at all, and then the whole block is
        // absent rather than sitting there empty.
        SectionRule {
            visible: hero.visible && (hero.ntf.total ?? 0) > 0
            height:  visible ? 16 : 0
            text: "On the phone"
            trailing: (hero.ntf.total ?? 0) > (hero.ntf.items ?? []).length
                      ? ((hero.ntf.items ?? []).length + " of " + hero.ntf.total) : ""
        }
        Repeater {
            model: hero.visible ? (hero.ntf.items ?? []) : []
            delegate: StyledRect {
                id: nrow
                required property var modelData
                width: parent.width
                height: 44
                radius: Style.rTile
                color: nh.containsMouse ? Style.tint(Colors.bgElement, Style.lift(0.16))
                                        : Style.tint(Colors.bgElement, Style.lift(0.07))
                Behavior on color { ColorAnimation { duration: 110 } }
                MouseArea { id: nh; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                Column {
                    anchors { left: parent.left; right: ndel.left; verticalCenter: parent.verticalCenter
                              leftMargin: 11; rightMargin: 8 }
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: nrow.modelData.app
                        color: Colors.bgActive
                        font.family: Style.font; font.pixelSize: 9; font.bold: true
                        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: nrow.modelData.text !== ""
                              ? (nrow.modelData.title + " · " + nrow.modelData.text)
                              : nrow.modelData.title
                        color: Colors.fgPrimary
                        font.family: Style.font; font.pixelSize: 11
                    }
                }
                Rectangle {
                    id: ndel
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 7 }
                    visible: nrow.modelData.dismissable === true
                    width: 22; height: 22; radius: 11
                    color: dh.containsMouse ? Style.tint(Colors.fgUrgent, 0.25) : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: Colors.fgMuted
                           font.family: Style.font; font.pixelSize: 10 }
                    MouseArea {
                        id: dh; anchors.fill: parent; hoverEnabled: true
                        onClicked: PhoneService.dismissNotif(hero.d.id, nrow.modelData.id)
                    }
                }
            }
        }

        // ══ The other devices — one line each, there to be promoted ═══════════════════════════
        SectionRule {
            visible: root.others.length > 0
            height:  visible ? 16 : 0
            text: "Other devices"
            trailing: "drop files to send"
        }
        Repeater {
            model: root.others
            delegate: StyledRect {
                id: orow
                required property var modelData
                readonly property bool live:   orow.modelData.reachable && orow.modelData.paired
                readonly property var  bat:    orow.modelData.battery ?? ({})
                readonly property bool hasBat: orow.bat.ok === true && orow.bat.charge >= 0

                width: parent.width
                height: 52
                radius: Style.rTile
                clip: true
                color: oh.containsMouse ? Style.tint(Colors.bgElement, Style.lift(0.16))
                                        : Style.tint(Colors.bgElement, Style.lift(0.07))
                opacity: orow.live ? 1.0 : 0.55
                Behavior on color { ColorAnimation { duration: 110 } }
                MouseArea {
                    id: oh; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton
                    onContainsMouseChanged: if (containsMouse && orow.live) root.dropTarget = orow.modelData.id
                }

                Item {
                    id: oidn
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 40; height: 40
                    ValueRing {
                        anchors.fill: parent
                        visible: orow.hasBat
                        value: Math.max(0, Math.min(1, (orow.bat.charge ?? 0) / 100))
                        thickness: 3
                        dim: !orow.live
                        ringColor: orow.hasBat && orow.bat.charge <= 15 && !orow.bat.charging
                                   ? Colors.fgUrgent : Style.accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: PhoneService.icon(orow.modelData)
                        color: orow.live ? Colors.fgBright : Colors.fgMuted
                        font.family: Style.font; font.pixelSize: 20
                    }
                }
                Column {
                    anchors { left: oidn.right; right: opin.left; verticalCenter: parent.verticalCenter
                              leftMargin: 10; rightMargin: 8 }
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: orow.modelData.name
                        color: Colors.fgBright
                        font.family: Style.font; font.pixelSize: 13; font.bold: true
                    }
                    Row {
                        spacing: 8
                        MetaTag {
                            text: !orow.modelData.paired ? "not paired"
                                : !orow.live ? "offline" : "connected"
                            good: orow.live
                        }
                        MetaTag { text: orow.hasBat ? (orow.bat.charge + "%") : "" }
                    }
                }
                // Promote: this device becomes the one tracked at the top.
                RoundBtn {
                    id: opin
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    icon: "󰐃"
                    onTrig: PhoneService.setMain(orow.modelData.id)
                }
            }
        }
    }

    // A round button — the transport keys and the promote pin are one object at two sizes.
    component RoundBtn: StyledRect {
        id: rb
        property string icon: ""
        property bool   big:  false
        signal trig()
        width: rb.big ? 34 : 28; height: rb.width; radius: rb.width / 2
        color: rbH.containsMouse ? Style.tint(Colors.bgActive, Style.lift(0.30))
             : rb.big ? Style.tint(Colors.bgElement, Style.lift(0.26))
                      : Style.tint(Colors.bgElement, Style.lift(0.14))
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            anchors.centerIn: parent
            text: rb.icon; color: Colors.fgBright
            font.family: Style.font; font.pixelSize: rb.big ? 15 : 12
        }
        MouseArea { id: rbH; anchors.fill: parent; hoverEnabled: true; onClicked: rb.trig() }
    }
}
