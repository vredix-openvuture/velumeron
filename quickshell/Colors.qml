pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live palette. wallust writes the 16+2 colours to <USER_DIR>/quickshell/colors.json on every theme
// change; FileView watches that file and we re-parse it, so the WHOLE shell recolours in place — no
// quickshell restart, hence no bar reload / exclusive-zone flicker on any monitor. The baked defaults
// mean colours are never blank even if the file is missing or momentarily unreadable.
QtObject {
    id: root
    property var p: ({})
    function _c(k, def) { var v = root.p[k]; return (typeof v === "string" && v.charAt(0) === "#") ? v : def }

    readonly property color background: _c("background", "#020300")
    readonly property color foreground: _c("foreground", "#F6CF8D")
    readonly property color color0:  _c("color0",  "#020401")
    readonly property color color1:  _c("color1",  "#4F5441")
    readonly property color color2:  _c("color2",  "#795443")
    readonly property color color3:  _c("color3",  "#427782")
    readonly property color color4:  _c("color4",  "#A55D38")
    readonly property color color5:  _c("color5",  "#4D9387")
    readonly property color color6:  _c("color6",  "#BE944B")
    readonly property color color7:  _c("color7",  "#E8C281")
    readonly property color color8:  _c("color8",  "#9F7E44")
    readonly property color color9:  _c("color9",  "#4F5441")
    readonly property color color10: _c("color10", "#795443")
    readonly property color color11: _c("color11", "#427782")
    readonly property color color12: _c("color12", "#A55D38")
    readonly property color color13: _c("color13", "#4D9387")
    readonly property color color14: _c("color14", "#BE944B")
    readonly property color color15: _c("color15", "#EBD8B8")

    // Semantic aliases — mirrors colors_gtk.css
    readonly property color bgPrimary:   color0
    readonly property color bgElement:   color1
    readonly property color bgSecondary: color2
    readonly property color bgActive:    color3
    readonly property color bgHover:     color4
    readonly property color boNormal:    color5
    readonly property color boActive:    color6
    readonly property color fgPrimary:   color7
    readonly property color fgMuted:     color8
    readonly property color fgUrgent:    color13
    readonly property color fgBright:    color15

    function _parse(t) { try { if (t && ("" + t).trim() !== "") root.p = JSON.parse(t) } catch (e) { /* keep last good */ } }

    readonly property FileView _fv: FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell/colors.json"
        watchChanges: true
        onLoaded:      root._parse(text())
        onFileChanged: reload()
    }
}
