import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// Native lockscreen — replaces hyprlock. Engaged via LockState.locked (set by the `lock` IPC:
// loginctl lock-session → hypridle lock_cmd → lock.sh). WlSessionLock speaks the same compositor
// ext-session-lock protocol hyprlock used, so the screen stays locked even if the shell dies.
// Instantiated ONCE in shell.qml (WlSessionLock manages one surface per monitor itself).
Item {
    id: root

    // PAM config travels with the package — no /etc/pam.d install, no root. A self-contained
    // pam_unix stack read from a confdir under assets/pam; the setuid unix_chkpwd helper lets this
    // non-root process verify /etc/shadow (same mechanism swaylock/hyprlock use).
    readonly property string _pamDir: (Quickshell.env("VELUMERON_DIR") || "") + "/assets/pam"
    // Pre-lock desktop screenshots (user-private runtime dir). LockContent shows the one for its
    // monitor as the base layer, so the iris grows out of the real screen instead of black.
    readonly property string _shotDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    WlSessionLock {
        id: sessionLock
        locked: LockState.locked

        WlSessionLockSurface {
            id: surface
            color: "black"
            LockContent {
                anchors.fill: parent
                screenName: surface.screen ? surface.screen.name : ""
            }
        }
    }

    // ── PAM authentication ──────────────────────────────────────────────────────────────────────
    PamContext {
        id: pam
        config: "velumeron"
        configDirectory: root._pamDir
    }

    function authenticate() {
        if (LockState.authenticating) return
        LockState.failMsg = ""
        LockState.authenticating = true
        if (!pam.start()) {
            LockState.authenticating = false
            LockState.failMsg = "Authentifizierung nicht möglich"
        }
    }

    // Correct password → play the reveal-out animation (LockState.unlocking), then drop the lock. A
    // WlSessionLock unlock is instant (surface destroyed), so we hold `locked` for the animation and
    // release it in _finishUnlock. "none" reveal unlocks immediately.
    function doUnlock() {
        LockState.buffer = ""
        LockState.failMsg = ""
        LockState.failCount = 0
        if (VtlConfig.lockReveal === "none") { root._finishUnlock(); return }
        LockState.unlocking = true
        unlockTimer.restart()
    }
    function _finishUnlock() {
        LockState.unlocking = false
        LockState.locked = false
        // Clear logind's lock hint (loginctl set it) + drop the desktop screenshots.
        unlockProc.command = ["bash", "-c",
            "loginctl unlock-session; rm -f \"" + root._shotDir + "\"/velumeron-lock-*.png"]
        unlockProc.running = false; unlockProc.running = true
    }
    Timer { id: unlockTimer; interval: 440; onTriggered: root._finishUnlock() }
    Process { id: unlockProc }

    // Screenshot the live desktop per monitor, THEN engage the lock — so LockContent's base is the
    // frozen desktop and the iris grows out of it instead of over black.
    Process { id: grimProc; onExited: LockState.locked = true }

    Connections {
        target: LockState
        function onSubmitted() { root.authenticate() }
        function onEngageRequested() {
            if (LockState.locked) return
            LockState.unlocking = false
            // Full resolution, parallel, UNCOMPRESSED (-l 0). The original ~2 s stall was grim's
            // default PNG level-6 *compression* done sequentially — not the decode. -l 0 skips
            // compression (fast to write AND to decode) and grim's own -s downscale added more time
            // than it saved, so we keep native resolution for a sharp frozen-desktop base.
            // Enumerate outputs from Quickshell itself instead of `hyprctl monitors -j`, so the
            // pre-lock screenshot base works on ANY wlroots compositor (Hyprland, sway, niri …) —
            // not only the hypr.lua runtime. The names match what WlSessionLockSurface.screen.name
            // reports, so the per-output PNGs line up with each lock surface exactly as before.
            var _names = Quickshell.screens.map(function(s) { return s.name })
                                           .filter(function(n) { return n })
            var _list = _names.map(function(n) { return "'" + ("" + n).replace(/'/g, "'\\''") + "'" })
                              .join(" ")
            grimProc.command = ["bash", "-c",
                "d=\"" + root._shotDir + "\"; for o in " + _list + "; do "
                + "grim -l 0 -o \"$o\" \"$d/velumeron-lock-$o.png\" 2>/dev/null & done; wait"]
            grimProc.running = false; grimProc.running = true
        }
        function onLockedChanged() {
            if (LockState.locked) { LockState.unlocking = false; statusProc.running = false; statusProc.running = true }  // capture + pause media
            else if (root._wasPlaying) {
                root._wasPlaying = false
                playProc.command = ["playerctl", "play"]; playProc.running = false; playProc.running = true
            }
        }
    }
    Connections {
        target: pam
        function onPamMessage() { if (pam.responseRequired) pam.respond(LockState.buffer) }
        function onCompleted(result) {
            LockState.authenticating = false
            if (result === PamResult.Success) {
                root.doUnlock()
            } else {
                LockState.failCount += 1
                LockState.buffer = ""
                LockState.failMsg = (result === PamResult.MaxTries) ? "Zu viele Versuche"
                                  : (result === PamResult.Error)    ? "PAM-Fehler"
                                  :                                    "Falsches Passwort"
            }
        }
    }

    // ── Media pause/resume (ports launch-hyprlock.sh's playerctl handling) ───────────────────────
    property bool _wasPlaying: false
    Process { id: pauseProc }
    Process { id: playProc }
    Process {
        id: statusProc
        command: ["playerctl", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._wasPlaying = (("" + this.text).trim() === "Playing")
                if (root._wasPlaying) { pauseProc.command = ["playerctl", "pause"]; pauseProc.running = false; pauseProc.running = true }
            }
        }
    }
}
