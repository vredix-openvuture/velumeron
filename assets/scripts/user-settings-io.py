#!/usr/bin/env python3
"""user-settings-io — the single GUI⇄Lua bridge for user_settings.lua.

user_settings.lua holds the device-specific Hyprland config in marker-delimited
sections (-- <<<NAME-START>>> / -- <<<NAME-END>>>). The settings GUI and the
onboarding wizard never touch the Lua file directly — they talk JSON to this
script, which rewrites exactly one section at a time and leaves every byte
outside the target section untouched.

Verbs:
  get <section>|all            print the section as JSON
  set <section> [--no-reload]  read JSON from stdin, rewrite the section,
                               then `hyprctl reload` (unless --no-reload)
  validate <section>           read JSON from stdin, print {"ok":…,"errors":[…]}
  init                         create a marker-complete skeleton if missing
  reload                       hyprctl reload (for batching several `set`s)

Sections: monitors workspaces autostart quickaccess peripherals windowrules roleapps

Exit codes: 0 ok · 2 usage · 3 validation/parse error · 4 markers damaged
(a START without its END aborts before anything is written — the bash
write_section in .setup/hyprland.sh would silently eat the rest of the file
in that case; this script must never do that).
"""

import json
import os
import re
import subprocess
import sys

SECTIONS = ("monitors", "workspaces", "autostart", "quickaccess",
            "peripherals", "windowrules", "roleapps")

# Utility workspaces owned by the system (lockscreen uses 111/112, see
# assets/scripts/launch-hyprlock.sh) — never exposed to the GUI, always
# preserved on write.
RESERVED_WS = ("10", "90", "99", "111", "112", "1111")

ROLEAPP_KEYS = (
    "terminal", "browser", "browser_float", "filemanager", "messenger",
    "player", "notes_app", "clock_app", "mail_app", "calendar_app",
    "tasks_app", "editor_app", "wifi_menu", "bluetooth_menu", "vpn_toggle",
    "audio_switch", "mic_mute", "night_light", "dnd_toggle", "screen_record",
    "bitwarden",
)

FN_KEYS = ("brightness_up", "brightness_down", "play_stop_play", "play_next",
           "play_prev", "volume_up", "volume_down", "volume_mute")

# Tolerates the historic 3-dash variant (the shipped file contains
# `--- <<<MONITORS-END>>>`); rewrites always emit the canonical 2-dash form.
MARKER = re.compile(r"^-{2,3}\s*<<<([A-Z]+)-(START|END)>>>\s*$")
QSTR = r'"((?:[^"\\]|\\.)*)"'


def user_dir():
    d = os.environ.get("VELUMERON_USER_DIR")
    if d:
        return d
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "velumeron")


def settings_path():
    return os.path.join(user_dir(), "hypr.lua", "user_settings.lua")


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def lua_quote(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_unquote(s):
    return re.sub(r"\\(.)", r"\1", s)


def numfmt(v):
    f = float(v)
    return str(int(f)) if f == int(f) else ("%g" % f)


# ── File / marker plumbing ───────────────────────────────────────────────────


def read_lines():
    p = settings_path()
    if not os.path.exists(p):
        return None
    with open(p, "r", encoding="utf-8") as f:
        return f.read().split("\n")


def find_section(lines, name):
    """Return (start_idx, end_idx) of the marker lines, or None if absent.
    Exits 4 if the section is damaged (START without END)."""
    start = end = None
    for i, ln in enumerate(lines):
        m = MARKER.match(ln)
        if not m or m.group(1) != name:
            continue
        if m.group(2) == "START" and start is None:
            start = i
        elif m.group(2) == "END" and start is not None:
            end = i
            break
    if start is not None and end is None:
        die(4, "section %s: START marker without END — refusing to touch the file" % name)
    if start is None:
        return None
    return (start, end)


def section_body(lines, name):
    span = find_section(lines, name)
    if span is None:
        return None
    return lines[span[0] + 1:span[1]]


def write_file(lines):
    p = settings_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, p)


