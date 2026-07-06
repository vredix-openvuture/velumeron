#!/usr/bin/env bash
# apply-app-theme.sh — wire velumeron's look into GTK and Qt apps, and flip the
# global dark/light preference. Everything wallust-side already exists (it renders
# ~/.config/gtk-{3,4}.0/wallust.css and qt5ct/qt6ct colors/vutureland.conf on every
# palette change) — this script only toggles the ACTIVATION so the user never has
# to touch config files:
#
#   apply-app-theme.sh status          {"gtk":bool,"qt":bool,"mode":"dark"|"light"}
#   apply-app-theme.sh gtk on|off      adw-gtk3 theme + wallust palette import
#   apply-app-theme.sh qt on|off       qt5ct/qt6ct custom palette (vutureland)
#   apply-app-theme.sh mode dark|light xdg color-scheme + GTK variant
set -euo pipefail
source "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/lib/env.sh"

GTK_DIRS=("$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0")
IMPORT='@import url("wallust.css");'

cur_mode() {
    [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)" == *light* ]] \
        && echo light || echo dark
}
gtk_active() { grep -qF 'wallust.css' "$HOME/.config/gtk-3.0/gtk.css" 2>/dev/null; }
qt_active()  { grep -q '^custom_palette=true' "$HOME/.config/qt5ct/qt5ct.conf" 2>/dev/null; }
theme_for()  { [[ "$1" == light ]] && echo "adw-gtk3" || echo "adw-gtk3-dark"; }

# settings.ini writes go through configparser so unrelated user keys survive.
write_settings_ini() {  # <dir> <theme> <prefer_dark 1|0>
    mkdir -p "$1"
    python3 - "$1/settings.ini" "$2" "$3" <<'PY'
import configparser, sys
p, theme, dark = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
c = configparser.RawConfigParser()
c.optionxform = str
c.read(p)
if not c.has_section("Settings"):
    c.add_section("Settings")
c.set("Settings", "gtk-theme-name", theme)
c.set("Settings", "gtk-application-prefer-dark-theme", "true" if dark else "false")
with open(p, "w") as f:
    c.write(f, space_around_delimiters=False)
PY
}

do_gtk() {
    local mode theme
    mode=$(cur_mode)
    case "$1" in
        on)
            theme=$(theme_for "$mode")
            for d in "${GTK_DIRS[@]}"; do
                mkdir -p "$d"; touch "$d/gtk.css"
                grep -qF 'wallust.css' "$d/gtk.css" || printf '\n%s\n' "$IMPORT" >> "$d/gtk.css"
                write_settings_ini "$d" "$theme" "$([[ $mode == dark ]] && echo 1 || echo 0)"
            done
            gsettings set org.gnome.desktop.interface gtk-theme "$theme" 2>/dev/null || true
            ;;
        off)
            for d in "${GTK_DIRS[@]}"; do
                [[ -f "$d/gtk.css" ]] && sed -i '/wallust\.css/d' "$d/gtk.css"
                write_settings_ini "$d" "Adwaita" "$([[ $mode == dark ]] && echo 1 || echo 0)"
            done
            gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" 2>/dev/null || true
            ;;
        *) echo "usage: apply-app-theme.sh gtk on|off" >&2; exit 2 ;;
    esac
}

do_qt() {
    [[ "$1" == on || "$1" == off ]] || { echo "usage: apply-app-theme.sh qt on|off" >&2; exit 2; }
    python3 - "$1" <<'PY'
import configparser, os, sys
on = sys.argv[1] == "on"
home = os.path.expanduser("~")
for tool in ("qt5ct", "qt6ct"):
    d = os.path.join(home, ".config", tool)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, tool + ".conf")
    c = configparser.RawConfigParser()
    c.optionxform = str
    c.read(p)
    if not c.has_section("Appearance"):
        c.add_section("Appearance")
    c.set("Appearance", "custom_palette", "true" if on else "false")
    if on:
        c.set("Appearance", "color_scheme_path", os.path.join(d, "colors", "vutureland.conf"))
        if not c.has_option("Appearance", "style"):
            c.set("Appearance", "style", "Fusion")
    with open(p, "w") as f:
        c.write(f, space_around_delimiters=False)
PY
}

do_mode() {
    [[ "$1" == dark || "$1" == light ]] || { echo "usage: apply-app-theme.sh mode dark|light" >&2; exit 2; }
    gsettings set org.gnome.desktop.interface color-scheme "prefer-$1" 2>/dev/null || true
    local theme
    if gtk_active; then theme=$(theme_for "$1"); else theme="Adwaita"; fi
    gsettings set org.gnome.desktop.interface gtk-theme "$theme" 2>/dev/null || true
    for d in "${GTK_DIRS[@]}"; do
        write_settings_ini "$d" "$theme" "$([[ $1 == dark ]] && echo 1 || echo 0)"
    done

    # The wallust palettes (GTK/Qt/kitty/quickshell) are what apps actually SHOW —
    # without re-deriving them in the chosen brightness the flip is invisible.
    # Persist the mode for every future `wallust run` (wallpaper-set.sh reads it),
    # then re-theme from the current main-monitor wallpaper so it applies now.
    mkdir -p "$VELUMERON_USER_DIR/wallust"
    printf '%s\n' "$1" > "$VELUMERON_USER_DIR/wallust/app-mode"
    local cmode main wp
    cmode=$(cat "$VELUMERON_USER_DIR/wallust/color-mode" 2>/dev/null || echo auto)
    if [[ "$cmode" == auto ]]; then
        main=$(hyprctl monitors -j 2>/dev/null | jq -r '[.[]|select(.focused)][0].name // .[0].name' 2>/dev/null || true)
        [[ -n "$main" && "$main" != null ]] \
            && wp=$(jq -r --arg m "$main" '.[$m].path // empty' \
                    "$VELUMERON_USER_DIR/quickshell/wallpapers.json" 2>/dev/null || true)
        [[ -n "${wp:-}" && -f "$wp" ]] && \
            bash "$VELUMERON_DIR/assets/scripts/wallpaper-set.sh" --mon "$main" --file "$wp" >/dev/null 2>&1 || true
    fi
}

case "${1:-}" in
    status)
        printf '{"gtk":%s,"qt":%s,"mode":"%s"}\n' \
            "$(gtk_active && echo true || echo false)" \
            "$(qt_active && echo true || echo false)" \
            "$(cur_mode)"
        ;;
    gtk)  do_gtk "${2:-}" ;;
    qt)   do_qt "${2:-}" ;;
    mode) do_mode "${2:-}" ;;
    *)    grep '^#   apply' "$0" | sed 's/^# *//' >&2; exit 2 ;;
esac
