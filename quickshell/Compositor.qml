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

    // ── Workspace blocks: one hundred ids per monitor ───────────────────────────
    // Monitor n owns (n-1)*100 + 1 … +99, so the main screen has 1-99, the second 101-199. The
    // scheme lives in hypr.lua/modules/workspaces.lua (it is the compositor that enforces it via
    // the generated block rules); these two are how every surface here reads a workspace id:
    // the SLOT is what the user presses and what a label shows, the BASE says which monitor it
    // belongs to. Ids below the block size have slot == id, so a single-monitor setup is
    // unchanged and a config from before the scheme still reads correctly.
    readonly property int wsBlock: 100
    // Screens left to right, then top to bottom — the order you would point at them across the desk.
    // Every settings page that lists monitors uses this instead of `Quickshell.screens`, whose order
    // is whatever the compositor enumerated: on a three-screen desk that put DP-3 before DP-2 and
    // read as a bug in the page rather than as an accident of hotplug order.
    readonly property var screensOrdered: {
        var out = []
        for (var i = 0; i < Quickshell.screens.length; i++) out.push(Quickshell.screens[i])
        out.sort(function (a, b) { return (a.x - b.x) || (a.y - b.y) })
        return out
    }

    function wsSlot(id) { return id > 0 ? (id % comp.wsBlock === 0 ? comp.wsBlock : id % comp.wsBlock) : id }
    function wsBaseOf(id) { return id > 0 ? id - comp.wsSlot(id) : 0 }

    // ── Reserved: the wallpaper showcase ────────────────────────────────────────
    // One workspace per monitor, 1001 upward, that exists solely so a wallpaper change can be
    // watched without windows over it (see assets/scripts/wallpaper-set.sh). They are machinery,
    // not places you work, so nothing that lists workspaces may ever show one — the indicator, the
    // OSD banner and the OSD's dot row all ask this rather than each inventing a cutoff.
    readonly property int wsShowcaseBase: 1000
    function isShowcaseWs(id) { return id > comp.wsShowcaseBase }
    // 1-based monitor index → its own showcase id, so two monitors changing at once cannot land on
    // the same one.
    function showcaseWsFor(monName) {
        var ms = comp.monitors.values
        for (var i = 0; i < ms.length; i++)
            if (ms[i].name === monName) return comp.wsShowcaseBase + i + 1
        return comp.wsShowcaseBase + 1
    }

    // Is a REAL fullscreen window covering this monitor right now (i.e. is the bar hidden)?
    // Every bar-docked surface asks this before deciding whether to dock onto the bar's inner
    // face or grow from the bare screen edge. Do NOT go back to the raw "fullscreen>>0/1" event
    // for it — see Hyprwindows.fullscreenOn(). Usable in a binding: it reads Hyprwindows.fsMons.
    function fullscreenOn(monId) { return Hyprwindows.fullscreenOn(monId) }

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
    // Close one window by address — the launcher's workspace overview offers it per miniature
    // (middle-click / the ×), the same way the GNOME overview does.
    function closeWindowAddress(addr) { Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + addr + "\" })") }

    // Session exit / logout — plain on Hyprland; a backend maps it to its own quit verb.
    function exit() { Hyprland.dispatch("exit") }
}
