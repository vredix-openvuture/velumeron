#!/usr/bin/env python3
"""Vutureland Settings — lightweight GTK4/Adwaita control panel"""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, GLib, Gio, Gdk
import os
import subprocess
import threading
import shutil

# ── Paths ─────────────────────────────────────────────────────────────────────

VTL          = os.path.expanduser("~/.config/vutureland")
WALLPAPER_H  = f"{VTL}/assets/wallpaper/horizontal"
THUMB_DIR    = os.path.expanduser("~/.cache/vutureland/wallpaper-thumbs")
SET_WP       = f"{VTL}/assets/scripts/wallpaper-set.sh"
GEN_THUMBS   = f"{VTL}/rofi/assets/generate-thumbnail.sh"
SETUP_HYPR   = f"{VTL}/.setup/hyprland.sh"
SETUP_WAYBAR = f"{VTL}/.setup/waybar.sh"
TERMINAL     = "kitty"

VIDEO_EXTS = {'.mp4', '.webm', '.mkv', '.avi', '.mov'}
IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}


# ── Wallpaper thumbnail item ───────────────────────────────────────────────────

class WallpaperItem(Gtk.Box):
    def __init__(self, filepath, thumb_path, display_name, is_video):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.filepath = filepath

        frame = Gtk.Frame()
        frame.add_css_class("wallpaper-frame")

        if thumb_path and os.path.exists(thumb_path):
            pic = Gtk.Picture.new_for_filename(thumb_path)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            pic.set_can_shrink(True)
        else:
            pic = Gtk.Image.new_from_icon_name("image-x-generic")

        pic.set_size_request(190, 108)  # 16:9
        frame.set_child(pic)

        if is_video:
            overlay = Gtk.Overlay()
            overlay.set_child(frame)
            badge = Gtk.Label(label=" ▶ ")
            badge.add_css_class("video-badge")
            badge.set_halign(Gtk.Align.END)
            badge.set_valign(Gtk.Align.END)
            badge.set_margin_end(6)
            badge.set_margin_bottom(6)
            overlay.add_overlay(badge)
            self.append(overlay)
        else:
            self.append(frame)

        label = Gtk.Label(label=display_name)
        label.set_max_width_chars(22)
        label.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
        label.add_css_class("caption")
        label.set_xalign(0.5)
        self.append(label)


# ── Main window ────────────────────────────────────────────────────────────────

class MainWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("Vutureland Settings")
        self.set_default_size(960, 680)

        stack = Adw.ViewStack()
        self.stack = stack

        self._build_hyprland_page()
        self._build_waybar_page()
        self._build_wallpaper_page()

        header = Adw.HeaderBar()
        switcher = Adw.ViewSwitcher()
        switcher.set_stack(stack)
        switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(stack)
        self.set_content(tv)

    # ── Setup pages ──────────────────────────────────────────────────────────

    def _setup_page(self, icon, title, desc, script, btn_label):
        status = Adw.StatusPage()
        status.set_icon_name(icon)
        status.set_title(title)
        status.set_description(desc)
        status.set_vexpand(True)

        btn = Gtk.Button(label=btn_label)
        btn.add_css_class("pill")
        btn.add_css_class("suggested-action")
        btn.connect("clicked", lambda _: subprocess.Popen([TERMINAL, "-e", script]))
        status.set_child(btn)
        return status

    def _build_hyprland_page(self):
        page = self._setup_page(
            "preferences-desktop-display-symbolic",
            "Hyprland",
            "Monitore, Workspaces, Peripherals,\nAutostart und Window Rules konfigurieren.",
            SETUP_HYPR,
            "Hyprland Setup öffnen",
        )
        self.stack.add_titled_with_icon(
            page, "hyprland", "Hyprland", "preferences-desktop-display-symbolic")

    def _build_waybar_page(self):
        page = self._setup_page(
            "view-grid-symbolic",
            "Waybar",
            "Module auswählen, anordnen\nund die Leiste neu aufbauen.",
            SETUP_WAYBAR,
            "Waybar Setup öffnen",
        )
        self.stack.add_titled_with_icon(
            page, "waybar", "Waybar", "view-grid-symbolic")

    # ── Wallpaper page ───────────────────────────────────────────────────────

    def _build_wallpaper_page(self):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(5)
        self.flow.set_min_children_per_line(2)
        self.flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flow.set_row_spacing(8)
        self.flow.set_column_spacing(8)
        self.flow.set_margin_top(16)
        self.flow.set_margin_bottom(16)
        self.flow.set_margin_start(16)
        self.flow.set_margin_end(16)
        self.flow.connect("child-activated", self._on_wp_activated)
        scroll.set_child(self.flow)
        root.append(scroll)

        # Action bar
        bar = Gtk.ActionBar()

        self.spinner = Gtk.Spinner()
        bar.pack_start(self.spinner)
        self.status = Gtk.Label(label="")
        self.status.add_css_class("caption")
        bar.pack_start(self.status)

        refresh = Gtk.Button(label="Aktualisieren")
        refresh.connect("clicked", lambda _: self._reload())
        bar.pack_end(refresh)

        add = Gtk.Button(label="Hinzufügen …")
        add.add_css_class("suggested-action")
        add.connect("clicked", self._on_add)
        bar.pack_end(add)

        root.append(bar)

        self.stack.add_titled_with_icon(
            root, "wallpaper", "Wallpaper", "image-x-generic-symbolic")

        self._reload()

    def _clear_flow(self):
        child = self.flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.flow.remove(child)
            child = nxt

    def _reload(self):
        self._clear_flow()
        self.spinner.start()
        self.status.set_text("Lade Thumbnails …")

        def _work():
            subprocess.run(["bash", GEN_THUMBS], capture_output=True)
            items = []
            if os.path.isdir(WALLPAPER_H):
                for fname in sorted(os.listdir(WALLPAPER_H)):
                    ext = os.path.splitext(fname)[1].lower()
                    if ext not in IMAGE_EXTS | VIDEO_EXTS:
                        continue
                    stem     = os.path.splitext(fname)[0]
                    base     = stem.removesuffix("_hor").removesuffix("_vid")
                    display  = base.removeprefix("wp_")
                    thumb    = os.path.join(THUMB_DIR, stem + ".png")
                    filepath = os.path.join(WALLPAPER_H, fname)
                    items.append((filepath, thumb, display, ext in VIDEO_EXTS))
            GLib.idle_add(self._populate, items)

        threading.Thread(target=_work, daemon=True).start()

    def _populate(self, items):
        self.spinner.stop()
        self.status.set_text(f"{len(items)} Wallpaper")
        for filepath, thumb, display, is_video in items:
            self.flow.append(WallpaperItem(filepath, thumb, display, is_video))
        return False

    def _on_wp_activated(self, _, child):
        item = child.get_child()
        if not isinstance(item, WallpaperItem):
            return
        self.status.set_text(f"Setze: {os.path.basename(item.filepath)} …")
        self.spinner.start()
        def _apply():
            subprocess.run(["bash", SET_WP, item.filepath])
            GLib.idle_add(lambda: (
                self.spinner.stop(),
                self.status.set_text("Wallpaper gesetzt."),
            ) and False)
        threading.Thread(target=_apply, daemon=True).start()

    def _on_add(self, _):
        dialog = Gtk.FileDialog(title="Wallpaper hinzufügen")
        f = Gtk.FileFilter()
        f.set_name("Bilder & Videos")
        for p in ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.mp4", "*.webm", "*.mkv"]:
            f.add_pattern(p)
        store = Gio.ListStore.new(Gtk.FileFilter)
        store.append(f)
        dialog.set_filters(store)
        dialog.open(self, None, self._on_file_chosen)

    def _on_file_chosen(self, dialog, result):
        try:
            file = dialog.open_finish(result)
            if file:
                shutil.copy2(file.get_path(), WALLPAPER_H)
                self._reload()
        except Exception:
            pass


# ── CSS ────────────────────────────────────────────────────────────────────────

CSS = b"""
.wallpaper-frame {
    border-radius: 8px;
    overflow: hidden;
}
.video-badge {
    background: rgba(0,0,0,0.65);
    color: white;
    border-radius: 4px;
    font-size: 0.75em;
    padding: 1px 4px;
}
flowboxchild:selected > box > frame,
flowboxchild:selected > box > overlay > frame {
    outline: 3px solid @accent_color;
    outline-offset: -3px;
}
"""


# ── App ────────────────────────────────────────────────────────────────────────

class VuturelandSettings(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.vutureland.settings",
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.connect("activate", self._on_activate)

    def _on_activate(self, _):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        win = MainWindow(application=self)
        win.present()


if __name__ == "__main__":
    VuturelandSettings().run()
