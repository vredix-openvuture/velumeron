import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// The desktop you are configuring, small, beside the page that configures it.
//
// A settings panel wide enough to hold three columns of cards is wide enough that the page runs out
// of content before it runs out of panel — and a half-filled page reads as badly as a stretched one.
// The width goes to something worth having instead: the thing you are adjusting, drawn from the
// same settings the controls write, changing as you touch them. You stop closing the menu to see
// what a number did.
//
// It is drawn, not captured. A real screenshot would need the menu out of the way, which is the one
// thing it cannot have; and a live surface at 1:5 would be unreadable anyway. What it draws is
// SHAPE — where things sit, how big, how round, how the modules are grouped — because that is what
// the pages beside it change.
//
// `kind` says which surface is the subject; everything else is context, dimmed back so the eye
// lands on the one the page owns.
Item {
    id: prev

    property string kind: ""        // bar · taskbar · osd · notifications · launcher · lock · wallpaper · style
    property string mon:  ""        // whose settings to draw; "" = the global set

    readonly property bool isSubject: true
    // Screen proportions, whatever box we are given.
    readonly property real vw: prev.width
    readonly property real vh: Math.round(prev.width * 9 / 16)

    // Everything is drawn at 1:s of a real desktop, so a 40 px bar is 40 * s px here and the
    // proportions are the ones you will actually get.
    readonly property real s: prev.vw / 2560

    function px(v) { return Math.max(1, Math.round(v * prev.s)) }
    function dim(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── What the pages are about ────────────────────────────────────────────────────────────────
    readonly property string barMode:  VtlConfig.barModeFor(prev.mon)
    readonly property var    barEdges: VtlConfig.activeEdgesFor(prev.mon)
    readonly property int    barT:     VtlConfig.barThicknessFor(prev.mon)
    readonly property int    barR:     VtlConfig.barInnerRadiusFor(prev.mon)
    readonly property int    barGap:   VtlConfig.barFloatGapFor(prev.mon)
    readonly property bool   pills:    VtlConfig.barModuleBgFor(prev.mon) === "module"
    // The module corner as the THEME resolves it (Auto) or as you set it — the same call the real
    // strip makes, so the picture and the bar cannot disagree about round versus square.
    readonly property int    modR:     Style.moduleR(VtlConfig.barModuleBgRadiusFor(prev.mon))
    readonly property bool   tbOn:     VtlConfig.taskbarEnabledFor(prev.mon)
    readonly property string tbPos:    VtlConfig.taskbarPosition
    readonly property string osdPos:   VtlConfig.osdPosition
    readonly property bool   osdDock:  VtlConfig.osdStyle === "dock"
    readonly property string ntPos:    VtlConfig.notifyPosition
    readonly property bool   ntDock:   VtlConfig.notifyDock

    implicitHeight: prev.vh
    height: implicitHeight
    clip: true

    // ── The desk ────────────────────────────────────────────────────────────────────────────────
    Rectangle {
        id: desk
        anchors.fill: parent
        // The same corner every other surface INSIDE a card uses. It had a rounding of its own
        // (0.6 of the card's), which put a third radius on a page that is trying to have one.
        radius: Style.rControl
        color: Colors.bgPrimary
        clip: true

        Image {
            anchors.fill: parent
            visible: prev.wallpaper !== ""
            source: prev.wallpaper !== "" ? "file://" + prev.wallpaper : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 800
            asynchronous: true
            opacity: prev.kind === "wallpaper" ? 1 : 0.62
        }

        // A window, so the desktop reads as a desktop rather than as a picture with strips on it.
        Rectangle {
            x: prev.width * 0.20; y: prev.vh * 0.26
            width: prev.width * 0.44; height: prev.vh * 0.5
            radius: Math.max(2, prev.px(12))
            color: prev.dim(Colors.bgSecondary, 0.88)
            border.width: 1; border.color: prev.dim(Colors.boNormal, 0.7)
            visible: prev.kind !== "lock" && prev.kind !== "wallpaper"
            Rectangle {
                id: winBar
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: Math.max(3, prev.px(26)); radius: parent.radius
                color: prev.dim(Colors.bgElement, 0.9)
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: winBar.bottom
                          margins: prev.px(18) }
                spacing: prev.px(11)
                Repeater {
                    model: [0.72, 0.9, 0.55, 0.84, 0.4]
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width * modelData; height: prev.px(7)
                        radius: height / 2
                        color: prev.dim(Colors.fgMuted, 0.4)
                    }
                }
            }
        }

        // ── The bar, on every edge its arrangement names ────────────────────────────────────────
        Repeater {
            model: prev.kind === "lock" ? [] : prev.barEdges
            delegate: Rectangle {
                id: strip
                required property var modelData
                readonly property bool horiz: modelData === "top" || modelData === "bottom"
                readonly property bool float_: prev.barMode === "float"
                readonly property real g: strip.float_ ? prev.px(prev.barGap) : 0
                readonly property bool subject: prev.kind === "bar"

                x: modelData === "right" ? prev.width - prev.px(prev.barT) - g : g
                y: modelData === "bottom" ? prev.vh - prev.px(prev.barT) - g : g
                width:  strip.horiz ? prev.width - 2 * g : prev.px(prev.barT)
                height: strip.horiz ? prev.px(prev.barT) : prev.vh - 2 * g
                // A capsule draws no strip at all — only the module marks below stay, standing on
                // the wallpaper, which is exactly what the mode looks like in the real thing.
                readonly property bool chrome: prev.barMode !== "capsule"
                radius: strip.float_ ? Math.max(1, prev.px(prev.barR)) : 0
                color: strip.chrome ? prev.dim(Colors.bgElement, strip.subject ? 0.97 : 0.8) : "transparent"
                border.width: (strip.chrome && strip.subject) ? 1 : 0
                border.color: Style.accent

                // Module marks: a group at each end and one in the middle, in the theme's own
                // module shape. Enough to show grouping and thickness, which is what the page sets.
                Row {
                    visible: strip.horiz
                    anchors { left: parent.left; leftMargin: prev.px(24); verticalCenter: parent.verticalCenter }
                    spacing: prev.px(10)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: prev.px(index === 0 ? 54 : 26); height: prev.px(prev.barT * 0.5)
                            radius: prev.pills ? Math.max(0, prev.px(prev.modR)) : Math.max(0, prev.px(Style.rTile))
                            color: prev.dim(Colors.fgMuted, index === 0 ? 0.85 : 0.5)
                        }
                    }
                }
                Row {
                    visible: strip.horiz
                    anchors { right: parent.right; rightMargin: prev.px(24); verticalCenter: parent.verticalCenter }
                    spacing: prev.px(10)
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: prev.px(22); height: prev.px(prev.barT * 0.5)
                            radius: prev.pills ? Math.max(0, prev.px(prev.modR)) : Math.max(0, prev.px(Style.rTile))
                            color: prev.dim(Colors.fgMuted, 0.55)
                        }
                    }
                }
                Column {
                    visible: !strip.horiz
                    anchors { top: parent.top; topMargin: prev.px(24); horizontalCenter: parent.horizontalCenter }
                    spacing: prev.px(10)
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: prev.px(prev.barT * 0.5); height: prev.px(22)
                            radius: prev.pills ? Math.max(0, prev.px(prev.modR)) : Math.max(0, prev.px(Style.rTile))
                            color: prev.dim(Colors.fgMuted, 0.6)
                        }
                    }
                }
            }
        }

        // ── The taskbar ─────────────────────────────────────────────────────────────────────────
        Rectangle {
            visible: prev.tbOn && prev.kind !== "lock"
            readonly property bool subject: prev.kind === "taskbar"
            width: prev.width * 0.34; height: prev.px(46)
            radius: Math.max(1, prev.px(Style.rCard))
            x: (prev.width - width) / 2
            y: prev.tbPos === "top" ? prev.px(prev.barT) + prev.px(14)
                                    : prev.vh - height - prev.px(14)
            color: prev.dim(Colors.bgElement, parent && subject ? 0.97 : 0.72)
            border.width: subject ? 1 : 0
            border.color: Style.accent
            Row {
                anchors.centerIn: parent
                spacing: prev.px(10)
                Repeater {
                    model: 5
                    delegate: Rectangle {
                        width: prev.px(26); height: prev.px(26)
                        radius: Math.max(0, prev.px(Style.rTile))
                        color: prev.dim(Colors.fgMuted, 0.6)
                    }
                }
            }
        }

        // ── The OSD ─────────────────────────────────────────────────────────────────────────────
        Rectangle {
            visible: prev.kind === "osd"
            width: prev.width * 0.26; height: prev.px(74)
            radius: prev.osdDock ? 0 : Math.max(1, prev.px(Style.rCard))
            x: prev.osdPos.indexOf("left") >= 0 ? prev.px(30)
             : prev.osdPos.indexOf("right") >= 0 ? prev.width - width - prev.px(30)
             : (prev.width - width) / 2
            y: prev.osdPos.indexOf("top") >= 0 ? prev.px(prev.barT) + prev.px(20)
             : prev.osdPos.indexOf("bottom") >= 0 ? prev.vh - height - prev.px(20)
             : (prev.vh - height) / 2
            color: prev.dim(Colors.bgElement, 0.97)
            border.width: 1; border.color: Style.accent
            Rectangle {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: prev.px(18); rightMargin: prev.px(18) }
                height: prev.px(10); radius: height / 2
                color: prev.dim(Colors.fgMuted, 0.35)
                Rectangle {
                    width: parent.width * 0.62; height: parent.height; radius: parent.radius
                    color: Style.accent
                }
            }
        }

        // ── A notification toast ────────────────────────────────────────────────────────────────
        Rectangle {
            visible: prev.kind === "notifications"
            width: prev.width * 0.24; height: prev.px(92)
            radius: prev.ntDock ? 0 : Math.max(1, prev.px(Style.rCard))
            x: prev.ntPos.indexOf("left") >= 0 ? prev.px(26) : prev.width - width - prev.px(26)
            y: prev.ntPos.indexOf("bottom") >= 0 ? prev.vh - height - prev.px(26)
                                                 : prev.px(prev.barT) + prev.px(18)
            color: prev.dim(Colors.bgElement, 0.97)
            border.width: 1; border.color: Style.accent
            Column {
                anchors { left: parent.left; top: parent.top; margins: prev.px(16) }
                spacing: prev.px(9)
                Rectangle { width: prev.px(120); height: prev.px(9); radius: height / 2
                            color: prev.dim(Colors.fgBright, 0.8) }
                Rectangle { width: prev.px(190); height: prev.px(7); radius: height / 2
                            color: prev.dim(Colors.fgMuted, 0.6) }
                Rectangle { width: prev.px(150); height: prev.px(7); radius: height / 2
                            color: prev.dim(Colors.fgMuted, 0.45) }
            }
        }

        // ── The launcher ────────────────────────────────────────────────────────────────────────
        Rectangle {
            visible: prev.kind === "launcher"
            width: prev.width * 0.42; height: prev.vh * 0.56
            radius: Math.max(1, prev.px(Style.rCard))
            x: (prev.width - width) / 2
            y: (prev.vh - height) / 2
            color: prev.dim(Colors.bgSecondary, 0.97)
            border.width: 1; border.color: Style.accent
            Column {
                anchors { fill: parent; margins: prev.px(18) }
                spacing: prev.px(12)
                Rectangle { width: parent.width; height: prev.px(34)
                            radius: Math.max(0, prev.px(Style.rControl))
                            color: prev.dim(Colors.bgElement, 0.9) }
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: parent.width; height: prev.px(26)
                        radius: Math.max(0, prev.px(Style.rControl))
                        color: index === 0 ? Style.tint(Style.accent, 0.3)
                                           : prev.dim(Colors.bgElement, 0.55)
                    }
                }
            }
        }

        // ── The lockscreen ──────────────────────────────────────────────────────────────────────
        Rectangle {
            visible: prev.kind === "lock" || prev.kind === "screensaver"
            anchors.fill: parent
            color: prev.dim(Colors.bgPrimary, prev.kind === "lock" ? 0.72 : 0.9)
            Column {
                anchors.centerIn: parent
                spacing: prev.px(14)
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter
                            width: prev.px(260); height: prev.px(54); radius: height / 6
                            color: prev.dim(Colors.fgBright, 0.85) }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter
                            width: prev.px(150); height: prev.px(14); radius: height / 2
                            color: prev.dim(Colors.fgMuted, 0.7) }
                Rectangle { visible: prev.kind === "lock"
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: prev.px(230); height: prev.px(34)
                            radius: Math.max(0, prev.px(Style.rControl))
                            color: prev.dim(Colors.bgElement, 0.9)
                            border.width: 1; border.color: Style.accent }
            }
        }
    }

    // What the page beside this is setting, in words — the numbers the miniature cannot show at
    // 1:6 and the ones you want to read back without hunting for the control that holds them.
    readonly property var facts: {
        function on(b) { return b ? "on" : "off" }
        if (prev.kind === "bar")
            return [{ k: "mode",      v: prev.barMode },
                    { k: "edges",     v: (prev.barEdges || []).join(" · ") || "none" },
                    { k: "thickness", v: prev.barT + " px" },
                    { k: "radius",    v: prev.barR + " px" },
                    { k: "modules",   v: prev.pills ? "own pill each" : "bare" },
                    { k: "others",    v: VtlConfig.barSecondary }]
        if (prev.kind === "taskbar")
            return [{ k: "shown",  v: on(prev.tbOn) },
                    { k: "place",  v: prev.tbPos }]
        if (prev.kind === "osd")
            return [{ k: "style", v: VtlConfig.osdStyle },
                    { k: "place", v: prev.osdPos }]
        if (prev.kind === "notifications")
            return [{ k: "place",  v: prev.ntPos },
                    { k: "docked", v: on(prev.ntDock) }]
        if (prev.kind === "launcher")
            return [{ k: "opens as", v: VtlConfig.launcherFullscreen ? "fullscreen" : "window" },
                    { k: "docked",   v: on(VtlConfig.launcherDock) }]
        if (prev.kind === "lock")
            return [{ k: "layout", v: "" + ((Theme.lock || ({})).layout || "breath") },
                    { k: "locks",  v: VtlConfig.idleLockSec > 0
                                      ? (Math.round(VtlConfig.idleLockSec / 60) + " min idle")
                                      : "on demand" }]
        if (prev.kind === "style")
            return [{ k: "theme",  v: Theme.name },
                    { k: "corner", v: Style.rCard + " px" },
                    { k: "border", v: Style.cardBorderW + " px" },
                    { k: "font",   v: Style.font }]
        if (prev.kind === "wallpaper")
            return [{ k: "picture", v: (prev.wallpaper || "").split("/").pop() || "none" }]
        return []
    }

    // The picture on the desk right now, watched — a preview of a desktop without the wallpaper on
    // it is a preview of somebody else's desktop.
    property string wallpaper: ""
    FileView {
        id: wpFile
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron"))
              + "/quickshell/wallpapers.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                var j = JSON.parse(wpFile.text())
                var e = j[prev.mon] || j[UiState.menuMon] || j[Object.keys(j)[0]]
                if (!e || !e.path) { prev.wallpaper = ""; return }
                // A live wallpaper is a video an Image cannot draw — but its first frame is already
                // in the thumbnail cache the pickers fill, so the desk is never blank just because
                // the picture on it moves.
                prev.wallpaper = (e.type === "video")
                    ? ((Quickshell.env("HOME") || "") + "/.cache/velumeron/wp-thumbs/"
                       + Qt.md5("" + e.path) + ".jpg")
                    : ("" + e.path)
            } catch (err) { prev.wallpaper = "" }
        }
    }
}
