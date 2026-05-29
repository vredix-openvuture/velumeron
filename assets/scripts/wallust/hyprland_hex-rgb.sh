#!/usr/bin/env bash
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/../lib/env.sh"

file="$VUTURELAND_USER_DIR/assets/colors_hyprland.conf"

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

# cp follows the symlink target; mv would replace the symlink itself
cp "$file.tmp" "$file" && rm -f "$file.tmp"
