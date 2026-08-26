import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// The catalogue behind BOTH shapes of the wallpaper quick-picker — the panel that grows out of the
// bar (osd/WallpaperQuick.qml) and the full-screen coverflow (wallpaper/WallpaperGallery.qml).
//
// Listing a monitor's folder, reading the defined sets out of settings.json, firing wallpaper-set.sh
// and knowing what is currently ON each monitor are the same four jobs however the picker looks, so
// they live here once: a picker is then only a layout over `items`. Two pickers that each ran their
// own listing is exactly how the three disagreeing "where does the menu open" answers happened
// (see UiState.openWallpaperQuick) — not a mistake worth making twice.
//
// (Settings → Wallpaper keeps its own copy for now: it lists per TARGET monitor rather than per
// opened monitor, and logs its applies to /tmp/vtl-wp.log.)
Item {
    id: feed

    // Monitor whose folder is listed, and which an apply() lands on.
    property string mon: ""
    // Whose image previews a set in the sets list (the picker's own monitor — a set holds one file
    // per monitor and the card should show the one you are looking at). Defaults to `mon`.
    property string setPreviewMon: ""

    property var    items:    []      // [{ path, name, sub }]
    property var    sets:     []      // [{ name, preview }]
    property bool   grouped:  false   // subfolder-as-sorting active (from wallpaper-list.py)
    property string status:   ""
    property string applying: ""      // path being applied — the picker highlights it

    signal loaded()

    visible: false                    // pure logic; never draws

    // ── What is on the monitors right now ───────────────────────────────────────────────────────
    // The same file the wallpaper surfaces read (WallpaperWindow), watched — so a change made
    // anywhere (auto-change, another picker, the CLI) marks the right card without a reload.
    property var current: ({})        // { "<mon>": { path, type } }
    function currentFor(m) { var e = feed.current["" + m]; return (e && e.path) ? ("" + e.path) : "" }
    FileView {
        id: curFile
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron"))
              + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      feed._parseCurrent(text())
        onFileChanged: reload()
    }
    function _parseCurrent(t) {
        try { if (t && ("" + t).trim() !== "") feed.current = JSON.parse(t) } catch (e) { /* keep last good */ }
    }

    // ── Listing ─────────────────────────────────────────────────────────────────────────────────
    // reload()  — empty the picker first, then fill it (the bar panel grows empty and fills in).
    // refresh() — keep showing the last listing while a new one is fetched, so a picker that is
    //             reopened on the same folder is populated from the first frame instead of
    //             flashing empty for as long as python takes to walk the directory.
    function reload()  { feed.items = []; feed._list("Loading…") }
    function refresh() { feed._list(feed.items.length > 0 ? feed.status : "Loading…") }
    function _list(st) {
        feed.status = st
        listProc._buf = []
        listProc.command = ["bash", "-c",
            "python3 \"$VELUMERON_DIR/assets/scripts/wallpaper-list.py\" \"$1\"", "vtl", feed.mon]
        listProc.running = false; listProc.running = true
        feed.reloadSets()
    }
    function reloadSets() {
        setsProc._buf = []
        setsProc.command = ["python3", "-c", feed._setsPy, feed.setPreviewMon !== "" ? feed.setPreviewMon : feed.mon]
        setsProc.running = false; setsProc.running = true
    }

    Process {
        id: listProc
        property var _buf: []
        // Accumulate into a buffer; assign the model ONCE when done (not per line) so the grid
        // isn't reset 100× — that O(n²) churn was the stutter.
        stdout: SplitParser {
            onRead: line => {
                // NO trim before the split: root-level files have an EMPTY rel, so their line
                // starts with the tab — trimming ate it and dropped every root-level wallpaper.
                var t = "" + line
                if (t.startsWith("GROUP:")) { feed.grouped = t.slice(6).trim() === "1"; return }
                var tab = t.indexOf("\t")
                if (tab < 0) return
                var full = t.slice(tab + 1)
                if (full === "") return
                listProc._buf.push({ path: full, name: full.split("/").pop(), sub: t.slice(0, tab) })
            }
        }
        onRunningChanged: if (!running) {
            feed.items = listProc._buf
            listProc._buf = []
            feed.status = feed.items.length + " wallpaper(s) · " + feed.mon
            feed.loaded()
        }
    }
    Process {
        id: setsProc
        property var _buf: []
        stdout: SplitParser {
            onRead: line => {
                var t = ("" + line).trim(); if (t === "") return
                var i = t.indexOf("\t")
                setsProc._buf.push({ name: i < 0 ? t : t.slice(0, i), preview: i < 0 ? "" : t.slice(i + 1) })
            }
        }
        onRunningChanged: if (!running) { feed.sets = setsProc._buf; setsProc._buf = [] }
    }

    // ── Applying ────────────────────────────────────────────────────────────────────────────────
    function stem(n) { return ("" + n).replace(/\.[^.]+$/, "") }
    function apply(path) {
        feed.applying = path
        feed.status   = "Applying " + feed.stem(("" + path).split("/").pop()) + " → " + feed.mon + "…"
        applyProc.command = ["bash", "-c",
            "setsid bash \"$VELUMERON_DIR/assets/scripts/wallpaper-set.sh\" "
            + "--mon " + JSON.stringify(feed.mon) + " --file " + JSON.stringify(path)
            + " </dev/null >/dev/null 2>&1 &"]
        applyProc.running = false; applyProc.running = true
    }
    // A whole set: one wallpaper-set.sh call per monitor in it (the focused one drives the colour
    // theme). Stored in settings.json as wallpaper_sets.<name> = { "<mon>": "<path>" }.
    function applySet(name) {
        feed.status = "Applying set " + name + "…"
        applyProc.command = ["python3", "-c", feed._applySetPy, name]
        applyProc.running = false; applyProc.running = true
    }
    Process { id: applyProc }

    readonly property string _applySetPy:
        "import json,os,sys,subprocess;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "d=json.load(open(os.path.join(pu,'gui','settings.json')));" +
        "vd=os.environ.get('VELUMERON_DIR','');" +
        "m=(d.get('wallpaper_sets',{}) or {}).get(sys.argv[1]) or {};" +
        "[subprocess.Popen(['setsid','bash',vd+'/assets/scripts/wallpaper-set.sh','--no-showcase','--mon',mon,'--file',path]) for mon,path in m.items()]"
    readonly property string _setsPy:
        "import json,os,sys;" +
        "pu=os.environ.get('VELUMERON_USER_DIR') or os.path.join(os.environ.get('XDG_CONFIG_HOME','') " +
          "or os.path.expanduser('~/.config'),'velumeron');" +
        "p=os.path.join(pu,'gui','settings.json');" +
        "d=json.load(open(p)) if os.path.exists(p) else {};" +
        "s=d.get('wallpaper_sets',{}) or {}; mon=sys.argv[1];" +
        "[print(n+'\\t'+((s[n].get(mon) or (list(s[n].values())[0] if s[n] else '')) or '')) for n in sorted(s)]"

    // ── Shared vocabulary the pickers both need ─────────────────────────────────────────────────
    function isVideo(n) { return /\.(mp4|webm|mkv|avi|mov)$/i.test(n) }
    // Stacks: every subfolder of the wallpaper directory is a pile you can switch off (the choice
    // persists in wallpaper_stacks_off). Filtering by stack + static/live is the same question in
    // both pickers, so the filter itself lives here too.
    readonly property var stackNames: {
        var seen = {}, out = []
        for (var i = 0; i < feed.items.length; i++) {
            var s = feed.items[i].sub || ""
            if (!(s in seen)) { seen[s] = true; out.push(s) }
        }
        out.sort(function (a, b) {
            return a === "" ? 1 : b === "" ? -1 : a.toLowerCase() < b.toLowerCase() ? -1 : 1
        })
        return out
    }
    readonly property bool hasStacks: feed.stackNames.length > 1
    function stackLabel(s) { return s === "" ? "Main" : s }
    function stackOn(s)    { return VtlConfig.wallpaperStackOn(s) }
    // Turning the LAST stack off would leave an empty picker and no obvious way back, so the final
    // one on refuses to switch itself off.
    function toggleStack(s) {
        var off = VtlConfig.wallpaperStacksOff.slice()
        var i = off.indexOf("" + s)
        if (i >= 0) off.splice(i, 1)
        else {
            var remaining = feed.stackNames.filter(function (n) { return feed.stackOn(n) })
            if (remaining.length <= 1) return
            off.push("" + s)
        }
        SettingsStore.set("wallpaper_stacks_off", off)
    }

    // `typeFilter`: all | static | live. The bar panel offers all three as a filter; the gallery
    // treats static and live as two separate piles and never shows "all", which is why the counts
    // below exist — a switch between two piles has to be able to say how big each one is.
    property string typeFilter: "all"
    readonly property var _stacked: feed.items.filter(function (it) {
        return VtlConfig.wallpaperStackOn(it.sub || "")
    })
    readonly property var filtered: {
        if (feed.typeFilter === "all") return feed._stacked
        var live = feed.typeFilter === "live"
        return feed._stacked.filter(function (it) { return feed.isVideo(it.name) === live })
    }
    readonly property int nLive: {
        var n = 0
        for (var i = 0; i < feed._stacked.length; i++) if (feed.isVideo(feed._stacked[i].name)) n++
        return n
    }
    readonly property int nStatic: feed._stacked.length - feed.nLive
}
