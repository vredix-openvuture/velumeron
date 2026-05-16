#!/usr/bin/env python3
"""Vutureland Settings — GTK4/Adwaita control panel"""

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Adw, Gdk, Gio
import os, sys

# Ensure the gui/ directory is on the path when run directly
sys.path.insert(0, os.path.dirname(__file__))

from pages.wallpaper import WallpaperPage
from pages.hyprland import HyprlandPage
from pages.waybar import WaybarPage

_CSS = os.path.join(os.path.dirname(__file__), 'style.css')


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title('Vutureland Settings')
        self.set_default_size(1050, 720)

        stack = Adw.ViewStack()

        stack.add_titled_with_icon(
            HyprlandPage(), 'hyprland', 'Hyprland',
            'preferences-desktop-display-symbolic')

        stack.add_titled_with_icon(
            WaybarPage(), 'waybar', 'Waybar',
            'view-grid-symbolic')

        stack.add_titled_with_icon(
            WallpaperPage(), 'wallpaper', 'Wallpaper',
            'image-x-generic-symbolic')

        header = Adw.HeaderBar()
        switcher = Adw.ViewSwitcher()
        switcher.set_stack(stack)
        switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(stack)
        self.set_content(tv)


class VuturelandSettings(Adw.Application):
    def __init__(self):
        super().__init__(application_id='com.vutureland.settings',
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.connect('activate', self._activate)

    def _activate(self, _):
        p = Gtk.CssProvider()
        p.load_from_path(_CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        MainWindow(application=self).present()


if __name__ == '__main__':
    VuturelandSettings().run()
