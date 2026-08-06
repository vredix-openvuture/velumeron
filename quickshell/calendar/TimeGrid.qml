pragma ComponentBehavior: Bound
import ".."
import QtQuick

// Disponera-style time grid for the calendar flyout's WEEK (7 days) and DAY (1 day) views: an hour
// gutter + one column per `day`, timed events as absolutely-positioned blocks (greedy lane-packing
// for overlaps), an all-day strip on top, day headers (week only), and a per-minute "now" line.
// Feeds off the same event dicts the flyout already builds (startMs/endMs/allDay/summary/cal/recurring).
Item {
    id: tg
    property var  days:        []          // [Date]
    property var  eventsByDay:  ({})        // dayKey → [event]
    property var  today:        new Date()
    signal addAt(var day)                   // double-click on an empty slot

    readonly property int  hourH:     44
    readonly property int  gutterW:   40
    readonly property int  startHour: 0
    readonly property int  endHour:   24
    readonly property int  hours:     endHour - startHour
    readonly property real dayW:      (width - gutterW) / Math.max(1, days.length)
    readonly property int  evPad:     4
    readonly property int  laneGap:   3
    readonly property int  sepW:      2

    function dayKey(d)    { return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate() }
    function sameDay(a, b) { return tg.dayKey(a) === tg.dayKey(b) }
    function allDayOf(d)  { return (tg.eventsByDay[tg.dayKey(d)] ?? []).filter(function (e) { return e.allDay }) }

    // Timed events of a day → positioned blocks with greedy lane-packing for overlaps.
    function layout(d) {
        var ds = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        var de = ds + 86400000
        var items = (tg.eventsByDay[tg.dayKey(d)] ?? [])
            .filter(function (e) { return !e.allDay })
            .map(function (e) { return { ev: e, start: Math.max(e.startMs, ds),
                                         end: Math.min(Math.max(e.endMs, e.startMs + 900000), de) } })
            .sort(function (a, b) { return a.start - b.start })
        var laneEnd = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i], lane = 0
            while (lane < laneEnd.length && laneEnd[lane] > it.start) lane++
            laneEnd[lane] = it.end; it.lane = lane
        }
        var lanes = Math.max(1, laneEnd.length)
        return items.map(function (it) {
            return { ev: it.ev,
                     y: ((it.start - ds) / 3600000 - tg.startHour) * tg.hourH,
                     h: Math.max(20, (it.end - it.start) / 3600000 * tg.hourH),
                     laneX: it.lane / lanes, laneW: 1 / lanes }
        })
    }

    readonly property int allDayMax: {
        var m = 0
        for (var i = 0; i < tg.days.length; i++) m = Math.max(m, tg.allDayOf(tg.days[i]).length)
        return m
    }
    readonly property int allDayH: tg.allDayMax > 0 ? (tg.allDayMax * 18 + 6) : 0
    readonly property int headerH: tg.days.length > 1 ? 22 : 0

    Timer { id: nowTick; interval: 60000; running: true; repeat: true; property int t: 0; onTriggered: t++ }
    readonly property int nowMin: { nowTick.t; var n = new Date(); return n.getHours() * 60 + n.getMinutes() }
    readonly property real nowMs: { nowTick.t; return Date.now() }   // for past-event dimming

    // ── Day headers (week only) ──────────────────────────────────────────────────
    Row {
        x: tg.gutterW; y: 0; height: tg.headerH
        visible: tg.days.length > 1
        Repeater {
            model: tg.days
            delegate: Item {
                id: dh
                required property var modelData
                width: tg.dayW; height: tg.headerH
                readonly property bool isToday: tg.sameDay(dh.modelData, tg.today)
                Text {
                    anchors.centerIn: parent
                    text:  Qt.formatDate(dh.modelData, "ddd d")
                    color: dh.isToday ? Style.accent : Colors.fgMuted
                    font.pixelSize: 12; font.bold: dh.isToday; font.family: Style.font
                }
            }
        }
    }

    // ── All-day strip ────────────────────────────────────────────────────────────
    Item {
        id: allDayStrip
        x: 0; y: tg.headerH; width: tg.width; height: tg.allDayH
        visible: tg.allDayH > 0
        Text {
            anchors { left: parent.left; leftMargin: 3; top: parent.top; topMargin: 4 }
            text: "all-day"; color: Colors.fgMuted; font.pixelSize: 8; font.family: Style.font
        }
        Row {
            x: tg.gutterW; width: tg.width - tg.gutterW; height: parent.height
            Repeater {
                model: tg.days
                delegate: Item {
                    id: adCell
                    required property var modelData
                    width: tg.dayW; height: allDayStrip.height
                    Column {
                        x: tg.evPad; y: 3; width: tg.dayW - 2 * tg.evPad; spacing: 2
                        Repeater {
                            model: tg.allDayOf(adCell.modelData)
                            delegate: Rectangle {
                                id: adEv
                                required property var modelData
                                width: parent.width; height: 16; radius: 5
                                color: Style.tint((adEv.modelData.color && adEv.modelData.color !== "")
                                       ? adEv.modelData.color : CalDavService.colorFor(adEv.modelData.cal), 0.5)
                                Text {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 4 }
                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                    text:  (adEv.modelData.isTask === true ? "󰄰  " : "") + adEv.modelData.summary
                                    color: Colors.fgBright; font.pixelSize: 10; font.family: Style.font
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Scrollable hour grid ─────────────────────────────────────────────────────
    Flickable {
        id: grid
        x: 0; y: tg.headerH + tg.allDayH
        width: tg.width; height: tg.height - y
        contentHeight: tg.hourH * tg.hours
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Auto-scroll so "now" sits ~2h from the top.
        Component.onCompleted: contentY = Math.max(0, Math.min(contentHeight - height,
                                                    (tg.nowMin / 60 - tg.startHour - 2) * tg.hourH))

        // Hour gutter
        Column {
            x: 0; width: tg.gutterW
            Repeater {
                model: tg.hours
                delegate: Item {
                    id: hg
                    required property int index
                    width: tg.gutterW; height: tg.hourH
                    Text {
                        visible: hg.index > 0
                        anchors { right: parent.right; rightMargin: 4; top: parent.top; topMargin: -7 }
                        text:  ("0" + (tg.startHour + hg.index)).slice(-2) + ":00"
                        color: Colors.fgMuted; font.pixelSize: 9; font.family: Style.font
                    }
                }
            }
        }

        // Day columns
        Row {
            x: tg.gutterW
            Repeater {
                model: tg.days
                delegate: Item {
                    id: dayCol
                    required property var modelData
                    required property int index
                    width: tg.dayW; height: tg.hourH * tg.hours

                    // Hour gridlines (every 6th stronger)
                    Repeater {
                        model: tg.hours
                        delegate: Rectangle {
                            id: gl
                            required property int index
                            x: 0; y: gl.index * tg.hourH; width: dayCol.width; height: 1
                            color: Style.tint(Colors.boNormal, (tg.startHour + gl.index) % 6 === 0 ? 0.45 : 0.20)
                        }
                    }
                    // Day separator (interior columns)
                    Rectangle {
                        visible: dayCol.index > 0
                        x: 0; y: 0; width: tg.sepW; height: parent.height
                        color: Style.tint(Colors.boNormal, 0.7)
                    }
                    // Empty-slot double-click → add
                    MouseArea {
                        anchors.fill: parent; z: 1
                        acceptedButtons: Qt.LeftButton
                        onDoubleClicked: tg.addAt(dayCol.modelData)
                    }

                    // Event blocks
                    Repeater {
                        model: tg.layout(dayCol.modelData)
                        delegate: Rectangle {
                            id: ev
                            required property var modelData
                            readonly property int    leftSep:  dayCol.index > 0 ? tg.sepW : 0
                            readonly property real   usable:   dayCol.width - leftSep - 2 * tg.evPad
                            readonly property bool   isTask:   ev.modelData.ev.isTask === true
                            readonly property color  calColor: (ev.modelData.ev.color && ev.modelData.ev.color !== "")
                                                              ? ev.modelData.ev.color : CalDavService.colorFor(ev.modelData.ev.cal)
                            // Remap stale image-cache dirs from the velorganize→velora→disponera
                            // rename so older events' pictures still resolve.
                            readonly property string _img: {
                                var p = "" + (ev.modelData.ev.image ?? "")
                                return p.replace("/velorganize/event-images/", "/disponera/event-images/")
                                        .replace("/velora/event-images/", "/disponera/event-images/")
                            }
                            readonly property bool   hasImage: ev._img !== ""
                            readonly property bool   past:     ev.modelData.ev.endMs < tg.nowMs
                            x:      leftSep + tg.evPad + ev.modelData.laneX * usable
                            y:      ev.modelData.y
                            width:  ev.modelData.laneW * usable
                                    - (ev.modelData.laneX + ev.modelData.laneW < 0.999 ? tg.laneGap : 0)
                            height: ev.modelData.h
                            radius: 6; clip: true; z: 2
                            color:   ev.calColor
                            opacity: ev.past ? 0.45 : 1.0                     // dim past events
                            border.width: 1; border.color: Qt.darker(ev.calColor, 1.3)

                            // Event image (Vikunja/Disponera-assigned) as the card background + a
                            // legibility scrim so the white title stays readable.
                            Image {
                                visible: ev.hasImage
                                anchors.fill: parent; anchors.margins: 1
                                source: ev._img.indexOf("/") === 0 ? "file://" + ev._img : ev._img
                                fillMode: Image.PreserveAspectCrop; asynchronous: true; clip: true
                            }
                            Rectangle {
                                visible: ev.hasImage
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.55) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.15) }
                                }
                            }
                            Column {
                                anchors { fill: parent; margins: 4 }
                                spacing: 1
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text:  (ev.isTask ? "󰄰  " : "") + ev.modelData.ev.summary
                                           + (ev.modelData.ev.recurring ? "  󰑖" : "")
                                    color: "#ffffff"; font.pixelSize: 11; font.bold: true; font.family: Style.font
                                }
                                Text {
                                    visible: ev.modelData.h > 40
                                    width: parent.width; elide: Text.ElideRight
                                    text:  Qt.formatTime(new Date(ev.modelData.ev.startMs), "hh:mm") + "–"
                                           + Qt.formatTime(new Date(ev.modelData.ev.endMs), "hh:mm")
                                    color: Qt.rgba(1, 1, 1, 0.9); font.pixelSize: 10; font.family: Style.font
                                }
                            }
                            MouseArea { anchors.fill: parent }   // swallow clicks so they don't add an event
                        }
                    }

                    // "Now" line (today's column only)
                    Item {
                        visible: tg.sameDay(dayCol.modelData, tg.today)
                        x: 0; width: dayCol.width; z: 3
                        y: (tg.nowMin / 60 - tg.startHour) * tg.hourH
                        Rectangle { x: 0; y: -1.5; width: parent.width; height: 3; radius: 1.5; color: Colors.fgUrgent }
                        Rectangle { x: -4; y: -4; width: 8; height: 8; radius: 4; color: Colors.fgUrgent
                                    border.width: 1.5; border.color: Colors.bgPrimary }
                    }
                }
            }
        }
    }
}
