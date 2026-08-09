pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// Local calendars and task lists — the third backend next to Vikunja and CalDAV,
// for everything that should live on this machine and nowhere else. No account,
// no network: one JSON file, gui/local.json.
//
// THE STORE IS SHARED WITH DISPONERA (its src/disponera/local.py owns the same
// file in-process). The app had local lists first, so its schema is the spec —
// assets/scripts/local-store.py documents it and is the only writer on this side.
// Reads go through a watched FileView instead of the script: the shell then picks
// up a list the user created in the app WITHOUT a sync, and vice versa, which is
// what makes the two feel like one program.
//
// Reading here and writing there is deliberate. A wholesale rewrite from an
// in-memory copy would drop whatever the other side changed in the meantime;
// local-store.py re-reads, patches and atomically replaces in one shot, so
// concurrent edits from the app and the shell can't lose each other.
//
// Shapes match the CalDAV service exactly (calendars/events) and the unified todo
// model (projects/tasks), so EventService and TodoService merge them in without a
// special case beyond the "loc:" id prefix.
Singleton {
    id: root

    property var data: ({ lists: [], items: [], ics: [], roles: ({}), eventTags: [] })

    readonly property string script:    Quickshell.env("VELUMERON_DIR") + "/assets/scripts/local-store.py"
    readonly property string storePath: VtlConfig.userDir + "/gui/local.json"

    readonly property var lists: data.lists ?? []
    readonly property var items: data.items ?? []

    readonly property var todoLists: root.lists.filter(l => l.kind === "todo")
    readonly property var calLists:  root.lists.filter(l => l.kind === "calendar")
    readonly property bool hasLists: root.lists.length > 0

    function listById(id) {
        var ls = root.lists
        for (var i = 0; i < ls.length; i++) if (ls[i].id === id) return ls[i]
        return null
    }

    // "YYYY-MM-DD" + optional "HH:MM" → epoch ms in LOCAL time. Mirrors local.py's
    // _ymd_to_ms (naive strptime + .timestamp()), so both sides agree on the value.
    //
    // Including on the two days a year where a wall clock is ambiguous and the two
    // languages disagree by default — an event stored on either must not sit an
    // hour apart in the shell and in the app:
    //   · spring forward — the asked-for time never happens. Python resolves it
    //     FORWARD (02:30 → 03:30, the iCalendar convention), JS resolves it back.
    //     Spotted by the constructed date not keeping the time we asked for.
    //   · autumn back — the asked-for time happens twice. Python takes the FIRST
    //     (naive .timestamp() is fold=0), JS takes the second. Spotted by stepping
    //     back one transition and landing on the same wall clock.
    function _ms(ymd, hm) {
        var p = ("" + (ymd ?? "")).split("-")
        if (p.length !== 3) return 0
        var t = ("" + (hm ?? "")).split(":")
        var da = parseInt(p[2], 10)
        var hh = t.length === 2 ? (parseInt(t[0], 10) || 0) : 0
        var mi = t.length === 2 ? (parseInt(t[1], 10) || 0) : 0
        var d = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, da, hh, mi, 0, 0)
        var ms = d.getTime()
        if (isNaN(ms)) return 0
        if (d.getHours() !== hh || d.getMinutes() !== mi) {
            // Minutes-of-day difference, wrapped so a gap across midnight resolves
            // the short way round rather than by a whole day.
            var off = (hh * 60 + mi) - (d.getHours() * 60 + d.getMinutes())
            if (off >  720) off -= 1440
            if (off < -720) off += 1440
            ms += off * 60000
        } else {
            // 2 h / 1 h / 30 min covers every transition in the tz database.
            var steps = [7200000, 3600000, 1800000]
            for (var k = 0; k < steps.length; k++) {
                var e = new Date(ms - steps[k])
                if (e.getHours() === hh && e.getMinutes() === mi && e.getDate() === da) {
                    ms -= steps[k]
                    break
                }
            }
        }
        return ms
    }

    // ── Calendar side (CalDavService.calendars / .events shapes) ────────────────
    readonly property var calendars: {
        var out = []
        var ls = root.calLists
        for (var i = 0; i < ls.length; i++)
            out.push({ id: "loc:" + ls[i].id, name: ls[i].name ?? "", account: "Local",
                       color: ls[i].color ?? "", vevent: true, vtodo: false,
                       writable: true, url: "" })
        return out
    }

    readonly property var events: {
        var out = []
        var its = root.items
        for (var i = 0; i < its.length; i++) {
            var it = its[i]
            var l = root.listById(it.listId)
            if (!l || l.kind !== "calendar") continue
            var start = root._ms(it.ymd, it.hm)
            if (!start) continue
            var allDay = !it.hm
            var end
            if (allDay) {
                // endYmd (an all-day range) is inclusive on disk; endMs is exclusive.
                var e = it.endYmd ? root._ms(it.endYmd, "") : 0
                end = (e >= start ? e : start) + 86400000
            } else {
                end = start + (it.durMin || 60) * 60000
            }
            out.push({ cal: "loc:" + it.listId, href: it.id, etag: "", uid: it.id,
                       summary: it.title ?? "(untitled)", allDay: allDay,
                       startMs: start, endMs: end, recurring: false,
                       notes: it.notes ?? "", location: it.location ?? "",
                       categories: it.categories ?? [], attendees: it.attendees ?? [],
                       icon: it.icon ?? "", image: it.image ?? "" })
        }
        return out
    }

    // ── Todo side (the unified project/task shapes — see TodoService) ───────────
    readonly property var todoProjects: {
        var out = []
        var ls = root.todoLists
        for (var i = 0; i < ls.length; i++)
            out.push({ id: "loc:" + ls[i].id, title: ls[i].name ?? "", parentId: "",
                       source: "local", color: ls[i].color ?? "",
                       writable: true, openCount: 0 })
        return out
    }

    readonly property var todoTasks: {
        var out = []
        var its = root.items
        for (var i = 0; i < its.length; i++) {
            var it = its[i]
            var l = root.listById(it.listId)
            if (!l || l.kind !== "todo") continue
            out.push({ id: "loc:" + it.id, projectId: "loc:" + it.listId,
                       title: it.title ?? "", done: it.done === true,
                       doneMs: it.doneMs ?? 0, dueMs: root._ms(it.ymd, it.hm),
                       dueAllDay: !it.hm, priority: it.priority ?? 0,
                       parentTaskId: "", notes: it.notes ?? "", cal: "", href: "",
                       recurring: false, repeatAfter: 0 })
        }
        return out
    }

    // ── Live read: the file is the model ───────────────────────────────────────
    // Keep the last good parse if a read lands mid-write; local-store.py replaces
    // atomically, so a torn read is rare and never worth flashing the lists away.
    function _parse(t) {
        var s = ("" + t).trim()
        if (s === "") return
        try {
            var d = JSON.parse(s)
            if (d && typeof d === "object") root.data = d
        } catch (e) { /* keep previous data */ }
    }
    FileView {
        id: fv
        path: root.storePath
        watchChanges: true
        // The store only exists once there's a first local list — a missing file is
        // the normal state, not something to log about on every start.
        printErrors: false
        onLoaded:      root._parse(text())
        onFileChanged: reload()
    }
    function reload() { fv.reload() }

    // ── Writes (one queued Process; every command prints the whole store) ──────
    property var _queue: []
    function _run(args) { _queue.push(args); _pump() }
    function _pump() {
        if (proc.running || root._queue.length === 0) return
        proc.command = ["python3", root.script].concat(root._queue.shift())
        proc.running = true
    }
    Process {
        id: proc
        // The script's own output lands the change a beat before the file watcher
        // would, so the UI never shows a stale list between write and reload.
        stdout: StdioCollector { onStreamFinished: root._parse(text) }   // a property, not a call
        // Re-point the watcher afterwards: the first write CREATES the store, and a
        // watch armed on a file that didn't exist yet would never fire for the app.
        onExited: { fv.reload(); Qt.callLater(root._pump) }
    }

    // ── List CRUD ──────────────────────────────────────────────────────────────
    function addList(name, kind, color)    { _run(["add-list", name, kind, color ?? ""]) }
    function renameList(id, name)          { _run(["rename-list", id, name]) }
    function setListColor(id, color)       { _run(["set-list-color", id, color ?? ""]) }
    function deleteList(id)                { _run(["delete-list", id]) }

    // ── Item CRUD — ids here are BARE (no "loc:"); the services strip the prefix ─
    // extra (optional): { priority, notes } — the full task editor's fields.
    function addTodo(listId, title, ymd, hm, extra) {
        var a = ["add-todo", listId, title, ymd ?? "", hm ?? ""]
        if (extra) a.push(JSON.stringify(extra))
        _run(a)
    }

    // One `load` at startup, like the CalDAV and Vikunja services. Reads are the
    // FileView's job — this is here for the side effect: local-store.py copies a
    // pre-move store (Disponera's own config dir) across on its first read, and
    // without this the user's existing lists would stay invisible until something
    // else happened to write.
    Component.onCompleted: _run(["load"])
    function addEvent(listId, ev)            { _run(["add-event", listId, JSON.stringify(ev)]) }
    function updateItem(id, patch)           { _run(["update-item", id, JSON.stringify(patch)]) }
    function toggleItem(id)                  { _run(["toggle-item", id]) }
    function deleteItem(id)                  { _run(["delete-item", id]) }
}
