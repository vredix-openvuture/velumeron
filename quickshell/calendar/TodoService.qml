pragma Singleton
import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// Unified todo state shared by the calendar flyout and (by contract) velorganize.
// Two backends feed ONE model: vikunja-client.py delivers the project TREE +
// task→subtask relations over Vikunja's REST API; every other CalDAV account
// contributes its flat VTODO lists through CalDavService. The merge spec below
// is duplicated in velorganize's src/velorganize/todomodel.py — keep them in
// lockstep (both read the same two cache files, so they agree by construction
// after any sync).
//
// Unified model:
//   project = { id: "vk:8"|"cd:<calId>", title, parentId (""=root), source,
//               color, writable, openCount }
//   task    = { id: "vk:16"|"cd:<calId>|<href>", projectId, title, done, doneMs,
//               dueMs, priority (0..5, Vikunja scale), parentTaskId, notes,
//               cal, href (cd only — kept for mutations) }
//
// Merge rule: Vikunja first; every CalDAV account whose URL host equals the
// Vikunja host is dropped (same data, richer over REST). iCal priorities
// (1=highest…9) map onto Vikunja's 0..5 (0=unset, 5=highest).
Singleton {
    id: root

    property var    vkData:  ({ syncedAt: 0, lastError: "", source: { ok: false, host: "" },
                                projects: [], tasks: [] })
    property bool   syncing:   false
    property string lastError: ""

    readonly property string script: Quickshell.env("VELUMERON_DIR") + "/assets/scripts/vikunja-client.py"

    readonly property bool vkOk:   (vkData.source ?? {}).ok === true
    readonly property string vkHost: (vkData.source ?? {}).host ?? ""

    // ── CalDAV side (reactive view on CalDavService — no second caldav process) ──
    // account name → URL host, to drop calendars already covered by Vikunja REST.
    readonly property var _accountHost: {
        var m = {}
        var as_ = CalDavService.accounts
        for (var i = 0; i < as_.length; i++) {
            var u = ("" + (as_[i].url ?? ""))
            var h = u.replace(/^[a-z]+:\/\//, "").split("/")[0]
            m[as_[i].name] = h
        }
        return m
    }
    function _cdKept(calId) {
        var cal = CalDavService.calById(calId)
        if (!cal) return false
        return !(root.vkOk && root._accountHost[cal.account] === root.vkHost)
    }
    readonly property var _cdCals: CalDavService.calendars.filter(c => c.vtodo && root._cdKept(c.id))

    function _icalPrio(p) {   // iCal 1=highest…9=lowest → Vikunja 0..5 (5=highest)
        if (!p || p <= 0) return 0
        if (p === 1) return 5
        if (p <= 4)  return 4
        if (p === 5) return 3
        if (p <= 8)  return 2
        return 1
    }

    // ── Unified model ─────────────────────────────────────────────────────────
    readonly property var projects: {
        var out = []
        if (root.vkOk) {
            var vp = root.vkData.projects ?? []
            for (var i = 0; i < vp.length; i++)
                out.push({ id: "vk:" + vp[i].id, title: vp[i].title,
                           parentId: vp[i].parentId ? "vk:" + vp[i].parentId : "",
                           source: "vikunja", color: vp[i].color ?? "",
                           writable: true, openCount: 0 })
        }
        var cc = root._cdCals
        for (var j = 0; j < cc.length; j++)
            out.push({ id: "cd:" + cc[j].id, title: cc[j].name, parentId: "",
                       source: "caldav", color: cc[j].color ?? "",
                       writable: cc[j].writable === true, openCount: 0 })
        // Fill openCount (own open tasks per project).
        var counts = {}
        var ts = root.tasks
        for (var k = 0; k < ts.length; k++)
            if (!ts[k].done) counts[ts[k].projectId] = (counts[ts[k].projectId] ?? 0) + 1
        for (var n = 0; n < out.length; n++) out[n].openCount = counts[out[n].id] ?? 0
        return out
    }

    readonly property var tasks: {
        var out = []
        if (root.vkOk) {
            var vt = root.vkData.tasks ?? []
            for (var i = 0; i < vt.length; i++)
                out.push({ id: "vk:" + vt[i].id, projectId: "vk:" + vt[i].projectId,
                           title: vt[i].title, done: vt[i].done === true,
                           doneMs: vt[i].doneMs ?? 0, dueMs: vt[i].dueMs ?? 0,
                           priority: vt[i].priority ?? 0,
                           parentTaskId: vt[i].parentId ? "vk:" + vt[i].parentId : "",
                           notes: vt[i].notes ?? "", cal: "", href: "" })
        }
        // CalDAV todos of kept calendars; RELATED-TO uid resolved within the same calendar.
        var todos = CalDavService.todos.filter(t => root._cdKept(t.cal))
        var byUid = {}
        for (var u = 0; u < todos.length; u++) byUid[todos[u].cal + "\n" + todos[u].uid] = todos[u]
        for (var j = 0; j < todos.length; j++) {
            var t = todos[j]
            var parent = t.parent ? byUid[t.cal + "\n" + t.parent] : null
            out.push({ id: "cd:" + t.cal + "|" + t.href, projectId: "cd:" + t.cal,
                       title: t.summary, done: t.completed === true,
                       doneMs: t.doneMs ?? 0, dueMs: t.dueMs ?? 0,
                       priority: root._icalPrio(t.priority),
                       parentTaskId: parent ? "cd:" + parent.cal + "|" + parent.href : "",
                       notes: t.notes ?? "", cal: t.cal, href: t.href })
        }
        return out
    }

    readonly property bool hasTodoAccounts: root.vkOk || root._cdCals.length > 0
    readonly property int  openCount: {
        var n = 0, ts = root.tasks
        for (var i = 0; i < ts.length; i++) if (!ts[i].done) n++
        return n
    }
    // Open tasks that are overdue or due today — the clock module shows a dot when > 0.
    readonly property int dueCount: {
        var end = new Date(); end.setHours(23, 59, 59, 999)
        var n = 0, ts = root.tasks
        for (var i = 0; i < ts.length; i++)
            if (!ts[i].done && ts[i].dueMs > 0 && ts[i].dueMs <= end.getTime()) n++
        return n
    }

    // ── Lookups ───────────────────────────────────────────────────────────────
    function projectById(id) {
        var ps = root.projects
        for (var i = 0; i < ps.length; i++) if (ps[i].id === id) return ps[i]
        return null
    }
    function childProjects(parentId) { return root.projects.filter(p => p.parentId === parentId) }
    function subtasksOf(taskId)      { return root.tasks.filter(t => t.parentTaskId === taskId) }
    // Project colour: server colour, else a stable palette pick by index.
    function colorFor(projectId) {
        var p = projectById(projectId)
        if (p && p.color) return p.color
        var pal = [Colors.bgActive, Colors.boActive, Colors.bgHover, Colors.boNormal, Colors.bgSecondary]
        var idx = 0, ps = root.projects
        for (var i = 0; i < ps.length; i++) if (ps[i].id === projectId) { idx = i; break }
        return pal[idx % pal.length]
    }

    // ── Command queue (one Process; every command prints the fresh vikunja cache) ──
    property var _queue: []
    function _run(args) { _queue.push(args); _pump() }
    function _pump() {
        if (proc.running || root._queue.length === 0) return
        proc.command = ["python3", root.script].concat(root._queue.shift())
        proc.running = true
    }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                var t = ("" + text).trim()
                if (t !== "") {
                    try {
                        var d = JSON.parse(t)
                        root.vkData = d
                        root.lastError = d.lastError ?? ""
                    } catch (e) { /* keep the previous model on a garbled read */ }
                }
                root.syncing = root._queue.some(a => a[0] === "sync")
                Qt.callLater(root._pump)
            }
        }
        onExited: Qt.callLater(root._pump)
    }

    function sync() {
        CalDavService.sync()
        if (root._queue.some(a => a[0] === "sync")) return
        root.syncing = true
        _run(["sync"])
    }

    // ── Mutations — routed on the id prefix, vikunja side patched optimistically ──
    function _vkId(id) { return parseInt(("" + id).slice(3), 10) }

    function addTask(projectId, title, dueYmd, parentTaskId) {
        if (("" + projectId).indexOf("vk:") === 0) {
            var args = ["add-task", "" + _vkId(projectId), title, dueYmd ?? ""]
            if (parentTaskId && ("" + parentTaskId).indexOf("vk:") === 0)
                args.push("" + _vkId(parentTaskId))
            _run(args)
        } else if (("" + projectId).indexOf("cd:") === 0) {
            CalDavService.addTodo(("" + projectId).slice(3), title, dueYmd ?? "")
        }
    }

    function toggleTask(task) {
        if (("" + task.id).indexOf("vk:") === 0) {
            var d = Object.assign({}, root.vkData)
            var nid = _vkId(task.id)
            d.tasks = (d.tasks ?? []).map(t => t.id === nid
                ? Object.assign({}, t, { done: !task.done, doneMs: !task.done ? Date.now() : 0 })
                : t)
            root.vkData = d
            _run(["toggle-task", "" + nid, task.done ? "0" : "1"])
        } else {
            CalDavService.toggleTodo({ cal: task.cal, href: task.href, completed: task.done })
        }
    }

    function deleteTask(task) {
        if (("" + task.id).indexOf("vk:") === 0) {
            var d = Object.assign({}, root.vkData)
            var nid = _vkId(task.id)
            d.tasks = (d.tasks ?? []).filter(t => t.id !== nid)
            root.vkData = d
            _run(["delete-task", "" + nid])
        } else {
            CalDavService.deleteItem(task.cal, task.href)
        }
    }

    function setDue(task, dueYmd) {   // vikunja only in M1 (caldav-client has no set-due yet)
        if (("" + task.id).indexOf("vk:") !== 0) return
        _run(["set-due", "" + _vkId(task.id), dueYmd ?? ""])
    }

    // ── Startup: instant cache, then a real sync; refresh on the caldav cadence ──
    Component.onCompleted: { _run(["load"]); _run(["sync"]) }
    Timer {
        interval: Math.max(2, VtlConfig.caldavSyncMinutes) * 60000
        repeat:   true
        running:  root.vkOk
        onTriggered: { if (!root._queue.some(a => a[0] === "sync")) root._run(["sync"]) }
    }
}
