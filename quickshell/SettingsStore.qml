pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The ONE writer for gui/settings.json. Every settings page (and any surface that persists a
// preference) calls SettingsStore.set(key, value) — this replaces the identical python
// one-liner that used to be copy-pasted into every page.
//
// set() applies the value optimistically to the in-memory config (VtlConfig.applyLocal) so
// bindings react instantly, then queues the file write.
//
// ── Why this coalesces, which is the whole reason the UI felt slow ──────────────────────────────
// It used to push EVERY call onto a FIFO and spawn one python3 per entry, serialised on the
// previous process exiting. Dragging a slider emits `moved` on every mouse move, so one drag =
// dozens of interpreter start-ups, dozens of read-modify-write cycles on the same file, and dozens
// of change notifications back into VtlConfig — each one re-parsing the whole document and
// re-evaluating every binding in the shell. The value on screen was right (applyLocal is
// immediate), but the shell spent the next second or two chewing through a backlog of writes for
// values that were already obsolete, and everything else stuttered while it did. Toggles felt
// sticky for the same reason: a toggle pressed during that backlog waited behind it.
//
// So: pending changes accumulate in a map (last value per key wins — nobody wants the intermediate
// positions of a slider drag), a short debounce lets a burst settle, and one interpreter writes
// the whole batch. A drag that used to cost 40 processes costs one.
Singleton {
    id: root

    // Reads a JSON object of {key: value} from argv[1] and merges it into the file. Same atomic
    // tmp+rename as before, now for a batch instead of a single key.
    readonly property string _py:
        "import json,os,sys;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "p=os.path.join(pu,'gui','settings.json');" +
        "os.makedirs(os.path.dirname(p),exist_ok=True);" +
        "d=json.load(open(p)) if os.path.exists(p) else {};" +
        "d.update(json.loads(sys.argv[1]));" +
        "t=p+'.tmp';open(t,'w').write(json.dumps(d,indent=2));os.replace(t,p)"

    // Changes waiting to be written. A map, NOT a list: re-setting a key before the flush replaces
    // the value instead of queueing a second write of the same key.
    property var _pending: ({})
    property bool _hasPending: false

    function set(key, value) {
        VtlConfig.applyLocal(key, value)
        root._pending[key] = value
        root._hasPending = true
        flushTimer.restart()
    }

    // Flip one entry of the component_enabled map (the à-la-carte on/off shown atop each
    // feature's settings page). Clones the map so every other feature's explicit state survives.
    function setComponentEnabled(key, on) {
        var m = {}
        var cur = VtlConfig.componentEnabledMap
        for (var k in cur) m[k] = cur[k]
        m[key] = on
        set("component_enabled", m)
    }

    // Long enough that a slider drag or a burst of related keys becomes one write, short enough
    // that letting go of a control and pulling the power cord a moment later still persists it.
    Timer {
        id: flushTimer
        interval: 140
        onTriggered: root._flush()
    }

    // The batch currently being written, so it can be confirmed to VtlConfig once it is really on
    // disk — until then VtlConfig must keep overlaying it onto every re-read (see applyLocal).
    property var _inFlight: ({})

    function _flush() {
        if (proc.running) { flushTimer.restart(); return }   // a batch is in flight; try again after
        if (!root._hasPending) return
        var batch = root._pending
        root._pending = ({})
        root._hasPending = false
        root._inFlight = batch
        proc.command = ["python3", "-c", root._py, JSON.stringify(batch)]
        proc.running = true
    }

    // Force everything out now — for callers that are about to end the session, where a debounce
    // that has not fired yet would simply lose the change.
    function flushNow() { flushTimer.stop(); root._flush() }

    Process {
        id: proc
        onExited: {
            VtlConfig.confirmWritten(root._inFlight)   // now safe for a re-read to supply these
            root._inFlight = ({})
            if (root._hasPending) Qt.callLater(root._flush)
        }
    }
}