def replace_section(name, body_lines):
    """Rewrite one section (markers normalized), append it if wholly absent."""
    lines = read_lines()
    if lines is None:
        die(4, "user_settings.lua not found — run `init` first")
    span = find_section(lines, name)
    block = ["-- <<<%s-START>>>" % name] + body_lines + ["-- <<<%s-END>>>" % name]
    if span is None:
        # Section never existed (e.g. ROLEAPPS on older installs) — append it.
        while lines and lines[-1].strip() == "":
            lines.pop()
        lines += ["", ""] + block + [""]
    else:
        lines = lines[:span[0]] + block + lines[span[1] + 1:]
    write_file(lines)


# ── Section parsers (Lua → JSON) ─────────────────────────────────────────────


def parse_monitors(body):
    text = "\n".join(body)
    vars_ = {}
    for m in re.finditer(r'^mon(\d+)\s*=\s*' + QSTR, text, re.M):
        vars_[lua_unquote(m.group(2))] = "mon" + m.group(1)
    mons = []
    for block in re.finditer(r"hl\.monitor\s*\(\s*\{(.*?)\}\s*\)", text, re.S):
        b = block.group(1)

        def fstr(key, default=""):
            m = re.search(r"%s\s*=\s*%s" % (key, QSTR), b)
            return lua_unquote(m.group(1)) if m else default

        def fraw(key, default):
            m = re.search(r"%s\s*=\s*([^,\n}]+)" % key, b)
            return m.group(1).strip() if m else default

        out = fstr("output")
        mons.append({
            "var": vars_.get(out, ""),
            "output": out,
            "mode": fstr("mode"),
            "transform": int(fraw("transform", "0")),
            "position": fstr("position", "auto"),
            "scale": float(fraw("scale", "1")),
            "bitdepth": int(fraw("bitdepth", "10")),
            "supports_hdr": fraw("supports_hdr", "false") == "true",
            "vrr": int(fraw("vrr", "0")),
            "cm": fstr("cm", "auto"),
            # SDR content mapping while the display runs in HDR (cm = "hdr"):
            # without these the whole desktop looks dim and washed out.
            "sdrbrightness": float(fraw("sdrbrightness", "1")),
            "sdrsaturation": float(fraw("sdrsaturation", "1")),
        })
    # Array order = var order (mon1 first); unmapped outputs keep file order.
    mons.sort(key=lambda m: int(m["var"][3:]) if m["var"].startswith("mon") else 99)
    return {"monitors": mons}


def parse_workspaces(body):
    rules = []
    for ln in body:
        if "hl.workspace_rule" not in ln:
            continue
        m = re.search(r"workspace\s*=\s*" + QSTR, ln)
        mon = re.search(r"monitor\s*=\s*([A-Za-z_][A-Za-z0-9_]*)", ln)
        if not m or not mon:
            continue
        name = re.search(r"default_name\s*=\s*" + QSTR, ln)
        layout = re.search(r"layout\s*=\s*" + QSTR, ln)
        rules.append({
            "workspace": lua_unquote(m.group(1)),
            "monitor": mon.group(1),
            "persistent": bool(re.search(r"persistent\s*=\s*true", ln)),
            "default": bool(re.search(r"default\s*=\s*true", ln)),
            "default_name": lua_unquote(name.group(1)) if name else "",
            "layout": lua_unquote(layout.group(1)) if layout else "",
        })
    reserved = [r for r in rules if r["workspace"] in RESERVED_WS]
    rules = [r for r in rules if r["workspace"] not in RESERVED_WS]
    return {"rules": rules, "reserved": reserved}


