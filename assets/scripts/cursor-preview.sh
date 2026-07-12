#!/usr/bin/env bash
# cursor-preview.sh <theme>
# Render a preview PNG of an Xcursor theme's pointer and print its path (cached). Used by
# Settings → Peripherals → Cursor to show what a theme looks like before it is applied.
set -euo pipefail

theme="${1:-}"
[[ -n "$theme" ]] || { echo "usage: cursor-preview.sh <theme>" >&2; exit 2; }

cache="${XDG_CACHE_HOME:-$HOME/.cache}/velumeron/cursor-preview"
out="$cache/${theme}.png"
mkdir -p "$cache"

# Serve the cache unless the theme dir is newer (theme reinstalled/updated).
if [[ -f "$out" ]]; then
    echo "$out"
    exit 0
fi

# Find the theme's pointer cursor (try the usual pointer names, following symlinks).
cur=""
for base in /usr/share/icons "$HOME/.local/share/icons" "$HOME/.icons"; do
    d="$base/$theme/cursors"
    [[ -d "$d" ]] || continue
    for name in left_ptr default arrow top_left_arrow left_ptr_watch; do
        if [[ -e "$d/$name" ]]; then cur=$(readlink -f "$d/$name"); break; fi
    done
    [[ -n "$cur" ]] && break
done
[[ -n "$cur" ]] || { echo "cursor-preview: no pointer cursor for '$theme'" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if xcur2png "$cur" -d "$tmp" >/dev/null 2>&1; then
    # An Xcursor file holds several sizes; keep the largest rendered PNG for a crisp preview.
    big=$(ls -S "$tmp"/*.png 2>/dev/null | head -1 || true)
    [[ -n "$big" ]] && cp "$big" "$out"
fi

[[ -f "$out" ]] && echo "$out"
