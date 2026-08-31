#!/usr/bin/env python3
"""boot-theme.py — manage the boot chain's themes from Velumeron.

The shell, GTK and Qt all follow the wallust palette; everything BEFORE quickshell
starts does not. This is the one entry point for that stretch — Plymouth (boot
splash), GRUB (boot menu) and SDDM (login) — as a management surface, not a
one-shot installer:

    boot-theme.py status                   what is installed / active / selected  (JSON)
    boot-theme.py preview <comp> <theme>   path to a preview image, or nothing
    boot-theme.py generate [comp…]         (re)build the `velumeron` themes
    boot-theme.py apply <comp> <theme>     switch the component to <theme>   ← needs root
    boot-theme.py show <comp>              look at the theme now, without rebooting
    boot-theme.py doctor                   plain-text sanity report

<comp> is one of: plymouth · grub · sddm

Design notes
------------
• Unprivileged by default. `status`, `preview`, `generate` and `doctor` never need
  root: generation writes to $VELUMERON_USER_DIR/boot/, the listings read only
  world-readable directories. Only `apply` touches /etc, /usr/share and /boot, and
  it refuses to run unless it is actually root — the GUI sends it through
  term-run.sh so the sudo prompt is visible and framed, exactly like the bar's
  update module.

• À la carte. A component that is not installed is reported as unavailable with a
  reason instead of being conjured into existence; nothing here installs packages
  or switches your display manager.

• The `velumeron` theme of each component is generated from the SAME palette the shell
  reads, so the boot chain matches whatever the wallpaper last produced. It cannot
  follow it LIVE, though: the Plymouth theme lives inside the initramfs and GRUB reads
  its theme before any filesystem is up, so a palette change reaches them only through
  `generate` + a privileged `apply`. It is offered as one more entry in the theme list
  — never forced.
"""
import configparser
import io
import json
import math
import os
import re
import shutil
import subprocess
import time
import sys
from pathlib import Path

HOME = Path.home()
CFG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))

VELUMERON_DIR = Path(os.environ.get(
    "VELUMERON_DIR", Path(__file__).resolve().parent.parent.parent))
USER_DIR = Path(os.environ.get("VELUMERON_USER_DIR", CFG / "velumeron"))

# Where `generate` puts its output. Root-free by construction: apply() copies from
# here into the system directory when the velumeron theme is the one being picked.
STAGE = USER_DIR / "boot"

GENERATED = "velumeron"          # the name the generated theme carries everywhere
COMPONENTS = ("plymouth", "grub", "sddm")

# When run as root through sudo, $HOME/XDG point at root's own dirs — but the
# palette and the staged themes live in the INVOKING user's home. Re-anchor.
if os.geteuid() == 0 and os.environ.get("SUDO_USER"):
    try:
        import pwd
        _pw = pwd.getpwnam(os.environ["SUDO_USER"])
        _uhome = Path(_pw.pw_dir)
        if "VELUMERON_USER_DIR" not in os.environ:
            USER_DIR = _uhome / ".config/velumeron"
            STAGE = USER_DIR / "boot"
        CACHE = _uhome / ".cache"
    except (KeyError, ImportError):
        pass


# ── palette ──────────────────────────────────────────────────────────────────
FALLBACK = {
    "background": "#020300", "foreground": "#F6CF8D",
    "color0": "#020401", "color1": "#4F5441", "color2": "#795443", "color3": "#427782",
    "color4": "#A55D38", "color5": "#4D9387", "color6": "#BE944B", "color7": "#E8C281",
    "color8": "#9F7E44", "color15": "#EBD8B8",
}


def load_palette():
    """The live palette, by the same precedence the shell uses."""
    for p in (USER_DIR / "quickshell/colors.json", CACHE / "wallust/colors.json"):
        try:
            d = json.loads(p.read_text())
            if isinstance(d.get("color0"), str):
                out = dict(FALLBACK)
                out.update({k: v for k, v in d.items() if isinstance(v, str)})
                return out
        except (OSError, ValueError):
            continue
    return dict(FALLBACK)


def rgb(h):
    h = (h or "").lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        return (0, 0, 0)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(t):
    return "#" + "".join("%02x" % max(0, min(255, round(c))) for c in t)


def mix(a, b, t):
    ra, rb = rgb(a), rgb(b)
    return hexs(tuple(ra[i] + (rb[i] - ra[i]) * t for i in range(3)))


def roles(pal):
    """The shell's semantic roles (Colors.qml)."""
    return {
        "bg":      pal.get("color0", FALLBACK["color0"]),        # bgPrimary
        "element": pal.get("color1", FALLBACK["color1"]),        # bgElement
        "accent":  pal.get("color3", FALLBACK["color3"]),        # bgActive
        "border":  pal.get("color5", FALLBACK["color5"]),        # boNormal
        "fg":      pal.get("color7", FALLBACK["color7"]),        # fgPrimary
        "muted":   pal.get("color8", FALLBACK["color8"]),        # fgMuted
        "bright":  pal.get("color15", FALLBACK["color15"]),      # fgBright
    }


# ── fallback colours ─────────────────────────────────────────────────────────
# The boot themes follow the LIVE wallust palette (see boot_roles). This set is only
# what they fall back to when no colors.json can be read — the Velumeron brand purple,
# with `accent` sampled from the logo itself so colour and artwork cannot drift apart.
BRAND = {
    "bg":      "#0D0716",   # gradient top — near-black with a purple cast
    "bg2":     "#2A1A55",   # gradient foot — the "slightly purple" wash
    "element": "#1E1236",   # card / raised surface
    "accent":  "#482898",   # THE Velumeron purple
    "glow":    "#7A54D8",   # lifted accent for highlights and the sweep
    "border":  "#5B3AA8",
    "fg":      "#E4DCF2",
    "muted":   "#9F8FC4",
    "bright":  "#FFFFFF",
}


# Per-component colour source, from the shell's own settings.json:
#   boot_theme_colors = { "plymouth": true, "grub": true, "sddm": false }
# true (and absent) → the live wallust palette; false → the built-in Velumeron brand.
SETTINGS_JSON = "gui/settings.json"


def use_theme_colors(comp):
    try:
        d = json.loads((USER_DIR / SETTINGS_JSON).read_text())
    except (OSError, ValueError):
        return True
    m = d.get("boot_theme_colors")
    if not isinstance(m, dict):
        return True
    v = m.get(comp)
    return True if v is None else bool(v)


def boot_roles(comp=None):
    """What the boot themes paint with: the shell's own palette, plus the two roles
    the shell has no name for.

    `bg2` is the foot of the background wash and `glow` the lifted accent used for
    highlights and the Plymouth sweep — Colors.qml has neither, so they are derived
    from the palette rather than invented, which keeps the boot chain in step with the
    shell however the wallpaper shifts. Falls back to BRAND when there is no palette
    to read (a fresh install, or a root run that cannot reach the user's config).

    With `comp` given and its "use theme colours" switch off, the brand set is returned
    outright — that is the switch's whole job."""
    if comp is not None and not use_theme_colors(comp):
        return dict(BRAND)
    pal = load_palette()
    if pal is None or pal.get("color0") == FALLBACK["color0"]:
        # load_palette() hands back FALLBACK verbatim when it found nothing usable.
        r = dict(BRAND)
        return r
    r = roles(pal)
    r["bg2"] = mix(r["bg"], r["accent"], 0.38)      # background wash, accent-tinted
    r["glow"] = mix(r["accent"], r["bright"], 0.38)  # highlights, sweep, hairlines
    return r


