import ".."
import QtQuick

// The sky, as a widget. Reads WeatherService — the one reading the bar module, the popout and the
// lockscreen already share, so a widget here starts no second fetcher and asks for no second city.
// Placing one on a desk is what makes the service want a reading at all (UiState.deskKeys →
// WeatherService.wantedByDesk).
//
// Three faces, chosen from the cell rather than from a setting: a 1x1 is a glyph and a number, a
// wide short cell is a row, and anything with real height gets the hero reading with the forecast
// under it. What each face is ALLOWED to show is the instance's own business — see
// dashboard/opts/WeatherOpts.qml.
DashTile {
    id: root

    readonly property bool ok: WeatherService.ok
    // How many forecast days this instance wants (0 = none). The service always fetches three; a
    // widget that draws fewer costs nothing extra.
    readonly property int  wantDays: {
        var v = root.opts?.days
        return (typeof v === "number") ? Math.max(0, Math.min(3, v)) : 3
    }
    readonly property bool showPlace: (root.opts?.place ?? true) !== false
    readonly property bool showDesc:  (root.opts?.desc  ?? true) !== false
    // The drawn sky can move — the sun turns, clouds drift, rain falls. OFF by default here and
    // nowhere else in the shell, because this is the one surface that is on screen all day: the
    // popout animates while it is open and the bar module never does, but a desk widget would
    // repaint from login to logout for a cloud nobody is watching. Switch it on if you want it.
    readonly property bool motion: (root.opts?.motion ?? false) === true

    // Room for the forecast row only once the tile is genuinely tall — the row is four lines of its
    // own and squeezing it into a two-cell tile turns the hero reading into a caption.
    readonly property bool roomy: root.wantDays > 0 && root.innerH >= 150 && root.innerW >= 150
    readonly property var  days:  root.roomy ? WeatherService.days.slice(0, root.wantDays) : []

    function dayName(iso) {
        var p = ("" + iso).split("-")
        if (p.length < 3) return "" + iso
        return Qt.formatDate(new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2])), "ddd")
    }

    // ── Nothing fetched yet ─────────────────────────────────────────────────────
    Column {
        visible: !root.ok
        anchors.centerIn: parent
        spacing: 6
        WeatherIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width:  Math.max(18, Math.min(root.innerW, root.innerH) * 0.5)
            height: width
            cond: "cloudy"
            opacity: 0.45
            sunColor:   root.fgTint
            cloudColor: root.fgSub
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.tiny
            text: WeatherService.city === "" ? "No city set" : "No reading yet"
            color: Colors.fgMuted
            font.pixelSize: 11; font.family: root.uiFont
        }
    }

    // ── One cell: sky + temperature ─────────────────────────────────────────────
    Row {
        visible: root.ok && root.tiny
        anchors.centerIn: parent
        spacing: 6
        WeatherIcon {
            anchors.verticalCenter: parent.verticalCenter
            width:  Math.max(14, Math.min(root.innerW * 0.4, root.innerH * 0.6))
            height: width
            cond:  WeatherService.cond
            night: !WeatherService.daytime
            sunColor:   root.fgTint
            cloudColor: root.fgSub
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherService.reading
            color: root.fgMain
            font.pixelSize: Math.max(11, Math.min(root.innerH * 0.34, root.innerW * 0.22))
            font.family: root.uiFont
            font.weight: Font.Medium
        }
    }

    // ── Anything bigger: the reading, and the forecast when there is room ───────
    Column {
        visible: root.ok && !root.tiny
        anchors {
            left: parent.left; right: parent.right
            leftMargin: root.pad; rightMargin: root.pad
            verticalCenter: parent.verticalCenter
        }
        spacing: root.roomy ? Math.round(root.innerH * 0.06) : 4

        // Hero: sky, temperature, and the two captions beside them.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.max(8, Math.round(root.innerW * 0.05))

            WeatherIcon {
                anchors.verticalCenter: parent.verticalCenter
                width:  Math.max(24, Math.min(root.innerW * 0.28, root.innerH * (root.roomy ? 0.34 : 0.62)))
                height: width
                cond:     WeatherService.cond
                night:    !WeatherService.daytime
                animated: root.live && root.motion
                sunColor:   root.fgTint
                cloudColor: root.fgSub
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: WeatherService.reading
                    color: root.fgMain
                    font.family: root.uiFont
                    font.weight: Font.Medium
                    font.pixelSize: Math.max(14, Math.min(root.innerH * (root.roomy ? 0.22 : 0.36),
                                                          root.innerW * 0.22))
                }
                Text {
                    visible: root.showDesc && WeatherService.desc !== ""
                    text: WeatherService.desc
                    color: root.fgSub
                    font.family: root.uiFont
                    font.pixelSize: Math.max(9, Math.min(root.innerH * 0.09, root.innerW * 0.062))
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.innerW * 0.55)
                }
                Text {
                    visible: root.showPlace && WeatherService.place !== ""
                    text: WeatherService.place
                    color: Colors.fgMuted
                    font.family: root.uiFont
                    font.pixelSize: Math.max(8, Math.min(root.innerH * 0.075, root.innerW * 0.05))
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, root.innerW * 0.55)
                }
            }
        }

        // Forecast: one column per day, evenly spread.
        Row {
            visible: root.roomy && root.days.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.max(10, Math.round(root.innerW * 0.07))
            Repeater {
                model: root.days
                delegate: Column {
                    id: fc
                    required property var modelData
                    spacing: 2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.dayName(fc.modelData.date)
                        color: Colors.fgMuted
                        font.family: root.uiFont
                        font.pixelSize: Math.max(8, Math.min(root.innerH * 0.07, 12))
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                    }
                    WeatherIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:  Math.max(14, Math.min(root.innerH * 0.13, 26))
                        height: width
                        cond: "" + (fc.modelData.cond ?? "cloudy")
                        sunColor:   root.fgTint
                        cloudColor: root.fgSub
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: fc.modelData.max + "° / " + fc.modelData.min + "°"
                        color: root.fgSub
                        font.family: root.uiFont
                        font.pixelSize: Math.max(8, Math.min(root.innerH * 0.075, 13))
                    }
                }
            }
        }
    }
}
