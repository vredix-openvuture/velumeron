pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// What a theme's own bar is given. The shipped bar is a set of modules, each owning its own source;
// a theme that draws one line of text instead needs those values as VALUES, not as widgets.
//
// This is deliberately not everything the modules can show. It is the set a status line reads out —
// who the machine is, how long it has been up, what is playing, what the battery says, which
// workspace you are on — and it grows when a theme's bar actually asks for more. Anything a module
// computes in a way that is genuinely its own (network state machines, the update checker's cache)
// stays in the module rather than being copied here.
QtObject {
    id: root

    property var now: new Date()
    property Timer _tick: Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

    readonly property string user: Quickshell.env("USER") ?? "user"

    property string _host: ""
    property FileView _hostFile: FileView {
        path: "/etc/hostname"
        onLoaded: root._host = ("" + text()).trim()
    }
    readonly property string host: root._host !== "" ? root._host : "velumeron"

    property string _kernel: ""
    property FileView _kernelFile: FileView {
        path: "/proc/sys/kernel/osrelease"
        onLoaded: root._kernel = ("" + text()).trim()
    }
    readonly property string kernel: root._kernel !== "" ? root._kernel : "linux"

    // Re-read once a minute, which is as often as a "4d 06:11" can change its mind.
    property real _uptimeSec: 0
    property FileView _uptimeFile: FileView {
        path: "/proc/uptime"
        onLoaded: root._uptimeSec = parseFloat(("" + text()).split(" ")[0]) || 0
    }
    property Timer _uptimeTick: Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: root._uptimeFile.reload()
    }
    readonly property string uptime: {
        var s = Math.max(0, Math.floor(root._uptimeSec))
        var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
        function pad(n) { return (n < 10 ? "0" : "") + n }
        return (d > 0 ? d + "d " : "") + pad(h) + ":" + pad(m)
    }

    // The playing player if there is one, else any player with a title — the same rule the lock uses.
    function _hasTitle(p) { return ((("" + (p.trackTitle ?? "")).trim()) !== "") }
    readonly property MprisPlayer player: {
        var vs = Mpris.players.values
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying && root._hasTitle(vs[i])) return vs[i]
        for (var j = 0; j < vs.length; j++) if (root._hasTitle(vs[j])) return vs[j]
        return vs.length ? vs[0] : null
    }
    readonly property string mediaTitle:  root.player ? ("" + (root.player.trackTitle ?? "")) : ""
    readonly property string mediaArtist: root.player ? ("" + (root.player.trackArtist ?? "")) : ""
    readonly property bool   mediaPlaying: root.player ? root.player.isPlaying : false

    readonly property UPowerDevice _bat: UPower.displayDevice
    // `percentage` is a 0..1 fraction, and "charging" covers the two states that are also not
    // discharging — the same rule the Battery module applies, so a theme's bar cannot disagree with
    // the shipped one about whether the machine is on mains.
    readonly property bool batPresent:  root._bat !== null && root._bat.isPresent
    readonly property int  batPercent:  root._bat ? Math.round(root._bat.percentage * 100) : 0
    readonly property bool batCharging: root._bat ? (root._bat.state === UPowerDeviceState.Charging
                                                  || root._bat.state === UPowerDeviceState.FullyCharged
                                                  || root._bat.state === UPowerDeviceState.PendingCharge)
                                                  : false

    // Workspaces for one monitor, as plain data.
    //
    // The two rules below are not simplifications and must not be "cleaned up" — both are scars.
    // The owning monitor comes from the raw IPC json rather than the linked monitor object, and the
    // active one is matched against the MONITOR's active id, also from the json: Quickshell.Hyprland
    // latches those object pointers to the wrong workspace when a second monitor gains focus, which
    // once painted an active pill on the wrong bar and none on the right one. See Workspaces.qml,
    // where the same rules are written out at length.
    function workspacesFor(monitorName) {
        var out = []
        var vs = Compositor.workspaces.values
        var monitor = Compositor.monitors.values.find(function (m) { return m.name === monitorName })
        var activeId = monitor ? (monitor.lastIpcObject?.activeWorkspace?.id
                                  ?? monitor.activeWorkspace?.id ?? -1) : -1
        for (var i = 0; i < vs.length; i++) {
            var w = vs[i]
            var owner = w.lastIpcObject?.monitor ?? w.monitor?.name ?? ""
            if (monitorName !== "" && owner !== monitorName) continue
            if (w.id <= 0 || Compositor.isShowcaseWs(w.id)) continue
            out.push({ "id": w.id,
                       // The SLOT, not the id: with a hundred ids per monitor a pill reading "103"
                       // next to a key that says 3 is a puzzle, not information.
                       "slot": Compositor.wsSlot(w.id),
                       "focused": activeId === w.id,
                       "occupied": (w.lastIpcObject?.windows ?? 0) > 0 })
        }
        out.sort(function (a, b) { return a.slot - b.slot })
        return out
    }
}