def parse_autostart(body):
    text = "\n".join(body)
    daemons = []
    m = re.search(r"exec_once_daemons\s*=\s*\{(.*?)\n\}", text, re.S)
    if m:
        daemons = [lua_unquote(x.group(1)) for x in re.finditer(QSTR, m.group(1))]
    start_apps = []
    m = re.search(r"start_apps\s*=\s*\{(.*?)\n\}", text, re.S)
    if m:
        for row in re.finditer(r"\{\s*app\s*=\s*%s\s*,\s*ws\s*=\s*(\d+)" % QSTR, m.group(1)):
            app = lua_unquote(row.group(1))
            if app:
                start_apps.append({"app": app, "ws": int(row.group(2))})
    return {"daemons": daemons, "start_apps": start_apps}


def parse_quickaccess(body):
    apps = [""] * 12
    for m in re.finditer(r"\[\s*(\d+)\s*\]\s*=\s*" + QSTR, "\n".join(body)):
        i = int(m.group(1))
        if 1 <= i <= 12:
            apps[i - 1] = lua_unquote(m.group(2))
    return {"apps": apps}


def parse_peripherals(body):
    text = "\n".join(body)

    def fstr(key, default=""):
        m = re.search(r"^%s\s*=\s*%s" % (key, QSTR), text, re.M)
        return lua_unquote(m.group(1)) if m else default

    size = re.search(r"^cur_size\s*=\s*(\d+)", text, re.M)
    return {
        "cursor": {"theme": fstr("cur_theme"), "size": int(size.group(1)) if size else 24},
        "fn": {k: fstr("fn_" + k) for k in FN_KEYS},
    }


def parse_windowrules(body):
    text = "\n".join(body)

    def fstr(key):
        m = re.search(r"^%s\s*=\s*%s" % (key, QSTR), text, re.M)
        return lua_unquote(m.group(1)) if m else ""

    return {"floating_window": fstr("floating_window"), "opacity_window": fstr("opacity_window")}


def parse_roleapps(body):
    apps, raw = {}, {}
    for ln in body:
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", ln)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        qs = re.fullmatch(QSTR, val)
        if qs is not None:
            apps[key] = lua_unquote(qs.group(1))
        else:
            # Lua expression (e.g. VTL_DIR .. "…") — round-tripped verbatim,
            # shown read-only in the GUI.
            raw[key] = val
    return {"apps": apps, "raw": raw}


PARSERS = {
    "monitors": parse_monitors,
    "workspaces": parse_workspaces,
    "autostart": parse_autostart,
    "quickaccess": parse_quickaccess,
    "peripherals": parse_peripherals,
    "windowrules": parse_windowrules,
    "roleapps": parse_roleapps,
}

EMPTY = {
    "monitors": {"monitors": []},
    "workspaces": {"rules": [], "reserved": []},
    "autostart": {"daemons": [], "start_apps": []},
    "quickaccess": {"apps": [""] * 12},
    "peripherals": {"cursor": {"theme": "", "size": 24}, "fn": {k: "" for k in FN_KEYS}},
    "windowrules": {"floating_window": "", "opacity_window": ""},
    "roleapps": {"apps": {}, "raw": {}},
}


# ── Validation ───────────────────────────────────────────────────────────────

MODE_RE = re.compile(r"^\d+x\d+@\d+(\.\d+)?$")
POS_RE = re.compile(r"^(auto|-?\d+x-?\d+)$")


def validate_monitors(data):
    errors = []
    mons = data.get("monitors", [])
    if not mons:
        errors.append("at least one monitor is required")
    outs = [m.get("output", "") for m in mons]
    if len(set(outs)) != len(outs) or "" in outs:
        errors.append("monitor outputs must be unique and non-empty")
    for m in mons:
        o = m.get("output", "?")
        if not MODE_RE.match(str(m.get("mode", ""))):
            errors.append("%s: mode must look like 2560x1440@165" % o)
        if not 0 <= int(m.get("transform", 0)) <= 7:
            errors.append("%s: transform must be 0–7" % o)
        if not 0.25 <= float(m.get("scale", 1)) <= 4:
            errors.append("%s: scale must be within 0.25–4" % o)
        if not POS_RE.match(str(m.get("position", "auto"))):
            errors.append("%s: position must be XxY or auto" % o)
        if not 0.5 <= float(m.get("sdrbrightness", 1)) <= 3:
            errors.append("%s: sdrbrightness must be within 0.5–3" % o)
        if not 0.5 <= float(m.get("sdrsaturation", 1)) <= 2:
            errors.append("%s: sdrsaturation must be within 0.5–2" % o)
    return errors


