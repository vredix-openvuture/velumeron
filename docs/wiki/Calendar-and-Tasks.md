# Calendar & Tasks

Click the **clock** in the bar: a calendar + task menu grows out of it. It speaks plain
**CalDAV**, so Nextcloud Calendar, Nextcloud Tasks and Vikunja all work — events (VEVENT) feed the
month view, todos (VTODO) feed the task list.

## Connecting accounts (Settings → Calendar)

1. **Name** — any label ("Nextcloud", "Vikunja")
2. **Server URL** — any CalDAV entry point works; discovery handles the rest:
   - Nextcloud: `https://cloud.example.com` (or `…/remote.php/dav`)
   - Vikunja: `https://vikunja.example.com/dav/projects`
3. **Username**
4. **App password** — never your main password:
   - Nextcloud: Settings → Security → App passwords
   - Vikunja: Settings → CalDAV tokens

"Connect" validates the credentials before saving. Accounts are stored in
`~/.config/velumeron/gui/caldav-accounts.json` (mode 600 — readable only by your user, but
plaintext: use app passwords). Everything else (hidden calendars, defaults, sync cadence) lives in
settings.json.

## The menu

**Calendar tab**
- Month grid with per-calendar event dots; click a day for its agenda, double-click to jump into
  quick-add. `‹ ›` pages months, the middle button returns to today.
- Left rail: one switch per calendar — hides it from the view (synced state stays).
- Quick-add: `14:00 Standup` → timed 1-hour event, plain text → all-day event on the selected day.
  The "into" chips pick the target calendar (remembered).
- Hover an event → ✕ deletes it (single events only; recurring series are read-only).

**Tasks tab**
- Left rail: **General** (all lists) on top, then one entry per task list with its open count —
  selecting switches the view to that list.
- Groups: Overdue / Today / Upcoming, completed collapsed behind a count.
- Round checkbox completes/reopens (optimistic — instant, synced in the background); hover ✕ deletes.
- Quick-add creates the task in the selected list (in General: your default list).

**Footer**: sync state, manual refresh, gear → Settings → Calendar.

## Sync behaviour

- Instant load from the local cache (`~/.cache/velumeron/caldav-cache.json`), then a refresh on
  open and every N minutes (Settings → Calendar → Refresh).
- Recurring events are expanded locally (daily/weekly/monthly/yearly incl. `BYDAY` ordinals,
  `COUNT`/`UNTIL`, exceptions). Exotic rules (`BYSETPOS`) show their first occurrence only.
- All network work runs in `assets/scripts/caldav-client.py` (stdlib only) — the UI never blocks.

## Settings

Menu width and max height, first day of week, per-calendar visibility, sync interval —
all in Settings → Calendar. The clock module shows a small dot while tasks are overdue or due today.

## IPC

```bash
qs -p $VELUMERON_DIR/quickshell ipc call flyout calendar   # toggle the menu
```
