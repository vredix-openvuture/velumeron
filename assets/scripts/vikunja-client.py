#!/usr/bin/env python3
"""Vikunja REST client for the velumeron todo surfaces (stdlib only).

Sibling of caldav-client.py with the same contract: every command prints the
full JSON cache on stdout (single line) so the QML service (TodoService.qml)
and the velora bridge (todomodel.py) share one parse path. Where plain
CalDAV only offers flat VTODO lists, Vikunja's REST API adds the project TREE
(parent_project_id) and task→subtask relations — the whole reason this client
exists (see the unified todo model spec referenced in both consumers).

Commands:
  load                                       print the cache without touching the network
  sync                                       refresh projects + tasks + labels, write + print
  add-task <projectId> <title> [dueYMD] [parentTaskId]
  toggle-task <taskId> <0|1>
  delete-task <taskId>
  set-due <taskId> <dueYMD|"">               "" clears the due date
  update-task <taskId> <jsonPatch>           {title,notes,priority,dueYmd} — any subset
  move-task <taskId> <newProjectId>          move a task to another project
  set-labels <taskId> <jsonIdArray>          reconcile the task's labels to this exact set
  add-label <title> [colorHex]               create a new label
  add-project <title> [parentId] [colorHex] [description]
  update-project <projectId> <jsonPatch>     {title,color,description,parentId} — any subset
  delete-project <projectId>

Mutations refresh only the affected project (one GET) before printing, so the
optimistic UI patch is confirmed without a full multi-request sync. Unlike
caldav-client.py this script ALWAYS exits 0 with the cache on stdout — errors
land in cache["lastError"] — because the PySide bridge runs with check=True
and would otherwise discard the printed cache.

Config resolution:
  1. $VELUMERON_USER_DIR/gui/vikunja.json          {"url": ..., "token": ...}
  2. the caldav account whose URL path contains /dav/  →  base = scheme://host,
     token from ~/.config/vikunja/token

Cache: ~/.cache/velumeron/vikunja-cache.json — schema:
  { syncedAt, lastError, source:{name,base,host,ok},
    projects:[{id,title,parentId,color,description,archived,favorite}],
    tasks:[{id,projectId,title,done,doneMs,dueMs,priority,percentDone,
            parentId,notes,labels:[{id,title,color}],updatedMs}],
    labels:[{id,title,color}] }
Ids are the raw Vikunja integers; consumers prefix them ("vk:16").
"""

import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

COMPLETED_KEEP_DAYS = 30       # drop done tasks older than this (mirrors caldav-client)
PER_PAGE = 250
TIMEOUT = 20


def user_dir():
    u = os.environ.get("VELUMERON_USER_DIR")
    if u:
        return u
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(xdg, "velumeron")


CONFIG_PATH = os.path.join(user_dir(), "gui", "vikunja.json")
ACCOUNTS_PATH = os.path.join(user_dir(), "gui", "caldav-accounts.json")
TOKEN_FALLBACK = os.path.expanduser("~/.config/vikunja/token")
CACHE_PATH = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "velumeron", "vikunja-cache.json")
BG_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "velumeron", "vikunja-bg")


# ── Small file helpers ────────────────────────────────────────────────────────

def _read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def load_cache():
    c = _read_json(CACHE_PATH)
    if isinstance(c, dict) and "projects" in c:
        return c
    return {"syncedAt": 0, "lastError": "",
            "source": {"name": "", "base": "", "host": "", "ok": False},
            "projects": [], "tasks": []}


def save_cache(cache):
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    tmp = CACHE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cache, f)
    os.replace(tmp, CACHE_PATH)


def emit(cache):
    print(json.dumps(cache, separators=(",", ":")))


# ── Source resolution (which Vikunja, which token) ────────────────────────────

def resolve_source():
    """{name, base, host, token} or None. gui/vikunja.json wins; else the
    caldav account that looks like Vikunja (/dav/ path) + the token file."""
    cfg = _read_json(CONFIG_PATH) or {}
    url = (cfg.get("url") or "").strip().rstrip("/")
    token = (cfg.get("token") or "").strip()
    name = (cfg.get("name") or "Vikunja").strip() or "Vikunja"
    if not url or not token:
        accounts = (_read_json(ACCOUNTS_PATH) or {}).get("accounts", [])
        for a in accounts:
            au = (a.get("url") or "").strip()
            p = urllib.parse.urlsplit(au)
            if "/dav/" in p.path or p.path.rstrip("/").endswith("/dav"):
                if not url:
                    url = f"{p.scheme}://{p.netloc}"
                    name = a.get("name") or name
                break
        if not token:
            try:
                with open(TOKEN_FALLBACK) as f:
                    token = f.read().strip()
            except OSError:
                token = ""
    if not url or not token:
        return None
    return {"name": name, "base": url, "host": urllib.parse.urlsplit(url).netloc,
            "token": token}


