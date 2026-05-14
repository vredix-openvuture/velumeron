#!/usr/bin/env bash
# Converts hex color values in hypr.lua/colors.lua from "#rrggbb" to "rgb(r,g,b)".
# Called as a wallust hook after the colors.lua template is rendered.

file=~/.config/vutureland/hypr.lua/colors.lua

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
done < "$file" > "$file.tmp"

mv "$file.tmp" "$file"
