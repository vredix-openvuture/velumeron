from __future__ import annotations
import json, os, re, shutil
from dataclasses import dataclass, field

_POSITIONS = frozenset({"top", "bottom", "left", "right"})


def _vtl() -> str:
    return os.path.expanduser("~/.config/vutureland")


def _output_dir() -> str:
    return os.path.join(_vtl(), "waybar-modular", "output")


def _modules_dir() -> str:
    return os.path.join(_vtl(), "waybar-modular", "modules")


def _effective_base_dir(design: str) -> str:
    if design:
        return os.path.join(_vtl(), "waybar-modular", "config", design, "base")
    return os.path.join(_vtl(), "waybar-modular", "base")


def _effective_modules_dir(design: str) -> str:
    if design:
        return os.path.join(_vtl(), "waybar-modular", "config", design, "modules")
    return _modules_dir()


def scan_config_styles() -> list[str]:
    """Return sorted list of design style names from waybar-modular/config/."""
    config_dir = os.path.join(_vtl(), "waybar-modular", "config")
    if not os.path.isdir(config_dir):
        return []
    return sorted(d for d in os.listdir(config_dir)
                  if os.path.isdir(os.path.join(config_dir, d)))


@dataclass
class BarConfig:
    style: str
    position: str
    monitor: str
    design: str = ""

    @property
    def groups_file(self) -> str:
        if self.design:
            return os.path.join(_output_dir(), self.design, self.style, self.position, self.monitor, "groups.json")
        return os.path.join(_output_dir(), self.style, self.position, self.monitor, "groups.json")

    @property
    def label(self) -> str:
        if self.design:
            return f"{self.design} / {self.style} / {self.position}"
        return f"{self.style} / {self.position}"

    def orientation(self) -> str:
        return "horizontal" if self.position in ("top", "bottom") else "vertical"

    def modules_orientation(self) -> str:
        if self.position == "left":
            return "vertical-left"
        if self.position == "right":
            return "vertical-right"
        return "horizontal"


def _known_monitors() -> list[str]:
    """Collect monitor names from existing output tree (both legacy and design structures)."""
    monitors: set[str] = set()
    out = _output_dir()
    if not os.path.isdir(out):
        return []
    for d1 in os.listdir(out):
        p1 = os.path.join(out, d1)
        if not os.path.isdir(p1):
            continue
        for d2 in os.listdir(p1):
            p2 = os.path.join(p1, d2)
            if not os.path.isdir(p2):
                continue
            if d2 in _POSITIONS:
                # Legacy: output/{style}/{position}/{monitor}
                monitors.update(m for m in os.listdir(p2) if os.path.isdir(os.path.join(p2, m)))
            else:
                # Design: output/{design}/{style}/{position}/{monitor}
                for d3 in os.listdir(p2):
                    p3 = os.path.join(p2, d3)
                    if os.path.isdir(p3) and d3 in _POSITIONS:
                        monitors.update(m for m in os.listdir(p3) if os.path.isdir(os.path.join(p3, m)))
    return sorted(monitors)


def _build_includes(orientation: str, design: str = "") -> list[str]:
    """Collect all module config.json paths for the given orientation."""
    orient_dir = os.path.join(_effective_modules_dir(design), orientation)
    includes = []
    if os.path.isdir(orient_dir):
        for folder in sorted(os.listdir(orient_dir)):
            cfg = os.path.join(orient_dir, folder, "config.json")
            if os.path.exists(cfg):
                includes.append(cfg)
    return includes


def _build_module_css(orientation: str, design: str = "") -> list[str]:
    """Collect all module style.css paths for the given orientation."""
    orient_dir = os.path.join(_effective_modules_dir(design), orientation)
    css_files = []
    if os.path.isdir(orient_dir):
        for folder in sorted(os.listdir(orient_dir)):
            css = os.path.join(orient_dir, folder, "style.css")
            if os.path.exists(css):
                css_files.append(css)
    return css_files


def init_groups_json(bar: BarConfig) -> None:
    """Create groups.json skeleton (with module includes) if it doesn't exist yet."""
    gf = bar.groups_file
    if os.path.exists(gf):
        return
    os.makedirs(os.path.dirname(gf), exist_ok=True)
    orient = bar.orientation()
    includes = _build_includes(bar.modules_orientation(), bar.design)
    data: dict = {}
    if includes:
        data["include"] = includes
    data.update({
        "group/left":   {"orientation": orient, "modules": []},
        "group/center": {"orientation": orient, "modules": []},
        "group/right":  {"orientation": orient, "modules": []},
    })
    with open(gf, "w") as f:
        json.dump(data, f, indent=2)