# ── HTTP ──────────────────────────────────────────────────────────────────────

def http(method, url, token, body=None):
    """Returns (status, parsed json | None, headers). Raises on transport errors."""
    hdrs = {"User-Agent": "velumeron-vikunja/1.0",
            "Authorization": "Bearer " + token,
            "Accept": "application/json"}
    data = None
    if body is not None:
        hdrs["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            raw = r.read()
            parsed = json.loads(raw) if raw.strip() else None
            return r.status, parsed, dict(r.headers)
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = (e.read() or b"").decode()[:200]
        except OSError:
            pass
        raise RuntimeError(f"{method} {url} -> HTTP {e.code} {detail}".strip())


def api(src, method, path, body=None):
    return http(method, src["base"] + "/api/v1" + path, src["token"], body)


# ── Field normalization ───────────────────────────────────────────────────────

def ms(rfc3339):
    """RFC3339 → epoch ms; Vikunja's zero date ('0001-01-01…') / '' → 0."""
    s = (rfc3339 or "").strip()
    if not s or s.startswith("0001-01-01"):
        return 0
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)
    except ValueError:
        return 0


def due_rfc3339(ymd):
    """YYYY-MM-DD → local NOON as RFC3339 (noon avoids day flips across TZs);
    '' → Vikunja's zero date (clears the due)."""
    if not ymd:
        return "0001-01-01T00:00:00Z"
    d = datetime.strptime(ymd, "%Y-%m-%d").replace(hour=12).astimezone()
    return d.isoformat()


def shape_project(p):
    color = (p.get("hex_color") or "").strip()
    return {"id": p.get("id", 0),
            "title": p.get("title") or "(untitled)",
            "parentId": p.get("parent_project_id") or 0,
            "color": ("#" + color) if color and not color.startswith("#") else color,
            "description": p.get("description") or "",
            "archived": bool(p.get("is_archived")),
            "favorite": bool(p.get("is_favorite")),
            # Project background (upload provider): blurHash is an instant
            # placeholder; bgPath is filled by sync() after the JPEG is cached.
            "hasBg": bool(p.get("background_information")),
            "blurHash": p.get("background_blur_hash") or "",
            "bgPath": ""}


def hex_norm(c):
    """Normalize a colour to Vikunja's storage form: 6 hex digits, no '#'."""
    return (c or "").strip().lstrip("#")


def shape_label(lbl):
    return {"id": lbl.get("id", 0),
            "title": lbl.get("title") or "",
            "color": ("#" + hex_norm(lbl.get("hex_color"))) if lbl.get("hex_color") else ""}


def shape_task(t, parent_of):
    pct = t.get("percent_done") or 0
    return {"id": t.get("id", 0),
            "projectId": t.get("project_id") or 0,
            "title": t.get("title") or "(untitled)",
            "done": bool(t.get("done")),
            "doneMs": ms(t.get("done_at")),
            "dueMs": ms(t.get("due_date")),
            "priority": int(t.get("priority") or 0),
            "percentDone": int(round(pct * 100)) if pct <= 1 else int(pct),
            "parentId": parent_of.get(t.get("id", 0), 0),
            "notes": t.get("description") or "",
            "labels": [shape_label(l) for l in (t.get("labels") or [])],
            "recurring": bool(t.get("repeat_after")),
            "updatedMs": ms(t.get("updated"))}


def parent_map(raw_tasks):
    """task id → parent task id, from related_tasks.parenttask AND the inverse
    of related_tasks.subtask (either side may be the only one populated)."""
    parents = {}
    for t in raw_tasks:
        rel = t.get("related_tasks") or {}
        pts = rel.get("parenttask") or []
        if pts and isinstance(pts, list):
            pid = (pts[0] or {}).get("id")
            if pid:
                parents[t.get("id", 0)] = pid
        for sub in (rel.get("subtask") or []):
            sid = (sub or {}).get("id")
            if sid:
                parents.setdefault(sid, t.get("id", 0))
    return parents