def validate_workspaces(data, monitors_json=None):
    errors = []
    rules = data.get("rules", [])
    nums = [str(r.get("workspace", "")) for r in rules]
    if len(set(nums)) != len(nums):
        errors.append("workspace numbers must be unique")
    known_vars = None
    if monitors_json is not None:
        known_vars = {m["var"] for m in monitors_json.get("monitors", []) if m.get("var")}
    for r in rules:
        n = str(r.get("workspace", ""))
        if not n.isdigit():
            errors.append("workspace %r: not a number" % n)
        elif n in RESERVED_WS:
            errors.append("workspace %s is reserved for the system" % n)
        if known_vars is not None and r.get("monitor") not in known_vars:
            errors.append("workspace %s: unknown monitor %r" % (n, r.get("monitor")))
    return errors


def validate_autostart(data):
    errors = []
    for r in data.get("start_apps", []):
        ws = r.get("ws")
        if not (isinstance(ws, int) and 1 <= ws <= 9999):
            errors.append("start app %r: invalid workspace %r" % (r.get("app", ""), ws))
    return errors


def validate_quickaccess(data):
    apps = data.get("apps", [])
    return [] if isinstance(apps, list) and len(apps) <= 12 else ["apps must be a list of at most 12 commands"]


def validate_peripherals(data):
    errors = []
    size = data.get("cursor", {}).get("size", 24)
    if not (isinstance(size, int) and 8 <= size <= 128):
        errors.append("cursor size must be 8–128")
    return errors


def validate_windowrules(data):
    errors = []
    for key in ("floating_window", "opacity_window"):
        pat = data.get(key, "")
        if not pat:
            continue
        try:
            re.compile(pat)
        except re.error as e:
            errors.append("%s: %s (warning — Hyprland may still accept it)" % (key, e))
    return errors


def validate_roleapps(data):
    apps = data.get("apps", {})
    return [] if isinstance(apps, dict) else ["apps must be an object"]


VALIDATORS = {
    "monitors": validate_monitors,
    "workspaces": validate_workspaces,
    "autostart": validate_autostart,
    "quickaccess": validate_quickaccess,
    "peripherals": validate_peripherals,
    "windowrules": validate_windowrules,
    "roleapps": validate_roleapps,
}


# ── Section emitters (JSON → Lua) ────────────────────────────────────────────


def emit_monitors(data):
    mons = data.get("monitors", [])
    out = []
    for i, m in enumerate(mons):
        # Format is load-bearing: launch-hyprlock.sh greps ^mon1 = "…",
        # apply-hyprlock-theme.sh substitutes {{mon1}}/{{mon2}}.
        out.append('mon%d = %s' % (i + 1, lua_quote(m["output"])))
    for i, m in enumerate(mons):
        out += [
            "",
            "hl.monitor({",
            "    output       = %s," % lua_quote(m["output"]),
            "    mode         = %s," % lua_quote(m["mode"]),
            "    transform    = %d," % int(m.get("transform", 0)),
            "    position     = %s," % lua_quote(m.get("position", "auto")),
            "    scale        = %s," % numfmt(m.get("scale", 1)),
            "    bitdepth     = %d," % int(m.get("bitdepth", 10)),
            "    supports_hdr = %s," % ("true" if m.get("supports_hdr") else "false"),
            "    vrr          = %d," % int(m.get("vrr", 0)),
            "    cm           = %s," % lua_quote(m.get("cm", "auto")),
        ] + (
            ["    sdrbrightness = %s," % numfmt(m["sdrbrightness"])]
            if float(m.get("sdrbrightness", 1)) != 1.0 else []
        ) + (
            ["    sdrsaturation = %s," % numfmt(m["sdrsaturation"])]
            if float(m.get("sdrsaturation", 1)) != 1.0 else []
        ) + [
            "})",
        ]
    return out


