pragma ComponentBehavior: Bound
import QtQuick

// Console's lockscreen, supplied by the THEME rather than by the shell.
//
// This file lives outside the shell tree on purpose. It cannot see Style, Colors or VtlConfig —
// that is measured, not assumed — so everything it draws with arrives in `ctx`, the lock contract
// (see Style.themeContext() and LockContent's lockContext). It owns the arrangement and nothing
// else: keystrokes, PAM, focus and the iris stay in the shell, because a lockscreen that hands its
// key handling to a dropped-in folder is a lockscreen you cannot get out of.
//
// The idea is one sentence: the machine talking. Heavy corner brackets instead of a hairline frame,
// a rail that prints what a locked machine can honestly say about itself, the time read as an
// instrument, and a prompt whose dots are what you typed. Every line in the rail comes from a file
// that already exists; nothing here is decoration pretending to be data.
Item {
    id: root
    anchors.fill: parent

    // The contract. `ctx` is the state and changes about once a second; the two animation clocks
    // arrive separately because they run at frame rate and folding them into the object would
    // rebuild the whole thing sixty times a second.
    property var  ctx: ({})
    property real entrance: 1      // 0..1 arrival
    property real pulse:    1      // the accent breath

    readonly property var  pal:   root.ctx.palette || ({})
    readonly property real w:     root.ctx.w || root.width
    readonly property real h:     root.ctx.h || root.height
    readonly property string font: root.ctx.font || "monospace"
    readonly property color accent: root.pal.accent   || "#c9a0ff"
    readonly property color ink:    root.pal.fgBright || "#ffffff"
    readonly property color faint:  root.pal.fgMuted  || "#888888"

    // Console's own knobs, written by settings/ConsoleSection.qml into the theme's namespace. The
    // component and the page read the SAME object, so a click on the page moves the lock.
    readonly property var cfg: root.ctx.settings || ({})
    function opt(k, def) { var v = root.cfg[k]; return (v === undefined || v === null) ? def : v }
    readonly property bool showRail:     root.opt("lock_rail", true)
    readonly property bool showSeconds:  root.opt("lock_seconds", true)
    readonly property bool showBrackets: root.opt("lock_brackets", true)
    readonly property real backdrop: {
        var b = root.opt("lock_backdrop", "half")
        return b === "clear" ? 0.0 : b === "solid" ? 0.80 : 0.55
    }

    // The arrival clock, sliced the way the built-in layouts slice it.
    function stagger(i) { return Math.max(0, Math.min(1, (root.entrance - i * 0.13) / 0.6)) }
    function rise(i)    { return (1 - root.stagger(i)) * Math.max(10, root.h * 0.012) }

    readonly property real m:      Math.round(Math.max(28, Math.min(root.w, root.h) * 0.045))
    readonly property int  bodyPx: Math.round(Math.max(12, Math.min(16, root.h * 0.0105)))
    readonly property int  headPx: Math.round(Math.max(10, Math.min(13, root.h * 0.0085)))

    // Console lays its OWN black over the backdrop. A terminal that followed a dim slider would
    // stop reading as one, so the theme sets lock.dim to 0 and takes the contrast itself.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.backdrop)
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    // ── Corner brackets. Two strokes each, drawn as plain rectangles rather than as a Shape: an
    // axis-aligned run at these coordinates is exactly the case where the curve renderer saturates
    // both pixel rows, and a rectangle has no such problem. ─────────────────────────────────────
    Repeater {
        model: root.showBrackets ? [{ x: 0, y: 0, sx:  1, sy:  1 },
                { x: 1, y: 0, sx: -1, sy:  1 },
                { x: 0, y: 1, sx:  1, sy: -1 },
                { x: 1, y: 1, sx: -1, sy: -1 }] : []
        delegate: Item {
            id: brk
            required property var modelData
            readonly property real len: Math.round(Math.min(root.w, root.h) * 0.085)
            readonly property real th:  2
            x: brk.modelData.x === 0 ? root.m : root.w - root.m
            y: brk.modelData.y === 0 ? root.m : root.h - root.m
            opacity: root.stagger(0)
            Rectangle {
                width: brk.len; height: brk.th; color: root.accent
                x: brk.modelData.sx > 0 ? 0 : -brk.len
                y: brk.modelData.sy > 0 ? 0 : -brk.th
            }
            Rectangle {
                width: brk.th; height: brk.len; color: root.accent
                x: brk.modelData.sx > 0 ? 0 : -brk.th
                y: brk.modelData.sy > 0 ? 0 : -brk.len
            }
        }
    }

    Text {
        anchors { right: parent.right; rightMargin: root.m + Math.round(root.w * 0.012)
                  top: parent.top;     topMargin: root.m + Math.round(root.h * 0.045) }
        text: root.ctx.failMsg && root.ctx.failMsg !== "" ? "AUTH FAILED"
            : root.ctx.authenticating ? "CHECKING" : "SESSION LOCKED"
        color: root.ctx.failMsg && root.ctx.failMsg !== "" ? (root.pal.fgUrgent || "#ff6b6b") : root.accent
        font.family: root.font; font.pixelSize: root.headPx
        font.letterSpacing: root.headPx * 0.22
        opacity: root.stagger(1)
    }

    // ── The rail. What a locked machine can honestly say about itself. ──────────────────────────
    Column {
        id: rail
        visible: root.showRail
        x: root.m + Math.round(root.w * 0.035)
        y: root.m + Math.round(root.h * 0.075)
        spacing: Math.round(root.bodyPx * 0.42)
        opacity: root.stagger(1)
        transform: Translate { y: root.rise(1) }

        Repeater {
            model: root.railLines
            delegate: Row {
                id: railRow
                required property var modelData
                spacing: Math.round(root.bodyPx * 0.9)
                Text {
                    width: Math.round(root.bodyPx * 5.4)
                    text: railRow.modelData.k
                    color: root.faint
                    font.family: root.font; font.pixelSize: root.bodyPx
                    font.letterSpacing: root.bodyPx * 0.12
                }
                Text {
                    text: railRow.modelData.v
                    color: root.ink
                    font.family: root.font; font.pixelSize: root.bodyPx
                }
            }
        }
    }
    // Built here rather than in the shell: which lines a theme prints is the theme's business.
    readonly property var railLines: {
        var host = root.ctx.host || {}
        var out = [{ k: "HOST",    v: host.name   || "" },
                   { k: "KERNEL",  v: host.kernel || "" },
                   { k: "UPTIME",  v: host.uptime || "" },
                   { k: "SESSION", v: "locked · pam_unix" }]
        var ws = root.ctx.widgets || []
        for (var i = 0; i < ws.length; i++) {
            var t = ("" + (ws[i].text || "")).trim()
            if (t !== "") out.push({ k: ("" + ws[i].name).toUpperCase(), v: t })
        }
        return out
    }

    // ── The time, read as an instrument: hours and minutes large, the seconds their own accent
    // block sitting on the baseline with a rule under it. ───────────────────────────────────────
    Item {
        id: clockBlock
        x: root.m + Math.round(root.w * 0.035)
        y: Math.round(root.h * 0.36)
        width: clockRow.width; height: clockRow.height + dateT.height + Math.round(root.h * 0.02)
        opacity: root.stagger(2)
        transform: Translate { y: root.rise(2) }

        readonly property int px: Math.round(Math.max(64, Math.min(root.h * 0.20, root.w * 0.22)))

        Row {
            id: clockRow
            spacing: Math.round(clockBlock.px * 0.10)
            Text {
                text: root.ctx.clockText || ""
                color: root.ink
                font.family: root.font; font.pixelSize: clockBlock.px
                font.letterSpacing: clockBlock.px * 0.04
            }
            Column {
                anchors.bottom: parent.bottom
                visible: root.showSeconds
                spacing: Math.round(clockBlock.px * 0.05)
                Text {
                    text: Qt.formatTime(root.tick, "ss")
                    color: root.accent
                    font.family: root.font; font.pixelSize: Math.round(clockBlock.px * 0.30)
                }
                Rectangle {
                    width: Math.round(clockBlock.px * 0.42); height: 2
                    color: root.accent
                    opacity: root.pulse
                }
            }
        }
        Text {
            id: dateT
            anchors { left: parent.left; top: clockRow.bottom; topMargin: Math.round(root.h * 0.018) }
            text: ("" + (root.ctx.dateText || "")).toUpperCase()
            color: root.faint
            font.family: root.font; font.pixelSize: root.bodyPx
            font.letterSpacing: root.bodyPx * 0.28
        }
    }
    // The seconds are the one thing the contract does not carry, because no built-in layout wanted
    // them. Ticking locally is cheaper than widening the contract for one component.
    property var tick: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.tick = new Date() }

    // ── The prompt. The dots ARE the field; there is no box and no placeholder. ─────────────────
    Row {
        id: prompt
        x: root.m + Math.round(root.w * 0.035) + root.ctx.shakeX
        y: root.h - root.m - Math.round(root.h * 0.075)
        spacing: Math.round(root.bodyPx * 0.7)
        opacity: root.stagger(3)
        transform: Translate { y: root.rise(3) }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.ctx.user ? root.ctx.user.name : "user") + "@"
                  + (root.ctx.host ? root.ctx.host.name : "velumeron") + " $"
            color: root.faint
            font.family: root.font; font.pixelSize: root.bodyPx
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(root.bodyPx * 0.55)
            Repeater {
                model: root.ctx.dotCount || 0
                delegate: Rectangle {
                    width: Math.round(root.bodyPx * 0.62); height: width; radius: width / 2
                    color: root.ctx.failMsg && root.ctx.failMsg !== "" ? (root.pal.fgUrgent || "#ff6b6b") : root.ink
                }
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(root.bodyPx * 0.55); height: Math.round(root.bodyPx * 1.15)
            color: root.ink
            opacity: caret.on ? 1 : 0
            Timer { id: caret; property bool on: true
                    interval: 560; running: true; repeat: true; onTriggered: caret.on = !caret.on }
        }
    }
}
