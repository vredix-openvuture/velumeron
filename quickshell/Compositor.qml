// ─────────────────────────────────────────────────────────────────────────────
// Compositor — the single seam between the shell and the window manager.
//
// TODAY this is a thin pass-through over Quickshell.Hyprland: ZERO behaviour change.
// Its reason to exist is twofold, and both are the SAME work:
//
//   • à-la-carte / Tier-0 — features read `Compositor.*` instead of importing
//     Quickshell.Hyprland directly, so they stop hard-depending on Hyprland and can
//     run standalone next to a foreign bar/config.
//   • multi-WM — swap what backs these members (a niri / sway backend) and every
//     consumer follows. `import Quickshell.Hyprland` currently sits in ~35 files,
//     almost all just to read `focusedMonitor`; funnel that through here and porting
//     becomes "implement one backend", not "rewrite 35 call sites".
//
// Migration is incremental: consumers move off `Hyprland.*` onto `Compositor.*` per
// Tier as their couplings are removed. Nothing on Hyprland changes today — every
// member below returns exactly what the direct Hyprland call returned.
// ─────────────────────────────────────────────────────────────────────────────
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

Item {
    id: comp
    visible: false

    // ── Monitors ──────────────────────────────────────────────────────────────
    // Focused monitor — by far the most common Hyprland usage across the shell
    // (which screen shows the launcher / OSD / a notification toast). A backend swap
    // re-points just these two.
    readonly property var    focusedMonitor:     Hyprland.focusedMonitor
    readonly property string focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    // All screens — already WM-neutral (Quickshell core). Surfaced here so consumers
    // have ONE compositor facade instead of mixing Quickshell.screens with Hyprland.
    readonly property var screens: Quickshell.screens

    // Map a per-surface `screen` to its compositor monitor object. Consumers read
    // .name / .activeWorkspace / .id off it and compare it against focusedMonitor.
    // Passed through verbatim today (a HyprlandMonitor); type the RESULT `var`, not
    // HyprlandMonitor, so a backend can return its own monitor shape.
    function monitorFor(screen) { return Hyprland.monitorFor(screen) }

    // Monitor / workspace lists the shell reads (the "main monitor" heuristic, the
    // workspace OSD). Passed through today; a backend supplies its own equivalents.
    readonly property var monitors:   Hyprland.monitors
    readonly property var workspaces: Hyprland.workspaces

    // Force the monitor/workspace graph to re-query (shell.qml's cold-start resync
    // uses this — the Hyprland event graph can latch a stale association at boot).
    function refreshMonitors()   { Hyprland.refreshMonitors() }
    function refreshWorkspaces() { Hyprland.refreshWorkspaces() }

    // ── Events ────────────────────────────────────────────────────────────────
    // Re-emit the compositor's raw event stream so features connect to Compositor
    // instead of importing Quickshell.Hyprland. CAVEAT: the payload is Hyprland's
    // verbatim today (event.name is "workspacev2" / "fullscreen" / …) — this relocates
    // the coupling off the import, but handlers still know Hyprland's event names. A
    // niri/sway backend will add NEUTRAL signals (workspaceChanged, fullscreenChanged…)
    // that handlers migrate onto; until then, moving Connections{target:Hyprland} →
    // target:Compositor is what removes the hard import dependency.
    signal rawEvent(var event)
    Connections {
        target: Hyprland
        function onRawEvent(event) { comp.rawEvent(event) }
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    // Raw dispatch escape hatch — the literal string still travels to Hyprland. Prefer
    // the semantic helpers below (a backend can translate those); this stays for the
    // long tail of one-off dispatches that don't warrant a named method.
    function dispatch(cmd) { Hyprland.dispatch(cmd) }

    // Semantic actions — the Tier-1 de-Lua seam. These emit Hyprland's hypr.lua form
    // TODAY (bit-identical to the current call sites), but once consumers migrate here
    // this is the ONLY place that form lives, so a stock-Hyprland or niri backend swaps
    // the body — not ten scattered dispatch strings.
    function focusWorkspace(id)       { Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })") }
    function focusWorkspaceDir(dir)   { Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + dir + "\" })") }
    function focusWindowAddress(addr) { Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })") }

    // Session exit / logout — plain on Hyprland; a backend maps it to its own quit verb.
    function exit() { Hyprland.dispatch("exit") }
}
