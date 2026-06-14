import re
from dataclasses import dataclass
from constants import USER_SETTINGS


@dataclass
class MonitorConfig:
    output: str
    mode: str
    transform: int = 0
    position: str = "auto"
    scale: float = 1.0
    bitdepth: int = 10
    supports_hdr: bool = False
    vrr: int = 0
    cm: str = "auto"


def _lua_val(v) -> str:
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def _read_section(content: str, name: str) -> str:
    m = re.search(rf'<<<{name}-START>>>(.*?)<<<{name}-END>>>', content, re.DOTALL)
    return m.group(1) if m else ''


def _write_section(content: str, name: str, new_body: str) -> str:
    # Capture the optional "-- " comment prefix on the START/END markers into the
    # marker groups, so it is preserved. Otherwise the prefix on the END marker
    # lives inside the replaced body and gets stripped, turning
    #   -- <<<NAME-END>>>   into   <<<NAME-END>>>   (invalid Lua).
    return re.sub(
        rf'((?:--[ \t]*)?<<<{name}-START>>>)(.*?)((?:--[ \t]*)?<<<{name}-END>>>)',
        lambda mo: mo.group(1) + new_body + mo.group(3),
        content, flags=re.DOTALL
    )


def _parse_kv(text: str) -> dict:
    result = {}
    for m in re.finditer(r'(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|\d+(?:\.\d+)?|true|false)', text):
        k, v = m.group(1), m.group(2)
        if v.startswith('"'):
            result[k] = v[1:-1]
        elif v == 'true':
            result[k] = True
        elif v == 'false':
            result[k] = False
        elif '.' in v:
            result[k] = float(v)
        else:
            result[k] = int(v)
    return result


def parse_monitors(content: str) -> list:
    section = _read_section(content, 'MONITORS')
    monitors = []
    for m in re.finditer(r'hl\.monitor\(\{(.*?)\}\)', section, re.DOTALL):
        kv = _parse_kv(m.group(1))
        monitors.append(MonitorConfig(
            output       = kv.get('output', ''),
            mode         = kv.get('mode', ''),
            transform    = kv.get('transform', 0),
            position     = kv.get('position', 'auto'),
            scale        = float(kv.get('scale', 1)),
            bitdepth     = kv.get('bitdepth', 10),
            supports_hdr = kv.get('supports_hdr', False),
            vrr          = kv.get('vrr', 0),
            cm           = kv.get('cm', 'auto'),
        ))
    return monitors


def generate_monitors_section(monitors: list) -> str:
    vars_ = '\n'.join(f'mon{i+1} = "{m.output}"' for i, m in enumerate(monitors))
    blocks = '\n\n'.join(
        f'hl.monitor({{\n'
        f'    output       = "{m.output}",\n'
        f'    mode         = "{m.mode}",\n'
        f'    transform    = {m.transform},\n'
        f'    position     = "{m.position}",\n'
        f'    scale        = {_lua_val(m.scale)},\n'
        f'    bitdepth     = {m.bitdepth},\n'
        f'    supports_hdr = {_lua_val(m.supports_hdr)},\n'
        f'    vrr          = {m.vrr},\n'
        f'    cm           = "{m.cm}",\n'
        f'}})'
        for m in monitors
    )
    return f'\n{vars_}\n\n{blocks}\n'


def parse_peripherals(content: str) -> dict:
    return _parse_kv(_read_section(content, 'PERIPHERALS'))


def generate_peripherals_section(p: dict) -> str:
    lines = [
        f'cur_theme  = "{p.get("cur_theme", "breeze_cursors")}"',
        f'cur_size   = {p.get("cur_size", 20)}',
        f'kb_layout  = "{p.get("kb_layout", "eu")}"',
        f'sys_locale = "{p.get("sys_locale", "en_US.UTF-8")}"',
    ]
    # Only write terminal/browser when non-empty so Lua's `or` fallback still works
    if p.get('terminal'):
        lines.append(f'terminal   = "{p["terminal"]}"')
    if p.get('browser'):
        lines.append(f'browser    = "{p["browser"]}"')
    return '\n' + '\n'.join(lines) + '\n'