def prune_done(tasks):
    horizon = (datetime.now().timestamp() - COMPLETED_KEEP_DAYS * 86400) * 1000
    return [t for t in tasks
            if not t["done"] or t["doneMs"] == 0 or t["doneMs"] >= horizon]


def sort_tasks(tasks):
    # Open before done; earlier due first (no due last); high priority first.
    tasks.sort(key=lambda t: (t["done"], t["dueMs"] or 2**62, -t["priority"], t["id"]))
    return tasks


# ── Fetching ──────────────────────────────────────────────────────────────────

def fetch_projects(src):
    _, projects, _ = api(src, "GET", "/projects")
    return projects or []


def fetch_labels(src):
    """All labels the user can attach to tasks (paginated like tasks)."""
    out, page, total = [], 1, 1
    while page <= total:
        _, chunk, hdrs = api(src, "GET", f"/labels?per_page={PER_PAGE}&page={page}")
        out.extend(chunk or [])
        try:
            total = max(1, int(hdrs.get("x-pagination-total-pages", "1")))
        except ValueError:
            total = 1
        page += 1
    return [shape_label(l) for l in out]


def cache_background(src, pid):
    """Download a project's background JPEG (GET /projects/{id}/background,
    Bearer) into BG_DIR/<id>.jpg once; return the local path (or "" on failure).
    Re-download only when the file is missing, so sync stays cheap."""
    path = os.path.join(BG_DIR, f"{pid}.jpg")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    url = src["base"] + f"/api/v1/projects/{pid}/background"
    req = urllib.request.Request(
        url, headers={"User-Agent": "velumeron-vikunja/1.0",
                      "Authorization": "Bearer " + src["token"]})
    try:
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            data = r.read()
        if not data:
            return ""
        os.makedirs(BG_DIR, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
        return path
    except (urllib.error.URLError, OSError):
        return ""


def fetch_project_tasks(src, pid):
    """All tasks of one project, following x-pagination-total-pages."""
    out, page, total = [], 1, 1
    while page <= total:
        _, chunk, hdrs = api(src, "GET",
                             f"/projects/{pid}/tasks?per_page={PER_PAGE}&page={page}")
        out.extend(chunk or [])
        try:
            total = max(1, int(hdrs.get("x-pagination-total-pages", "1")))
        except ValueError:
            total = 1
        page += 1
    return out


def shape_all(src, raw_projects, raw_tasks):
    projects = [shape_project(p) for p in raw_projects]
    projects = [p for p in projects if not p["archived"]]
    keep = {p["id"] for p in projects}
    parents = parent_map(raw_tasks)
    tasks = [shape_task(t, parents) for t in raw_tasks
             if (t.get("project_id") or 0) in keep]
    return projects, sort_tasks(prune_done(tasks))


def sync(cache):
    src = resolve_source()
    if src is None:
        cache["lastError"] = "no vikunja account (gui/vikunja.json or caldav account + ~/.config/vikunja/token)"
        cache["source"] = {"name": "", "base": "", "host": "", "ok": False}
        return cache
    raw_projects = fetch_projects(src)
    active = [p for p in raw_projects if not p.get("is_archived")]
    # One GET per project (+ one for labels) — sequentially that's ~25 round
    # trips to a remote host (~1s). They're all independent reads, so fan them
    # out; this is what made a fresh sync (and app launch) feel sluggish.
    with ThreadPoolExecutor(max_workers=8) as pool:
        task_futures = [pool.submit(fetch_project_tasks, src, p.get("id", 0)) for p in active]
        labels_future = pool.submit(fetch_labels, src)
        raw_tasks = [t for fut in task_futures for t in fut.result()]
        labels = labels_future.result()
    projects, tasks = shape_all(src, raw_projects, raw_tasks)
    bg_projects = [p for p in projects if p.get("hasBg")]
    if bg_projects:                          # cache background images once
        with ThreadPoolExecutor(max_workers=8) as pool:
            for p, path in zip(bg_projects, pool.map(lambda p: cache_background(src, p["id"]), bg_projects)):
                p["bgPath"] = path
    cache.update({
        "syncedAt": int(datetime.now().timestamp() * 1000),
        "lastError": "",
        "source": {"name": src["name"], "base": src["base"],
                   "host": src["host"], "ok": True},
        "projects": projects,
        "tasks": tasks,
        "labels": labels,
    })
    return cache


def _splice_task(cache, raw_task):
    """Splice ONE fresh task (as returned by a GET/POST /tasks/{id} response)
    into the cache — confirms an optimistic UI patch with the single response
    already in hand instead of a whole extra refresh_project() round trip
    (previously the dominant per-click latency: GET + POST + a paginated
    project-wide GET for e.g. a single checkbox toggle). Parent linkage is
    derived from THIS task's own related_tasks, which is exactly what a
    single-task mutation can change (its relations, not anyone else's)."""
    parents = parent_map([raw_task])
    fresh = shape_task(raw_task, parents)
    tasks = [t for t in cache.get("tasks", []) if t.get("id") != fresh["id"]]
    tasks.append(fresh)
    cache["tasks"] = sort_tasks(prune_done(tasks))
    cache["syncedAt"] = int(datetime.now().timestamp() * 1000)
    cache["lastError"] = ""
    return cache


# ── Mutations ─────────────────────────────────────────────────────────────────

def need_source():
    src = resolve_source()
    if src is None:
        raise RuntimeError("no vikunja account configured")
    return src


def add_task(cache, project_id, title, due_ymd="", parent_id=0):
    src = need_source()
    body = {"title": title}
    if due_ymd:
        body["due_date"] = due_rfc3339(due_ymd)
    _, created, _ = api(src, "PUT", f"/projects/{project_id}/tasks", body)
    created = created or {}
    new_id = created.get("id")
    if parent_id and new_id:
        api(src, "PUT", f"/tasks/{new_id}/relations",
            {"other_task_id": parent_id, "relation_kind": "parenttask"})
        # We just created this relation ourselves — inject it locally rather
        # than a third round trip to re-fetch and read it back. related_tasks
        # is `null` (not missing) on a freshly created task, so setdefault
        # wouldn't replace it — build the dict explicitly instead.
        created["related_tasks"] = {**(created.get("related_tasks") or {}),
                                     "parenttask": [{"id": parent_id}]}
    return _splice_task(cache, created)


def toggle_task(cache, task_id, done):
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    t["done"] = bool(done)
    _, updated, _ = api(src, "POST", f"/tasks/{task_id}", t)
    return _splice_task(cache, updated or t)


def delete_task(cache, task_id):
    src = need_source()
    api(src, "DELETE", f"/tasks/{task_id}")
    cache["tasks"] = [t for t in cache.get("tasks", []) if t.get("id") != task_id]
    cache["syncedAt"] = int(datetime.now().timestamp() * 1000)
    cache["lastError"] = ""
    return cache


def set_due(cache, task_id, due_ymd):
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    t["due_date"] = due_rfc3339(due_ymd)
    _, updated, _ = api(src, "POST", f"/tasks/{task_id}", t)
    return _splice_task(cache, updated or t)


def refresh_projects(cache, src):
    """Re-fetch the project list (+ backgrounds) and splice into the cache,
    keeping the task list (minus tasks of projects that vanished). Used after
    project CRUD, where tasks are unaffected but the tree changed."""
    raw = fetch_projects(src)
    projects = [shape_project(p) for p in raw if not p.get("is_archived")]
    for p in projects:
        if p.get("hasBg"):
            p["bgPath"] = cache_background(src, p["id"])
    keep = {p["id"] for p in projects}
    cache["projects"] = projects
    cache["tasks"] = [t for t in cache.get("tasks", []) if t.get("projectId") in keep]
    cache["syncedAt"] = int(datetime.now().timestamp() * 1000)
    cache["lastError"] = ""
    return cache


def add_project(cache, title, parent_id=0, color="", description=""):
    src = need_source()
    body = {"title": title}
    if color:
        body["hex_color"] = hex_norm(color)
    if parent_id:
        body["parent_project_id"] = int(parent_id)
    if description:
        body["description"] = description
    api(src, "PUT", "/projects", body)
    return refresh_projects(cache, src)


def update_project(cache, project_id, patch):
    """patch keys (all optional): title, color, description, parentId."""
    src = need_source()
    _, p, _ = api(src, "GET", f"/projects/{project_id}")
    p = p or {}
    if "title" in patch:
        p["title"] = patch["title"]
    if "color" in patch:
        p["hex_color"] = hex_norm(patch["color"])
    if "description" in patch:
        p["description"] = patch["description"]
    if "parentId" in patch:
        p["parent_project_id"] = int(patch["parentId"] or 0)
    api(src, "POST", f"/projects/{project_id}", p)
    return refresh_projects(cache, src)


def delete_project(cache, project_id):
    src = need_source()
    api(src, "DELETE", f"/projects/{project_id}")
    return refresh_projects(cache, src)


def update_task(cache, task_id, patch):
    """patch keys (all optional): title, notes, priority, dueYmd."""
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    if "title" in patch:
        t["title"] = patch["title"]
    if "notes" in patch:
        t["description"] = patch["notes"]
    if "priority" in patch:
        t["priority"] = int(patch["priority"] or 0)
    if "dueYmd" in patch:
        t["due_date"] = due_rfc3339(patch["dueYmd"])
    _, updated, _ = api(src, "POST", f"/tasks/{task_id}", t)
    return _splice_task(cache, updated or t)


def move_task(cache, task_id, new_project_id):
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    t["project_id"] = int(new_project_id)
    _, updated, _ = api(src, "POST", f"/tasks/{task_id}", t)
    return _splice_task(cache, updated or t)


def set_labels(cache, task_id, desired_ids):
    """Reconcile a task's labels to exactly `desired_ids` (add missing, drop
    extra), then splice the confirmed task back into the cache."""
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    current = {(l or {}).get("id") for l in (t.get("labels") or []) if l}
    desired = {int(x) for x in desired_ids}
    for lid in desired - current:
        api(src, "PUT", f"/tasks/{task_id}/labels", {"label_id": lid})
    for lid in current - desired:
        api(src, "DELETE", f"/tasks/{task_id}/labels/{lid}")
    _, updated, _ = api(src, "GET", f"/tasks/{task_id}")
    return _splice_task(cache, updated or t)


def add_label(cache, title, color=""):
    src = need_source()
    body = {"title": title}
    if color:
        body["hex_color"] = hex_norm(color)
    api(src, "PUT", "/labels", body)
    cache["labels"] = fetch_labels(src)
    return cache


# ── Dispatch ──────────────────────────────────────────────────────────────────

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "load"
    args = sys.argv[2:]
    cache = load_cache()
    try:
        if cmd == "load":
            pass
        elif cmd == "sync":
            cache = sync(cache)
            save_cache(cache)
        elif cmd == "add-task":
            due = args[2] if len(args) > 2 else ""
            parent = int(args[3]) if len(args) > 3 and args[3] else 0
            cache = add_task(cache, int(args[0]), args[1], due, parent)
            save_cache(cache)
        elif cmd == "toggle-task":
            cache = toggle_task(cache, int(args[0]), args[1] == "1")
            save_cache(cache)
        elif cmd == "delete-task":
            cache = delete_task(cache, int(args[0]))
            save_cache(cache)
        elif cmd == "set-due":
            cache = set_due(cache, int(args[0]), args[1] if len(args) > 1 else "")
            save_cache(cache)
        elif cmd == "add-project":
            parent = int(args[1]) if len(args) > 1 and args[1] else 0
            color = args[2] if len(args) > 2 else ""
            desc = args[3] if len(args) > 3 else ""
            cache = add_project(cache, args[0], parent, color, desc)
            save_cache(cache)
        elif cmd == "update-project":
            cache = update_project(cache, int(args[0]), json.loads(args[1]))
            save_cache(cache)
        elif cmd == "delete-project":
            cache = delete_project(cache, int(args[0]))
            save_cache(cache)
        elif cmd == "update-task":
            cache = update_task(cache, int(args[0]), json.loads(args[1]))
            save_cache(cache)
        elif cmd == "move-task":
            cache = move_task(cache, int(args[0]), int(args[1]))
            save_cache(cache)
        elif cmd == "set-labels":
            cache = set_labels(cache, int(args[0]), json.loads(args[1]))
            save_cache(cache)
        elif cmd == "add-label":
            cache = add_label(cache, args[0], args[1] if len(args) > 1 else "")
            save_cache(cache)
        else:
            cache["lastError"] = f"unknown command: {cmd}"
    except Exception as exc:                                    # noqa: BLE001
        cache["lastError"] = str(exc)
    emit(cache)


if __name__ == "__main__":
    main()
