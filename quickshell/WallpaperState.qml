pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// What is on each monitor right now, read once for the whole shell.
//
// `quickshell/wallpapers.json` = { "<mon>": { "path": "…", "type": "image|video" } }, written by
// assets/scripts/wallpaper-set.sh and watched here. Six surfaces read this file with a FileView of
// their own (WallpaperWindow, LockContent, WallpaperFeed, LauncherRail, DeskPreview, DashEditor)
// because each of them only ever needed its own monitor's picture. The desk needs it for something
// else: which LAYOUT a screen shows can depend on which wallpaper is on it, and that question is
// asked from VtlConfig, which is a singleton and has no monitor of its own.
//
// Deliberately dependency-free — no VtlConfig, no UiState. VtlConfig resolves desk layouts and would
// import this back if this imported it, and two singletons that construct each other is a startup
// order problem nobody should have to think about. Anything that needs to SETTLE a change (wait out
// the wallpaper transition before acting on it) does that at the call site, where the transition
// duration is already known — see desk/DeskWindow.qml.
Singleton {
    id: root

    // { "<mon>": { path, type } }. The last good parse is kept: the file is replaced atomically, but
    // a half-written read would otherwise blank every wallpaper-dependent surface for one frame.
    property var current: ({})

    function pathFor(mon) {
        var e = root.current["" + mon]
        return (e && e.path) ? ("" + e.path) : ""
    }
    function isVideoFor(mon) {
        var e = root.current["" + mon]
        return !!(e && e.type === "video")
    }

    FileView {
        id: file
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron"))
              + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      root._parse(text())
        onFileChanged: reload()
    }
    function _parse(t) {
        try {
            if (t && ("" + t).trim() !== "") root.current = JSON.parse(t)
        } catch (e) { /* keep the last good map */ }
    }
}
