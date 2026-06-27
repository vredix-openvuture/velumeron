"""Notification-popup settings — read by the daemon, written by the GUI.

Kept separate from osd.json so system-OSD and notification settings don't
interfere with each other.
"""
from __future__ import annotations
import json, os

DEFAULTS: dict = {
    # Layout
    'notify_position':      'top-right',   # same 9-position grid as the system OSD
    'notify_style':         'float',       # 'float' | 'dock'
    'notify_margin_px':     12,            # gap from the anchored screen edges
    'notify_width_px':      380,           # card width in pixels
    # Stacking
    'notify_max_popups':    5,             # max visible cards before oldest is dropped
    'notify_stack_order':   'newest_top',  # 'newest_top' | 'newest_bottom'
    # Timing
    'notify_timeout_ms':    5000,          # default auto-dismiss (ms); 0 = never
    # Content
    'notify_show_icons':    True,          # show app/image icon on the card
    'notify_show_app_name': True,          # show app name in the header row
    # Interaction
    'notify_click_action':  'dismiss',     # 'dismiss' | 'action' | 'none'
    # Appearance details
    'notify_overlap_px':     5,            # how many px each card overlaps the one above/below
    'notify_heading_size_px': 14,          # font-size of the notification summary line (px)
}


def _user_dir() -> str:
    xdg = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.environ.get('VUTURELAND_USER_DIR', os.path.join(xdg, 'vutureland'))


def config_path() -> str:
    return os.path.join(_user_dir(), 'gui', 'notify.json')


def load() -> dict:
    cfg = dict(DEFAULTS)
    try:
        with open(config_path()) as f:
            data = json.load(f)
        for k in DEFAULTS:
            if k in data:
                cfg[k] = type(DEFAULTS[k])(data[k])
    except Exception:
        pass
    return cfg


def dock_edge(cfg: dict | None = None) -> str | None:
    """Return 'top'|'bottom'|'left'|'right' for the anchored screen edge in dock
    mode, or None when style is 'float'."""
    if cfg is None:
        cfg = load()
    if cfg.get('notify_style') != 'dock':
        return None
    pos = cfg.get('notify_position', 'top-right')
    if 'top'    in pos: return 'top'
    if 'bottom' in pos: return 'bottom'
    if 'left'   in pos: return 'left'
    if 'right'  in pos: return 'right'
    return None


def save(values: dict) -> None:
    cfg = load()
    cfg.update({k: v for k, v in values.items() if k in DEFAULTS})
    path = config_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            json.dump(cfg, f, indent=2)
    except OSError:
        pass
