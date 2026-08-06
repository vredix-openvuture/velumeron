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

    readonly property Timer _hold: Timer { interval: st.holdMs; onTriggered: st.shown = false }
    readonly property Timer _gone: Timer { interval: st.holdMs + st.fadeMs; onTriggered: st.active = false }

    // The setting is the TOTAL time on screen, tear included — that's the number you actually
    // experience, so the fade is subtracted here rather than added on top.
    // secs undefined → take the live setting (the preview button, after an edit).
    function begin(secs) {
        var s = (secs !== undefined && secs !== null) ? secs : VtlConfig.splashSeconds
        var total = Math.max(900, Math.min(15000, s * 1000))
        st.holdMs = Math.max(400, total - st.fadeMs)
        st.active = true
        st.shown  = true
        st._hold.restart()
        st._gone.restart()
    }
    // Click / preview: cut it short without waiting out the hold.
    function finish() {
        st._hold.stop()
        st.shown = false
        st._gone.restart()          // still let the fade play
    }
    function replay() { st.begin() }

    Component.onCompleted: {
        var d = {}
        try { d = JSON.parse(st._cfg.text()) || {} } catch (e) { d = {} }
        if (d.splash_enabled === false) return
        st.begin(d.splash_seconds)
    }
}