# ── small helpers ────────────────────────────────────────────────────────────
def _read(p):
    try:
        return Path(p).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _listdir(p):
    """Sorted child dirs, tolerating the unreadable (/boot is 700 root:root)."""
    try:
        return sorted((d for d in Path(p).iterdir() if d.is_dir()), key=lambda d: d.name.lower())
    except (OSError, PermissionError):
        return []


def _readable(p):
    try:
        os.listdir(p)
        return True
    except (OSError, PermissionError):
        return False


def _desktop_entry(path):
    """Parse a .desktop / .plymouth style INI without choking on odd keys."""
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read_string(_read(path))
    except configparser.Error:
        return {}
    return {s: dict(cp.items(s)) for s in cp.sections()}


def _pick(sections, key, *names):
    """First `key` found, searching the named sections then every other one."""
    for s in list(names) + [s for s in sections if s not in names]:
        v = sections.get(s, {}).get(key)
        if v:
            return v
    return ""


_PREVIEW_HINTS = ("preview", "screenshot", "logo", "splash", "background", "wallpaper")


def _preview_image(dirpath, declared=""):
    """Best preview image for a theme dir: a declared one, else a hinted name, else
    the largest image. Themes have no common convention, so this is heuristic."""
    d = Path(dirpath)
    if declared:
        cand = d / declared
        if cand.is_file():
            return str(cand)
    try:
        imgs = [p for p in d.rglob("*")
                if p.is_file() and p.suffix.lower() in (".png", ".jpg", ".jpeg", ".svg")]
    except (OSError, PermissionError):
        return ""
    if not imgs:
        return ""
    for hint in _PREVIEW_HINTS:
        hits = [p for p in imgs if hint in p.name.lower()]
        if hits:
            return str(max(hits, key=lambda p: p.stat().st_size))
    return str(max(imgs, key=lambda p: p.stat().st_size))


def _active_dm():
    """The display manager systemd actually starts, or ''."""
    try:
        target = os.path.realpath("/etc/systemd/system/display-manager.service")
        name = Path(target).name
        if name.endswith(".service"):
            return name[:-len(".service")]
    except OSError:
        pass
    return ""


# ═══════════════════════════════════════════════════════════════════════════════
#  Plymouth
# ═══════════════════════════════════════════════════════════════════════════════
PLY_DIR = Path("/usr/share/plymouth/themes")
PLY_CONF = Path("/etc/plymouth/plymouthd.conf")


