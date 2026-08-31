pragma Singleton
import ".."          // VtlConfig lives in the root qmldir — a subdirectory doesn't see it otherwise
import QtQuick
import Quickshell
import Quickshell.Io

// Startup splash — the curtain that hides the shell assembling itself (KDE's session splash is the
// model). Nothing can cover the seconds BEFORE quickshell exists, but everything after it can be
// hidden: wallpaper decode, bar strips, tray icons and OSD surfaces all pop in within the first
// second, and that popping is what looks broken.
//
// Plays on EVERY start of the shell — login as well as a restart from the settings page. Switch it
// off in Settings → Velumeron → Shell.
QtObject {
    id: st

    property bool active: false     // surfaces exist (kept until the fade has played)
    property bool shown:  false     // opacity target — false starts the fade-out

    // The gate the rest of the shell builds behind. False means "anything mapping right now would
    // be SEEN" — either no curtain has painted yet, or one is on its way. It only ever goes
    // false→true: no splash this start, or the curtain has actually put pixels on the screen
    // (Splash.qml reports its first rendered frame). shell.qml holds the bar back until then, so
    // the bar assembles itself hidden instead of flashing in the frames before the curtain lands.
    // Monotonic on purpose: a preview replay from the settings page must not tear the bar down.
    property bool curtainUp: false

    property int holdMs: 4000       // latched when the splash begins, see begin()
    readonly property int fadeMs: 760      // the tear (640 ms) plus a little slack

    // The decision has to be right on the FIRST frame: VtlConfig reads settings.json
    // asynchronously, so asking it here would answer with the default (on) and a user who turned
    // the splash off would still catch a flash of it at every start. blockLoading makes this one
    // read synchronous — a few KB of local JSON, once, at startup.
    readonly property FileView _cfg: FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR")
               || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/velumeron"))
              + "/gui/settings.json"
        blockLoading: true
    }

    // A splash run has three moments, and they used to be one. Keeping them apart is what fixed a
    // start that showed five seconds of black and then skipped the splash entirely:
    //
    //   onScreen — the curtain has actually put pixels on a screen. The contents breathe in, and
    //              the clock starts, HERE — not when these objects were constructed, which is a
    //              second earlier and used to be where the duration began running out.
    //   curtainUp — the gate for the rest of the shell (shell.qml `bootScreens` and its waves).
    //              Held one beat longer, so the contents have played their 420 ms fade before the
    //              shell starts building behind them.
    //   ticking  — the clock itself. Separate from `active` because the surfaces exist a little
    //              before and a little after it.
    property bool onScreen: false
    property bool ticking:  false

    readonly property Timer _hold: Timer { interval: st.holdMs; onTriggered: st.shown = false }
    readonly property Timer _gone: Timer { interval: st.holdMs + st.fadeMs; onTriggered: st.active = false }

    // One beat between "the curtain is up" and "build the shell", so the contents have played their
    // 420 ms fade before the GUI thread has anything else to do.
    readonly property Timer _gate: Timer {
        interval: 420
        onTriggered: { st.curtainUp = true; st._ready.restart() }
    }
    // Zero interval, so it can only fire once the event loop is free again — which is the moment
    // the surfaces the curtain gates have finished building. THEN the clock starts. Starting it any
    // earlier put a ~380 ms freeze in the middle of the wordmark's fill (measured), because the
    // build and the animation are the same thread and the animation always loses.
    readonly property Timer _ready: Timer {
        interval: 0
        onTriggered: {
            if (!st.active || st.ticking) return
            st.ticking = true
            st._hold.restart()
            st._gone.restart()
        }
    }

    // Safety net: if no splash surface ever reports a frame — a screen that never renders, a
    // compositor that withholds the first commit — neither the shell nor the splash may wait for
    // it. Kept under the shortest possible splash (900 ms total), so the worst case is the old
    // behaviour — a bar that mapped without waiting — never a shell that stays bar-less.
    readonly property Timer _wait: Timer { interval: 800; onTriggered: st.painted() }

    // Called by every Splash surface on its first rendered frame; the first one through wins.
    function painted() {
        st._wait.stop()
        if (st.onScreen || !st.active) { st.curtainUp = true; return }
        st.onScreen = true
        st._gate.restart()
    }

    // The setting is the TOTAL time on screen, tear included — that's the number you actually
    // experience, so the fade is subtracted here rather than added on top.
    // secs undefined → take the live setting (the preview button, after an edit).
    function begin(secs) {
        var s = (secs !== undefined && secs !== null) ? secs : VtlConfig.splashSeconds
        var total = Math.max(900, Math.min(15000, s * 1000))
        st.holdMs = Math.max(400, total - st.fadeMs)
        st.active   = true
        st.shown    = true
        st.onScreen = false
        st.ticking  = false
        st._wait.restart()
        // The login sound plays UNDER the curtain, not before or after it. SoundService keeps its
        // own once-per-session rule, so a restart shows the splash without making a noise.
        SoundService.loginOnSplash()
    }
    // Click / preview: cut it short without waiting out the hold.
    function finish() {
        st._hold.stop()
        st.ticking = true       // whatever cut it short, the clock is done with this run
        st.shown = false
        st._gone.restart()          // still let the fade play
    }
    function replay() { st.begin() }

    // The curtain over a THEME SWITCH, not over a start. Wearing a theme rewrites ~80 settings and
    // reloads whatever components the new theme brings, and watching the shell take itself apart
    // and put itself back together is not something anyone wants to see. Same curtain, same tear,
    // just started from Theme.wear() instead of from the shell coming up.
    //
    // A user who turned the splash off means it: no curtain here either.
    function cover() {
        if (!VtlConfig.splashEnabled) return
        st.begin(Math.max(1.4, VtlConfig.splashSeconds))
    }

    Component.onCompleted: {
        var d = {}
        try { d = JSON.parse(st._cfg.text()) || {} } catch (e) { d = {} }
        // No curtain: nothing to hide behind, so the bar comes up immediately.
        if (d.splash_enabled === false) { st.curtainUp = true; return }
        st.begin(d.splash_seconds)
    }
}
