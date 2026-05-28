import os, re, json, subprocess, random, string
from dataclasses import dataclass, field
from typing import Optional
from constants import (
    WALLPAPER_H, WALLPAPER_V, THUMB_DIR, THEME_NAMES, SETS_JSON,
    VIDEO_EXTS, ALL_EXTS, ID_RE,
)


def gen_id() -> str:
    return ''.join(random.choices(string.ascii_letters + string.digits, k=6))


def load_theme_names() -> dict:
    names = {}
    try:
        with open(THEME_NAMES) as f:
            for line in f:
                m = re.match(r'^(wp_[a-zA-Z0-9]+)\s*=\s*"([^"]+)"', line.strip())
                if m:
                    names[m.group(1)] = m.group(2)
    except FileNotFoundError:
        pass
    return names


def extract_id(stem: str) -> Optional[str]:
    m = ID_RE.match(stem)
    return m.group(1) if m else None


def get_dims(path: str):
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in VIDEO_EXTS:
            r = subprocess.run(
                ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', path],
                capture_output=True, text=True)
            for s in json.loads(r.stdout).get('streams', []):
                if s.get('codec_type') == 'video':
                    return int(s['width']), int(s['height'])
        else:
            r = subprocess.run(['identify', '-format', '%w %h', path],
                               capture_output=True, text=True)
            parts = r.stdout.strip().split()
            if len(parts) >= 2:
                return int(parts[0]), int(parts[1])
    except Exception:
        pass
    return None, None


def is_horizontal_file(path: str) -> bool:
    w, h = get_dims(path)
    return (w >= h) if w else True


@dataclass
class WallpaperEntry:
    id: str
    hor_file: Optional[str] = None
    ver_file: Optional[str] = None
    hor_thumb: Optional[str] = None
    ver_thumb: Optional[str] = None

    @property
    def category(self) -> str:
        if self.hor_file and self.ver_file:
            return 'set'
        return 'hor' if self.hor_file else 'ver'


def scan_wallpapers() -> list:
    entries: dict = {}

    def _scan(directory, is_hor):
        if not os.path.isdir(directory):
            return
        for fname in sorted(os.listdir(directory)):
            ext = os.path.splitext(fname)[1].lower()
            if ext not in ALL_EXTS:
                continue
            stem = os.path.splitext(fname)[0]
            wp_id = extract_id(stem)
            if not wp_id:
                continue
            e = entries.setdefault(wp_id, WallpaperEntry(id=wp_id))
            thumb = os.path.join(THUMB_DIR, stem + '.png')
            if is_hor:
                e.hor_file  = os.path.join(directory, fname)
                e.hor_thumb = thumb
            else:
                e.ver_file  = os.path.join(directory, fname)
                e.ver_thumb = thumb

    _scan(WALLPAPER_H, True)
    _scan(WALLPAPER_V, False)
    return sorted(entries.values(), key=lambda e: e.id)


# ── Set data model ─────────────────────────────────────────────────────────

@dataclass
class SetImage:
    file: str                    # basename, e.g. "wp_abc_hor.jpg"
    monitor: Optional[str] = None  # explicit monitor name, None = orientation fallback

    @property
    def orientation(self) -> str:
        return 'ver' if '_ver' in self.file else 'hor'

    def full_path(self) -> Optional[str]:
        d = WALLPAPER_V if self.orientation == 'ver' else WALLPAPER_H
        p = os.path.join(d, self.file)
        return p if os.path.exists(p) else None

    def thumb_path(self) -> Optional[str]:
        stem = os.path.splitext(self.file)[0]
        p = os.path.join(THUMB_DIR, stem + '.png')
        return p if os.path.exists(p) else None


@dataclass
class WallpaperSet:
    set_id: str
    name: str
    images: list = field(default_factory=list)  # list[SetImage]


def load_sets() -> dict:
    """Load sets.json → dict[set_id, WallpaperSet]."""
    if not os.path.exists(SETS_JSON):
        return {}
    with open(SETS_JSON) as f:
        data = json.load(f)
    result = {}
    for sid, entry in data.items():
        images = [SetImage(file=img['file'], monitor=img.get('monitor'))
                  for img in entry.get('images', [])]
        result[sid] = WallpaperSet(set_id=sid, name=entry.get('name', sid), images=images)
    return result


def save_sets(sets: dict) -> None:
    """Save dict[set_id, WallpaperSet] → sets.json."""
    os.makedirs(os.path.dirname(SETS_JSON), exist_ok=True)
    data = {}
    for sid, ws in sets.items():
        data[sid] = {
            'name': ws.name,
            'images': [{'file': img.file, 'monitor': img.monitor} for img in ws.images],
        }
    with open(SETS_JSON, 'w') as f:
        json.dump(data, f, indent=2)


def remove_file_from_sets(filename: str) -> None:
    """Remove all references to filename (basename) from sets.json."""
    sets = load_sets()
    changed = False
    for ws in sets.values():
        before = len(ws.images)
        ws.images = [img for img in ws.images if img.file != filename]
        if len(ws.images) != before:
            changed = True
    if changed:
        save_sets(sets)


def get_monitor_names() -> list:
    """Return list of monitor names from hyprctl."""
    try:
        r = subprocess.run(['hyprctl', 'monitors', '-j'],
                           capture_output=True, text=True, timeout=2)
        return [m['name'] for m in json.loads(r.stdout)]
    except Exception:
        return []


def migrate_pairs_to_sets() -> None:
    """If sets.json doesn't exist, create it from wp_{id}_hor/ver pairs
    and rename ver files to decouple IDs (idempotent)."""
    if os.path.exists(SETS_JSON):
        return
    theme_names = load_theme_names()
    entries = scan_wallpapers()
    sets = {}

    # Build set of existing ver IDs to avoid collisions when renaming
    existing_ver_ids: set = set()
    if os.path.isdir(WALLPAPER_V):
        for fname in os.listdir(WALLPAPER_V):
            m = re.match(r'^wp_([a-zA-Z0-9]+)_ver', fname)
            if m:
                existing_ver_ids.add(m.group(1))

    for e in entries:
        if e.category != 'set':
            continue
        hor_basename = os.path.basename(e.hor_file)
        ver_basename = os.path.basename(e.ver_file)
        ver_ext = os.path.splitext(ver_basename)[1]

        # Generate unique new ID for ver file
        new_id = gen_id()
        while new_id in existing_ver_ids:
            new_id = gen_id()
        existing_ver_ids.add(new_id)

        new_ver_basename = f'wp_{new_id}_ver{ver_ext}'
        old_ver_path = os.path.join(WALLPAPER_V, ver_basename)
        new_ver_path = os.path.join(WALLPAPER_V, new_ver_basename)

        try:
            os.rename(old_ver_path, new_ver_path)
            # Rename thumb if present
            old_thumb = os.path.join(THUMB_DIR, os.path.splitext(ver_basename)[0] + '.png')
            new_thumb = os.path.join(THUMB_DIR, os.path.splitext(new_ver_basename)[0] + '.png')
            if os.path.exists(old_thumb):
                os.rename(old_thumb, new_thumb)
        except Exception:
            new_ver_basename = ver_basename  # keep original on failure

        name = theme_names.get(f'wp_{e.id}', e.id)
        sets[e.id] = WallpaperSet(
            set_id=e.id,
            name=name,
            images=[
                SetImage(file=hor_basename, monitor=None),
                SetImage(file=new_ver_basename, monitor=None),
            ],
        )
    save_sets(sets)
