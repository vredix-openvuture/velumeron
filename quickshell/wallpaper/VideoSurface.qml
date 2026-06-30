import QtQuick
import Velumeron.Mpv

// Thin wrapper whose only job is to carry the `Velumeron.Mpv` import in ISOLATION. WallpaperWindow
// loads this via a Loader (by URL), so if the compiled mpv plugin isn't on the import path the Loader
// just fails gracefully (no video) instead of taking the whole shell down with it. Properties
// (source / paused / loop / mute) are driven by the parent through Bindings on the Loader item.
MpvVideo {
    loop: true
    mute: true
}
