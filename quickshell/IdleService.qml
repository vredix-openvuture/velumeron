pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The idle chain's SETTINGS and its one action — screensaver → lock → suspend. The three
// IdleMonitors themselves live in shell.qml, as direct children of the root object.
//
// That split is not taste, it is measured (2026-08-19). An `IdleMonitor` declared inside a QML
// singleton — or inside an Item that is a child of the root — reports `enabled true` with the right
// timeout and NEVER delivers an idle, while an identical monitor declared directly in the shell
// root fires within its timeout every time, in the same process, on the same seat. Quickshell arms
// its wayland objects through the object tree it owns; only the root's own children are reliably in
// it. The silent version is what made the whole chain look "not configured" while every value read
// back correctly, so: values here, protocol objects in the root.
//
// Each stage holds an ABSOLUTE timeout measured from the last input, not a delay after the previous
// stage — so the three simply have to ascend. They are independent: switching the screensaver off
// does not move the lock. A timeout of 0 switches a stage off entirely.
//
// What did NOT move: the logind bridge. `loginctl lock-session`, the Lock signal and before-sleep
// handling are session management, not idle detection, and they are not compositor-specific.
Singleton {
    id: svc

    readonly property int  saverSec:   Math.max(0, VtlConfig.idleScreensaverSec)
    readonly property int  lockSec:    Math.max(0, VtlConfig.idleLockSec)
    readonly property int  suspendSec: Math.max(0, VtlConfig.idleSuspendSec)
    readonly property bool respect:    VtlConfig.idleRespectInhibitors

    // Keep-awake stops the whole chain. It has to be checked HERE: caffeine holds a systemd idle
    // inhibitor, and Hyprland has no logind integration whatsoever, so an inhibitor that used to
    // stop hypridle's listeners is invisible to ext-idle-notify. Gating the stages is what makes
    // the switch mean something again — see CaffeineService.
    readonly property bool awake: CaffeineService.active

    // Still guarded by idle-suspend.sh: "no input" is not "no work", and that script is what knows
    // about block inhibitors, load and audio.
    readonly property Process _suspendProc: Process {}
    function runSuspend() {
        var vd = Quickshell.env("VELUMERON_DIR") || ""
        svc._suspendProc.command = ["bash", vd + "/assets/scripts/idle-suspend.sh"]
        svc._suspendProc.running = false
        svc._suspendProc.running = true
    }
}
