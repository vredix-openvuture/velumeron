#!/usr/bin/env bash
# update-check.sh [--no-aur] [--no-flatpak]
# Counts available updates for the bar's Updates module and prints one JSON line:
#   {"repo":N,"aur":N,"flatpak":N,"total":N,"list":["pkg old -> new", …]}
# repo   — official repos via checkupdates (pacman-contrib; safe, no root, own temp db)
# aur    — paru/yay -Qua when an AUR helper is installed
# flatpak— flatpak remote-ls --updates (off by default in the module; network-heavier)
# `list` — up to LIST_CAP package lines (repo + aur + flatpak), for the module's hover glide.

with_aur=1 with_flatpak=1
for a in "$@"; do
    case "$a" in
        --no-aur)     with_aur=0 ;;
        --no-flatpak) with_flatpak=0 ;;
    esac
done

LIST_CAP=60

repo_arr=() aur_arr=() fp_arr=()

if command -v checkupdates >/dev/null 2>&1; then
    mapfile -t repo_arr < <(checkupdates 2>/dev/null || true)
fi

if (( with_aur )); then
    helper=$(command -v paru 2>/dev/null || command -v yay 2>/dev/null || true)
    [[ -n "$helper" ]] && mapfile -t aur_arr < <("$helper" -Qua 2>/dev/null || true)
fi

if (( with_flatpak )) && command -v flatpak >/dev/null 2>&1; then
    mapfile -t fp_arr < <(flatpak remote-ls --updates --app --columns=application 2>/dev/null || true)
fi

repo=${#repo_arr[@]} aur=${#aur_arr[@]} fp=${#fp_arr[@]}

# Build a JSON array of strings (repo, then aur, then flatpak), capped and JSON-escaped.
json_list() {
    local out="[" first=1 s n=0
    for s in "${repo_arr[@]}" "${aur_arr[@]}" "${fp_arr[@]/%/ (flatpak)}"; do
        [[ -z "$s" ]] && continue
        (( n++ >= LIST_CAP )) && break
        s=${s//\\/\\\\}          # escape backslashes first
        s=${s//\"/\\\"}          # then double quotes
        if (( first )); then first=0; else out+=","; fi
        out+="\"$s\""
    done
    out+="]"
    printf '%s' "$out"
}

printf '{"repo":%d,"aur":%d,"flatpak":%d,"total":%d,"list":%s}\n' \
    "$repo" "$aur" "$fp" "$(( repo + aur + fp ))" "$(json_list)"
