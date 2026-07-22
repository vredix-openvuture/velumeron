pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
// Velumeron — STANDALONE lockscreen entry point (Tier-0 à-la-carte).
//
// A minimal ShellRoot that brings up ONLY the native lockscreen (WlSessionLock +
// PAM) — no bar, no OSD, no notifications, no services, no hypr.lua. Meant to run
// as its OWN quickshell instance next to a user's own bar / compositor config:
//
//   qs -p <this-file>                      # start the (invisible) lock daemon
//   qs -p <this-file> ipc call lock lock   # engage — wire into your hypridle lock_cmd
//
// Engagement is compositor-agnostic: loginctl lock-session → logind → hypridle
// lock_cmd → the `lock` IPC below → LockState.engageRequested(). Works on Hyprland,
// sway, niri — anything speaking the ext-session-lock protocol. Colours / Style /
// VtlConfig all fall back to sane defaults when VELUMERON_USER_DIR isn't a full
// velumeron install, so this stays self-contained on a foreign setup.
//
// The full shell.qml carries its OWN copy of this `lock` IpcHandler + Lock{} (see
// quickshell/shell.qml) — this file is the trimmed sibling for "just the lockscreen".
// Keep the two `lock` handlers in sync.
// ─────────────────────────────────────────────────────────────────────────────
ShellRoot {
    // LockPresets backs the "build your own" lock layout that the display reads via
    // VtlConfig; boot it so a persisted custom layout renders even with no settings UI.
    Component.onCompleted: LockPresets.boot()

    // Engage the lock. UNLOCK happens EXCLUSIVELY through PAM inside Lock.qml — never
    // via IPC, so the user-local IPC socket can't bypass the password.
    IpcHandler {
        target: "lock"
        function lock(): void { LockState.engageRequested() }
    }

    Lock { }
}
