pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The keyboard layout, as one piece of state the bar module and its popout share.
//
// Two half-answers have to be stitched together, because the compositor gives no whole one:
//   · `input:kb_layout` is the ordered list the session was configured with ("de,us") — the codes,
//     and the ORDER `switchxkblayout <device> <index>` counts in.
//   · `hyprctl devices` reports the main keyboard's `active_keymap` — a human name ("EurKEY (US)"),
//     with no index and no code attached.
// There is no reliable mapping between the two (a keymap name is the VARIANT's description, so
// "German (dead acute)" and "de" share no substring), so the index is the shell's OWN count: it
// starts at 0 and is exact from the first switch onwards, while the human name is always true
// because it comes straight from the compositor. The module can show either; the popout highlights
// the index and prints the name, so a wrong index is visible rather than silent.
Singleton {
    id: root

    property var    layouts:  []      // ordered codes from input:kb_layout
    property var    variants: []      // ordered codes from input:kb_variant (may be shorter)
    property string keymap:   ""      // the compositor's own name for what is active now
    property string device:   ""      // main keyboard, the one switchxkblayout is aimed at
    property int    index:    0       // our count into `layouts` (see the header)

    readonly property bool   multi:   root.layouts.length > 1
    readonly property string code:    (root.index >= 0 && root.index < root.layouts.length)
                                      ? root.layouts[root.index] : (root.layouts[0] ?? "")
    readonly property string variant: (root.index >= 0 && root.index < root.variants.length)
                                      ? root.variants[root.index] : ""
    // "de (nodeadkeys)" — what one entry in the picker is called.
    function labelAt(i) {
        var c = root.layouts[i] ?? ""
        var v = root.variants[i] ?? ""
        return v === "" ? c : (c + " (" + v + ")")
    }

    function _split(s) {
        var out = ("" + s).split(",")
        var clean = []
        for (var i = 0; i < out.length; i++) { var t = out[i].trim(); if (t !== "") clean.push(t) }
        return clean
    }

    // Both options in one run, each line TAGGED — a positional read (first line = layout, second =
    // variant) desyncs for good the moment one of the two calls fails and prints nothing.
    readonly property Process _opts: Process {
        command: ["bash", "-c",
            "echo L:$(hyprctl getoption input:kb_layout -j | tr -d '\\n'); " +
            "echo V:$(hyprctl getoption input:kb_variant -j | tr -d '\\n')"]
        stdout: SplitParser {
            onRead: line => {
                var s = "" + line
                if (s.length < 2) return
                var tag = s.charAt(0)
                try {
                    var v = JSON.parse(s.slice(2)).str ?? ""
                    if (tag === "L") root.layouts  = root._split(v)
                    if (tag === "V") root.variants = root._split(v)
                } catch (e) { /* keep what we had */ }
            }
        }
    }
    readonly property Process _dev: Process {
        command: ["bash", "-c", "hyprctl devices -j | tr -d '\\n'"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    var ks = JSON.parse(data).keyboards ?? []
                    var main = null
                    for (var i = 0; i < ks.length; i++) if (ks[i].main) { main = ks[i]; break }
                    if (!main && ks.length > 0) main = ks[0]
                    if (!main) return
                    root.device = "" + (main.name ?? "")
                    root.keymap = "" + (main.active_keymap ?? "")
                } catch (e) { /* keep */ }
            }
        }
    }

    function refresh() {
        root._opts.running = false; root._opts.running = true
        root._dev.running  = false; root._dev.running  = true
    }

    readonly property Process _switch: Process {
        onRunningChanged: if (!running) { root._dev.running = false; root._dev.running = true }
    }
    function setIndex(i) {
        if (root.device === "" || i < 0 || i >= root.layouts.length) return
        root.index = i
        root._switch.command = ["hyprctl", "switchxkblayout", root.device, "" + i]
        root._switch.running = false
        root._switch.running = true
    }
    function next() { root.setIndex(root.layouts.length ? (root.index + 1) % root.layouts.length : 0) }

    // The compositor announces every switch, including the ones made outside the shell (a keybind,
    // another tool) — the name is re-read from it so the bar never shows a layout that is not on.
    readonly property Connections _ev: Connections {
        target: Compositor
        function onRawEvent(event) {
            var n = "" + (event.name ?? "")
            if (n === "activelayout") { root._dev.running = false; root._dev.running = true }
            // A config reload can change the list itself.
            else if (n === "configreloaded") root.refresh()
        }
    }
    Component.onCompleted: root.refresh()
}
