"""Cross-app design (theme) switching.

A *design* (e.g. ``miboro``) is both a Waybar layout set
(``waybar-modular/config/<design>/``) and a per-app theme
(``themes/<design>`` files for hyprland, swaync and this GUI). Picking a design
records it in ``active-theme`` and makes every app adopt it — this is the logic
that used to live behind the Waybar page's "Design" dropdown, now driven from the
Home page (the theme name overlaid on the wallpaper preview).
"""
from __future__ import annotations
import os, sys, subprocess

from constants import LAUNCH_WAYBAR
from models.waybar import (
    scan_config_styles, scan_bar_styles, active_bar_for_monitor,
    _known_monitors, BarConfig, init_groups_json, refresh_groups_includes,
    build_bar_config, remove_other_bar_configs,
)


def _user_dir() -> str:
    return os.environ.get('VUTURELAND_USER_DIR') or os.path.join(
        os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config')),
        'vutureland')


def _vtl() -> str:
    return os.environ.get('VUTURELAND_DIR') or os.path.realpath(
        os.path.join(os.path.dirname(__file__), '..'))


def _clean_env() -> dict:
    env = dict(os.environ)
    env.pop('LD_PRELOAD', None)
    return env


def list_designs() -> list[str]:
    """Available designs — the waybar config dirs (each also has themes/<d> files)."""
    return scan_config_styles()


def current_design() -> str:
    """The active design, from the ``active-theme`` record (fallback: first / miboro)."""
    designs = list_designs()
    try:
        with open(os.path.join(_user_dir(), 'active-theme')) as f:
            d = f.read().strip()
        if d:
            return d
    except OSError:
        pass
    return designs[0] if designs else 'miboro'


def _rebuild_waybar(design: str) -> None:
    """Rebuild each monitor's active bar under `design`, keeping its style/position
    where the design provides it. Clears stale bars so launch-waybar.sh merges only
    the new design's configs."""
    styles = scan_bar_styles(design)
    if not styles:
        return
    style_names = {s.name for s in styles}
    for monitor in _known_monitors():
        active = active_bar_for_monitor(monitor)
        if not active:
            continue
        _d, style, position = active
        if style not in style_names:          # design lacks this style → first one
            style, position = styles[0].name, styles[0].position
        bar = BarConfig(style=style, position=position, monitor=monitor, design=design)
        remove_other_bar_configs(monitor, style, design, position)
        init_groups_json(bar)
        refresh_groups_includes(bar)
        build_bar_config(bar)
        bs = next((s for s in styles if s.name == style), None)
        if bs and bs.is_frame:               # frame styles need their sibling bars too
            for pos in bs.sub_positions:
                if pos == position:
                    continue
                sib = BarConfig(style=style, position=pos, monitor=monitor, design=design)
                init_groups_json(sib)
                refresh_groups_includes(sib)
                build_bar_config(sib)


def apply_design(design: str) -> None:
    """Switch the active design and make every app adopt it — exactly what the
    Waybar page used to do when a design was selected there."""
    # 1. Record the active design
    try:
        with open(os.path.join(_user_dir(), 'active-theme'), 'w') as f:
            f.write(design + '\n')
    except OSError:
        pass

    # 2. Rebuild + restart Waybar for the new design
    try:
        _rebuild_waybar(design)
        subprocess.Popen(['bash', LAUNCH_WAYBAR], env=_clean_env())
    except Exception:
        pass

    # 3. GUI: restyle live (the running app's main module owns the provider)
    for modname in ('__main__', 'main'):
        m = sys.modules.get(modname)
        fn = getattr(m, 'reload_design_theme', None) if m else None
        if fn:
            try:
                fn()
            except Exception:
                pass
            break

    # 4. swaync (re-reads active-theme) + hyprland (hyprctl reload re-runs the config)
    vtl = _vtl()
    try:
        subprocess.Popen(['bash', os.path.join(vtl, 'assets', 'scripts', 'launch-swaync.sh')],
                         env=_clean_env())
    except Exception:
        pass
    try:
        subprocess.Popen(['hyprctl', 'reload'], env=_clean_env())
    except Exception:
        pass
