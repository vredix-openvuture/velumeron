pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The font families installed on this machine, fetched once and shared.
//
// Two surfaces offer a font picker — the bar's per-module customization and the widget editor —
// and fc-list is a process, not a lookup: run per surface it is the same subprocess twice, run per
// picker it is one per dropdown. It is also stable for the lifetime of a session, so it is asked
// for once, on demand, and kept.
//
// LAZY on purpose. Nothing about the shell's start needs the list, and paying for a subprocess at
// login for a dropdown nobody may open is exactly the kind of cost the shell keeps out of its boot.
// Every consumer calls load() when its picker becomes reachable; the second caller is a no-op.
Singleton {
    id: root

    property var families: []
    property var _buf: []

    function load() {
        if (root.families.length > 0 || fontsProc.running) return
        root._buf = []
        fontsProc.running = false
        fontsProc.running = true
    }

    Process {
        id: fontsProc
        command: ["bash", "-c", "fc-list : family | sed 's/,.*//' | sort -u"]
        stdout: SplitParser {
            onRead: line => { var t = ("" + line).trim(); if (t !== "") root._buf.push(t) }
        }
        onRunningChanged: {
            if (running) return
            root.families = root._buf.slice()
            root._buf = []
        }
    }
}
