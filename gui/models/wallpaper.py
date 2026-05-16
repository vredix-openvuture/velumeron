import os, re, json, subprocess, random, string
from dataclasses import dataclass
from typing import Optional
from constants import (
    WALLPAPER_H, WALLPAPER_V, THUMB_DIR, THEME_NAMES,
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
