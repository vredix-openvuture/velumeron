import QtQuick
import QtQuick.Effects

// Lockscreen design study — four directions, at the real 2560x1440.
//
// Standalone on purpose: no Quickshell types, no VtlConfig, so it runs under plain `qml6` and can
// be iterated in seconds instead of through a shell restart. Nothing here is meant to ship as is —
// it exists to CHOOSE a direction. The winner gets rebuilt as a layout in lock/LockContent.qml,
// against the real clock, the real PAM state and the real widget zones.
//
//   qml6 _lab/LockMock.qml -- 0     # 0 Vitrage · 1 Vault · 2 Console · 3 Curtain
//
// Everything is anchored to the edges rather than typed as a coordinate: the study has to be
// judged at 2560x1440, and a hand-placed y that happens to fit one size says nothing about the
// layout. The palette is a wallust reading of the shipped "apartment" wallpaper, so the study
// shows what the lock looks like on a first-run desktop rather than in a swatch.
Window {
    id: win
    width: 2560
    height: 1440
    visible: true
    color: "#000000"
    title: "lockmock"

    readonly property int variant: {
        var a = Qt.application.arguments
        var n = parseInt(a[a.length - 1])
        return isNaN(n) ? 0 : Math.max(0, Math.min(3, n))
    }

    // ── Palette (wallust, "velumeron-apartment") ────────────────────────────────────────────────
    readonly property color accent: "#A15ACB"
    readonly property color warm:   "#BE8456"
    readonly property color pale:   "#E5C7F6"

    readonly property string uiFont: "Fredoka"
    readonly property string monoFont: "FantasqueSansM Nerd Font"

    // ── The data a lock screen actually has ─────────────────────────────────────────────────────
    readonly property string wall: "file:///home/vredix/DEV/velumeron/assets/wallpaper/horizontal/velumeron-apartment.jpg"
    readonly property string mark: "file:///home/vredix/DEV/velumeron/assets/icons/vuture.png"
    readonly property string timeStr:   "13:12"
    readonly property string dateStr:   "Thursday, 27 August"
    readonly property string userStr:   "user"
    readonly property string hostStr:   "velumeron"
    readonly property string wxStr:     "17°C"
    readonly property string wxWord:    "Clear"
    readonly property string trackStr:  "ascend"
    readonly property string artistStr: "KORZIX"
    readonly property int    filled: 3      // PIN dots typed
    readonly property int    dotsN:  6

    Loader {
        anchors.fill: parent
        sourceComponent: win.variant === 0 ? vitrage
                       : win.variant === 1 ? vault
                       : win.variant === 2 ? consoleHud
                                           : curtain
    }

    // A row of PIN dots, shared by the studies that use round ones.
    component DotRow: Row {
        property color tone: win.pale
        property int   dia:  16
        spacing: 22
        Repeater {
            model: win.dotsN
            Rectangle {
                required property int index
                width: dia; height: dia; radius: dia / 2
                color: index < win.filled ? tone : "transparent"
                border.color: tone; border.width: 2
                opacity: index < win.filled ? 1.0 : 0.45
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════════
    // A · VITRAGE — the screen as a printed page. The picture stays sharp and whole; the time is
    // set as a headline that runs off the left edge, and everything else lives in the margins.
    // No card, no panel: the only chrome is one hairline rule and the type itself.
    // ════════════════════════════════════════════════════════════════════════════════════════════
    Component {
        id: vitrage
        Item {
            Image { anchors.fill: parent; source: win.wall; fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 2560; sourceSize.height: 1440 }
            // Ink for the type to sit on: heavy at the foot, gone by the top, so the picture is
            // never flattened by an all-over dim.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.00; color: "#33000000" }
                    GradientStop { position: 0.35; color: "#1A000000" }
                    GradientStop { position: 1.00; color: "#E6050103" }
                }
            }

            // Top margin: the state on one side, the machine on the other.
            Text { id: vState
                   anchors { left: parent.left; top: parent.top; leftMargin: 120; topMargin: 96 }
                   text: "SESSION LOCKED"; color: win.pale; opacity: 0.75
                   font.family: win.uiFont; font.pixelSize: 20; font.letterSpacing: 7 }
            Rectangle { anchors { left: vState.left; top: vState.bottom; topMargin: 18 }
                        width: 300; height: 1; color: win.pale; opacity: 0.35 }
            Text { anchors { right: parent.right; top: parent.top; rightMargin: 120; topMargin: 96 }
                   text: win.hostStr.toUpperCase(); color: win.pale; opacity: 0.55
                   font.family: win.uiFont; font.pixelSize: 20; font.letterSpacing: 7 }

            // The mark, huge and quiet, bleeding off the right edge — a watermark, not a badge.
            Image {
                source: win.mark; opacity: 0.13
                width: 760; height: 858
                anchors { right: parent.right; rightMargin: -180
                          verticalCenter: parent.verticalCenter; verticalCenterOffset: -60 }
                fillMode: Image.PreserveAspectFit; sourceSize.width: 1600
            }

            // The headline. It starts left of the frame on purpose: a number cut by the edge reads
            // as bigger than the screen, which is the whole trick of a poster.
            Text {
                id: vTime
                anchors { left: parent.left; leftMargin: -26
                          bottom: parent.bottom; bottomMargin: 292 }
                text: win.timeStr; color: win.pale
                font.family: win.uiFont; font.pixelSize: 400; font.weight: Font.Light
                font.letterSpacing: -12
            }
            Rectangle { anchors { left: parent.left; leftMargin: 128
                                  bottom: parent.bottom; bottomMargin: 262 }
                        width: 1220; height: 2; color: win.accent; opacity: 0.9 }
            Text { anchors { left: parent.left; leftMargin: 128
                             bottom: parent.bottom; bottomMargin: 208 }
                   text: win.dateStr.toUpperCase(); color: win.pale; opacity: 0.8
                   font.family: win.uiFont; font.pixelSize: 26; font.letterSpacing: 10 }

            // The field: a rule you type on, not a box. Dots sit ON the line.
            DotRow { anchors { left: parent.left; leftMargin: 128
                               bottom: parent.bottom; bottomMargin: 122 } }
            Rectangle { anchors { left: parent.left; leftMargin: 128
                                  bottom: parent.bottom; bottomMargin: 100 }
                        width: 430; height: 2; color: win.pale; opacity: 0.55 }
            Text { anchors { left: parent.left; leftMargin: 128
                             bottom: parent.bottom; bottomMargin: 62 }
                   text: "PIN or password"; color: win.pale; opacity: 0.45
                   font.family: win.uiFont; font.pixelSize: 17; font.letterSpacing: 3 }

            // Right margin: the ambient facts, right-aligned, plain text, no cards.
            Column {
                anchors { right: parent.right; rightMargin: 120
                          bottom: parent.bottom; bottomMargin: 100 }
                spacing: 16
                Text { anchors.right: parent.right
                       text: win.wxStr + "   " + win.wxWord.toUpperCase(); color: win.pale
                       opacity: 0.85; font.family: win.uiFont; font.pixelSize: 30; font.letterSpacing: 4 }
                Text { anchors.right: parent.right
                       text: win.trackStr + "  ·  " + win.artistStr; color: win.warm
                       opacity: 0.95; font.family: win.uiFont; font.pixelSize: 24; font.letterSpacing: 3 }
                Text { anchors.right: parent.right; text: win.userStr.toUpperCase(); color: win.pale
                       opacity: 0.5; font.family: win.uiFont; font.pixelSize: 20; font.letterSpacing: 8 }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════════
    // B · VAULT — the screen is shut, and the lock says so. Everything is behind heavy glass except
    // one round port that stays sharp; the PIN is the ring around it, and the time is engraved into
    // the glass below. The one gesture: the ring fills as you type.
    // ════════════════════════════════════════════════════════════════════════════════════════════
    Component {
        id: vault
        Item {
            id: vaultRoot
            readonly property real portR: 300

            Image { id: vBlurSrc; anchors.fill: parent; source: win.wall; visible: false
                    fillMode: Image.PreserveAspectCrop; sourceSize.width: 2560; sourceSize.height: 1440 }
            MultiEffect { anchors.fill: parent; source: vBlurSrc; blurEnabled: true; blur: 1.0; blurMax: 64 }
            Rectangle { anchors.fill: parent; color: "#050103"; opacity: 0.62 }

            // The port: the same picture, unblurred, cut to a circle. A hole, not a card — the
            // wallpaper is the thing behind the door.
            Item {
                id: port
                width: vaultRoot.portR * 2; height: vaultRoot.portR * 2
                anchors { horizontalCenter: parent.horizontalCenter
                          top: parent.top; topMargin: 210 }
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: portMask }
                Image {
                    // Same crop as the backdrop, offset so the port reads as a hole in the glass
                    // rather than a picture placed on it.
                    width: 2560; height: 1440
                    x: -port.x; y: -port.y
                    source: win.wall; fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 2560; sourceSize.height: 1440
                }
            }
            Item { id: portMask; visible: false; width: port.width; height: port.height
                   layer.enabled: true
                   Rectangle { anchors.fill: parent; radius: width / 2; color: "black" } }

            // The rim, and the PIN as studs set into it.
            Rectangle { anchors.centerIn: port
                        width: port.width + 26; height: port.height + 26; radius: width / 2
                        color: "transparent"; border.width: 2; border.color: win.pale; opacity: 0.45 }
            Repeater {
                model: win.dotsN
                Rectangle {
                    required property int index
                    readonly property real a: (-90 + (index - (win.dotsN - 1) / 2) * 15) * Math.PI / 180
                    width: 20; height: 20; radius: 10
                    x: port.x + port.width / 2 + Math.cos(a) * (vaultRoot.portR + 13) - width / 2
                    y: port.y + port.height / 2 + Math.sin(a) * (vaultRoot.portR + 13) - height / 2
                    color: index < win.filled ? win.accent : "#050103"
                    border.width: 2; border.color: index < win.filled ? win.accent : win.pale
                    opacity: index < win.filled ? 1.0 : 0.65
                }
            }

            // Engraved time: an outline, not a fill.
            Text {
                id: vaultTime
                anchors { horizontalCenter: parent.horizontalCenter; top: port.bottom; topMargin: 56 }
                text: win.timeStr; color: Qt.rgba(1, 1, 1, 0.10)
                style: Text.Outline; styleColor: win.pale
                font.family: win.uiFont; font.pixelSize: 210; font.weight: Font.Light
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: vaultTime.bottom; topMargin: 6 }
                text: win.dateStr.toUpperCase() + "   ·   " + win.userStr.toUpperCase()
                color: win.pale; opacity: 0.6
                font.family: win.uiFont; font.pixelSize: 22; font.letterSpacing: 9
            }

            // The four margins carry the plaque: state, weather, what is playing, the mark.
            Text { anchors { left: parent.left; top: parent.top; leftMargin: 110; topMargin: 100 }
                   text: "SESSION LOCKED"; color: win.pale; opacity: 0.5
                   font.family: win.uiFont; font.pixelSize: 19; font.letterSpacing: 7 }
            Text { anchors { right: parent.right; top: parent.top; rightMargin: 110; topMargin: 100 }
                   text: win.wxStr + "  " + win.wxWord; color: win.pale; opacity: 0.5
                   font.family: win.uiFont; font.pixelSize: 19; font.letterSpacing: 4 }
            Text { anchors { left: parent.left; bottom: parent.bottom; leftMargin: 110; bottomMargin: 110 }
                   text: win.trackStr + "  ·  " + win.artistStr; color: win.warm; opacity: 0.75
                   font.family: win.uiFont; font.pixelSize: 19; font.letterSpacing: 3 }
            Image { anchors { right: parent.right; bottom: parent.bottom; rightMargin: 110; bottomMargin: 100 }
                    source: win.mark; width: 46; height: 52; opacity: 0.6
                    fillMode: Image.PreserveAspectFit; sourceSize.width: 120 }
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════════
    // C · CONSOLE — the machine talking. Not the thin hairline HUD the current preset draws: heavy
    // brackets, a telemetry rail, and a clock that reads like an instrument. The wallpaper is a
    // ghost behind a scan grid, because this look is about the system, not the picture.
    // ════════════════════════════════════════════════════════════════════════════════════════════
    Component {
        id: consoleHud
        Item {
            Rectangle { anchors.fill: parent; color: "#050208" }
            Image { anchors.fill: parent; source: win.wall; fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 2560; sourceSize.height: 1440; opacity: 0.18 }
            Canvas {
                anchors.fill: parent; opacity: 0.14
                onPaint: {
                    var c = getContext("2d")
                    c.clearRect(0, 0, width, height)
                    c.strokeStyle = "#A15ACB"; c.lineWidth = 1
                    for (var y = 0; y < height; y += 6) {
                        c.beginPath(); c.moveTo(0, y + 0.5); c.lineTo(width, y + 0.5); c.stroke()
                    }
                }
            }

            // Heavy corner brackets — long on the outside, short on the in.
            Item { anchors { left: parent.left; top: parent.top; leftMargin: 80; topMargin: 70 }
                   Rectangle { width: 240; height: 6; color: win.accent }
                   Rectangle { width: 6; height: 120; color: win.accent } }
            Item { anchors { right: parent.right; top: parent.top; rightMargin: 80; topMargin: 70 }
                   Rectangle { anchors.right: parent.right; width: 240; height: 6; color: win.accent }
                   Rectangle { anchors.right: parent.right; width: 6; height: 120; color: win.accent } }
            Item { anchors { left: parent.left; bottom: parent.bottom; leftMargin: 80; bottomMargin: 70 }
                   Rectangle { anchors.bottom: parent.bottom; width: 240; height: 6; color: win.accent }
                   Rectangle { anchors.bottom: parent.bottom; width: 6; height: 120; color: win.accent } }
            Item { anchors { right: parent.right; bottom: parent.bottom; rightMargin: 80; bottomMargin: 70 }
                   Rectangle { anchors { right: parent.right; bottom: parent.bottom }
                               width: 240; height: 6; color: win.accent }
                   Rectangle { anchors { right: parent.right; bottom: parent.bottom }
                               width: 6; height: 120; color: win.accent } }

            // The rail: what a locked machine can honestly tell you about itself.
            Column {
                anchors { left: parent.left; top: parent.top; leftMargin: 300; topMargin: 190 }
                spacing: 12
                Repeater {
                    model: ["HOST      " + win.hostStr,
                            "SESSION   locked · pam_unix",
                            "UPTIME    4d 06:11",
                            "NET       wifi · velumeron",
                            "MEDIA     " + win.trackStr + " · " + win.artistStr,
                            "WEATHER   " + win.wxStr + " · " + win.wxWord]
                    Text {
                        required property string modelData
                        text: modelData; color: win.pale; opacity: 0.62
                        font.family: win.monoFont; font.pixelSize: 22; font.letterSpacing: 2
                    }
                }
            }

            // The instrument: hours and minutes big, seconds as a smaller accent block, so the eye
            // gets a moving part without a second hand.
            Row {
                id: hudClock
                anchors { left: parent.left; leftMargin: 296
                          verticalCenter: parent.verticalCenter; verticalCenterOffset: 40 }
                spacing: 26
                Text { text: win.timeStr; color: win.pale
                       font.family: win.monoFont; font.pixelSize: 300; font.letterSpacing: 10 }
                Column {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 74; spacing: 12
                    Text { text: "38"; color: win.accent; font.family: win.monoFont; font.pixelSize: 108 }
                    Rectangle { width: 128; height: 4; color: win.accent }
                }
            }
            Text { anchors { left: parent.left; leftMargin: 306; top: hudClock.bottom; topMargin: -10 }
                   text: win.dateStr.toUpperCase(); color: win.pale; opacity: 0.7
                   font.family: win.monoFont; font.pixelSize: 28; font.letterSpacing: 12 }

            // The prompt: a caret and the dots, on the machine's own line.
            Row {
                anchors { left: parent.left; leftMargin: 306; bottom: parent.bottom; bottomMargin: 220 }
                spacing: 18
                Text { text: win.userStr + "@" + win.hostStr; color: win.accent
                       font.family: win.monoFont; font.pixelSize: 30 }
                Text { text: "$"; color: win.pale; opacity: 0.6
                       font.family: win.monoFont; font.pixelSize: 30 }
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 16
                    Repeater {
                        model: win.dotsN
                        Rectangle {
                            required property int index
                            width: 20; height: 20
                            color: index < win.filled ? win.accent : "transparent"
                            border.width: 2; border.color: win.accent
                            opacity: index < win.filled ? 1.0 : 0.45
                        }
                    }
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 34; color: win.pale; opacity: 0.9 }
            }

            Image { anchors { right: parent.right; bottom: parent.bottom
                              rightMargin: 240; bottomMargin: 200 }
                    source: win.mark; width: 190; height: 214; opacity: 0.25
                    fillMode: Image.PreserveAspectFit; sourceSize.width: 400 }
        }
    }

    // ════════════════════════════════════════════════════════════════════════════════════════════
    // D · CURTAIN — a slab of frosted glass drawn across a third of the screen, with the picture
    // sharp beside it. Everything you need is in one left-aligned column on the glass, and the
    // album art bleeds its colour through the glass edge, so the lock is tinted by what is playing.
    // ════════════════════════════════════════════════════════════════════════════════════════════
    Component {
        id: curtain
        Item {
            id: curtainRoot
            readonly property real panelW: Math.round(width * 0.36)

            Image { anchors.fill: parent; source: win.wall; fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 2560; sourceSize.height: 1440 }

            // The glow: what is playing, thrown against the back of the glass.
            Rectangle {
                x: curtainRoot.panelW - 340; y: parent.height * 0.26
                width: 900; height: 900; radius: 450
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.63, 0.35, 0.80, 0.50) }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
            }

            // The glass: a clipped copy of the wallpaper, blurred hard, plus a tint.
            Item {
                width: curtainRoot.panelW; height: parent.height
                clip: true
                Item {
                    id: glassSrc
                    width: 2560; height: 1440; visible: false
                    Image { anchors.fill: parent; source: win.wall; fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 2560; sourceSize.height: 1440 }
                }
                MultiEffect { width: 2560; height: 1440; source: glassSrc
                              blurEnabled: true; blur: 1.0; blurMax: 64 }
                Rectangle { anchors.fill: parent; color: "#0C0510"; opacity: 0.5 }
            }
            Rectangle { x: curtainRoot.panelW; width: 2; height: parent.height
                        color: win.accent; opacity: 0.85 }

            Column {
                anchors { left: parent.left; leftMargin: 128; top: parent.top; topMargin: 280 }
                spacing: 0
                Text { text: win.timeStr; color: win.pale
                       font.family: win.uiFont; font.pixelSize: 230; font.weight: Font.Light
                       font.letterSpacing: -6 }
                Text { text: win.dateStr.toUpperCase(); color: win.pale; opacity: 0.7
                       topPadding: 4
                       font.family: win.uiFont; font.pixelSize: 24; font.letterSpacing: 9 }
            }

            Rectangle { anchors { left: parent.left; leftMargin: 128; top: parent.top; topMargin: 700 }
                        width: curtainRoot.panelW - 256; height: 1; color: win.pale; opacity: 0.25 }

            Row {
                anchors { left: parent.left; leftMargin: 128; top: parent.top; topMargin: 760 }
                spacing: 22
                Rectangle {
                    width: 76; height: 76; radius: 38; color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.20)
                    Image { anchors.centerIn: parent; source: win.mark; width: 34; height: 38
                            fillMode: Image.PreserveAspectFit; sourceSize.width: 80 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 4
                    Text { text: win.userStr; color: win.pale; font.family: win.uiFont; font.pixelSize: 34 }
                    Text { text: "Good afternoon"; color: win.pale; opacity: 0.55
                           font.family: win.uiFont; font.pixelSize: 20 }
                }
            }

            // The field: a trough on the glass, dots centred in it.
            Rectangle {
                anchors { left: parent.left; leftMargin: 128; top: parent.top; topMargin: 900 }
                width: curtainRoot.panelW - 256; height: 64; radius: 32
                color: Qt.rgba(1, 1, 1, 0.07); border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.18)
                DotRow { anchors.centerIn: parent; dia: 14; spacing: 20 }
            }

            // The foot of the glass: the ambient facts, one line each, quiet.
            Column {
                anchors { left: parent.left; leftMargin: 128; bottom: parent.bottom; bottomMargin: 120 }
                spacing: 12
                Text { text: win.wxStr + "   " + win.wxWord; color: win.pale; opacity: 0.65
                       font.family: win.uiFont; font.pixelSize: 22; font.letterSpacing: 3 }
                Text { text: win.trackStr + "  ·  " + win.artistStr; color: win.warm; opacity: 0.9
                       font.family: win.uiFont; font.pixelSize: 22; font.letterSpacing: 3 }
            }

            Text { anchors { right: parent.right; top: parent.top; rightMargin: 120; topMargin: 100 }
                   text: "SESSION LOCKED"; color: "#FFFFFF"; opacity: 0.6
                   font.family: win.uiFont; font.pixelSize: 20; font.letterSpacing: 7 }
        }
    }
}
