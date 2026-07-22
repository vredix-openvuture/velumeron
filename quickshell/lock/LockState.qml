pragma Singleton
import QtQuick

// Central, monitor-spanning state for the native lockscreen (Lock.qml / LockContent.qml).
// One buffer shared by every monitor's lock surface, so the dot count mirrors everywhere and
// the compositor-focused surface is the only one that actually receives keystrokes.
QtObject {
    id: ls

    // Engaged state — WlSessionLock.locked binds to this. Set true by the `lock` IPC handler
    // (loginctl lock-session → hypridle lock_cmd → lock.sh → qs ipc call lock lock). Cleared
    // ONLY by a successful PAM authentication in Lock.qml — never via IPC (that would let the
    // user-local IPC socket bypass the password).
    property bool locked: false
    // True during the unlock-out animation: Lock.qml sets it after a correct password so LockContent
    // shrinks the reveal back to 0, THEN drops `locked` (WlSessionLock would otherwise destroy the
    // surface instantly, giving no close animation).
    property bool unlocking: false

    property string buffer: ""              // password being typed (shared across monitors)
    property bool   authenticating: false   // PAM conversation in flight — input frozen
    property string failMsg: ""             // last auth error, shown under the field
    property int    failCount: 0

    // Raised by LockContent on Enter; Lock.qml runs the PAM conversation.
    signal submitted()
    // Raised by the `lock` IPC. Lock.qml grabs a screenshot of the live desktop FIRST (so the iris
    // reveal grows out of the real screen, not black), then engages the compositor lock.
    signal engageRequested()

    function append(c)  { if (!ls.authenticating) { ls.failMsg = ""; ls.buffer += c } }
    function backspace() { if (!ls.authenticating && ls.buffer.length > 0) ls.buffer = ls.buffer.slice(0, -1) }
    function clear()    { ls.buffer = "" }
    function submit()   { if (!ls.authenticating && ls.buffer.length > 0) ls.submitted() }
}
