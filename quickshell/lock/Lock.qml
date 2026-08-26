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

    // ── Suspend sequencing: "the lockscreen is fully up" flag ───────────────────────────────────
    // hypridle's inhibit_sleep=3 holds the sleep inhibitor only until the compositor reports the
    // ext-session-lock ACTIVE — that is "the surfaces exist", not "they have drawn". A suspend
    // triggered from the session menu / a keybind therefore cut into the still-assembling lock
    // (screenshot base, wallpaper decode, iris reveal). We touch this flag once the surfaces are up
    // AND the reveal has played; assets/scripts/suspend.sh waits for it before pulling the plug.
    readonly property string _readyFlag: root._shotDir + "/velumeron-lock-ready"
    Process { id: readyProc }
    function _setReady(on) {
        readyProc.command = ["bash", "-c",
            (on ? "touch " : "rm -f ") + "\"" + root._readyFlag + "\""]
        readyProc.running = false; readyProc.running = true
    }
    // Reveal duration (LockContent's openAnim is 640 ms) + a frame of margin; "none" only needs the
    // surfaces to have painted once.
    Timer {
        id: readyTimer
        interval: VtlConfig.lockReveal === "none" ? 120 : 760
        onTriggered: root._setReady(true)
    }
    // A crash while locked would leave the flag behind and make the next suspend skip its wait.
    Component.onCompleted: root._setReady(false)

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
            // The screensaver over a LOCKED screen. It cannot be a layer surface here: the
            // ext-session-lock protocol draws this surface above every layer, on purpose, so that
            // nothing can be shown over a password prompt. The lock therefore hosts the very same
            // component the desktop overlay uses, above its own content. The idle clock does not
            // care whether the screen is locked — it runs its own timer either way.
            ScreensaverView {
                anchors.fill: parent
                monName: surface.screen ? surface.screen.name : ""
                active:  UiState.screensaverOn
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
            LockState.failMsg = "Authentication unavailable"
            return
        }
        pamWatchdog.restart()
    }

    // LockContent drops EVERY keystroke while `authenticating` is set, so a conversation that never
    // reports back turns the lockscreen into a dead end with no way out but a hard reboot. The
    // onError handler below covers the failure PAM tells us about; this covers a helper that simply
    // never answers (seen after resume, 2026-07-28).
    Timer {
        id: pamWatchdog
        interval: 15000
        onTriggered: {
            if (!LockState.authenticating) return
            pam.abort()
            LockState.authenticating = false
            LockState.buffer = ""
            LockState.failMsg = "Timed out, try again"
        }
    }

    // Correct password → play the reveal-out animation (LockState.unlocking), then drop the lock. A
    // WlSessionLock unlock is instant (surface destroyed), so we hold `locked` for the animation and
    // release it in _finishUnlock. "none" reveal unlocks immediately.
    function doUnlock() {
        LockState.buffer = ""
        LockState.failMsg = ""
        LockState.failCount = 0
        // At the START of the unlock, not after it: the reveal-out runs for 440 ms and the sound
        // belongs to the moment the password was accepted, not to the animation finishing.
        SoundService.play("unlock")
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
            if (LockState.locked) {
                LockState.unlocking = false
                // On the state change, not on the one process that happens to set it today: this
                // fires whichever way the screen came to be locked, and it fires on the frame the
                // screen actually goes — the screenshot pass ahead of it takes long enough that
                // an earlier hook would sound like the lock happened before it had.
                SoundService.play("lock")
                statusProc.running = false; statusProc.running = true   // capture + pause media
                readyTimer.restart()                                    // → suspend may proceed once it fires
            } else {
                readyTimer.stop()
                root._setReady(false)
                if (root._wasPlaying) {
                    root._wasPlaying = false
                    playProc.command = ["playerctl", "play"]; playProc.running = false; playProc.running = true
                }
            }
        }
    }
    Connections {
        target: pam
        function onPamMessage() { if (pam.responseRequired) pam.respond(LockState.buffer) }
        function onCompleted(result) {
            pamWatchdog.stop()
            LockState.authenticating = false
            if (result === PamResult.Success) {
                root.doUnlock()
            } else {
                LockState.failCount += 1
                LockState.buffer = ""
                LockState.failMsg = (result === PamResult.MaxTries) ? "Too many attempts"
                                  : (result === PamResult.Error)    ? "PAM error"
                                  :                                    "Wrong password"
            }
        }
        // PamContext reports a broken conversation through `error`, and then `completed` never
        // arrives — without this the lockscreen stayed in `authenticating` forever and ignored all
        // further input. Always hand input back; the message says which stage broke.
        function onError(err) {
            pamWatchdog.stop()
            LockState.authenticating = false
            LockState.buffer = ""
            LockState.failMsg = (err === PamError.StartFailed)   ? "PAM will not start (configuration?)"
                              : (err === PamError.TryAuthFailed) ? "PAM request failed"
                              :                                    "Internal PAM error"
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