def refresh_groups_includes(bar: BarConfig) -> None:
    """Ensure groups.json has up-to-date module includes."""
    gf = bar.groups_file
    if not os.path.exists(gf):
        return
    includes = _build_includes(bar.modules_orientation(), bar.design)
    if not includes:
        return
    with open(gf) as f:
        data = json.load(f)
    data["include"] = includes
    with open(gf, "w") as f:
        json.dump(data, f, indent=2)


def _is_frame_style(style: str, design: str) -> bool:
    base_dir = _effective_base_dir(design)
    frame_cfg = os.path.join(base_dir, "base-frame", f"{style}.config.json")
    return os.path.exists(frame_cfg) and os.path.getsize(frame_cfg) > 0


def remove_other_bar_configs(monitor: str, keep_style: str, keep_design: str = "", keep_position: str = "") -> None:
    """Delete config.json for all style/design/position combos except the kept one on the given monitor."""
    out = _output_dir()
    if not os.path.isdir(out):
        return
    for d1 in os.listdir(out):
        p1 = os.path.join(out, d1)
        if not os.path.isdir(p1):
            continue
        for d2 in os.listdir(p1):
            p2 = os.path.join(p1, d2)
            if not os.path.isdir(p2):
                continue
            if d2 in _POSITIONS:
                # Legacy structure: d1=style, d2=position
                if d1 == keep_style and keep_design == "":
                    if _is_frame_style(keep_style, "") or d2 == keep_position:
                        continue
                cfg = os.path.join(p2, monitor, "config.json")
                if os.path.exists(cfg):
                    os.remove(cfg)
            else:
                # Design structure: d1=design, d2=style
                if d1 == keep_design and d2 == keep_style:
                    if _is_frame_style(keep_style, keep_design):
                        continue  # frame: keep all positions (built explicitly in _on_apply)
                    # Non-frame: only keep the selected position
                    for pos in os.listdir(p2):
                        p3 = os.path.join(p2, pos)
                        if os.path.isdir(p3) and pos != keep_position:
                            cfg = os.path.join(p3, monitor, "config.json")
                            if os.path.exists(cfg):
                                os.remove(cfg)
                else:
                    for pos in os.listdir(p2):
                        p3 = os.path.join(p2, pos)
                        if os.path.isdir(p3):
                            cfg = os.path.join(p3, monitor, "config.json")
                            if os.path.exists(cfg):
                                os.remove(cfg)


def build_bar_config(bar: BarConfig) -> None:
    """Generate config.json and style.css in the output dir from the base template."""
    base_dir = _effective_base_dir(bar.design)

    # Try frame template first (base-frame/{style}.config.json)
    frame_cfg = os.path.join(base_dir, "base-frame", f"{bar.style}.config.json")
    if os.path.exists(frame_cfg) and os.path.getsize(frame_cfg) > 0:
        is_frame = True
        base_cfg_path = frame_cfg
        css_src = os.path.join(base_dir, "base-frame", f"{bar.style}.css")
    else:
        base_cfg_path = os.path.join(base_dir, f"base-{bar.position}", f"{bar.style}.config.json")
        if not os.path.exists(base_cfg_path) or os.path.getsize(base_cfg_path) == 0:
            return
        is_frame = False
        css_src = os.path.join(base_dir, f"base-{bar.position}", f"{bar.style}.css")

    with open(base_cfg_path) as f:
        base = json.load(f)

    entry = (
        next((e for e in base if e.get("position") == bar.position), None)
        if is_frame else base
    )
    if entry is None:
        return

    out = dict(entry)
    out["output"] = bar.monitor
    out["id"] = f"{bar.style}-{bar.position}-{bar.monitor}"
    out["include"] = [bar.groups_file]
    out["modules-left"] = ["group/left"]
    out["modules-center"] = ["group/center"]
    out["modules-right"] = ["group/right"]

    out_dir = os.path.dirname(bar.groups_file)
    os.makedirs(out_dir, exist_ok=True)

    config_path = os.path.join(out_dir, "config.json")
    with open(config_path, "w") as f:
        json.dump(out, f, indent=2)

    css_dst = os.path.join(out_dir, "style.css")
    with open(css_dst, "w") as f:
        if os.path.exists(css_src):
            f.write(f'@import url("{css_src}");\n')
        for module_css in _build_module_css(bar.modules_orientation(), bar.design):
            f.write(f'@import url("{module_css}");\n')


