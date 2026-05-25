from __future__ import annotations
import json, os, re
from dataclasses import dataclass


def _vtl() -> str:
    return os.path.expanduser("~/.config/vutureland")


def _output_dir() -> str:
    return os.path.join(_vtl(), "waybar-modular", "output")


def _modules_dir() -> str:
    return os.path.join(_vtl(), "waybar-modular", "modules")


@dataclass
class BarConfig:
    style: str
    position: str
    monitor: str

    @property
    def groups_file(self) -> str:
        return os.path.join(_output_dir(), self.style, self.position, self.monitor, "groups.json")

    @property
    def label(self) -> str:
        return f"{self.style} / {self.position}"

    def orientation(self) -> str:
        return "horizontal" if self.position in ("top", "bottom") else "vertical"


def scan_bars() -> list[BarConfig]:
    bars: list[BarConfig] = []
    out = _output_dir()
    if not os.path.isdir(out):
        return bars
    for style in sorted(os.listdir(out)):
        sd = os.path.join(out, style)
        if not os.path.isdir(sd):
            continue
        for position in sorted(os.listdir(sd)):
            pd = os.path.join(sd, position)
            if not os.path.isdir(pd):
                continue
            for monitor in sorted(os.listdir(pd)):
                md = os.path.join(pd, monitor)
                if os.path.isdir(md) and os.path.exists(os.path.join(md, "groups.json")):
                    bars.append(BarConfig(style=style, position=position, monitor=monitor))
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


def scan_modules_by_section(orientation: str = "horizontal") -> list[tuple[str, list[tuple[str, str]]]]:
    """Return [(section_name, [(waybar_key, display_name), ...]), ...] from modules.md order."""
    orient_dir = os.path.join(_modules_dir(), orientation)
    modules_md = os.path.join(_modules_dir(), "modules.md")
    containers_md = os.path.join(_modules_dir(), "containers.md")

    # Scan module folders for key + display
    folder_meta: dict[str, dict] = {}
    if os.path.isdir(orient_dir):
        for folder in os.listdir(orient_dir):
            fp = os.path.join(orient_dir, folder)
            for md_name in ("module.md", "container.md"):
                md_path = os.path.join(fp, md_name)
                if not os.path.exists(md_path):
                    continue
                content = open(md_path).read()
                key_m   = re.search(r'^name\s*=\s*"([^"]+)"',  content, re.M)
                alias_m = re.search(r'^alias\s*=\s*"([^"]+)"', content, re.M)
                key     = key_m.group(1)   if key_m   else folder
                display = alias_m.group(1) if alias_m else folder.replace("-", " ").title()
                folder_meta[folder] = {"key": key, "display": display}
                break

    sections: list[tuple[str, list]] = []
    seen: set[str] = set()

    for md_path in (modules_md, containers_md):
        if not os.path.exists(md_path):
            continue
        cur_section = ""
        cur_mods: list[tuple[str, str]] = []
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
            cur_mods.append((meta["key"], meta["display"]))
            seen.add(folder)
        if cur_mods:
            sections.append((cur_section, cur_mods))

    # Append any module not listed in md files
    extras: list[tuple[str, str]] = []
    for folder, meta in sorted(folder_meta.items()):
        if folder not in seen:
            extras.append((meta["key"], meta["display"]))
    if extras:
        sections.append(("Other", extras))

    return sections