def plymouth_status():
    st = {"component": "plymouth", "label": "Plymouth", "themes": [],
          "current": "", "available": False, "active": False, "reason": "",
          "note": "", "root_dir": str(PLY_DIR)}

    if not PLY_DIR.is_dir() and not shutil.which("plymouth-set-default-theme"):
        st["reason"] = "plymouth is not installed"
        return st
    st["available"] = True

    # Selected theme: the config file is authoritative and needs no subprocess.
    sec = _desktop_entry(PLY_CONF)
    st["current"] = _pick(sec, "Theme", "Daemon") or ""
    if not st["current"] and shutil.which("plymouth-set-default-theme"):
        try:
            st["current"] = subprocess.run(["plymouth-set-default-theme"],
                                           capture_output=True, text=True,
                                           timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass

    # "Active" means it will actually be shown: the hook has to be in the initramfs.
    hooks = ""
    for line in _read("/etc/mkinitcpio.conf").splitlines():
        if line.strip().startswith("HOOKS"):
            hooks = line
    for extra in sorted(Path("/etc/mkinitcpio.conf.d").glob("*.conf")) if Path("/etc/mkinitcpio.conf.d").is_dir() else []:
        for line in _read(extra).splitlines():
            if line.strip().startswith("HOOKS"):
                hooks = line
    if re.search(r"\bplymouth\b", hooks):
        st["active"] = True
    elif Path("/usr/lib/dracut").is_dir() or Path("/etc/dracut.conf.d").is_dir():
        st["active"] = True        # dracut pulls the module in by itself
        st["note"] = "dracut initramfs — plymouth is included automatically"
    else:
        st["note"] = ("not in the mkinitcpio HOOKS — add `plymouth` to /etc/mkinitcpio.conf "
                      "for the splash to appear")

    for d in _listdir(PLY_DIR):
        meta = next(iter(sorted(d.glob("*.plymouth"))), None)
        if not meta:
            continue
        sec = _desktop_entry(meta)
        st["themes"].append({
            "name": d.name,
            "title": _pick(sec, "Name", "Plymouth Theme") or d.name,
            "description": _pick(sec, "Description", "Plymouth Theme"),
            "path": str(d),
            "kind": _pick(sec, "ModuleName", "Plymouth Theme"),
            "generated": d.name == GENERATED,
        })
    return st


def plymouth_apply(theme):
    _install_generated("plymouth", theme)
    if shutil.which("plymouth-set-default-theme"):
        # -R rebuilds the initramfs: the theme lives INSIDE it, so without this the
        # next boot still shows the old one.
        return _run(["plymouth-set-default-theme", "-R", theme])
    # No helper (non-Arch layouts): write the config and rebuild what we can find.
    _ini_set(PLY_CONF, "Daemon", "Theme", theme)
    if shutil.which("mkinitcpio"):
        return _run(["mkinitcpio", "-P"])
    if shutil.which("dracut-rebuild"):
        return _run(["dracut-rebuild"])
    print("! initramfs not rebuilt — no mkinitcpio/dracut found; do it by hand", file=sys.stderr)
    return 0


# ═══════════════════════════════════════════════════════════════════════════════
#  GRUB
# ═══════════════════════════════════════════════════════════════════════════════
GRUB_DEFAULT = Path("/etc/default/grub")
GRUB_DIRS = (Path("/usr/share/grub/themes"), Path("/boot/grub/themes"),
             Path("/boot/grub2/themes"))


def _grub_cfg_path():
    for p in (Path("/boot/grub/grub.cfg"), Path("/boot/grub2/grub.cfg")):
        if p.parent.is_dir():
            return p
    return Path("/boot/grub/grub.cfg")


def grub_status():
    st = {"component": "grub", "label": "GRUB", "themes": [],
          "current": "", "available": False, "active": False, "reason": "",
          "note": "", "root_dir": str(GRUB_DIRS[0])}

    if not GRUB_DEFAULT.is_file():
        st["reason"] = "grub is not installed (/etc/default/grub is missing)"
        return st
    if not shutil.which("grub-mkconfig") and not shutil.which("grub2-mkconfig"):
        st["reason"] = "grub-mkconfig not found"
        return st
    st["available"] = True
    st["active"] = True

    m = re.search(r'^\s*GRUB_THEME\s*=\s*"?([^"\n#]+)"?', _read(GRUB_DEFAULT), re.M)
    if m:
        # GRUB_THEME points at the theme.txt; the theme's identity is its directory.
        st["current"] = Path(m.group(1).strip()).parent.name
    else:
        st["current"] = "none"          # commented out / never set = the text menu

    # /boot is 700 root:root on most installs, so its themes are invisible to the
    # GUI. Say so rather than silently listing half the catalogue.
    hidden = [str(d) for d in GRUB_DIRS[1:] if d.exists() and not _readable(d)]
    if hidden:
        st["note"] = ("themes under %s need root to list — only %s is shown"
                      % (", ".join(hidden), GRUB_DIRS[0]))

    # A themed boot menu has to be undoable from the same place it was set, so the
    # plain text menu is offered as an entry rather than hidden behind editing
    # /etc/default/grub by hand.
    st["themes"].append({
        "name": "none", "title": "No theme", "description": "GRUB's plain text menu",
        "path": "", "kind": "builtin", "generated": False,
    })

    seen = set()
    for root in GRUB_DIRS:
        for d in _listdir(root):
            if d.name in seen or not (d / "theme.txt").is_file():
                continue
            seen.add(d.name)
            txt = _read(d / "theme.txt")
            title = re.search(r'^\s*title-text\s*:\s*"([^"]*)"', txt, re.M)
            st["themes"].append({
                "name": d.name,
                "title": (title.group(1).strip() if title and title.group(1).strip() else d.name),
                "description": "",
                "path": str(d),
                "kind": "theme.txt",
                "generated": d.name == GENERATED,
            })
    return st


def grub_apply(theme):
    dest = _install_generated("grub", theme)
    if theme == "none":
        target = ""
    else:
        target = ""
        for root in GRUB_DIRS:
            if (root / theme / "theme.txt").is_file():
                target = str(root / theme / "theme.txt")
                break
        if not target and dest:
            target = str(Path(dest) / "theme.txt")
        if not target:
            print("boot-theme: no theme.txt for grub theme %r" % theme, file=sys.stderr)
            return 1

    _grub_set_theme(target)
    mk = shutil.which("grub-mkconfig") or shutil.which("grub2-mkconfig")
    return _run([mk, "-o", str(_grub_cfg_path())])


def _grub_set_theme(target):
    """Rewrite GRUB_THEME in /etc/default/grub, preserving everything else.

    An empty target comments the line out (back to the plain text menu) instead of
    deleting it, so the previous value stays visible in the file."""
    lines = _read(GRUB_DEFAULT).splitlines()
    out, done = [], False
    for line in lines:
        if re.match(r'^\s*#?\s*GRUB_THEME\s*=', line):
            if done:
                continue                     # collapse duplicates
            out.append('GRUB_THEME="%s"' % target if target else '#GRUB_THEME=""')
            done = True
        else:
            out.append(line)
    if not done:
        out.append('GRUB_THEME="%s"' % target if target else '#GRUB_THEME=""')
    GRUB_DEFAULT.write_text("\n".join(out) + "\n", encoding="utf-8")


# ═══════════════════════════════════════════════════════════════════════════════
#  SDDM
# ═══════════════════════════════════════════════════════════════════════════════
SDDM_DIR = Path("/usr/share/sddm/themes")
SDDM_CONF = Path("/etc/sddm.conf")
SDDM_CONF_D = Path("/etc/sddm.conf.d")
# sddm reads /usr/lib/sddm/sddm.conf.d/*, then /etc/sddm.conf, then /etc/sddm.conf.d/*
# — alphabetically within each dir, later winning. `zz-` therefore beats a distro
# drop-in like kde_settings.conf instead of being silently overridden by it.
SDDM_DROPIN = SDDM_CONF_D / "zz-velumeron.conf"


def sddm_status():
    st = {"component": "sddm", "label": "SDDM", "themes": [],
          "current": "", "available": False, "active": False, "reason": "",
          "note": "", "root_dir": str(SDDM_DIR)}

    dm = _active_dm()
    if not SDDM_DIR.is_dir() and not shutil.which("sddm"):
        st["reason"] = "sddm is not installed" + (" (%s is the display manager)" % dm if dm else "")
        return st
    st["available"] = True
    st["active"] = dm == "sddm"
    if not st["active"]:
        st["note"] = ("sddm is installed but %s runs the login screen — the theme applies "
                      "once you switch to sddm" % (dm or "another display manager"))

    for src in _sddm_conf_chain():
        sec = _desktop_entry(src)
        cur = _pick(sec, "Current", "Theme")
        if cur:
            st["current"] = cur.strip()

    for d in _listdir(SDDM_DIR):
        meta = d / "metadata.desktop"
        sec = _desktop_entry(meta) if meta.is_file() else {}
        if not sec and not (d / "Main.qml").is_file():
            continue
        st["themes"].append({
            "name": d.name,
            "title": _pick(sec, "Name", "SddmGreeterTheme", "Desktop Entry") or d.name,
            "description": _pick(sec, "Description", "SddmGreeterTheme", "Desktop Entry"),
            "path": str(d),
            "kind": "qml",
            "preview": _pick(sec, "Preview", "SddmGreeterTheme"),
            "generated": d.name == GENERATED,
        })
    return st


def _sddm_conf_chain():
    """Every config source, in the order sddm applies them (later wins).

    The order is the one man 5 sddm.conf states: both directories first, then
    /etc/sddm.conf, "the latter having highest precedence". Getting this wrong
    made status() report our drop-in as the active theme while a Current= in
    /etc/sddm.conf was in fact the one sddm loaded."""
    out = []
    for d in (Path("/usr/lib/sddm/sddm.conf.d"), SDDM_CONF_D):
        out += sorted(d.glob("*.conf")) if d.is_dir() else []
    if SDDM_CONF.is_file():
        out.append(SDDM_CONF)
    return out


SDDM_FACES = Path("/usr/share/sddm/faces")


def _sddm_publish_face():
    """Copy the invoking user's ~/.face where the greeter can actually read it.

    The greeter runs as the `sddm` user, and a home directory is typically 700 or
    710 — so it cannot traverse into it, and an avatar left in $HOME simply never
    appears. /usr/share/sddm/faces/<user>.face.icon is sddm's own answer to that."""
    user = os.environ.get("SUDO_USER")
    if not user:
        return
    try:
        import pwd
        home = Path(pwd.getpwnam(user).pw_dir)
    except (KeyError, ImportError):
        return
    src = next((p for p in (home / ".face", home / ".face.icon") if p.is_file()), None)
    if not src:
        return
    SDDM_FACES.mkdir(parents=True, exist_ok=True)
    dst = SDDM_FACES / ("%s.face.icon" % user)
    shutil.copyfile(src, dst)
    dst.chmod(0o644)
    print("published avatar %s → %s" % (src, dst))


def _sddm_clear_conflicting_theme(theme):
    """Drop a [Theme] Current= from /etc/sddm.conf when it would override us.

    The `zz-` prefix on our drop-in only wins inside /etc/sddm.conf.d. The file
    /etc/sddm.conf is read after that whole directory (man 5 sddm.conf), so a
    Current= parked there by a distro installer or by another theme's setup
    script silently beats the drop-in whatever it is named. Only that one key
    goes; everything else in the file is left alone, and the original is kept
    next to it."""
    if not SDDM_CONF.is_file():
        return
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read_string(_read(SDDM_CONF))
    except configparser.Error:
        return
    if not cp.has_section("Theme") or not cp.has_option("Theme", "Current"):
        return
    current = cp.get("Theme", "Current").strip()
    if current == theme:
        return
    backup = Path(str(SDDM_CONF) + ".velumeron-bak")
    if not backup.exists():
        shutil.copyfile(SDDM_CONF, backup)
    cp.remove_option("Theme", "Current")
    if not cp.options("Theme"):
        cp.remove_section("Theme")
    buf = io.StringIO()
    # sddm's own files are written key=value; keep that rather than let
    # configparser pad the delimiter with spaces.
    cp.write(buf, space_around_delimiters=False)
    SDDM_CONF.write_text(buf.getvalue(), encoding="utf-8")
    print("cleared overriding [Theme] Current=%s from %s (backup: %s)"
          % (current, SDDM_CONF, backup))


def sddm_apply(theme):
    _install_generated("sddm", theme)
    _sddm_publish_face()
    SDDM_CONF_D.mkdir(parents=True, exist_ok=True)
    SDDM_DROPIN.write_text(
        "# Written by Velumeron (boot-theme.py). The `zz-` prefix makes this sort\n"
        "# after any distro drop-in (e.g. kde_settings.conf) inside this directory.\n"
        "# That alone is not enough: /etc/sddm.conf outranks the whole directory,\n"
        "# so sddm_apply also clears a conflicting Current= over there.\n"
        "[Theme]\nCurrent=%s\n" % theme, encoding="utf-8")
    print("wrote %s → [Theme] Current=%s" % (SDDM_DROPIN, theme))
    _sddm_clear_conflicting_theme(theme)
    return 0


# ═══════════════════════════════════════════════════════════════════════════════
#  shared apply plumbing
# ═══════════════════════════════════════════════════════════════════════════════
SYSTEM_DIR = {"plymouth": PLY_DIR, "grub": GRUB_DIRS[0], "sddm": SDDM_DIR}
APPLIERS = {"plymouth": plymouth_apply, "grub": grub_apply, "sddm": sddm_apply}
STATUSES = {"plymouth": plymouth_status, "grub": grub_status, "sddm": sddm_status}


def _run(cmd):
    print("· " + " ".join(str(c) for c in cmd))
    try:
        return subprocess.call([str(c) for c in cmd])
    except OSError as e:
        print("boot-theme: %s" % e, file=sys.stderr)
        return 1


def _ini_set(path, section, key, value):
    """Set one key in an INI file, creating file/section as needed."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    if path.is_file():
        try:
            cp.read_string(_read(path))
        except configparser.Error:
            pass
    if not cp.has_section(section):
        cp.add_section(section)
    cp.set(section, key, value)
    buf = io.StringIO()
    cp.write(buf)
    path.write_text(buf.getvalue(), encoding="utf-8")


def _restore_stage_owner():
    """Give $VELUMERON_USER_DIR/boot back to the invoking user after a root-side
    generate. A no-op when not running under sudo."""
    user = os.environ.get("SUDO_USER")
    if os.geteuid() != 0 or not user:
        return
    try:
        import pwd
        pw = pwd.getpwnam(user)
    except (KeyError, ImportError):
        return
    for p in [STAGE] + list(STAGE.rglob("*")):
        try:
            os.chown(p, pw.pw_uid, pw.pw_gid)
        except OSError:
            pass


def _install_generated(comp, theme):
    """If the pick is the generated theme, stage it fresh and copy it into place.

    Returns the system path it was installed to, or "" when nothing was copied."""
    if theme != GENERATED:
        return ""
    src = STAGE / comp / GENERATED
    if not src.is_dir():
        # Picking the generated theme without ever pressing "Rebuild" has to work, so
        # stage it now — but we are root here, and the staging dir belongs to the
        # user. Hand it straight back, or their next unprivileged rebuild would hit
        # EACCES on a root-owned tree it cannot even remove.
        generate(comp)
        _restore_stage_owner()
    if not src.is_dir():
        print("boot-theme: nothing generated for %s — run `generate` first" % comp,
              file=sys.stderr)
        return ""
    dest = SYSTEM_DIR[comp] / GENERATED
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    for p in dest.rglob("*"):
        p.chmod(0o755 if p.is_dir() else 0o644)
    dest.chmod(0o755)
    print("installed %s → %s" % (src, dest))
    return str(dest)


# ═══════════════════════════════════════════════════════════════════════════════
#  generate — the palette-driven `velumeron` theme of each component
# ═══════════════════════════════════════════════════════════════════════════════
LOGO = VELUMERON_DIR / "assets/splash_openvuture.png"
WORDMARK = VELUMERON_DIR / "assets/icons/velumeron_banner-white.png"
# The theme SOURCES are real, editable files — boot/<component>/velumeron/ in the
# repo. Anything ending .in is a template: known @tokens@ are replaced with the live
# palette and the suffix is dropped; everything else is copied verbatim.
SRC_DIR = VELUMERON_DIR / "boot"


def _stage(comp):
    d = STAGE / comp / GENERATED
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True, exist_ok=True)
    return d


def _tokens(r):
    """@token@ → value. Hex for CSS-ish files, 0..1 floats per channel for plymouth,
    whose script language only speaks floats."""
    t = dict(r)
    t.setdefault("bg2", mix(r["bg"], r["accent"], 0.18))    # gradient foot
    t.setdefault("glow", mix(r["accent"], "#ffffff", 0.30)) # lifted accent
    t["track"] = mix(r["bg"], r["border"], 0.40)            # progress-bar trough
    t["urgent"] = "#E0577A"
    t["theme_dir"] = ""                                     # set per component
    short = {"accent": "ac", "muted": "mu", "bright": "br", "glow": "gl",
             "border": "bo", "element": "el", "bg": "bg", "bg2": "bg2", "fg": "fg"}
    for name, abbr in short.items():
        cr, cg, cb = rgb(t[name])
        t["%s_r" % abbr] = "%.4f" % (cr / 255.0)
        t["%s_g" % abbr] = "%.4f" % (cg / 255.0)
        t["%s_b" % abbr] = "%.4f" % (cb / 255.0)
    return t


def _render_tree(comp, dest, tokens):
    """Copy boot/<comp>/velumeron/ → dest, substituting tokens in *.in files.

    Only KNOWN tokens are replaced, so a foreign placeholder in the same syntax
    (GRUB's own @KEYMAP_SHORT@) survives untouched."""
    src = SRC_DIR / comp / GENERATED
    if not src.is_dir():
        print("boot-theme: theme source missing: %s" % src, file=sys.stderr)
        return False
    for p in sorted(src.rglob("*")):
        out = Path(dest) / p.relative_to(src)
        if p.is_dir():
            out.mkdir(parents=True, exist_ok=True)
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        if p.suffix == ".in":
            txt = p.read_text(encoding="utf-8")
            for k, v in tokens.items():
                txt = txt.replace("@%s@" % k, str(v))
            out.with_suffix("").write_text(txt, encoding="utf-8")
        else:
            shutil.copyfile(p, out)
    return True


def _pil():
    try:
        from PIL import Image, ImageDraw
        return Image, ImageDraw
    except ImportError:
        return None, None


def _gradient(size, r):
    """The shared ground: a vertical wash from near-black to the purple foot, with a
    soft radial lift behind the centre so the mark does not sit on flat colour.

    DITHERED, and that is the whole point. A 1080-row ramp between two dark, close
    colours only passes through ~40 distinct 8-bit values, so it renders as a stack
    of visible bands — the edges you see on a login screen. A triangular-PDF dither
    of ±1 LSB scatters each step boundary into noise the eye integrates back into a
    smooth ramp. Without it, no amount of tweaking the two endpoints helps."""
    Image, ImageDraw = _pil()
    if Image is None:
        return None
    w, h = size
    ta, tb = rgb(r["bg"]), rgb(r["bg2"])

    try:
        import numpy as np
    except ImportError:
        # Undithered fallback — banded, but a picture beats no picture.
        img = Image.new("RGB", (w, h))
        d = ImageDraw.Draw(img)
        for y in range(h):
            t = y / max(1, h - 1)
            e = t * t * (3 - 2 * t)
            d.line([(0, y), (w, y)],
                   fill=tuple(round(ta[i] + (tb[i] - ta[i]) * e) for i in range(3)))
        return img

    t = np.linspace(0.0, 1.0, h)
    e = t * t * (3 - 2 * t)                       # smoothstep: purple gathers low
    a = np.array(ta, dtype=np.float64)
    b = np.array(tb, dtype=np.float64)
    img = (a[None, None, :] + (b - a)[None, None, :] * e[:, None, None]) \
        * np.ones((1, w, 1))

    # A wide, very faint accent bloom behind the middle — breaks the pure top-to-bottom
    # banding pattern and gives the mark something to sit in.
    yy = (np.arange(h)[:, None] - h * 0.42) / (h * 0.55)
    xx = (np.arange(w)[None, :] - w * 0.50) / (w * 0.55)
    bloom = np.exp(-(xx * xx + yy * yy)) * 0.09
    img += (np.array(rgb(r["accent"]), dtype=np.float64)[None, None, :]
            - img) * bloom[:, :, None]

    # Triangular PDF (difference of two uniforms), ±2 LSB. One LSB is enough at 1:1
    # but NOT once the image is rescaled: interpolation averages the dither back into
    # the smooth value, which the display then re-quantises into the very bands the
    # dither was meant to kill. Two survives a resample.
    # Fixed seed: regenerating the same theme must produce byte-identical artwork,
    # otherwise every `generate` looks like a change to anything diffing the output.
    rng = np.random.default_rng(20260805)
    img += 2.0 * (rng.random((h, w, 1)) - rng.random((h, w, 1)))

    return Image.fromarray(np.clip(img, 0, 255).round().astype(np.uint8), "RGB")


# The login sits on a slanted band of brand colour with the wallpaper showing on BOTH
# sides — an island rather than a border. The band's left edge runs from BAND_TOP of
# the width at the top of the screen to BAND_BOTTOM at the bottom; its right edge is
# the same diagonal shifted over by BAND_WIDTH, so the two cuts stay parallel.
#
# POINT SYMMETRY — keep BAND_TOP + BAND_BOTTOM == 1 - BAND_WIDTH. That makes the strip
# of wallpaper left of the band at the top exactly as wide as the strip right of it at
# the bottom, and vice versa, so the composition is its own 180° rotation. Break the
# identity and the picture reads lopsided even though both cuts are still parallel:
# at 0.33/0.15 it was 33% left at the top against 39% right at the bottom.
# The midline then also crosses the screen centre at mid-height, which is where the
# centred login column sits.
BAND_WIDTH = 0.46
BAND_SLANT = 0.18                                    # how far the band walks left, top → bottom
BAND_TOP = (1.0 - BAND_WIDTH + BAND_SLANT) / 2.0     # 0.36
BAND_BOTTOM = BAND_TOP - BAND_SLANT                  # 0.18

# GRUB gets its own geometry: its content (wordmark near the top, menu in the middle
# third) spans far more of the height than the login column does, so the same slant
# would push the bottom menu rows out of the band. Wider and flatter keeps every row
# inside it — see the clearance table computed in the comment above gen_grub.
GRUB_BAND_WIDTH = 0.52
GRUB_BAND_SLANT = 0.12
WEDGE_DIM = 0.62          # how far the wallpaper is pulled toward the brand purple
WEDGE_FEATHER = 1.5       # px of softening on the cut — enough to kill the jaggies


def _current_wallpaper():
    """The wallpaper the shell is showing, widest first (the login screen is landscape)."""
    try:
        data = json.loads((USER_DIR / "quickshell/wallpapers.json").read_text())
    except (OSError, ValueError):
        return None
    best, best_w = None, -1
    for v in (data or {}).values():
        path = (v or {}).get("path", "")
        if not path or (v.get("type") or "image") != "image" or not Path(path).is_file():
            continue
        try:
            from PIL import Image as _I
            w, h = _I.open(path).size
        except Exception:
            continue
        if w > h and w > best_w:
            best, best_w = path, w
    return best


def _band_edges(width, slant):
    """(top, bottom) of the band's LEFT edge for a given width and slant, always
    satisfying top + bottom == 1 - width so the result is point-symmetric."""
    top = (1.0 - width + slant) / 2.0
    return top, top - slant


def _wallpaper_band(img, r, width=BAND_WIDTH, slant=BAND_SLANT):
    """Composite the live wallpaper on both flanks of a slanted brand-coloured band.

    Baked into the PNG rather than masked in QML on purpose: the greeter runs as the
    `sddm` user and cannot read a 700 home directory, so the picture has to travel
    with the theme anyway — and doing the cut here means no QtQuick.Effects dependency
    in a process where a failed import takes the whole login screen down."""
    Image, ImageDraw = _pil()
    wp = _current_wallpaper()
    if Image is None or not wp:
        return img
    try:
        import numpy as np
        shot = Image.open(wp).convert("RGB")
    except Exception:
        return img

    W, H = img.size
    # Cover the frame, then centre-crop.
    sc = max(W / shot.width, H / shot.height)
    shot = shot.resize((max(1, round(shot.width * sc)), max(1, round(shot.height * sc))),
                       Image.LANCZOS)
    shot = shot.crop(((shot.width - W) // 2, (shot.height - H) // 2,
                      (shot.width - W) // 2 + W, (shot.height - H) // 2 + H))

    # Pull it toward the brand purple so it reads as a layer behind the login rather
    # than a second, competing picture.
    a = np.asarray(shot).astype(np.float64)
    tint = np.array(rgb(r["bg2"]), dtype=np.float64)
    a = a + (tint - a) * WEDGE_DIM

    # Two parallel soft edges; the wallpaper shows OUTSIDE the band between them.
    xs = np.arange(W)[None, :]
    ys = np.arange(H)[:, None] / max(1, H - 1)
    b_top, b_bottom = _band_edges(width, slant)
    left = (b_top + (b_bottom - b_top) * ys) * W
    right = left + width * W
    inside = (np.clip((xs - left) / WEDGE_FEATHER + 0.5, 0.0, 1.0)
              * np.clip((right - xs) / WEDGE_FEATHER + 0.5, 0.0, 1.0))
    m = 1.0 - inside

    base = np.asarray(img).astype(np.float64)
    out = base + (a - base) * m[:, :, None]

    # A hairline of accent along both cuts, so they read as deliberate edges.
    line = (np.exp(-((xs - left) ** 2) / (2 * 1.6 ** 2))
            + np.exp(-((xs - right) ** 2) / (2 * 1.6 ** 2)))
    glow = np.array(rgb(r["glow"]), dtype=np.float64)
    out = out + (glow - out) * (line * 0.55)[:, :, None]

    return Image.fromarray(np.clip(out, 0, 255).round().astype(np.uint8), "RGB")


def _wordmark(img, r, width_frac, center_y_frac, tint=None):
    """Paste the Velumeron wordmark (raven on the V) at a fraction of the image width."""
    Image, _ = _pil()
    if Image is None or not WORDMARK.is_file():
        return img
    try:
        mark = Image.open(WORDMARK).convert("RGBA")
    except OSError:
        return img
    bb = mark.split()[3].getbbox()
    if bb:
        mark = mark.crop(bb)
    w, h = img.size
    tw = max(1, int(w * width_frac))
    th = max(1, round(tw * mark.height / mark.width))
    mark = mark.resize((tw, th), Image.LANCZOS)
    if tint:
        solid = Image.new("RGBA", mark.size, rgb(tint) + (255,))
        solid.putalpha(mark.split()[3])
        mark = solid
    img.paste(mark, ((w - tw) // 2, int(h * center_y_frac) - th // 2), mark)
    return img


# ── Plymouth ──────────────────────────────────────────────────────────────────
SWEEP_FRAMES = 30      # one full pass; more = smoother but a bigger initramfs
SWEEP_HOLD   = 2       # plymouth refreshes to hold each frame (~50/s → ~1.2 s a pass)
SWEEP_WIDTH  = 900     # wordmark width in px — "large and central" on any sane screen


def _sweep_frames(dest, r, n=SWEEP_FRAMES, width=SWEEP_WIDTH):
    """Pre-render the wordmark with a highlight band travelling left → right.

    Plymouth script cannot touch pixels, so the animation has to exist as files.
    Each frame is the same mark with a soft gaussian band of brightness at a
    different x — dim purple-white at rest, near-white under the band."""
    Image, _ = _pil()
    if Image is None or not WORDMARK.is_file():
        return 0
    try:
        mark = Image.open(WORDMARK).convert("RGBA")
    except OSError:
        return 0
    bb = mark.split()[3].getbbox()
    if bb:
        mark = mark.crop(bb)
    h = max(1, round(width * mark.height / mark.width))
    mark = mark.resize((width, h), Image.LANCZOS)
    alpha = mark.split()[3]

    dim = rgb(mix(r["accent"], r["fg"], 0.35))     # resting colour — purple-washed
    hot = rgb(r["bright"])                          # under the band
    sigma = width * 0.16                            # band softness

    # The sweep varies along x only, so one row of the colour ramp stretched down
    # and masked by the mark's own alpha is the whole frame.
    for f in range(n):
        # Travel from off-left to off-right so the band enters and leaves cleanly.
        pos = (-0.35 + 1.70 * (f / float(n))) * width
        row = Image.new("RGB", (width, 1))
        px = row.load()
        for x in range(width):
            k = math.exp(-((x - pos) ** 2) / (2 * sigma * sigma))
            px[x, 0] = tuple(round(dim[i] + (hot[i] - dim[i]) * k) for i in range(3))
        frame = row.resize((width, h), Image.NEAREST).convert("RGBA")
        frame.putalpha(alpha)
        frame.save(Path(dest) / ("sweep-%d.png" % f))
    return n


def gen_plymouth(r):
    d = _stage("plymouth")
    n = _sweep_frames(d, r)
    t = _tokens(r)
    # The .plymouth file needs ABSOLUTE paths: plymouth reads it from inside the
    # initramfs, where a relative ImageDir resolves to nothing.
    t["theme_dir"] = "%s/%s" % (PLY_DIR, GENERATED)
    t["frames"] = str(max(1, n))
    t["hold"] = str(SWEEP_HOLD)
    t["seconds"] = "%.1f" % (max(1, n) * SWEEP_HOLD / 50.0)
    _render_tree("plymouth", d, t)

    # A still for the settings page — the real thing is an animation, so show the
    # mark mid-sweep rather than a frame nobody would recognise.
    Image, _ = _pil()
    # 1080p, not 720p: `show plymouth` draws this behind the frames in a window that
    # is usually larger, and upscaling a gradient re-bands it however well it was
    # dithered — the dither averages away and the smooth value re-quantises.
    big = _gradient((1920, 1080), r)
    if big is not None:
        big.save(d / "preview-bg.png")
    bg = _gradient((1280, 720), r)
    if bg is not None and Image is not None:
        mid = Path(d) / ("sweep-%d.png" % (max(1, n) // 3))
        if mid.is_file():
            m = Image.open(mid).convert("RGBA")
            tw = int(bg.width * 0.62)
            m = m.resize((tw, max(1, round(tw * m.height / m.width))), Image.LANCZOS)
            bg.paste(m, ((bg.width - m.width) // 2, (bg.height - m.height) // 2), m)
        bg.save(d / "preview.png")
    return d


# ── GRUB ──────────────────────────────────────────────────────────────────────
def gen_grub(r):
    d = _stage("grub")
    _render_tree("grub", d, _tokens(r))

    Image, _ = _pil()
    if Image is None:
        print("! Pillow missing — grub theme generated without artwork", file=sys.stderr)
        return d
    # Wordmark centred on 19% of the height at 34% of the width; theme.txt starts the
    # menu at 42% so the two never meet (see the LAYOUT note there).
    bg = _gradient((2560, 1440), r)
    bg = _wallpaper_band(bg, r, width=GRUB_BAND_WIDTH, slant=GRUB_BAND_SLANT)
    _wordmark(bg, r, width_frac=0.30, center_y_frac=0.21)
    bg.save(d / "background.png")

    _grub_fonts(d)
    _grub_icons(d, r)

    # 9-slice for the selected row. GRUB needs every piece of select_*.png to exist;
    # one missing slice silently disables the highlight, so all nine are written.
    # Small corners on purpose — the assembled minimum height must stay well under
    # theme.txt's item_height or the highlight overruns the row.
    # Both styles share the geometry so every row gets the same text inset; only the
    # selected one is actually painted. corner=10 is the highlight's padding.
    _nine_slice(d, "select", fill=mix(r["bg"], r["accent"], 0.85),
                border=r["glow"], radius=8, corner=10, edge=4)
    _nine_slice(d, "item", fill=r["bg"], border=r["bg"],
                radius=8, corner=10, edge=4, alpha=0)
    # The console box GRUB shows when you drop to its shell.
    _nine_slice(d, "terminal", fill=mix(r["bg"], r["element"], 0.7),
                border=r["border"], radius=4, corner=6, edge=4)
    return d


GRUB_FONT_SIZES = (20, 14)     # menu items, and the key-hint label

# Per-entry icons. GRUB looks an entry up by its --class values, in order, and draws
# the first icons/<class>.png it finds. This machine's grub-mkconfig emits
# "<distributor> gnu-linux gnu os" for kernels; the rest are here so a dual-boot or an
# os-prober find is not left blank. Entries with NO class (the UEFI firmware one, for
# instance) get no icon — GRUB still reserves the column, so the list stays aligned.
GRUB_ICONS = {
    "cachyos":       "\uf31a",          # tux
    "arch":          "\ue732",
    "archlinux":     "\ue732",
    "gnu-linux":     "\uf31a",
    "gnu":           "\uf31a",
    "linux":         "\uf31a",
    "os":            "\U000f02ca",      # generic disk — the catch-all class
    "windows":       "\ue70f",
    "osx":           "\ue711",
    "xen":           "\uec19",
    "uefi-firmware": "\uec19",          # chip
    "memtest86":     "\U000f035b",      # memory
    "memtest":       "\U000f035b",
    "recovery":      "\ueb53",          # shield
}
GRUB_ICON_PX = 28


def _grub_icons(dest, r):
    """Render the class icons as PNGs from the bundled Nerd Font.

    Drawing them by hand would mean maintaining a pile of tiny bitmaps; the glyphs are
    already in the font the shell uses everywhere else, so they stay consistent with
    the rest of Velumeron for free."""
    Image, ImageDraw = _pil()
    if Image is None:
        return
    try:
        from PIL import ImageFont
    except ImportError:
        return
    src = VELUMERON_DIR / "assets/fonts/FantasqueSansMNerdFont-Regular.ttf"
    if not src.is_file():
        print("! %s missing — grub entries get no icons" % src, file=sys.stderr)
        return
    try:
        font = ImageFont.truetype(str(src), GRUB_ICON_PX)
    except OSError:
        return
    out = Path(dest) / "icons"
    out.mkdir(parents=True, exist_ok=True)
    side = GRUB_ICON_PX + 8
    for name, ch in GRUB_ICONS.items():
        img = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.text((side / 2, side / 2), ch, font=font, anchor="mm", fill=rgb(r["fg"]) + (255,))
        img.save(out / ("%s.png" % name))


def _grub_fonts(dest):
    """Convert Fredoka to GRUB's own .pf2 format, one file per size.

    GRUB cannot read a TTF. It also cannot scale a bitmap font, so each size on
    screen needs its own file. The internal name grub-mkfont writes is
    "<family> <style> <size>" — that exact string is what theme.txt must reference,
    which is why the sizes here and the names there have to move together."""
    if not shutil.which("grub-mkfont"):
        print("! grub-mkfont missing — grub theme falls back to the built-in font",
              file=sys.stderr)
        return []
    src = VELUMERON_DIR / "assets/fonts/Fredoka-500.ttf"
    if not src.is_file():
        print("! %s missing — grub theme falls back to the built-in font" % src,
              file=sys.stderr)
        return []
    out = []
    for size in GRUB_FONT_SIZES:
        dst = Path(dest) / ("fredoka-%d.pf2" % size)
        rc = subprocess.call(["grub-mkfont", "-s", str(size), "-o", str(dst), str(src)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if rc == 0:
            out.append(dst)
        else:
            print("! grub-mkfont failed for size %d" % size, file=sys.stderr)
    return out


def _nine_slice(dirpath, stem, fill, border, radius=6, corner=12, edge=8, alpha=255):
    """Write <stem>_{c,n,s,e,w,nw,ne,sw,se}.png — a rounded box GRUB can stretch.

    `alpha=0` writes the same GEOMETRY with nothing visible. That is not a curiosity:
    GRUB insets an item's text by its box's border size, so a row that has a pixmap
    sits `corner` px lower than one that does not — which is why the selected entry
    used to drift toward its lower neighbour. Giving the unselected rows an invisible
    box of identical geometry gives every row the same inset, and the drift is gone."""
    Image, ImageDraw = _pil()
    side = corner * 2 + edge
    box = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    d = ImageDraw.Draw(box)
    d.rounded_rectangle([0, 0, side - 1, side - 1], radius=radius,
                        fill=rgb(fill) + (alpha,), outline=rgb(border) + (alpha,), width=1)
    parts = {
        "nw": (0, 0, corner, corner),
        "n":  (corner, 0, corner + edge, corner),
        "ne": (corner + edge, 0, side, corner),
        "w":  (0, corner, corner, corner + edge),
        "c":  (corner, corner, corner + edge, corner + edge),
        "e":  (corner + edge, corner, side, corner + edge),
        "sw": (0, corner + edge, corner, side),
        "s":  (corner, corner + edge, corner + edge, side),
        "se": (corner + edge, corner + edge, side, side),
    }
    for name, bbox in parts.items():
        box.crop(bbox).save(Path(dirpath) / ("%s_%s.png" % (stem, name)))


# ── SDDM ──────────────────────────────────────────────────────────────────────
def gen_sddm(r):
    d = _stage("sddm")
    _render_tree("sddm", d, _tokens(r))

    Image, _ = _pil()
    if Image is None:
        print("! Pillow missing — sddm theme generated without artwork", file=sys.stderr)
        return d

    # The greeter draws the mark itself (so it can place it against the card), so
    # ship it as its own file rather than baking it into the background.
    if WORDMARK.is_file():
        mark = Image.open(WORDMARK).convert("RGBA")
        bb = mark.split()[3].getbbox()
        if bb:
            mark = mark.crop(bb)
        tw = 900
        mark.resize((tw, max(1, round(tw * mark.height / mark.width))),
                    Image.LANCZOS).save(d / "logo.png")

    bg = _gradient((2560, 1440), r)
    _wallpaper_band(bg, r).save(d / "background.png")

    # Ship the font INSIDE the theme and load it from QML. The greeter runs as the
    # sddm user, before any session, so relying on the font being reachable through
    # fontconfig there is a bet — a self-contained FontLoader is not.
    font_src = VELUMERON_DIR / "assets/fonts/Fredoka-500.ttf"
    if font_src.is_file():
        shutil.copyfile(font_src, d / "Fredoka-500.ttf")

    prev = _wallpaper_band(_gradient((1280, 720), r), r)
    # Same fraction Main.qml uses (0.24), not a fatter one that reads better as a
    # thumbnail — an overstated mark would show it clipping the band's edge when the
    # real greeter keeps it comfortably inside.
    _wordmark(prev, r, width_frac=0.26, center_y_frac=0.34)
    prev.save(d / "preview.png")
    return d


GENERATORS = {"plymouth": gen_plymouth, "grub": gen_grub, "sddm": gen_sddm}


def generate(*comps):
    for c in (comps or COMPONENTS):
        if c not in GENERATORS:
            print("boot-theme: unknown component %r" % c, file=sys.stderr)
            continue
        # Resolved per component: each carries its own "use theme colours" switch.
        d = GENERATORS[c](boot_roles(c))
        print("generated %s (%s colours)"
              % (d, "theme" if use_theme_colors(c) else "brand"))
    return 0


# ═══════════════════════════════════════════════════════════════════════════════
#  show — look at a theme without rebooting
# ═══════════════════════════════════════════════════════════════════════════════
PLY_PREVIEW_QML = """// Generated by boot-theme.py — plays the REAL sweep frames at the REAL cadence.
import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    width: 1280; height: 720
    title: "Velumeron — Plymouth preview"
    color: "%(bg)s"

    Image {
        anchors.fill: parent
        source: "file://%(dir)s/preview-bg.png"
        fillMode: Image.PreserveAspectCrop
    }

    property int idx: 0    // read as win.idx below — see above
    Image {
        anchors.centerIn: parent
        source: "file://%(dir)s/sweep-" + win.idx + ".png"
        width: parent.width * 0.66
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    // plymouth refreshes ~50/s and holds each frame `hold` refreshes.
    Timer {
        interval: %(ms)d; running: true; repeat: true
        onTriggered: win.idx = (win.idx + 1) %% %(frames)d
    }

    Text {
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 18 }
        text: "the real frames, played back — not plymouth's own renderer.  Esc to close"
        color: "%(muted)s"; font.pixelSize: 12
    }
    Shortcut { sequences: ["Esc", "Ctrl+Q"]; onActivated: Qt.quit() }
}
"""

GRUB_PREVIEW_CFG = """insmod all_video
insmod gfxterm
insmod png
loadfont /boot/grub/themes/velumeron/fredoka-20.pf2
loadfont /boot/grub/themes/velumeron/fredoka-14.pf2
set gfxmode=1920x1080,1280x720
set gfxpayload=keep
terminal_output gfxterm
set theme=/boot/grub/themes/velumeron/theme.txt
export theme
set timeout=300
menuentry "CachyOS Linux" --class cachyos --class gnu-linux --class gnu --class os { true }
menuentry "Advanced options for CachyOS Linux" --class cachyos --class gnu-linux --class gnu --class os { true }
menuentry "UEFI Firmware Settings" --class uefi-firmware { true }
menuentry "Memory Tester (memtest86+)" --class memtest86 --class os { true }
"""


def _need(*tools):
    missing = [t for t in tools if not shutil.which(t)]
    if missing:
        print("boot-theme: missing %s" % ", ".join(missing), file=sys.stderr)
    return not missing


def _show_grub(shot=""):
    """Boot the real GRUB, with this theme, in a VM. No root, no reboot, no risk to
    the machine's own boot path — and the only way to see what GRUB actually draws
    rather than what theme.txt says.

    `shot` runs it headless and screendumps to that path instead of opening a window,
    which is how a theme change gets checked without a human in the loop."""
    if not _need("grub-mkrescue", "xorriso", "qemu-system-x86_64"):
        return 1
    src = STAGE / "grub" / GENERATED
    if not src.is_dir():
        generate("grub")
    work = STAGE / ".preview" / "grub"
    if work.exists():
        shutil.rmtree(work)
    (work / "boot" / "grub" / "themes").mkdir(parents=True)
    shutil.copytree(src, work / "boot/grub/themes" / GENERATED)
    (work / "boot/grub/grub.cfg").write_text(GRUB_PREVIEW_CFG, encoding="utf-8")

    iso = STAGE / ".preview" / "grub-preview.iso"
    print("building preview iso…")
    if subprocess.call(["grub-mkrescue", "-o", str(iso), str(work)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
        print("boot-theme: grub-mkrescue failed", file=sys.stderr)
        return 1
    if shot:
        ppm = Path(shot).with_suffix(".ppm")
        qemu = subprocess.Popen(
            ["qemu-system-x86_64", "-cdrom", str(iso), "-m", "512", "-vga", "std",
             "-display", "none", "-monitor", "stdio"],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            text=True)
        # The guest needs a good ten seconds to get through SeaBIOS and into GRUB's
        # graphics mode; screendumping before that captures "Guest has not
        # initialized the display (yet)".
        try:
            time.sleep(14)
            qemu.stdin.write("screendump %s\n" % ppm); qemu.stdin.flush()
            time.sleep(3)
            qemu.stdin.write("quit\n"); qemu.stdin.flush()
            qemu.wait(timeout=15)
        except (subprocess.TimeoutExpired, BrokenPipeError, OSError):
            qemu.kill()
        Image, _ = _pil()
        if Image is not None and ppm.is_file():
            Image.open(ppm).convert("RGB").save(shot)
            ppm.unlink()
            print("wrote %s" % shot)
            return 0
        print("boot-theme: no frame captured", file=sys.stderr)
        return 1
    print("booting it — close the window when done (Ctrl+Alt+G releases the mouse)")
    return subprocess.call(["qemu-system-x86_64", "-cdrom", str(iso), "-m", "512",
                            "-vga", "std", "-display", "gtk"])


def _show_sddm():
    """The real greeter, in a window. Harmless: --test-mode never authenticates."""
    greeter = shutil.which("sddm-greeter-qt6") or shutil.which("sddm-greeter")
    if not greeter:
        print("boot-theme: sddm-greeter not found", file=sys.stderr)
        return 1
    d = STAGE / "sddm" / GENERATED
    if not d.is_dir():
        generate("sddm")
    print("opening the greeter — close the window when done")
    return subprocess.call([greeter, "--test-mode", "--theme", str(d)])


def _show_plymouth():
    """Play the generated frames at the generated cadence.

    NOT plymouth itself: plymouthd has no --theme flag, so showing the real thing
    means installing this theme AND making it the system default first — a change to
    /etc for the sake of a look. These are the very files plymouth will cycle, over
    the very gradient it will draw, at the same frame rate, so it answers "what will
    I see" without touching the boot path."""
    if not shutil.which("qml6") and not shutil.which("qml"):
        print("boot-theme: qml6 not found (qt6-declarative)", file=sys.stderr)
        return 1
    d = STAGE / "plymouth" / GENERATED
    if not d.is_dir() or not (d / "preview-bg.png").is_file():
        generate("plymouth")
    frames = len(list(d.glob("sweep-*.png"))) or 1
    qml = d / "_preview.qml"
    _r = boot_roles("plymouth")
    qml.write_text(PLY_PREVIEW_QML % {
        "dir": str(d), "bg": _r["bg"], "muted": _r["muted"],
        "frames": frames, "ms": int(SWEEP_HOLD * 1000 / 50),
    }, encoding="utf-8")
    print("playing the sweep — Esc to close")
    return subprocess.call([shutil.which("qml6") or shutil.which("qml"), str(qml)])


SHOWERS = {"grub": _show_grub, "sddm": _show_sddm, "plymouth": _show_plymouth}


def cmd_show(comp, shot=""):
    if comp not in SHOWERS:
        print("boot-theme: show needs one of: %s" % " ".join(COMPONENTS), file=sys.stderr)
        return 1
    if comp == "grub":
        return _show_grub(shot)
    return SHOWERS[comp]()


# ═══════════════════════════════════════════════════════════════════════════════
#  commands
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_status():
    out = {"dm": _active_dm(), "generated": GENERATED, "stage": str(STAGE),
           "components": []}
    for c in COMPONENTS:
        st = STATUSES[c]()
        st["themeColors"] = use_theme_colors(c)
        # The generated theme is always offered, even before its first build —
        # picking it generates and installs it in one step.
        if st["available"] and not any(t["name"] == GENERATED for t in st["themes"]):
            st["themes"].insert(0, {
                "name": GENERATED, "title": "Velumeron",
                "description": "Generated from the live wallust palette — not installed yet",
                "path": str(STAGE / c / GENERATED), "kind": "generated",
                "generated": True, "staged": (STAGE / c / GENERATED).is_dir(),
            })
        else:
            for t in st["themes"]:
                if t["name"] == GENERATED:
                    t["staged"] = (STAGE / c / GENERATED).is_dir()
        out["components"].append(st)
    json.dump(out, sys.stdout)
    sys.stdout.write("\n")
    return 0


def cmd_preview(comp, theme):
    if comp not in COMPONENTS:
        return 1
    if theme == GENERATED:
        staged = STAGE / comp / GENERATED
        if not staged.is_dir():
            generate(comp)
        p = _preview_image(staged, "preview.png")
        if p:
            print(p)
            return 0
    for t in STATUSES[comp]()["themes"]:
        if t["name"] == theme:
            p = _preview_image(t["path"], t.get("preview", ""))
            if p:
                print(p)
            return 0
    return 0


def cmd_apply(comp, theme):
    if comp not in COMPONENTS:
        print("boot-theme: unknown component %r" % comp, file=sys.stderr)
        return 1
    if os.geteuid() != 0:
        print("boot-theme: `apply` writes to /etc, /usr/share and /boot — run it with sudo",
              file=sys.stderr)
        return 2
    st = STATUSES[comp]()
    if not st["available"]:
        print("boot-theme: %s unavailable — %s" % (comp, st["reason"]), file=sys.stderr)
        return 1
    known = {t["name"] for t in st["themes"]} | {GENERATED}
    if theme not in known and theme != "none":
        print("boot-theme: %s has no theme %r" % (comp, theme), file=sys.stderr)
        return 1
    print("→ %s: %s" % (st["label"], theme))
    rc = APPLIERS[comp](theme)
    print("done" if rc == 0 else "failed (exit %d)" % rc)
    return rc


def cmd_doctor():
    d = _active_dm()
    print("display manager : %s" % (d or "none"))
    print("palette         : %s" % (USER_DIR / "quickshell/colors.json"))
    print("staged themes   : %s" % STAGE)
    for c in COMPONENTS:
        st = STATUSES[c]()
        st["themeColors"] = use_theme_colors(c)
        mark = "ok " if st["available"] else "-- "
        print("\n%s%-9s %s" % (mark, c, st["reason"] or ("current: %s" % (st["current"] or "(none)"))))
        if st["note"]:
            print("   note: %s" % st["note"])
        for t in st["themes"]:
            print("   %s %s" % ("*" if t["name"] == st["current"] else " ", t["name"]))
    return 0


USAGE = __doc__.split("Design notes")[0].strip()


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(USAGE)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "status":
        return cmd_status()
    if cmd == "doctor":
        return cmd_doctor()
    if cmd == "generate":
        return generate(*rest)
    if cmd == "show" and len(rest) in (1, 3) :
        # `show grub --shot out.png` renders headless — used to check a theme change.
        shot = rest[2] if len(rest) == 3 and rest[1] == "--shot" else ""
        return cmd_show(rest[0], shot)
    if cmd == "preview" and len(rest) == 2:
        return cmd_preview(*rest)
    if cmd == "apply" and len(rest) == 2:
        return cmd_apply(*rest)
    print(USAGE, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
