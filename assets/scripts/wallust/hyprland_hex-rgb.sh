#!/usr/bin/env bash

file=~/.config/vutureland/assets/colors_hyprland.conf

while IFS= read -r line; do
    if [[ "$line" == *"#"* ]]; then
        varname="${line%%=*}"
        hex="${line#*=}"
        hex="${hex//[[:space:]]/}"
        hex="${hex#\#}"

        r=$((16#${hex:0:2}))
        g=$((16#${hex:2:2}))
        b=$((16#${hex:4:2}))

        echo "${varname}= rgb($r,$g,$b)"
    else
        echo "$line"
    fi
done < "$file" > "$file.tmp"

mv "$file.tmp" "$file"
