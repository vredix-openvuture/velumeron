pragma Singleton
import ".."
import QtQuick
import Quickshell

// Unified calendar state for every event surface — the sibling of TodoService.
// Two backends feed ONE model: CalDavService contributes the synced VEVENT
// calendars, LocalService the machine-only ones (gui/local.json, shared with
// Disponera). Calendars keep their backend's id — a CalDAV "<account>|<href>" or
// a local "loc:<listId>" — and every mutation routes on that prefix, so the UI
// only ever sees one list of calendars and one list of events.
//
// Visibility rules stay where they were: caldav_hidden hides a calendar of either
// kind (local ids live in the same map), and a per-account role of "tasks" drops
// a CalDAV account's events. Local lists have no account, so their kind alone
// decides — a local calendar holds events, a local todo list holds tasks.
Singleton {
    id: root

    readonly property var calendars: {
        var out = []
        var cd = CalDavService.calendars
        for (var i = 0; i < cd.length; i++) out.push(cd[i])
        var lo = LocalService.calendars
        for (var j = 0; j < lo.length; j++) out.push(lo[j])
        return out
    }

    readonly property var events: {
        var out = []
        var cd = CalDavService.events            // already hidden/role filtered
        for (var i = 0; i < cd.length; i++) out.push(cd[i])
        var lo = LocalService.events
        for (var j = 0; j < lo.length; j++)
            if (!VtlConfig.caldavCalHidden(lo[j].cal)) out.push(lo[j])
        return out
    }

    // Calendars that can be shown / written to (the sidebar and the event editor).
    readonly property var eventCalendars: root.calendars.filter(c => c.vevent && c.writable
                                          && VtlConfig.caldavRole(c.account) !== "tasks")
    readonly property var visibleCalendars: root.calendars.filter(c => c.vevent
                                            && VtlConfig.caldavRole(c.account) !== "tasks")
    readonly property bool hasCalendars: root.calendars.length > 0

    function calById(id) {
        var cs = root.calendars
        for (var i = 0; i < cs.length; i++) if (cs[i].id === id) return cs[i]
        return null
    }
    function accountOf(calId) { var c = calById(calId); return c ? (c.account ?? "") : "" }

    // Calendar colour: the server/list colour, else a stable palette pick by index.
    function colorFor(calId) {
        var c = calById(calId)
        if (c && c.color) return c.color
        var pal = [Colors.bgActive, Colors.boActive, Colors.bgHover, Colors.boNormal, Colors.bgSecondary]
        var idx = 0, cs = root.calendars
        for (var i = 0; i < cs.length; i++) if (cs[i].id === calId) { idx = i; break }
        return pal[idx % pal.length]
    }

    function _isLocal(id) { return ("" + id).indexOf("loc:") === 0 }
    function _locId(id)   { return ("" + id).slice(4) }

    // ── Mutations (routed on the calendar id) ──────────────────────────────────
    function addEvent(calId, summary, ymd, hm, durationMin, notes) {
        if (root._isLocal(calId))
            LocalService.addEvent(root._locId(calId),
                                  { summary: summary, ymd: ymd, hm: hm ?? "",
                                    durMin: durationMin ?? 60, notes: notes ?? "" })
        else
            CalDavService.addEvent(calId, summary, ymd, hm, durationMin, notes)
    }
    // All-day event spanning startYmd..endYmd (inclusive); endYmd defaults to startYmd.
    function addEventRange(calId, summary, startYmd, endYmd, notes) {
        if (root._isLocal(calId))
            LocalService.addEvent(root._locId(calId),
                                  { summary: summary, ymd: startYmd, hm: "", durMin: 0,
                                    endYmd: endYmd ?? startYmd, notes: notes ?? "" })
        else
            CalDavService.addEventRange(calId, summary, startYmd, endYmd, notes)
    }
    function deleteEvent(calId, href) {
        if (root._isLocal(calId)) LocalService.deleteItem(href)
        else                      CalDavService.deleteItem(calId, href)
    }

    // ── Sync state (local needs none — its file watcher is always current) ─────
    readonly property bool   syncing:   CalDavService.syncing
    readonly property string lastError: CalDavService.lastError
    readonly property int    syncedAt:  CalDavService.data.syncedAt ?? 0
    function sync() { CalDavService.sync(); LocalService.reload() }
}
