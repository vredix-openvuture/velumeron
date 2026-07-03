#!/usr/bin/env python3
"""onboarding-state — first-run/update decision + CHANGELOG slicing for the onboarding GUI.

The shell calls `state` on boot and opens the onboarding window accordingly:
  first-run  fresh install (no version stamp AND no configured monitors) → setup wizard
  update     the package is newer than the stamp → "what's new" report from CHANGELOG.md
  none       up to date

Verbs:
  state       print {"mode", "current", "lastSeen", "changelog":[{version,date,body}]}
  mark-seen   stamp the current VERSION as seen (gui/last-seen-version)

Env override for testing: VELUMERON_ONBOARDING_FORCE=first-run|update|none.
"""

import json
import os
import re
import sys


def _dir(env, fallback):
    d = os.environ.get(env)
    return d if d else fallback


def repo_dir():
    here = os.path.dirname(os.path.realpath(__file__))
    return _dir("VELUMERON_DIR", os.path.abspath(os.path.join(here, "..", "..")))


def user_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return _dir("VELUMERON_USER_DIR", os.path.join(base, "velumeron"))


def stamp_path():
    return os.path.join(user_dir(), "gui", "last-seen-version")


def pending_path():
    """Flag written by welcome_to_velumeron.sh on a genuinely fresh install —
    the only reliable way to tell "fresh, monitors already auto-configured"
    apart from "existing install updating into the versioned world"."""
    return os.path.join(user_dir(), "gui", "first-run-pending")


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def current_version():
    return read_text(os.path.join(repo_dir(), "VERSION")).strip() or "0.0.0"


def vtuple(v):
    """Version as an int tuple; suffixes like -rc1 are ignored for ordering."""
    nums = re.findall(r"\d+", ("" + v).split("-")[0])
    return tuple(int(n) for n in nums) if nums else (0,)


def parse_changelog():
    """[{version, date, body}] in file order (newest first by convention)."""
    text = read_text(os.path.join(repo_dir(), "CHANGELOG.md"))
    out = []
    cur = None
    for line in text.split("\n"):
        m = re.match(r"^##\s*\[([^\]]+)\]\s*(?:[—–-]+\s*(.*))?$", line)
        if m:
            if cur:
                out.append(cur)
            cur = {"version": m.group(1).strip(), "date": (m.group(2) or "").strip(), "body": ""}
        elif cur is not None:
            cur["body"] += line + "\n"
    if cur:
        out.append(cur)
    for e in out:
        e["body"] = e["body"].strip()
    return out


def changelog_between(last_seen, current):
    lo, hi = vtuple(last_seen), vtuple(current)
    return [e for e in parse_changelog() if lo < vtuple(e["version"]) <= hi]


def has_configured_monitors():
    us = os.path.join(user_dir(), "hypr.lua", "user_settings.lua")
    return "hl.monitor" in read_text(us)


def verb_state():
    current = current_version()
    last_seen = read_text(stamp_path()).strip()
    force = os.environ.get("VELUMERON_ONBOARDING_FORCE", "")

    if force in ("first-run", "update", "none"):
        mode = force
        changelog = changelog_between("0", current) if force == "update" else []
    elif not last_seen and os.path.exists(pending_path()):
        mode, changelog = "first-run", []
    elif not last_seen and not has_configured_monitors():
        # No welcome marker but also nothing configured — manual/partial install.
        mode, changelog = "first-run", []
    elif not last_seen:
        # Existing install upgrading into the versioned world: show only the
        # current release, don't dump the whole history.
        mode = "update"
        changelog = [e for e in parse_changelog() if vtuple(e["version"]) == vtuple(current)]
    elif vtuple(last_seen) < vtuple(current):
        mode = "update"
        changelog = changelog_between(last_seen, current)
    else:
        mode, changelog = "none", []

    print(json.dumps({
        "mode": mode,
        "current": current,
        "lastSeen": last_seen,
        "changelog": changelog,
    }, ensure_ascii=False))


def verb_mark_seen():
    p = stamp_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(current_version() + "\n")
    os.replace(tmp, p)
    try:
        os.remove(pending_path())
    except OSError:
        pass
    print("ok")


def main():
    verb = sys.argv[1] if len(sys.argv) > 1 else ""
    if verb == "state":
        verb_state()
    elif verb == "mark-seen":
        verb_mark_seen()
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