def ws_rule_line(r):
    tok = '%s,' % lua_quote(str(r["workspace"]))
    line = "hl.workspace_rule({ workspace = %s monitor = %s, persistent = %s" % (
        tok.ljust(8), r["monitor"], "true" if r.get("persistent") else "false")
    if r.get("default_name"):
        line += ", default_name = %s" % lua_quote(r["default_name"])
    if r.get("default"):
        line += ", default = true"
    if r.get("layout"):
        line += ", layout = %s" % lua_quote(r["layout"])
    return line + " })"


def emit_workspaces(data):
    rules = sorted(data.get("rules", []), key=lambda r: int(r["workspace"]))
    out = []
    prev = None
    for r in rules:
        if r["monitor"] != prev:
            if prev is not None:
                out.append("")
            out.append("-- %s" % r["monitor"])
            prev = r["monitor"]
        out.append(ws_rule_line(r))
    reserved = data.get("reserved", [])
    if reserved:
        if out:
            out.append("")
        out.append("-- Special / utility workspaces")
        for r in sorted(reserved, key=lambda r: int(r["workspace"])):
            out.append(ws_rule_line(r))
    return out


def emit_autostart(data):
    out = ["exec_once_daemons = {"]
    out += ["    %s," % lua_quote(d) for d in data.get("daemons", []) if d]
    out += ["}", "", "-- { app = command, ws = workspace_number }", "start_apps = {"]
    out += ["    { app = %s, ws = %d }," % (lua_quote(r["app"]), int(r["ws"]))
            for r in data.get("start_apps", []) if r.get("app")]
    out += ["}"]
    return out


def emit_quickaccess(data):
    apps = (list(data.get("apps", [])) + [""] * 12)[:12]
    out = ["quick_app = {"]
    for i, app in enumerate(apps, 1):
        out.append("    %s = %s," % (("[%d]" % i).ljust(4), lua_quote(app)))
    out += ["}"]
    return out


def emit_peripherals(data):
    cur = data.get("cursor", {})
    fn = data.get("fn", {})
    out = [
        "cur_theme = %s" % lua_quote(cur.get("theme", "")),
        "cur_size  = %d" % int(cur.get("size", 24)),
        "",
    ]
    for k in FN_KEYS:
        out.append("%s = %s" % (("fn_" + k).ljust(18), lua_quote(fn.get(k, ""))))
    return out


def emit_windowrules(data):
    return [
        "floating_window = %s" % lua_quote(data.get("floating_window", "")),
        "opacity_window  = %s" % lua_quote(data.get("opacity_window", "")),
    ]


def emit_roleapps(data):
    apps = data.get("apps", {})
    raw = data.get("raw", {})
    out = []
    # Empty values are OMITTED on purpose: `""` is truthy in Lua, so an empty
    # assignment would permanently defeat the `x = x or _first_of(...)`
    # auto-detect fallbacks in hypr.lua/modules/variables.lua.
    for key in ROLEAPP_KEYS:
        if apps.get(key):
            out.append("%s = %s" % (key.ljust(16), lua_quote(apps[key])))
    for key, val in apps.items():
        if key not in ROLEAPP_KEYS and val:
            out.append("%s = %s" % (key.ljust(16), lua_quote(val)))
    for key, val in raw.items():
        out.append("%s = %s" % (key.ljust(16), val))
    return out