def parse_autostart(content: str):
    section = _read_section(content, 'AUTOSTART')
    daemons = []
    m = re.search(r'exec_once_daemons\s*=\s*\{([^}]+)\}', section, re.DOTALL)
    if m:
        daemons = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
    apps = []
    m = re.search(r'start_apps\s*=\s*\{(.*)\}\s*$', section, re.DOTALL)
    if m:
        for am in re.finditer(
                r'\{\s*app\s*=\s*"((?:[^"\\]|\\.)*)",\s*ws\s*=\s*(\d+)\s*\}',
                m.group(1)):
            apps.append({'app': am.group(1), 'ws': int(am.group(2))})
    return daemons, apps


def generate_autostart_section(daemons: list, apps: list) -> str:
    d = ',\n'.join(f'    "{d}"' for d in daemons)
    a = ',\n'.join(f'    {{ app = "{e["app"]}", ws = {e["ws"]} }}' for e in apps)
    return (
        f'\nexec_once_daemons = {{\n{d}\n}}\n\n'
        f'-- {{ app = command, ws = workspace_number }}\n'
        f'start_apps = {{\n{a}\n}}\n'
    )


def parse_windowrules(content: str):
    kv = _parse_kv(_read_section(content, 'WINDOWRULES'))
    return kv.get('floating_window', ''), kv.get('opacity_window', '')


def generate_windowrules_section(floating: str, opacity: str) -> str:
    return f'\nfloating_window = "{floating}"\nopacity_window  = "{opacity}"\n'


def parse_rule_entries(pattern: str) -> list:
    """Turn a window-rule regex into a list of plain app names for the GUI list.
    e.g.  (.*[Kk]itty.*|.*[Aa]rk.*)  ->  ['kitty', 'ark'].
    Unrecognised tokens are kept verbatim so nothing is silently dropped."""
    pattern = (pattern or '').strip()
    if pattern.startswith('(') and pattern.endswith(')'):
        pattern = pattern[1:-1]
    names = []
    for tok in pattern.split('|'):
        tok = tok.strip()
        if not tok:
            continue
        m = re.match(r'^\.\*\[(.)(.)\](.*)\.\*$', tok)
        if m and m.group(1).lower() == m.group(2).lower():
            names.append(m.group(2).lower() + m.group(3))
        else:
            names.append(tok)
    return names


def build_rule_pattern(names: list) -> str:
    """Inverse of parse_rule_entries: ['kitty', 'ark'] -> (.*[Aa]rk.*|.*[Kk]itty.*).
    De-duplicated and sorted alphabetically (case-insensitive)."""
    toks = []
    for n in sorted({x.strip() for x in names if x and x.strip()}, key=str.lower):
        c = n[0]
        head = f'[{c.upper()}{c.lower()}]' if c.isalpha() else c
        toks.append(f'.*{head}{n[1:]}.*')
    return '(' + '|'.join(toks) + ')' if toks else ''


# ── Look and Feel (overrides for hypr.lua defaults) ──────────────────────────
# Defaults must mirror hypr.lua/modules/look_and_feel.lua so an un-set value
# shows the same number the config would use.
LNF_DEFAULTS = {'lnf_rounding': 10, 'lnf_border_size': 2}


def parse_lookandfeel(content: str) -> dict:
    return _parse_kv(_read_section(content, 'LOOKANDFEEL'))


def generate_lookandfeel_section(rounding: int, border_size: int) -> str:
    return (f'\nlnf_rounding     = {int(rounding)}\n'
            f'lnf_border_size  = {int(border_size)}\n')


def ensure_lookandfeel_section(content: str) -> str:
    """Append the LOOKANDFEEL markers if an older user_settings.lua lacks them,
    so _write_section can target the section."""
    if '<<<LOOKANDFEEL-START>>>' in content:
        return content
    return content.rstrip('\n') + (
        '\n\n\n-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
        '-- Look and Feel — overrides for hypr.lua defaults.\n'
        '-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
        '-- <<<LOOKANDFEEL-START>>>\n-- <<<LOOKANDFEEL-END>>>\n')


def read_user_settings() -> str:
    with open(USER_SETTINGS) as f:
        return f.read()


def write_user_settings(content: str):
    with open(USER_SETTINGS, 'w') as f:
        f.write(content)
