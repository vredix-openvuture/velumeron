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
    panelW:   500
    maxH:     760

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
        spacing: 13

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
            pad:     18
            spacing: 14

            readonly property var  d:      root.main ?? ({})
            readonly property bool live:   hero.d.reachable === true && hero.d.paired === true
            readonly property var  bat:    hero.d.battery ?? ({})
            readonly property var  con:    hero.d.connectivity ?? ({})
            readonly property var  med:    hero.d.media ?? ({})
            readonly property bool hasBat: hero.bat.ok === true && hero.bat.charge >= 0
            readonly property bool low:    hero.hasBat && hero.bat.charge <= 15 && !hero.bat.charging

            // ── Identity. The device's own glyph, big, wearing its charge as the ring around it.
            Row {
                width: parent.width
                spacing: 18
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
                    width: Math.max(0, parent.width - idn.width - mainDot.width - 2 * parent.spacing)
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
                SelectDot {
                    id: mainDot
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: PhoneService.devices.length > 1 ? 1 : 0
                    on: true
                }
            }

            // ── The readings.
            Row {
                id: facts
                width: parent.width
                spacing: 9
                readonly property int cellW: Math.floor((width - spacing) / 2)
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
            }

            // ── What the phone is playing, and the transport for it. The cover is a real file the
            //    daemon already cached, so there is nothing to fetch here.
            StyledRect {
                id: np
                width: parent.width
                height: 104
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
                    anchors { left: parent.left; top: parent.top; leftMargin: 11; topMargin: 11 }
                    width: 62; height: 62
                    radius: Style.rTile
                    source: hero.med.art ?? ""
                    fallback: "󰝚"
                }
                Column {
                    anchors { left: art.right; right: transport.left; top: parent.top
                              leftMargin: 13; rightMargin: 13; topMargin: 13 }
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
                    // Which of the phone's players is being driven — it can have several, and
                    // pressing pause on the wrong one is a puzzle nobody enjoys.
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: hero.med.player ?? ""
                        color: Style.accent
                        font.family: Style.font; font.pixelSize: 9
                        font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
                    }
                }
                Row {
                    id: transport
                    anchors { right: parent.right; top: parent.top; rightMargin: 11; topMargin: 18 }
                    spacing: 7
                    RoundBtn { icon: "󰒮"; onTrig: PhoneService.media(hero.d.id, "Previous") }
                    RoundBtn {
                        big: true
                        icon: hero.med.playing === true ? "󰏤" : "󰐊"
                        onTrig: PhoneService.media(hero.d.id, "PlayPause")
                    }
                    RoundBtn { icon: "󰒭"; onTrig: PhoneService.media(hero.d.id, "Next") }
                }

                // ── Elapsed / total, full width under the lot.
                Item {
                    id: prog
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                              leftMargin: 13; rightMargin: 13; bottomMargin: 11 }
                    height: 20
                    readonly property real frac: Math.max(0, Math.min(1, np.pos / Math.max(1, hero.med.length ?? 1)))

                    Text {
                        id: tNow
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: (hero.med.length ?? 0) > 0 ? PhoneService.fmtTime(np.pos) : ""
                        color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9
                    }
                    Text {
                        id: tEnd
                        anchors { right: volume.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: (hero.med.length ?? 0) > 0 ? PhoneService.fmtTime(hero.med.length) : ""
                        color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 9
                    }
                    Rectangle {
                        anchors { left: tNow.right; right: tEnd.left; leftMargin: 8; rightMargin: 8
                                  verticalCenter: parent.verticalCenter }
                        height: 3; radius: 2
                        visible: (hero.med.length ?? 0) > 0
                        color: Style.tint(Colors.bgElement, Style.lift(0.34))
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * prog.frac
                            radius: 2
                            color: Style.accent
                        }
                    }

                    // The PHONE's player volume. Tracked locally while dragging and written once on
                    // release: mprisremote's volume is a D-Bus property set, and firing one per
                    // mouse move would be a round trip per frame.
                    Item {
                        id: volume
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 84; height: 20
                        visible: (hero.med.volume ?? -1) >= 0
                        property real v: hero.med.volume ?? 0
                        property bool dragging: false
                        Connections {
                            target: hero
                            function onMedChanged() { if (!volume.dragging) volume.v = hero.med.volume ?? 0 }
                        }
                        Text {
                            id: vGlyph
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: volume.v <= 0 ? "󰝟" : volume.v < 50 ? "󰖀" : "󰕾"
                            color: Colors.fgMuted; font.family: Style.font; font.pixelSize: 11
                        }
                        Rectangle {
                            id: vTrack
                            anchors { left: vGlyph.right; right: parent.right; leftMargin: 7
                                      verticalCenter: parent.verticalCenter }
                            height: 3; radius: 2
                            color: Style.tint(Colors.bgElement, Style.lift(0.34))
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * Math.max(0, Math.min(1, volume.v / 100))
                                radius: 2
                                color: Style.accent
                            }
                        }
                        MouseArea {
                            anchors { left: vTrack.left; right: vTrack.right; top: parent.top; bottom: parent.bottom }
                            function apply(x) { volume.v = Math.max(0, Math.min(100, Math.round(x / width * 100))) }
                            onPressed: e => { volume.dragging = true; apply(e.x) }
                            onPositionChanged: e => { if (pressed) apply(e.x) }
                            onReleased: {
                                volume.dragging = false
                                PhoneService.mediaVolume(hero.d.id, volume.v)
                            }
                            onCanceled: volume.dragging = false
                        }
                    }
                }
            }

            // ── Everything it can be asked to do.
            Flow {
                width: parent.width
                spacing: 7
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
                height: 60
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
                    anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                    width: 44; height: 44
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
                        font.family: Style.font; font.pixelSize: 22
                    }
                }
                Column {
                    anchors { left: oidn.right; right: opin.left; verticalCenter: parent.verticalCenter
                              leftMargin: 13; rightMargin: 10 }
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
                // Choose: this device becomes the one tracked at the top.
                SelectDot {
                    id: opin
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    on: false
                    onPick: PhoneService.setMain(orow.modelData.id)
                }
            }
        }
    }

    // Which device the panel is about. A radio, not a pin: a pin says "keep this", and what this
    // actually does is pick one of a set — so it should look like the thing that picks one of a set.
    component SelectDot: Item {
        id: sd
        property bool on: false
        signal pick()
        width: 22; height: 22
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: sd.on ? Style.tint(Style.accent, 0.20)
                 : sdH.containsMouse ? Style.tint(Colors.bgActive, Style.lift(0.24)) : "transparent"
            border.width: 2
            border.color: sd.on ? Style.accent
                        : sdH.containsMouse ? Style.tint(Style.accent, 0.65)
                                            : Style.tint(Colors.bgElement, Style.lift(0.40))
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
        }
        Rectangle {
            anchors.centerIn: parent
            width: sd.on ? 10 : 0; height: width; radius: width / 2
            color: Style.accent
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
        }
        MouseArea { id: sdH; anchors.fill: parent; hoverEnabled: true; onClicked: sd.pick() }
    }

    // A round button — the transport keys.
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