@dataclass
class BarStyle:
    """One entry from base/ — represents an available bar type."""
    name: str
    position: str
    is_frame: bool
    sub_positions: list[str]
    config_path: str


def scan_bar_styles(design: str = "") -> list[BarStyle]:
    """Scan base dir for ALL .config.json files."""
    styles: list[BarStyle] = []
    base_dir = _effective_base_dir(design)
    if not os.path.isdir(base_dir):
        return styles
    for pos_dir in sorted(os.listdir(base_dir)):
        if not pos_dir.startswith("base-"):
            continue
        dir_pos = pos_dir[len("base-"):]
        is_frame = (dir_pos == "frame")
        pd = os.path.join(base_dir, pos_dir)
        if not os.path.isdir(pd):
            continue
        for fname in sorted(os.listdir(pd)):
            if not fname.endswith(".config.json"):
                continue
            fp = os.path.join(pd, fname)
            if is_frame and os.path.getsize(fp) == 0:
                continue
            name = fname[:-len(".config.json")]
            if is_frame:
                try:
                    with open(fp) as f:
                        cfg = json.load(f)
                    seen_pos: set[str] = set()
                    sub_pos: list[str] = []
                    for entry in cfg:
                        p = entry.get("position")
                        if p and p not in seen_pos:
                            sub_pos.append(p)
                            seen_pos.add(p)
                except Exception:
                    sub_pos = []
            elif not is_frame:
                sub_pos = [dir_pos]
            else:
                sub_pos = []
            styles.append(BarStyle(
                name=name, position=dir_pos, is_frame=is_frame,
                sub_positions=sub_pos, config_path=fp,
            ))
    return styles


def _auto_init_from_base(base_dir: str, design: str, monitors: list,
                          seen: set, bars: list) -> None:
    """Auto-init groups.json for base configs not yet present in output."""
    for pos_dir in sorted(os.listdir(base_dir)):
        if not pos_dir.startswith("base-"):
            continue
        dir_pos = pos_dir[len("base-"):]
        pd = os.path.join(base_dir, pos_dir)
        if not os.path.isdir(pd):
            continue
        for fname in sorted(os.listdir(pd)):
            if not fname.endswith(".config.json"):
                continue
            fp = os.path.join(pd, fname)
            if os.path.getsize(fp) == 0:
                continue
            style = fname[:-len(".config.json")]
            if dir_pos == "frame":
                try:
                    with open(fp) as f:
                        cfg = json.load(f)
                    sub_positions = {e["position"] for e in cfg if "position" in e}
                except Exception:
                    sub_positions = {"top"}
                for position in sorted(sub_positions):
                    for monitor in monitors:
                        key = (design, style, position, monitor)
                        if key not in seen:
                            bar = BarConfig(style=style, position=position,
                                            monitor=monitor, design=design)
                            init_groups_json(bar)
                            bars.append(bar)
                            seen.add(key)
            else:
                position = dir_pos
                for monitor in monitors:
                    key = (design, style, position, monitor)
                    if key not in seen:
                        bar = BarConfig(style=style, position=position,
                                        monitor=monitor, design=design)
                        init_groups_json(bar)
                        bars.append(bar)
                        seen.add(key)


def scan_bars() -> list[BarConfig]:
    bars: list[BarConfig] = []
    seen: set[tuple] = set()
    out = _output_dir()

    # 1. Existing output bars (legacy + design structures)
    if os.path.isdir(out):
        for d1 in sorted(os.listdir(out)):
            p1 = os.path.join(out, d1)
            if not os.path.isdir(p1):
                continue
            for d2 in sorted(os.listdir(p1)):
                p2 = os.path.join(p1, d2)
                if not os.path.isdir(p2):
                    continue
                if d2 in _POSITIONS:
                    # Legacy: output/{style}/{position}/{monitor}
                    for monitor in sorted(os.listdir(p2)):
                        md = os.path.join(p2, monitor)
                        if os.path.isdir(md) and os.path.exists(os.path.join(md, "groups.json")):
                            bars.append(BarConfig(style=d1, position=d2, monitor=monitor, design=""))
                            seen.add(("", d1, d2, monitor))
                else:
                    # Design: output/{design}/{style}/{position}/{monitor}
                    for d3 in sorted(os.listdir(p2)):
                        p3 = os.path.join(p2, d3)
                        if not os.path.isdir(p3) or d3 not in _POSITIONS:
                            continue
                        for monitor in sorted(os.listdir(p3)):
                            md = os.path.join(p3, monitor)
                            if os.path.isdir(md) and os.path.exists(os.path.join(md, "groups.json")):
                                bars.append(BarConfig(style=d2, position=d3, monitor=monitor, design=d1))
                                seen.add((d1, d2, d3, monitor))

    # 2. Auto-init groups.json for configs not yet in output
    monitors = _known_monitors()
    if monitors:
        legacy_base = os.path.join(_vtl(), "waybar-modular", "base")
        if os.path.isdir(legacy_base):
            _auto_init_from_base(legacy_base, "", monitors, seen, bars)

        config_dir = os.path.join(_vtl(), "waybar-modular", "config")
        if os.path.isdir(config_dir):
            for design in sorted(os.listdir(config_dir)):
                design_base = os.path.join(config_dir, design, "base")
                if os.path.isdir(design_base):
                    _auto_init_from_base(design_base, design, monitors, seen, bars)

    return bars


