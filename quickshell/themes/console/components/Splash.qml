pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Console's boot curtain: a tube warming up with the machine reporting into it.
//
//   ┌──────────────────────────────────────┐
//   │            V E L U M E R O N         │   ← the wordmark, charging in the accent
//   │   ████████████░░░░░░░░░░░░░░░░  48 % │
//   │                                      │
//   │   velumeron · 7.1.8-1-cachyos        │
//   │   [ ok ]  compositor                 │
//   │   [ .. ]  shell                      │
//
// The logo is the one thing every splash has in common — a theme decides how it is presented, not
// whether it is there — so Console takes the same wordmark (`ctx.brandmark`) and puts it through
// its own screen: tinted to the phosphor, revealed left to right by the splash's own progress, with
// a block-character bar under it and the boot log beneath that.
//
// Everything is driven by `ctx.progress`, which is the shell's charge on the wordmark. There is no
// second duration to keep in sync: a slower splash simply fills more slowly and reads more lines.
Item {
    id: root
    anchors.fill: parent

    property var ctx: ({})

    readonly property var  pal:    root.ctx.palette || ({})
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent   || "#b269e0"
    readonly property color ink:    root.pal.fgBright || "#e5c7f6"
    readonly property color faint:  root.pal.fgMuted  || "#6b5480"

    readonly property int px: Math.round(Math.max(12, Math.min(18, root.height * 0.015)))
    readonly property real progress: root.ctx.progress !== undefined ? root.ctx.progress : 1

    readonly property var stages: [
        "compositor", "palette", "wallpaper", "bar", "notifications", "shell"
    ]
    // How many lines have been reached. The last one stays busy until the very end, so the curtain
    // never shows a finished list sitting there doing nothing.
    readonly property int reached: Math.min(root.stages.length,
                                            Math.floor(root.progress * (root.stages.length + 0.6)))

    Column {
        anchors.centerIn: parent
        width: Math.min(Math.round(root.width * 0.52), 720)
        spacing: Math.round(root.px * 1.1)

        // ── The wordmark, charging ──────────────────────────────────────────────────────────────
        // Two copies of the same asset, both tinted to the phosphor: a dim one that is always there
        // and a full one revealed left to right. The same construction the shell's own curtain uses,
        // which is what makes it read as the same logo rather than as another logo.
        Item {
            id: mark
            width: parent.width
            height: Math.round(width * 1000 / 1900)          // the banner's own aspect

            Image {
                id: base
                anchors.fill: parent
                source: root.ctx.brandmark || ""
                sourceSize.width: 1280
                fillMode: Image.PreserveAspectFit
                smooth: true; mipmap: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: base
                colorization: 1.0
                colorizationColor: root.accent
                opacity: 0.22
            }
            Item {
                width: parent.width * Math.max(0, Math.min(1, root.progress))
                height: parent.height
                clip: true
                MultiEffect {
                    width: mark.width; height: mark.height
                    source: base
                    colorization: 1.0
                    colorizationColor: root.accent
                }
            }
        }

        // ── The bar, in cells ───────────────────────────────────────────────────────────────────
        Row {
            spacing: Math.round(root.px * 0.9)
            TextMetrics { id: cell; font.family: root.font; font.pixelSize: root.px; text: "█" }
            readonly property int cells: Math.max(8, Math.floor(
                (mark.width - root.px * 5) / (cell.advanceWidth > 0 ? cell.advanceWidth : root.px * 0.6)))
            readonly property int filled: Math.round(Math.max(0, Math.min(1, root.progress)) * cells)
            Text {
                id: cellsT
                text: {
                    var on = "", off = ""
                    for (var i = 0; i < parent.filled; i++) on += "█"
                    for (var j = parent.filled; j < parent.cells; j++) off += "░"
                    return on + off
                }
                color: root.ink
                font.family: root.font; font.pixelSize: root.px
            }
            Text {
                anchors.verticalCenter: cellsT.verticalCenter
                text: Math.round(Math.max(0, Math.min(1, root.progress)) * 100) + " %"
                color: root.accent
                font.family: root.font; font.pixelSize: root.px
            }
        }

        Item { width: 1; height: Math.round(root.px * 0.6) }

        // ── What it is doing ────────────────────────────────────────────────────────────────────
        // Honest about being a curtain: these are the stages the shell actually goes through on the
        // way up, in the order it goes through them, not a fake bar with invented percentages.
        Column {
            spacing: Math.round(root.px * 0.4)
            Text {
                text: (root.ctx.host || "velumeron") + "  ·  " + (root.ctx.kernel || "linux")
                color: root.accent
                font.family: root.font; font.pixelSize: root.px
                font.letterSpacing: root.px * 0.16
                bottomPadding: root.px * 0.8
            }
            Repeater {
                model: root.stages
                delegate: Row {
                    id: stage
                    required property var modelData
                    required property int index
                    readonly property bool done: stage.index < root.reached
                    opacity: stage.index <= root.reached ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    spacing: Math.round(root.px * 0.9)

                    Text {
                        text: stage.done ? "[ ok ]" : "[ .. ]"
                        color: stage.done ? root.accent : root.faint
                        font.family: root.font; font.pixelSize: root.px
                    }
                    Text {
                        text: stage.modelData
                        color: stage.done ? root.ink : root.faint
                        font.family: root.font; font.pixelSize: root.px
                    }
                }
            }
        }
    }

    // The tube the whole thing sits in: the same phosphor grid the rest of Console wears, so the
    // curtain belongs to the desktop it is opening onto.
    Repeater {
        model: Math.ceil(root.height / 4)
        delegate: Rectangle {
            required property int index
            y: index * 4
            width: root.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.06)
        }
    }
}
