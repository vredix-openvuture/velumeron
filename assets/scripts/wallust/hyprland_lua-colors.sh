#!/usr/bin/env bash
# Converts hex color values in hypr.lua/colors.lua from "#rrggbb" to "rgb(r,g,b)".
# Called as a wallust hook after the colors.lua template is rendered.
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/../lib/env.sh"

file="$VELUMERON_USER_DIR/hypr.lua/colors.lua"

# Unique temp (never a shared "$file.tmp") so two runs can't clobber each other's scratch file and
# leave colors.lua full of NUL bytes (which breaks the Hyprland config). wallpaper-set.sh also
# serialises wallust via flock; this is cheap defence-in-depth.
tmp=$(mktemp "${file}.XXXXXX")

while IFS= read -r line; do
    if [[ "$line" =~ \"#([0-9a-fA-F]{6})\" ]]; then
        hex="${BASH_REMATCH[1]}"
        r=$((16#${hex:0:2}))
        g=$((16#${hex:2:2}))
        b=$((16#${hex:4:2}))
        echo "${line/\"#${hex}\"/\"rgb($r,$g,$b)\"}"
    else
        echo "$line"
    fi
done < "$file" > "$tmp"

# cp follows the symlink target if colors.lua is one; mv would replace the symlink itself
cp "$tmp" "$file" && rm -f "$tmp"
