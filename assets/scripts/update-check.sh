#!/usr/bin/env bash
# update-check.sh [--no-aur] [--no-flatpak]
# Counts available updates for the bar's Updates module and prints one JSON line:
#   {"repo":N,"aur":N,"flatpak":N,"total":N}
# repo   — official repos via checkupdates (pacman-contrib; safe, no root, own temp db)
# aur    — paru/yay -Qua when an AUR helper is installed
# flatpak— flatpak remote-ls --updates (off by default in the module; network-heavier)

with_aur=1 with_flatpak=1
for a in "$@"; do
    case "$a" in
        --no-aur)     with_aur=0 ;;
        --no-flatpak) with_flatpak=0 ;;
    esac
done

repo=0 aur=0 fp=0

if command -v checkupdates >/dev/null 2>&1; then
    repo=$(checkupdates 2>/dev/null | grep -c '^' || true)
fi

if (( with_aur )); then
    helper=$(command -v paru 2>/dev/null || command -v yay 2>/dev/null || true)
    [[ -n "$helper" ]] && aur=$("$helper" -Qua 2>/dev/null | grep -c '^' || true)
fi

if (( with_flatpak )) && command -v flatpak >/dev/null 2>&1; then
    fp=$(flatpak remote-ls --updates --app --columns=application 2>/dev/null | grep -c '^' || true)
fi

echo "{\"repo\":${repo:-0},\"aur\":${aur:-0},\"flatpak\":${fp:-0},\"total\":$(( repo + aur + fp ))}"
