pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The ONE writer for gui/settings.json. Every settings page (and any surface that persists a
// preference) calls SettingsStore.set(key, value) — this replaces the identical python
// one-liner that used to be copy-pasted into every page.
//
// set() applies the value optimistically to the in-memory config (VtlConfig.applyLocal) so
// bindings react instantly, then queues the file write. Writes are queued, not restarted:
// killing an in-flight write on a rapid second change could lose the first key.
Singleton {
    id: root

    readonly property string _py:
        "import json,os,sys;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "p=os.path.join(pu,'gui','settings.json');" +
        "os.makedirs(os.path.dirname(p),exist_ok=True);" +
        "d=json.load(open(p)) if os.path.exists(p) else {};" +
        "d[sys.argv[1]]=json.loads(sys.argv[2]);" +
        "t=p+'.tmp';open(t,'w').write(json.dumps(d,indent=2));os.replace(t,p)"

    property var _queue: []
    function set(key, value) {
        VtlConfig.applyLocal(key, value)
        root._queue.push([key, JSON.stringify(value)])
        _pump()
    }
    function _pump() {
        if (proc.running || root._queue.length === 0) return
        var next = root._queue.shift()
        proc.command = ["python3", "-c", root._py, next[0], next[1]]
        proc.running = true
    }
    Process {
        id: proc
        onExited: Qt.callLater(root._pump)
    }
}
