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
#   apply-app-theme.sh icon <name>     global app icon theme (gsettings + GTK settings.ini)
#   apply-app-theme.sh icon-list       list installed icon themes (one name per line)
#   apply-app-theme.sh refresh-portals restart the GTK portal backend (re-theme file dialogs)
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
cur_icon()   { gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'" | tr -d '"'; }

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
    # ONLY the desktop-wide preference: xdg color-scheme + the GTK theme variant. Deliberately
    # does NOT touch the wallust pipeline: re-deriving a light palette here flipped colors.json
    # (making the shell unreadable) and recoloured kitty — terminals and the shell keep their
    # own colours; this switch is for portal-aware apps and websites.
    gsettings set org.gnome.desktop.interface color-scheme "prefer-$1" 2>/dev/null || true
    local theme
    if gtk_active; then theme=$(theme_for "$1"); else theme="Adwaita"; fi
    gsettings set org.gnome.desktop.interface gtk-theme "$theme" 2>/dev/null || true
    for d in "${GTK_DIRS[@]}"; do
        write_settings_ini "$d" "$theme" "$([[ $1 == dark ]] && echo 1 || echo 0)"
    done
    # Drop the old behaviour's palette marker so future wallpaper changes never re-derive a
    # light palette again.
    rm -f "$VELUMERON_USER_DIR/wallust/app-mode" 2>/dev/null || true
    # The GTK portal backend caches its dialog look — refresh it so file choosers flip too.
    refresh_portals
}

# Global app icon theme. gsettings is the live source of truth (dconf-persisted, so it survives
# reboots — no separate velumeron store needed); GTK apps that read settings.ini rather than
# gsettings get gtk-icon-theme-name written into both gtk-3.0 and gtk-4.0 too. Qt apps pick the
# icon theme up from the same gsettings key via the platform theme. configparser keeps unrelated
# keys intact.
do_icon() {
    local name="$1" d
    [[ -n "$name" ]] || { echo "usage: apply-app-theme.sh icon <theme-name>" >&2; exit 2; }
    gsettings set org.gnome.desktop.interface icon-theme "$name" 2>/dev/null || true
    for d in "${GTK_DIRS[@]}"; do
        mkdir -p "$d"
        python3 - "$d/settings.ini" "$name" <<'PY'
import configparser, sys
p, name = sys.argv[1], sys.argv[2]
c = configparser.RawConfigParser(); c.optionxform = str; c.read(p)
if not c.has_section("Settings"): c.add_section("Settings")
c.set("Settings", "gtk-icon-theme-name", name)
with open(p, "w") as f: c.write(f, space_around_delimiters=False)
PY
    done
    # Qt apps — INCLUDING the quickshell shell itself — take their icon theme from qt5ct/qt6ct
    # (QT_QPA_PLATFORMTHEME=qt5ct:qt6ct), NOT gsettings. Without this the shell never re-themes.
    # Read at Qt startup, so the shell reflects it on its next restart (GTK apps update live).
    python3 - "$name" <<'PY'
import configparser, os, sys
name = sys.argv[1]
home = os.path.expanduser("~")
for tool in ("qt5ct", "qt6ct"):
    d = os.path.join(home, ".config", tool)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, tool + ".conf")
    c = configparser.RawConfigParser(); c.optionxform = str; c.read(p)
    if not c.has_section("Appearance"): c.add_section("Appearance")
    c.set("Appearance", "icon_theme", name)
    with open(p, "w") as f: c.write(f, space_around_delimiters=False)
PY
}

# Installed icon themes = dirs with an index.theme that declares Directories= (real icon themes).
# Cursor-only themes have no Directories key, and the hicolor/default/locolor fallbacks are useless
# as a pick — all excluded. Sorted by display name, de-duplicated across the three search roots.
list_icons() {
    python3 - <<'PY'
import os, glob, configparser
seen, out = set(), []
bases = [os.path.expanduser("~/.icons"),
         os.path.expanduser("~/.local/share/icons"),
         "/usr/share/icons"]
for b in bases:
    for idx in glob.glob(os.path.join(b, "*", "index.theme")):
        name = os.path.basename(os.path.dirname(idx))
        if name in seen or name.lower() in ("hicolor", "default", "locolor"):
            continue
        c = configparser.RawConfigParser(); c.optionxform = str
        try:
            c.read(idx)
        except Exception:
            continue
        if not c.has_section("Icon Theme"):
            continue
        if not (c.has_option("Icon Theme", "Directories") and c.get("Icon Theme", "Directories").strip()):
            continue
        seen.add(name)
        out.append((c.get("Icon Theme", "Name", fallback=name), name))
for _disp, name in sorted(out, key=lambda x: x[0].lower()):
    print(name)
PY
}

# xdg-desktop-portal-gtk renders the file-chooser dialogs that GTK4 apps (zenity 4 → the wallpaper
# folder picker) delegate to via GtkFileChooserNative. That backend reads its light/dark look ONCE
# at startup; when it is activated early at login — before the color-scheme/theme has settled — it
# gets stuck light and every portal dialog opens light despite `color-scheme=prefer-dark`. Bouncing
# the service makes it re-read the current scheme. try-restart is a no-op if it isn't running (then
# the next on-demand activation reads the settled theme anyway), so this is always safe.
refresh_portals() {
    systemctl --user try-restart xdg-desktop-portal-gtk.service 2>/dev/null || true
}

case "${1:-}" in
    status)
        printf '{"gtk":%s,"qt":%s,"mode":"%s","icon":"%s"}\n' \
            "$(gtk_active && echo true || echo false)" \
            "$(qt_active && echo true || echo false)" \
            "$(cur_mode)" \
            "$(cur_icon)"
        ;;
    gtk)  do_gtk "${2:-}" ;;
    qt)   do_qt "${2:-}" ;;
    mode) do_mode "${2:-}" ;;
    icon)      do_icon "${2:-}" ;;
    icon-list) list_icons ;;
    refresh-portals) refresh_portals ;;
    *)    grep '^#   apply' "$0" | sed 's/^# *//' >&2; exit 2 ;;
esac