EMITTERS = {
    "monitors": emit_monitors,
    "workspaces": emit_workspaces,
    "autostart": emit_autostart,
    "quickaccess": emit_quickaccess,
    "peripherals": emit_peripherals,
    "windowrules": emit_windowrules,
    "roleapps": emit_roleapps,
}


# ── set glue ─────────────────────────────────────────────────────────────────


def get_section(name):
    lines = read_lines()
    if lines is None:
        return dict(EMPTY[name])
    body = section_body(lines, name.upper())
    if body is None:
        return dict(EMPTY[name])
    return PARSERS[name](body)


def fix_workspaces(data, monitor_vars):
    """Normalize a workspaces payload in place: strip reserved numbers from
    the editable rules, enforce one default per monitor, remap dangling
    monitor vars, and make sure the lockscreen workspaces 111/112 exist."""
    rules = [r for r in data.get("rules", []) if str(r.get("workspace")) not in RESERVED_WS]
    fallback = monitor_vars[0] if monitor_vars else "mon1"
    for r in rules:
        if r.get("monitor") not in monitor_vars:
            r["monitor"] = fallback
    per_mon = {}
    for r in rules:
        per_mon.setdefault(r["monitor"], []).append(r)
    for mon, rs in per_mon.items():
        defaults = [r for r in rs if r.get("default")]
        if not defaults:
            min(rs, key=lambda r: int(r["workspace"]))["default"] = True
        else:
            for r in defaults[1:]:
                r["default"] = False
    reserved = {str(r["workspace"]): r for r in get_section("workspaces").get("reserved", [])}
    for r in reserved.values():
        if r.get("monitor") not in monitor_vars:
            r["monitor"] = fallback
    if "111" not in reserved:
        reserved["111"] = {"workspace": "111", "monitor": fallback, "persistent": False,
                           "default": False, "default_name": "", "layout": ""}
    if "112" not in reserved and len(monitor_vars) > 1:
        reserved["112"] = {"workspace": "112", "monitor": monitor_vars[1], "persistent": False,
                           "default": False, "default_name": "", "layout": ""}
    data["rules"] = rules
    data["reserved"] = list(reserved.values())
    return data


def hyprctl(*args):
    try:
        r = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def set_section(name, data, reload_after):
    validator = VALIDATORS[name]
    if name == "workspaces":
        mons = get_section("monitors")
        data = fix_workspaces(data, [m["var"] for m in mons.get("monitors", []) if m.get("var")])
        errors = validator(data, mons)
    else:
        errors = validator(data)
    if errors:
        print(json.dumps({"ok": False, "errors": errors}))
        sys.exit(3)

    replace_section(name.upper(), EMITTERS[name](data))

    if name == "monitors":
        # Dropping a monitor must not leave workspace rules pointing at a
        # now-undefined Lua var (hl.workspace_rule would see monitor = nil).
        vars_ = ["mon%d" % (i + 1) for i in range(len(data.get("monitors", [])))]
        ws = get_section("workspaces")
        fixed = fix_workspaces(ws, vars_)
        replace_section("WORKSPACES", EMITTERS["workspaces"](fixed))
    if name == "peripherals":
        cur = data.get("cursor", {})
        if cur.get("theme"):
            hyprctl("setcursor", cur["theme"], str(int(cur.get("size", 24))))

    if reload_after and not hyprctl("reload"):
        print(json.dumps({"ok": True, "warning": "hyprctl reload failed — changes apply on next reload"}))
        return
    print(json.dumps({"ok": True}))


# ── init skeleton ────────────────────────────────────────────────────────────

