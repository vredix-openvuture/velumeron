pragma ComponentBehavior: Bound
import "../.."
import QtQuick

// Weather flyout: the current conditions in full, then the outlook wttr.in shipped with them. Grows
// out of the bar from the Weather module (or from whichever module was pointed at it — see
// bar/Popouts.qml). Everything here is read from WeatherService; nothing is fetched a second time.
Flyout {
    id: root
    flyoutId: "weather"
    panelW:   Math.max(280, Math.round(root.sw * VtlConfig.moduleSetting("weather", "menu_width_pct", 16) / 100))
    maxH:     Math.round(root.sh * VtlConfig.moduleSetting("weather", "menu_height_pct", 45) / 100)

    // What the fetch delivered, capped to what the module asks to show.
    readonly property var outlook: {
        var n = Math.max(0, Math.min(3, VtlConfig.moduleSetting("weather", "forecast_days", 3)))
        var src = WeatherService.days
        var out = []
        for (var i = 0; i < src.length && out.length < n; i++) out.push(src[i])
        return out
    }
    function weekday(iso) {
        var d = new Date(iso)
        return isNaN(d.getTime()) ? "—" : Qt.formatDate(d, "ddd")
    }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 10

        Text {
            text: WeatherService.place !== "" ? WeatherService.place.toUpperCase() : "WEATHER"
            width: parent.width; elide: Text.ElideRight
            color: Colors.fgMuted
            font.pixelSize: 10; font.bold: true; font.letterSpacing: 0.5; font.family: Style.font
        }

        // ── Now ─────────────────────────────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            // The only thing on this panel that moves: clouds drift, rain falls, the sun turns.
            // It runs while the panel is open and stops with it — `animated` is bound to the
            // flyout being on screen, so a closed popout costs nothing.
            WeatherIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 60; height: 60
                cond:     WeatherService.ok ? WeatherService.cond : "cloudy"
                night:    !WeatherService.daytime
                animated: root.isOpen
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text:  WeatherService.ok ? WeatherService.reading : "—"
                    color: Colors.fgBright
                    font.pixelSize: 26; font.family: Style.font; font.weight: Font.Medium
                }
                Text {
                    text:  WeatherService.ok ? WeatherService.desc : "No reading yet"
                    color: Colors.fgMuted
                    font.pixelSize: 11; font.family: Style.font
                }
            }
        }

        // ── The days ahead ──────────────────────────────────────────────────────────────────────
        // Sized to be READ, not to fit as much as possible: a forecast at 10 px is a row of grey
        // smudges you lean into. The day and the two temperatures carry the same weight the "now"
        // block does, and the high is the figure your eye should land on, so it is the bright one.
        Row {
            id: outlookRow
            width: parent.width
            visible: root.outlook.length > 0
            spacing: 8
            Repeater {
                model: root.outlook
                delegate: StyledRect {
                    id: day
                    required property var modelData
                    width:  (outlookRow.width - outlookRow.spacing * (root.outlook.length - 1))
                            / Math.max(1, root.outlook.length)
                    height: 116
                    radius: Style.rTile
                    color:  Style.controlFill
                    borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                    Column {
                        anchors.centerIn: parent
                        width: day.width - 8
                        spacing: 6
                        Text { anchors.horizontalCenter: parent.horizontalCenter
                               text: root.weekday(day.modelData.date)
                               color: Colors.fgMuted
                               font.pixelSize: 13; font.family: Style.font }
                        // Still: three looping skies behind the one that matters is noise.
                        WeatherIcon { anchors.horizontalCenter: parent.horizontalCenter
                                      width: 38; height: 38
                                      cond: "" + (day.modelData.cond ?? "cloudy") }
                        // One line, but two readings: the high in the panel's own ink, the low
                        // beside it in the muted one. Shrinks to fit a narrow card rather than
                        // eliding — half a temperature is worse than a small one.
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            textFormat: Text.StyledText
                            text: "<font color=\"" + Colors.fgBright + "\">"
                                  + (day.modelData.max ?? "") + "°</font>"
                                  + "<font color=\"" + Colors.fgMuted + "\"> / "
                                  + (day.modelData.min ?? "") + "°</font>"
                            color: Colors.fgPrimary
                            font.pixelSize: 15; font.family: Style.font
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 11
                        }
                    }
                }
            }
        }

        // Footer: where the city is set. The reading is only ever as right as that field.
        StyledRect {
            width: parent.width; height: 30
            radius: Style.rTile
            color: cfgHov.containsMouse ? Style.controlHover : "transparent"
            Row {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "󰒓"; color: Colors.fgMuted; font.pixelSize: 12; font.family: Style.iconFont }
                Text { text: "Weather settings"; color: Colors.fgMuted; font.pixelSize: 11; font.family: Style.font }
            }
            MouseArea {
                id: cfgHov
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    UiState.flyout = ""
                    UiState.barCustomizeRequest    = "weather"
                    UiState.settingsRequestSection = "bar"
                    UiState.menuMon      = root.mon
                    UiState.openDropdown = "vuture-icon"
                }
            }
        }
    }
}