def read_bar_slots(bar: BarConfig) -> tuple[list, list, list]:
    if not os.path.exists(bar.groups_file):
        return [], [], []
    with open(bar.groups_file) as f:
        data = json.load(f)
    left   = data.get("group/left",   {}).get("modules", [])
    center = data.get("group/center", {}).get("modules", [])
    right  = data.get("group/right",  {}).get("modules", [])
    return list(left), list(center), list(right)


def write_bar_slots(bar: BarConfig, left: list, center: list, right: list) -> None:
    if not os.path.exists(bar.groups_file):
        return
    with open(bar.groups_file) as f:
        data = json.load(f)
    orient = bar.orientation()
    for key, mods in [("group/left", left), ("group/center", center), ("group/right", right)]:
        if key not in data:
            data[key] = {"orientation": orient, "modules": []}
        data[key]["modules"] = mods
    with open(bar.groups_file, "w") as f:
        json.dump(data, f, indent=2)


def scan_modules_by_section(orientation: str = "horizontal", design: str = "") -> list[tuple[str, list[tuple[str, str, str]]]]:
    """Return [(section_name, [(waybar_key, display_name, description), ...]), ...] from modules.md order."""
    mdir = _effective_modules_dir(design)
    orient_dir = os.path.join(mdir, orientation)
    modules_md = os.path.join(mdir, "modules.md")
    containers_md = os.path.join(mdir, "containers.md")

    folder_meta: dict[str, dict] = {}
    if os.path.isdir(orient_dir):
        for folder in os.listdir(orient_dir):
            fp = os.path.join(orient_dir, folder)
            for md_name in ("module.md", "container.md"):
                md_path = os.path.join(fp, md_name)
                if not os.path.exists(md_path):
                    continue
                content = open(md_path).read()
                key_m   = re.search(r'^name\s*=\s*"([^"]+)"',        content, re.M)
                alias_m = re.search(r'^alias\s*=\s*"([^"]+)"',       content, re.M)
                desc_m  = re.search(r'^description\s*=\s*"([^"]+)"', content, re.M)
                key     = key_m.group(1)   if key_m   else folder
                display = alias_m.group(1) if alias_m else folder.replace("-", " ").title()
                desc    = desc_m.group(1)  if desc_m  else ""
                folder_meta[folder] = {"key": key, "display": display, "description": desc}
                break

    sections: list[tuple[str, list]] = []
    seen: set[str] = set()

    for md_path in (modules_md, containers_md):
        if not os.path.exists(md_path):
            continue
        cur_section = ""
        cur_mods: list[tuple[str, str, str]] = []
        for raw_line in open(md_path):
            line = raw_line.rstrip()
            if line.startswith("#"):
                if cur_mods:
                    sections.append((cur_section, cur_mods))
                    cur_mods = []
                cur_section = line.lstrip("#").strip()
                continue
            folder = line.strip()
            if not folder or folder not in folder_meta or folder in seen:
                continue
            meta = folder_meta[folder]
            cur_mods.append((meta["key"], meta["display"], meta["description"]))
            seen.add(folder)
        if cur_mods:
            sections.append((cur_section, cur_mods))

    extras: list[tuple[str, str, str]] = []
    for folder, meta in sorted(folder_meta.items()):
        if folder not in seen:
            extras.append((meta["key"], meta["display"], meta["description"]))
    if extras:
        sections.append(("Other", extras))

    return sections