SKELETON = """\
-- ════════════════════════════════════════════════════════════════════════
--
--  USER SETTINGS — Device-specific settings.
--  Managed by the settings GUI (user-settings-io.py). Not in git.
--
-- ════════════════════════════════════════════════════════════════════════


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  MONITORS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<MONITORS-START>>>
-- <<<MONITORS-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  WORKSPACES
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<WORKSPACES-START>>>
-- <<<WORKSPACES-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  PERIPHERALS
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<PERIPHERALS-START>>>
cur_theme = "Oxygen"
cur_size  = 24

fn_brightness_up   = "F2"
fn_brightness_down = "F1"
fn_play_stop_play  = "F8"
fn_play_next       = "F9"
fn_play_prev       = "F7"
fn_volume_up       = "F12"
fn_volume_down     = "F11"
fn_volume_mute     = "F10"
-- <<<PERIPHERALS-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  QUICK ACCESS APPS  (index = key number)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<QUICKACCESS-START>>>
quick_app = {
    [1]  = "",
    [2]  = "",
    [3]  = "",
    [4]  = "",
    [5]  = "",
    [6]  = "",
    [7]  = "",
    [8]  = "",
    [9]  = "",
    [10] = "",
    [11] = "",
    [12] = "",
}
-- <<<QUICKACCESS-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  AUTOSTART — Device daemons & workspace startup apps
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<AUTOSTART-START>>>
exec_once_daemons = {
}

-- { app = command, ws = workspace_number }
start_apps = {
}
-- <<<AUTOSTART-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  WINDOW RULE VARIABLES
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<WINDOWRULES-START>>>
floating_window = "(.*kitty.*|.*ark.*|.*bitwarden.*)"
opacity_window  = "(.*obsidian.*)"
-- <<<WINDOWRULES-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Look and Feel — overrides for hypr.lua defaults. Leave a value unset
-- (commented / absent) to fall back to the default in look_and_feel.lua.
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<LOOKANDFEEL-START>>>
-- <<<LOOKANDFEEL-END>>>


-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ROLE APPS & SYSTEM COMMANDS — set per device, not in git.
--  Unset keys fall back to auto-detection in modules/variables.lua —
--  never assign "" here (empty strings defeat the fallback).
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <<<ROLEAPPS-START>>>
mic_mute         = "pactl set-source-mute @DEFAULT_SOURCE@ toggle"
dnd_toggle       = VTL_DIR .. "/bin/velumeron --dnd"
bitwarden        = "bitwarden"
-- <<<ROLEAPPS-END>>>
"""


def verb_init():
    p = settings_path()
    if os.path.exists(p):
        print("exists")
        return
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(SKELETON)
    os.replace(tmp, p)
    print("created")


# ── main ─────────────────────────────────────────────────────────────────────


def read_stdin_json():
    try:
        return json.loads(sys.stdin.read())
    except ValueError as e:
        die(3, "invalid JSON on stdin: %s" % e)


def main():
    args = sys.argv[1:]
    if not args:
        die(2, __doc__)
    verb = args[0]

    if verb == "init":
        verb_init()
    elif verb == "reload":
        print(json.dumps({"ok": hyprctl("reload")}))
    elif verb == "get":
        if len(args) < 2:
            die(2, "usage: get <section>|all")
        if args[1] == "all":
            print(json.dumps({s: get_section(s) for s in SECTIONS}, ensure_ascii=False))
        elif args[1] in SECTIONS:
            print(json.dumps(get_section(args[1]), ensure_ascii=False))
        else:
            die(2, "unknown section: %s" % args[1])
    elif verb == "set":
        if len(args) < 2 or args[1] not in SECTIONS:
            die(2, "usage: set <section> [--no-reload]")
        set_section(args[1], read_stdin_json(), "--no-reload" not in args[2:])
    elif verb == "validate":
        if len(args) < 2 or args[1] not in SECTIONS:
            die(2, "usage: validate <section>")
        data = read_stdin_json()
        if args[1] == "workspaces":
            errors = VALIDATORS["workspaces"](data, get_section("monitors"))
        else:
            errors = VALIDATORS[args[1]](data)
        print(json.dumps({"ok": not errors, "errors": errors}))
    else:
        die(2, "unknown verb: %s" % verb)


if __name__ == "__main__":
    main()
