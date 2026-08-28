pragma ComponentBehavior: Bound
import QtQuick

// Console's boot curtain: the machine says what it is doing instead of showing a logo and waiting.
//
//   velumeron 1.x
//   [ ok ]  compositor
//   [ ok ]  wallpaper
//   [ .. ]  shell
//
// The lines are revealed by the splash's own progress, so the list fills at exactly the pace the
// curtain takes to open — there is no second duration to keep in sync, and a slower splash simply
// reads more lines rather than sitting on a finished list.
//
// What it prints is honest about being a curtain: these are the stages the shell actually goes
// through on the way up, in the order it goes through them. It is not a fake progress bar with
// invented percentages.
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
        anchors { left: parent.left; top: parent.top
                  leftMargin: Math.round(root.width * 0.07)
                  topMargin: Math.round(root.height * 0.30) }
        spacing: Math.round(root.px * 0.4)

        Text {
            text: (root.ctx.host || "velumeron") + "  ·  " + (root.ctx.kernel || "linux")
            color: root.accent
            font.family: root.font; font.pixelSize: root.px
            font.letterSpacing: root.px * 0.16
            bottomPadding: root.px * 1.2
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
