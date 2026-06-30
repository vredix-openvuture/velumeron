#!/usr/bin/env bash
# wallpaper-auto.sh <silent|show>
# Picks the NEXT wallpaper for the main (focused) monitor following the configured order, then
# applies it via wallpaper-set.sh's per-monitor path — which also drives the colour theme (it's the
# focused monitor). Driven on a timer by the quickshell shell when wallpaper_auto_mode != off.
#
#   order (settings.json wallpaper_auto_order):
#     alpha_all   – every file across all subfolders, one alphabetical list
#     alpha_per   – alphabetical, grouped per subfolder (folder order, then name)
#     random_all  – random pick from the whole pool (avoids immediate repeat)
#     random_per  – advance subfolder each tick, random pick within it
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

mode="${1:-silent}"   # silent | show

main=$(hyprctl monitors -j 2>/dev/null | jq -r '[.[] | select(.focused)][0].name // .[0].name')
[[ -z "$main" || "$main" == "null" ]] && exit 0
main_vertical=$(hyprctl monitors -j 2>/dev/null | jq -r --arg m "$main" \
    '[.[] | select(.name==$m)][0] | ((.transform%2)==1) or (.height > .width)')

next=$(python3 - "$main" "$main_vertical" <<'PY'
import json, os, sys, random
mon  = sys.argv[1]
vert = (sys.argv[2] == 'true')
pu = os.environ.get('VELUMERON_USER_DIR') or os.path.join(
        os.environ.get('XDG_CONFIG_HOME','') or os.path.expanduser('~/.config'), 'velumeron')
sp = os.path.join(pu, 'gui', 'settings.json')
d  = json.load(open(sp)) if os.path.exists(sp) else {}
vd = os.environ.get('VELUMERON_DIR', '')
order = d.get('wallpaper_auto_order', 'alpha_all')

# Monitor's wallpaper folder: per-monitor dir → orientation-matched legacy/env → bundled.
legacy  = d.get('wallpaper_dir_ver' if vert else 'wallpaper_dir_hor')
envd    = os.environ.get('WALLPAPER_DIR_V' if vert else 'WALLPAPER_DIR_H')
bundled = os.path.join(vd, 'assets/wallpaper/' + ('vertical' if vert else 'horizontal'))
dirp = (d.get('wallpaper_dirs', {}) or {}).get(mon) or legacy or envd or bundled
dirp = os.path.expanduser(dirp or '')
if not dirp or not os.path.isdir(dirp):
    sys.exit(0)

exts = {'.png', '.jpg', '.jpeg', '.webp', '.mp4', '.webm', '.mkv', '.avi', '.mov'}
items = []   # (subfolder, fullpath); '' = directly in dirp
for rootd, _dirs, files in os.walk(dirp):
    rel = os.path.relpath(rootd, dirp)
    sub = '' if rel == '.' else rel.split(os.sep)[0]
    for f in files:
        if os.path.splitext(f)[1].lower() in exts:
            items.append((sub, os.path.join(rootd, f)))
if not items:
    sys.exit(0)

st_path = os.path.join(pu, 'wallust', 'auto-state.json')
try:    st = json.load(open(st_path))
except Exception: st = {}
last = st.get('last', '')

if order in ('alpha_all', 'alpha_per'):
    if order == 'alpha_all':
        lst = [p for _s, p in sorted(items, key=lambda x: os.path.basename(x[1]).lower())]
    else:
        lst = [p for _s, p in sorted(items, key=lambda x: (x[0].lower(), os.path.basename(x[1]).lower()))]
    choice = lst[(lst.index(last) + 1) % len(lst)] if last in lst else lst[0]
elif order == 'random_per':
    subs = sorted({s for s, _ in items})
    si   = (int(st.get('sub_idx', -1)) + 1) % len(subs)
    pool = [p for s, p in items if s == subs[si]]
    if len(pool) > 1 and last in pool:
        pool = [p for p in pool if p != last]
    choice = random.choice(pool)
    st['sub_idx'] = si
else:   # random_all (default)
    pool = [p for _s, p in items]
    if len(pool) > 1 and last in pool:
        pool = [p for p in pool if p != last]
    choice = random.choice(pool)

st['last'] = choice
os.makedirs(os.path.dirname(st_path), exist_ok=True)
open(st_path, 'w').write(json.dumps(st))
print(choice)
PY
)

[[ -z "$next" ]] && exit 0

sc_flag="--no-showcase"
[[ "$mode" == "show" ]] && sc_flag=""

# Detached so it survives the wallust qs_reload that restarts quickshell.
# shellcheck disable=SC2086
setsid -f bash "$VELUMERON_DIR/assets/scripts/wallpaper-set.sh" --no-waybar $sc_flag \
    --mon "$main" --file "$next" >>/tmp/vtl-wp.log 2>&1
