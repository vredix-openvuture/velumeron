#!/usr/bin/env python3
"""Vikunja REST client for the velumeron todo surfaces (stdlib only).

Sibling of caldav-client.py with the same contract: every command prints the
full JSON cache on stdout (single line) so the QML service (TodoService.qml)
and the velorganize bridge (todomodel.py) share one parse path. Where plain
CalDAV only offers flat VTODO lists, Vikunja's REST API adds the project TREE
(parent_project_id) and task→subtask relations — the whole reason this client
exists (see the unified todo model spec referenced in both consumers).

Commands:
  load                                       print the cache without touching the network
  sync                                       refresh projects + all tasks, write + print
  add-task <projectId> <title> [dueYMD] [parentTaskId]
  toggle-task <taskId> <0|1>
  delete-task <taskId>
  set-due <taskId> <dueYMD|"">               "" clears the due date

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
    projects:[{id,title,parentId,color,archived,favorite}],
    tasks:[{id,projectId,title,done,doneMs,dueMs,priority,percentDone,
            parentId,notes,updatedMs}] }
Ids are the raw Vikunja integers; consumers prefix them ("vk:16").
"""

import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
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
            "archived": bool(p.get("is_archived")),
            "favorite": bool(p.get("is_favorite"))}


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
    raw_tasks = []
    for p in raw_projects:
        if p.get("is_archived"):
            continue
        raw_tasks.extend(fetch_project_tasks(src, p.get("id", 0)))
    projects, tasks = shape_all(src, raw_projects, raw_tasks)
    cache.update({
        "syncedAt": int(datetime.now().timestamp() * 1000),
        "lastError": "",
        "source": {"name": src["name"], "base": src["base"],
                   "host": src["host"], "ok": True},
        "projects": projects,
        "tasks": tasks,
    })
    return cache


def refresh_project(cache, src, pid):
    """Re-fetch ONE project's tasks and splice them into the cache — mutations
    confirm the optimistic UI patch without a full sync. Parent relations are
    rebuilt from this project's raw tasks only (cross-project relations are
    rare enough to wait for the next full sync)."""
    raw = fetch_project_tasks(src, pid)
    parents = parent_map(raw)
    fresh = sort_tasks(prune_done([shape_task(t, parents) for t in raw]))
    others = [t for t in cache.get("tasks", []) if t.get("projectId") != pid]
    cache["tasks"] = sort_tasks(others + fresh)
    cache["syncedAt"] = int(datetime.now().timestamp() * 1000)
    cache["lastError"] = ""
    return cache


# ── Mutations ─────────────────────────────────────────────────────────────────

def need_source():
    src = resolve_source()
    if src is None:
        raise RuntimeError("no vikunja account configured")
    return src


def task_project(cache, src, task_id):
    """Project id of a task — from the cache, else one GET."""
    for t in cache.get("tasks", []):
        if t.get("id") == task_id:
            return t.get("projectId") or 0
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    return (t or {}).get("project_id") or 0


def add_task(cache, project_id, title, due_ymd="", parent_id=0):
    src = need_source()
    body = {"title": title}
    if due_ymd:
        body["due_date"] = due_rfc3339(due_ymd)
    _, created, _ = api(src, "PUT", f"/projects/{project_id}/tasks", body)
    new_id = (created or {}).get("id")
    if parent_id and new_id:
        api(src, "PUT", f"/tasks/{new_id}/relations",
            {"other_task_id": parent_id, "relation_kind": "parenttask"})
    return refresh_project(cache, src, project_id)


def toggle_task(cache, task_id, done):
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    t["done"] = bool(done)
    api(src, "POST", f"/tasks/{task_id}", t)
    return refresh_project(cache, src, t.get("project_id") or task_project(cache, src, task_id))


def delete_task(cache, task_id):
    src = need_source()
    pid = task_project(cache, src, task_id)
    api(src, "DELETE", f"/tasks/{task_id}")
    return refresh_project(cache, src, pid) if pid else cache


def set_due(cache, task_id, due_ymd):
    src = need_source()
    _, t, _ = api(src, "GET", f"/tasks/{task_id}")
    t = t or {}
    t["due_date"] = due_rfc3339(due_ymd)
    api(src, "POST", f"/tasks/{task_id}", t)
    return refresh_project(cache, src, t.get("project_id") or task_project(cache, src, task_id))


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
        else:
            cache["lastError"] = f"unknown command: {cmd}"
    except Exception as exc:                                    # noqa: BLE001
        cache["lastError"] = str(exc)
    emit(cache)


if __name__ == "__main__":
    main()
