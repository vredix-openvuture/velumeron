pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every sound the shell makes goes through here. One catalogue, one volume, one set of reasons to
// stay quiet — so "why did that not make a sound?" has exactly one file to read.
//
// The design rule the event list follows: SOUNDS MARK THRESHOLDS, NOT ACTIVITY. A session
// starting, a screen locking, a capture being taken — those happen a handful of times a day and
// each one is a change of state you would otherwise have to verify by looking. Window opens,
// menu pops and button clicks happen hundreds of times a day, and a sound on those stops being
// feedback within an hour. Everything in the second class ships OFF; it is the difference between
// a shell people keep the sound on for and one where the first thing they look for is the mute.
//
// Playback goes out as a normal, named PulseAudio stream — see the note above the process pool
// for why that matters more than the latency it costs.
Singleton {
    id: root

    // ── The catalogue ────────────────────────────────────────────────────────────
    // ONE list drives the settings page, the defaults, the cache builder and play(). Adding a
    // sound is a line here plus a play() call at the site that knows the event happened.
    //
    // `fd` is the freedesktop sound-theme name to fall back on when the active pack has no file
    // of its own. That theme is installed on practically every Linux desktop, which is what makes
    // this audible on an untouched install instead of shipping a feature that does nothing until
    // someone finds the asset directory.
    //
    // The theme has no lock/unlock sounds — nothing does; it is not in the spec. Borrowing the
    // session pair is not a placeholder but the honest mapping: locking the screen and ending the
    // session are the same threshold to a listener, the screen going away and coming back.
    readonly property var events: [
        { key: "login",        fd: "service-login",   def: true,  label: "Login",
          hint: "Once when the session comes up — not on a shell restart." },
        { key: "logout",       fd: "service-logout",  def: true,  label: "Logout",
          hint: "Played by the session itself: by the time you hear it the shell is already gone." },
        { key: "lock",         fd: "service-logout",  def: true,  label: "Screen locked" },
        { key: "unlock",       fd: "service-login",   def: true,  label: "Screen unlocked" },
        { key: "screenshot",   fd: "camera-shutter",  def: true,  label: "Screenshot",
          hint: "The shutter confirms the capture happened — the flash alone is easy to miss." },
        { key: "notification", fd: "message",         def: false, label: "Notification",
          hint: "Every ordinary notification. Off by default: this is the one that wears out." },
        { key: "notification-critical", fd: "dialog-warning", def: true, label: "Critical notification",
          hint: "Only urgency=critical — the ones you are meant to not miss." }
    ]
    function meta(key) {
        for (var i = 0; i < root.events.length; i++) if (root.events[i].key === key) return root.events[i]
        return null
    }
    readonly property var keys: root.events.map(function (e) { return e.key })

    // ── Settings ─────────────────────────────────────────────────────────────────
    readonly property bool   enabled: VtlConfig.componentEnabled("sounds")
    readonly property string pack:    VtlConfig.soundPack
    readonly property int    volume:  VtlConfig.soundVolume        // 0…100, as the user sets it
    // PulseAudio's own scale, where 65536 is 100 %. No curve of our own on top: that scale already
    // maps percentage to dB the way an ear expects, and squaring it a second time (which the
    // in-process engine did need) only made the top half of the slider do nothing.
    readonly property int    paVolume: Math.round(Math.max(0, Math.min(100, root.volume)) / 100 * 65536)
    function eventEnabled(key) {
        var m = root.meta(key)
        if (m === null) return false
        return VtlConfig.soundEventEnabled(key, m.def)
    }

    // ── Reasons to stay quiet ────────────────────────────────────────────────────
    // Deliberately few and all explicable. A sound that goes missing for a reason nobody can name
    // is worse than one that plays at the wrong moment.
    //   • do-not-disturb — it silences the popup, so silencing its sound is the same promise
    //   • a fullscreen window on the focused monitor — games and film, where a shutter is an intrusion
    // Through the Compositor seam, never Quickshell.Hyprland directly: sounds are a Tier-0
    // feature — they want nothing from a window manager — and the one place that could have
    // dragged Hyprland in is this check.
    readonly property bool muted: NotifService.dnd
                                  || Compositor.fullscreenOn(Compositor.focusedMonitor?.id ?? -1)

    // ── Rate limiting ────────────────────────────────────────────────────────────
    // A build finishing can hand the notification server thirty messages inside a second. Without
    // this that is thirty overlapping copies of the same sound, which is a machine gun, not an
    // alert. Per key so one chatty source cannot silence a different, rarer event.
    readonly property int minGapMs: 350
    property var _lastPlayed: ({})

    // ── The resolved sounds ──────────────────────────────────────────────────────
    // key → absolute path of a playable file, produced by sound-resolve.sh. Empty until the first
    // resolve finishes, which is fine: play() on an unresolved key is a no-op, and the one event
    // that matters at that moment (login) waits for `ready` anyway.
    property var  paths: ({})
    property bool ready: false

    function play(key) {
        if (!root.enabled || !root.eventEnabled(key) || root.muted) return
        root._fire(key)
    }
    // The settings page's per-row preview: the point is to hear the file, so it ignores whether
    // the event is switched on — but not the master switch or the volume, or the preview would be
    // lying about what you are about to get.
    function preview(key) {
        if (!root.enabled) return
        root._fire(key)
    }
    function _fire(key) {
        if (!root.ready || root.volume <= 0) return
        var path = root.paths[key]
        if (path === undefined) return
        var now = Date.now()
        var last = root._lastPlayed[key] ?? 0
        if (now - last < root.minGapMs) return
        root._lastPlayed[key] = now

        var p = pool.objectAt(root._slot)
        root._slot = (root._slot + 1) % Math.max(1, pool.count)
        if (!p) return
        var m = root.meta(key)
        p.running = false
        p.command = ["paplay", "--client-name=Velumeron",
                     "--stream-name=" + (m ? m.label : key),
                     "--volume=" + root.paVolume, path]
        p.running = true
    }

    // ── Why paplay and not an in-process audio engine ────────────────────────────
    // This is a deliberate reversal. QtMultimedia's SoundEffect plays with no fork at all, which
    // is why it was the first choice — but it publishes its stream as media.role="event" with no
    // application name, and PipeWire's stream-restore keys the remembered volume by ROLE. Every
    // system sound on the machine therefore shares ONE volume. On this machine that shared bucket
    // sat at 10 % (−61 dB): every sound the shell made played correctly, into silence. Nothing in
    // the shell could see that, and nothing in the shell could fix it.
    //
    // `paplay --client-name` gives the shell exactly what every other application has — its own
    // named stream, its own line in the mixer, its own remembered volume, and the default sink by
    // default. The price is a process spawn, roughly 40 ms before the first sample. For sounds
    // that mark thresholds — a session starting, a screen locking, a capture being taken — that is
    // nothing. It would matter for click feedback, and that is the point at which to revisit this.
    //
    // A POOL rather than one Process: a Process runs one command at a time, so a single one would
    // cut a playing sound short to start the next. Four is well past what the rate limiter lets
    // through, and the round-robin means the oldest slot is always the one reused.
    property int _slot: 0
    Instantiator { id: pool; model: 4; delegate: Process {} }

    // ── Cache build ──────────────────────────────────────────────────────────────
    // Resolves every event against the user directory, the pack and the freedesktop theme.
    // Re-run when the pack changes; it is a handful of file tests, so that is free.
    Process {
        id: cacheProc
        stdout: SplitParser {
            onRead: line => {
                var tab = line.indexOf("\t")
                if (tab <= 0) return
                var next = {}
                for (var k in root.paths) next[k] = root.paths[k]
                next[line.slice(0, tab)] = line.slice(tab + 1)
                root.paths = next
            }
        }
        onExited: {
            root.ready = true
            if (root._loginPending) { root._loginPending = false; root._loginCheck() }
        }
    }
    function rebuild() {
        if (!root.enabled) return
        var args = ["bash", Quickshell.env("VELUMERON_DIR") + "/assets/scripts/sound-resolve.sh", root.pack]
        for (var i = 0; i < root.events.length; i++)
            args.push(root.events[i].key + ":" + (root.events[i].fd ?? ""))
        root.paths = ({})
        root.ready = false
        cacheProc.command = args
        cacheProc.running = true
    }
    onPackChanged:    root.rebuild()
    onEnabledChanged: if (root.enabled && !root.ready) root.rebuild()

    // ── Login ────────────────────────────────────────────────────────────────────
    // Once per SESSION, not once per shell start — this shell is restarted a lot (wallust's
    // qs_reload does it on every wallpaper change, and development does it far more often than
    // that), and a startup fanfare on each of those would be the fastest possible way to make
    // someone hate the feature. The marker lives in $XDG_RUNTIME_DIR, which systemd deletes when
    // the session ends: "already played" therefore expires exactly when the session does, with
    // nothing to clean up and no timestamp arithmetic to get wrong.
    Process {
        id: loginProc
        stdout: SplitParser { onRead: line => { if (line.trim() === "play") root._fire("login") } }
    }
    function _loginCheck() {
        if (!root.enabled || !root.eventEnabled("login")) return
        loginProc.command = ["bash", "-c",
            'm="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/velumeron-login-sound"; ' +
            '[ -e "$m" ] || { : > "$m"; echo play; }']
        loginProc.running = true
    }

    // Tied to the SPLASH rather than to "the resolver happened to finish". The splash is the
    // curtain over the shell assembling itself, and the login sound belongs UNDER that curtain —
    // firing it off the cache rebuild put it wherever that rebuild landed, which on a cold session
    // is a moving target. SplashState.begin() calls this; if the paths are not resolved yet the
    // request waits for them instead of being dropped.
    //
    // The once-per-session marker still applies, so a shell restart (wallust re-runs one on every
    // wallpaper change) shows the splash silently. That is deliberate: this sound should mean "the
    // session has begun", and hearing it because a wallpaper changed would make it mean nothing.
    property bool _loginPending: false
    function loginOnSplash() {
        if (!root.enabled || !root.eventEnabled("login")) return
        if (root.ready) root._loginCheck()
        else            root._loginPending = true
    }

    // Referenced from shell.qml's startup so the singleton exists before anything asks it to make
    // a sound — a singleton is not created until something touches it, and the login sound has to
    // fire without anyone having opened a menu first.
    function boot() { root.rebuild() }
}
