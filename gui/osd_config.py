"""Shared OSD settings — read by the daemon (osd.py) and edited by the GUI
(pages/hyprland.py). Kept in its own JSON file so it stays decoupled from the
GUI's main settings.json (which main.py rewrites wholesale)."""
from __future__ import annotations
import json, os

DEFAULTS = {
    'duration_ms':    1600,  # how long the banner lingers after the last update
    'margin_px':       140,  # gap from the screen edge (direction depends on position)
    'width_px':        400,  # banner width  (long axis for horizontal, long axis for vertical)
    'height_px':        56,  # banner height (short axis for horizontal, short axis for vertical)
    'show_device':   False,  # show the audio output device name on volume changes
    'osd_volume':              True,
    'volume_display':         'bar_and_value',   # 'bar_and_value' | 'bar_only' | 'value_only'
    'osd_brightness':          True,
    'brightness_display':     'bar_and_value',   # 'bar_and_value' | 'bar_only' | 'value_only'
    'osd_workspace':           True,
    'osd_workspace_local_only': True,
    'workspace_display':      'dots_only',        # 'dots_only' | 'number_only' | 'dots_and_number'
    # Position: 'bottom-left' | 'bottom-center' | 'bottom-right'
    #           'top-left'    | 'top-center'    | 'top-right'
    #           'center-left' | 'center-right'   (vertical layout)
    'osd_position': 'bottom-center',
    # Style: 'float' — inset from the edge by margin_px (current default)
    #        'dock'  — flush against the screen edge, slides out like a drawer
    'osd_style': 'float',
}


def _user_dir() -> str:
    xdg = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.environ.get('VUTURELAND_USER_DIR', os.path.join(xdg, 'vutureland'))


def config_path() -> str:
    return os.path.join(_user_dir(), 'gui', 'osd.json')


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
