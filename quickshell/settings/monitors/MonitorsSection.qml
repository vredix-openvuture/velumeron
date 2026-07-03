import "../.."
import QtQuick
import Quickshell.Io

// Monitors: mode, scale, rotation, VRR/HDR and drag-to-arrange positioning — the MONITORS
// section of user_settings.lua. Detected-but-unconfigured outputs can be added with their
// best mode. Apply rewrites the section and reloads Hyprland; because a bad mode can black
// out a display, a 15-second countdown then offers Keep/Revert against the pre-apply state.
Item {
    id: root

    property var    mons:     []    // working copy, helper JSON shape (+ _live per output)
    property var    live:     ({})  // output → { x, y, modes: [], description }
    property string selected: ""
    property bool   dirty:    false
    property string status:   ""

    // Revert-countdown state (snapshot = the JSON that was in place before Apply).
    property var  snapshot:  null
    property int  countdown: 0
    property bool reverting: false

    Component.onCompleted: reload()
    onVisibleChanged: if (visible) reload()
    function reload() {
        liveProc.buf = ""
        liveProc.running = false; liveProc.running = true
        UserSettings.get("monitors", function (d) {
            if (!d) return
            root.mons = (d.monitors || []).map(function (m) { return Object.assign({}, m) })
            root.dirty = false
            if (root.selected === "" && root.mons.length > 0) root.selected = root.mons[0].output
            root._injectLive()
        })
    }

    Process {
        id: liveProc
        property string buf: ""
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: SplitParser { onRead: line => liveProc.buf += line }
        onExited: {
            var arr = []
            try { arr = JSON.parse(liveProc.buf) } catch (e) {}
            var out = {}
            for (var i = 0; i < arr.length; i++) {
                var m = arr[i]
                out[m.name] = {
                    x: m.x, y: m.y,
                    modes: (m.availableModes || []).map(function (s) { return ("" + s).replace(/Hz$/, "") }),
                    description: m.description || ""
                }
            }
            root.live = out
            root._injectLive()
        }
    }
    function _injectLive() {
        root.mons = root.mons.map(function (m) {
            var c = Object.assign({}, m)
            if (root.live[m.output]) c._live = { x: root.live[m.output].x, y: root.live[m.output].y }
            return c
        })
    }

    readonly property var unconfigured: {
        var have = {}
        for (var i = 0; i < mons.length; i++) have[mons[i].output] = true
        var out = []
        for (var name in live) if (!have[name]) out.push(name)
        return out
    }
    readonly property var selMon: {
        for (var i = 0; i < mons.length; i++) if (mons[i].output === selected) return mons[i]
        return null
    }
    readonly property var selModes: {
        var ms = (live[selected] ? live[selected].modes : []).slice()
        ms.sort(function (a, b) {
            function key(s) {
                var p = s.split("@"), wh = p[0].split("x")
                return [parseInt(wh[0]) * parseInt(wh[1]), parseFloat(p[1] || "0")]
            }
            var ka = key(a), kb = key(b)
            return kb[0] - ka[0] || kb[1] - ka[1]
        })
        return ms
    }

    function upd(patch) {
        root.mons = root.mons.map(function (m) {
            return m.output === root.selected ? Object.assign({}, m, patch) : m
        })
        root.dirty = true
    }
    function addOutput(name) {
        var best = (root.live[name] && root.live[name].modes.length > 0)
                   ? root.live[name].modes.slice().sort(function (a, b) {
                         function px(s) { var wh = s.split("@")[0].split("x"); return parseInt(wh[0]) * parseInt(wh[1]) }
                         return px(b) - px(a) || parseFloat(b.split("@")[1]) - parseFloat(a.split("@")[1])
                     })[0]
                   : "1920x1080@60"
        root.mons = root.mons.concat([{
            output: name, mode: best, transform: 0, position: "auto", scale: 1,
            bitdepth: 10, supports_hdr: false, vrr: 0, cm: "auto",
            _live: root.live[name] ? { x: root.live[name].x, y: root.live[name].y } : undefined
        }])
        root.selected = name
        root.dirty = true
    }
    function removeSelected() {
        if (root.mons.length <= 1) return
        root.mons = root.mons.filter(function (m) { return m.output !== root.selected })
        root.selected = root.mons[0].output
        root.dirty = true
    }
    function makePrimary() {
        var sel = root.selMon
        if (!sel) return
        root.mons = [sel].concat(root.mons.filter(function (m) { return m.output !== sel.output }))
        root.dirty = true
    }

    function _strip(list) {
        return (list || []).map(function (m) {
            var c = Object.assign({}, m); delete c._live; return c
        })
    }
    function apply() {
        UserSettings.get("monitors", function (d) {
            root.snapshot = d
            root.status = "Applying…"
            UserSettings.set("monitors", { monitors: root._strip(root.mons) })
        })
    }
    function keep() { root.countdown = 0; root.snapshot = null; root.status = "Applied ✓" }
    function revert() {
        if (!root.snapshot) return
        root.countdown = 0
        root.reverting = true
        root.status = "Reverting…"
        UserSettings.set("monitors", root.snapshot)
        root.snapshot = null
    }
    Connections {
        target: UserSettings
        function onSectionSaved(section, ok, errors) {
            if (section !== "monitors") return
            if (root.reverting) {
                root.reverting = false
                root.status = ok ? "Reverted" : ("" + (errors[0] || "Revert failed"))
                root.reload()
                return
            }
            if (!ok) { root.status = "" + (errors[0] || "Failed"); root.snapshot = null; return }
            root.dirty = false
            root.status = ""
            root.countdown = 15
        }
    }
    Timer {
        interval: 1000; repeat: true; running: root.countdown > 0
        onTriggered: {
            root.countdown--
            if (root.countdown === 0) root.revert()
        }
    }
    // Closing the menu mid-countdown (e.g. clicking into a terminal to verify)
    // counts as Keep: the click proves the screen is usable, and the invisible
    // auto-revert would otherwise silently undo the apply. The countdown only
    // ever reverts while the banner is actually on screen.
    readonly property bool menuOpen: UiState.openDropdown === "vuture-icon"
    onMenuOpenChanged: if (!menuOpen && root.countdown > 0) root.keep()

    // ── Revert countdown — fixed banner above the scroll area so it is visible
    // no matter where the user is scrolled (the Apply button sits at the bottom).
    Rectangle {
        id: revertBanner
        visible: root.countdown > 0
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 46
        radius: Style.rControl
        color: Style.tint(Style.accent, 0.22)
        border.width: 1; border.color: Style.accent
        z: 10
        Text {
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: "Keep these settings?  Reverting in " + root.countdown + " s…"
            color: Colors.fgBright; font.pixelSize: 12; font.bold: true; font.family: Style.font
        }
        Row {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            spacing: 8
            TextButton { label: "Keep"; primary: true; onClicked: root.keep() }
            TextButton { label: "Revert now"; onClicked: root.revert() }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: revertBanner.visible ? revertBanner.height + 8 : 0
        contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: parent.width
            topPadding: 4
            spacing: Style.cardGap

            // ── Arrangement ────────────────────────────────────────────────────
            Card {
                CardLabel { text: "ARRANGEMENT" }
                MonitorLayoutGrid {
                    width: parent.width
                    monitors: root.mons
                    selected: root.selected
                    onSelect: o => root.selected = o
                    onChanged: m => { root.mons = m; root.dirty = true }
                }
                SubLabel {
                    width: parent.width
                    text: "Drag a monitor to arrange. Monitors set to automatic position don't move."
                }
                Flow {
                    width: parent.width; spacing: 6
                    visible: root.unconfigured.length > 0
                    Repeater {
                        model: root.unconfigured
                        delegate: TextButton {
                            required property string modelData
                            label: "+ " + modelData
                            onClicked: root.addOutput(modelData)
                        }
                    }
                    SubLabel { text: "detected, not configured" }
                }
            }

            // ── Selected monitor ───────────────────────────────────────────────
            Card {
                visible: root.selMon !== null
                CardLabel { text: (root.selected + "  ·  " + (root.live[root.selected]?.description ?? "")).toUpperCase() }

                FieldLabel { text: "Resolution / refresh rate" }
                Dropdown {
                    summary: root.selMon ? root.selMon.mode : ""
                    options: root.selModes.map(function (m) {
                        return { label: m, key: m, on: root.selMon && root.selMon.mode === m }
                    })
                    onPicked: key => root.upd({ mode: key })
                }

                FieldLabel { text: "Scale" }
                Segmented {
                    equal: true
                    segments: [1, 1.25, 1.5, 1.75, 2].map(function (s) {
                        return { label: "" + s, key: "" + s }
                    })
                    current: root.selMon ? "" + root.selMon.scale : "1"
                    onPicked: key => root.upd({ scale: parseFloat(key) })
                }

                FieldLabel { text: "Rotation" }
                Segmented {
                    equal: true
                    segments: [
                        { label: "0°",   key: "0" }, { label: "90°",  key: "1" },
                        { label: "180°", key: "2" }, { label: "270°", key: "3" }
                    ]
                    current: root.selMon ? "" + (root.selMon.transform % 4) : "0"
                    onPicked: key => {
                        var mirrored = root.selMon && root.selMon.transform >= 4
                        root.upd({ transform: parseInt(key) + (mirrored ? 4 : 0) })
                    }
                }
                Toggle {
                    label: "Mirrored"
                    on: root.selMon ? root.selMon.transform >= 4 : false
                    onToggled: root.upd({ transform: (root.selMon.transform + 4) % 8 })
                }

                Toggle {
                    label: "Automatic position"
                    sub: "Let Hyprland place this monitor"
                    on: root.selMon ? root.selMon.position === "auto" : false
                    onToggled: {
                        if (root.selMon.position === "auto") {
                            var lv = root.selMon._live
                            root.upd({ position: (lv ? lv.x : 0) + "x" + (lv ? lv.y : 0) })
                        } else {
                            root.upd({ position: "auto" })
                        }
                    }
                }
                Toggle {
                    label: "Variable refresh rate (VRR)"
                    on: root.selMon ? root.selMon.vrr === 1 : false
                    onToggled: root.upd({ vrr: root.selMon.vrr === 1 ? 0 : 1 })
                }
                Toggle {
                    label: "HDR"
                    sub: "Switches color management to the HDR preset"
                    on: root.selMon ? root.selMon.supports_hdr === true : false
                    // supports_hdr alone only advertises capability (preset "wide");
                    // actual HDR output needs cm = "hdr" as well.
                    onToggled: root.upd(root.selMon.supports_hdr
                                        ? { supports_hdr: false, cm: "auto" }
                                        : { supports_hdr: true, cm: "hdr" })
                }

                Row {
                    spacing: 10
                    TextButton {
                        visible: root.mons.length > 1 && root.selMon !== root.mons[0]
                        label: "Make primary"
                        onClicked: root.makePrimary()
                    }
                    TextButton {
                        visible: root.mons.length > 1
                        label: "Remove"
                        onClicked: root.removeSelected()
                    }
                }
                SubLabel {
                    visible: root.mons.length > 1
                    width: parent.width
                    text: "Workspace rules and the lockscreen follow the primary/secondary order (mon1/mon2) — "
                        + "changing it re-targets them on apply."
                }
            }

            // ── Apply ──────────────────────────────────────────────────────────
            Card {
                Row {
                    spacing: 10
                    TextButton { label: "Apply & reload"; primary: root.dirty; onClicked: root.apply() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dirty ? "unsaved changes" : root.status
                        color: root.dirty ? Colors.fgUrgent : Colors.fgMuted
                        font.pixelSize: Style.fsSub; font.family: Style.font
                    }
                }
            }
        }
    }
}
