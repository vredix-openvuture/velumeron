<!--
  Release checklist (both steps, every release):
    1. Bump VERSION (semver, single line).
    2. Add a `## [x.y.z] — YYYY-MM-DD` section below (newest first).
  The update GUI parses releases via the `## [version]` headings and shows
  every section newer than the user's last-seen version — write for users,
  not for developers (what changed for them, not which file moved).
-->

# Changelog

## [0.1.0] — 2026-07-03

### Added
- First versioned release: GUI-first onboarding & update reports replace the
  CLI wizard; the settings panel gains Monitors (drag-to-arrange, with revert
  countdown), Workspaces, Autostart, Quick access, Peripherals and Window
  rules sections.
- Style settings: one-click GTK/Qt app theming (adw-gtk3 + wallust palettes
  in qt5ct/qt6ct) and a global dark/light switch.
- Calendar & tasks (CalDAV), zones, layout switcher, btop dropdown and an
  updates bar module.
- Taskbar, hot corners, rofi successor overlays and template system.

### Fixed
- Suspending no longer crashes hyprlock (and with it the session) on wake:
  locking is now fully sequenced before sleep via hypridle.
- Notification stacks in the notification centre expand on click.
- Live video wallpapers no longer render black.
