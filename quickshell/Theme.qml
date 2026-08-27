// The theme registry. A THEME is a whole desktop on top of Velumeron, not a colour scheme: it
// brings its own token table, and later its own components and its own settings pages. This file is
// the first of those three seams — the tokens.
//
// Why the tokens had to become data: Style.qml used to decide every radius, fill, border and gap
// with a fourteen-deep ternary over ten hardcoded `is<Name>` booleans, so an eleventh look could
// only exist by editing Style.qml. Now the ten shipped looks are ten TABLES in `variantTokens`
// below, and a theme package supplies its own table on top. A new theme is a folder; it never
// touches the shell.
//
// A theme lives in one of two places, user first so a user theme can shadow a shipped one:
//
//   $VELUMERON_USER_DIR/themes/<id>/theme.json     the user's own
//   $VELUMERON_DIR/quickshell/themes/<id>/theme.json   shipped with Velumeron
//
// and the file looks like this (every field optional except id/name):
//
//   { "id": "console", "name": "Console", "author": "…", "version": 1,
//     "contract": 1,                        which contract version it was written against
//     "base": "flat",                       which shipped table it starts from
//     "tokens": { "rCard": 0, "cardBorderW": 1,
//                 "cardBorderColor": { "base": "accent", "alpha": 0.5 } } }
//
// COLOURS ARE RECIPES, NOT HEX. The palette is wallust's and changes with the wallpaper, so a token
// names a palette entry and what to do to it. Style.qml owns the resolution (it owns tint/lift), so
// the dependency runs one way: Style reads Theme, Theme never reads Style.
//
//   "boNormal"                          a Colors key, or "accent" / "onAccent"
//   "transparent"                       literally that
//   { "base": "accent", "alpha": 0.5 }  that colour at a fixed alpha
//   { "base": "accent", "lift": 0.06 }  …at an alpha the surface-contrast knob scales
//   { "base": "bgElement", "solid": true }   a solid fill nudged by the same knob
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string themeId: VtlConfig.theme
    readonly property string _userDir: (Quickshell.env("VELUMERON_USER_DIR")
                                        || (Quickshell.env("HOME") + "/.config/velumeron"))
    readonly property string _shipDir: (Quickshell.env("VELUMERON_DIR") || "") + "/quickshell/themes"

    // The contract version this shell speaks. A package written against a newer one is loaded
    // anyway (unknown token keys are simply never read), but it is worth saying out loud what the
    // shell will and will not honour.
    readonly property int contract: 1

    // ── The shipped looks, as tables ────────────────────────────────────────────────────────────
    // Migrated verbatim from the ternaries that used to sit in Style.qml. `flat` is the baseline:
    // every other table lists only what it changes, and every lookup falls through to it. That is
    // also what a theme package gets for free — it overrides three keys, not fifteen.
    readonly property var variantTokens: ({
        "flat": {
            "rCard": 14, "rControl": 10, "rTile": 8,
            "cardGap": 16, "cardPad": 14, "rowGap": 10,
            "cardFill":           { "base": "accent",   "lift": 0.06 },
            "cardBorderW":        0,
            "cardBorderColor":    { "base": "boNormal", "alpha": 0.40 },
            "controlFill":        { "base": "accent",   "lift": 0.12 },
            "controlHover":       { "base": "accent",   "lift": 0.22 },
            "controlBorderW":     0,
            "controlBorderColor": { "base": "boNormal", "alpha": 0.40 },
            "selFill":            "accent",
            "selText":            "onAccent",
            "selBorderW":         0,
            "selBorderColor":     "boActive"
        },
        "cards": {
            "rCard": 16, "rControl": 12, "rTile": 12,
            "cardGap": 14, "cardPad": 14, "rowGap": 8,
            "cardFill":       { "base": "bgElement", "solid": true },
            "cardBorderW":    1,
            "controlFill":    "bgPrimary",
            "controlHover":   { "base": "accent", "lift": 0.18 },
            "controlBorderW": 1,
            "selBorderW":     1
        },
        "outlined": {
            "rCard": 8, "rControl": 6, "rTile": 6,
            "cardGap": 12, "cardPad": 12, "rowGap": 8,
            "cardFill":           "transparent",
            "cardBorderW":        1,
            "cardBorderColor":    "boNormal",
            "controlFill":        "transparent",
            "controlHover":       { "base": "accent", "lift": 0.12 },
            "controlBorderW":     1,
            "controlBorderColor": "boNormal",
            "selFill":            "transparent",
            "selText":            "accent",
            "selBorderW":         1,
            "selBorderColor":     "accent"
        },
        "futuristic": {
            "rCard": 10, "rControl": 8, "rTile": 6,
            "cardGap": 16, "cardPad": 14, "rowGap": 8,
            "cardFill":           { "base": "bgPrimary", "alpha": 0.45 },
            "cardBorderW":        1,
            "cardBorderColor":    { "base": "accent", "alpha": 0.50 },
            "controlFill":        { "base": "accent", "lift":  0.05 },
            "controlHover":       { "base": "accent", "lift":  0.16 },
            "controlBorderW":     1,
            "controlBorderColor": { "base": "accent", "alpha": 0.45 },
            "selFill":            { "base": "accent", "alpha": 0.28 },
            "selBorderW":         1,
            "selBorderColor":     "accent"
        },
        "grimoire": {
            "rCard": 12, "rControl": 6, "rTile": 5,
            "cardGap": 18, "cardPad": 16, "rowGap": 10,
            "cardFill":           { "base": "accent", "lift":  0.07 },
            "cardBorderW":        1,
            "cardBorderColor":    { "base": "accent", "alpha": 0.55 },
            "controlFill":        { "base": "accent", "lift":  0.10 },
            "controlBorderW":     1,
            "controlBorderColor": { "base": "accent", "alpha": 0.35 },
            "selBorderW":         1
        },
        "straight": {
            "rCard": 0, "rControl": 0, "rTile": 0,
            "cardGap": 10, "cardPad": 14, "rowGap": 8,
            "cardFill":           { "base": "accent", "lift": 0.04 },
            "cardBorderW":        1,
            "cardBorderColor":    "boNormal",
            "controlFill":        { "base": "accent", "lift": 0.07 },
            "controlBorderW":     1,
            "controlBorderColor": "boNormal",
            "selBorderW":         1
        },
        "wobbly": {
            "rCard": 9, "rControl": 7, "rTile": 6,
            "cardGap": 18, "cardPad": 16, "rowGap": 10,
            "cardFill":           { "base": "accent", "lift":  0.09 },
            "cardBorderW":        1,
            "cardBorderColor":    { "base": "accent", "alpha": 0.42 },
            "controlFill":        { "base": "accent", "lift":  0.12 },
            "controlBorderW":     1,
            "controlBorderColor": { "base": "accent", "alpha": 0.35 },
            "selBorderW":         1
        },
        "nostalgic": {
            "rCard": 0, "rControl": 0, "rTile": 0,
            "cardGap": 10, "cardPad": 12, "rowGap": 8,
            "cardFill":           { "base": "bgElement", "solid": true },
            "cardBorderW":        2,
            "cardBorderColor":    "boNormal",
            "controlFill":        "bgElement",
            "controlBorderW":     2,
            "controlBorderColor": "boNormal",
            "selBorderW":         2
        },
        "sketch": {
            "rCard": 7, "rControl": 6, "rTile": 5,
            "cardGap": 18, "cardPad": 14, "rowGap": 10,
            "cardFill":           { "base": "accent",  "lift":  0.05 },
            "cardBorderW":        1,
            "cardBorderColor":    { "base": "fgMuted", "alpha": 0.85 },
            "controlFill":        { "base": "accent",  "lift":  0.07 },
            "controlBorderW":     1,
            "controlBorderColor": { "base": "fgMuted", "alpha": 0.70 },
            "selBorderW":         1
        },
        "cupertino": {
            "rCard": 18, "rControl": 12, "rTile": 10,
            "cardGap": 14, "cardPad": 16, "rowGap": 10,
            "cardFill":           { "base": "bgElement", "alpha": 0.55 },
            "cardBorderW":        1,
            "cardBorderColor":    { "base": "boNormal",  "alpha": 0.35 },
            "controlFill":        { "base": "bgPrimary", "alpha": 0.55 },
            "controlHover":       { "base": "accent",    "alpha": 0.16 },
            "controlBorderW":     1,
            "controlBorderColor": { "base": "boNormal",  "alpha": 0.35 },
            "selBorderW":         1
        }
    })

    // ── Components ──────────────────────────────────────────────────────────────────────────────
    // The second seam. A theme may bring its OWN QML for a surface instead of restyling the shipped
    // one, because restyling was measured not to be enough: a Console built out of the existing
    // components still read as mirobo with different corners.
    //
    // A theme DECLARES what it brings rather than the shell probing the disk for it:
    //
    //   "components": { "lock": "components/Lock.qml" }
    //
    // Declaring it is the contract. Guessing at file names would make every surface a stat() on
    // every theme switch, and a typo would fail silently instead of failing where it is written.
    // Anything a theme does not declare falls back to the shipped component.
    //
    // The path is relative to the theme's own directory, and it resolves against the directory the
    // package was FOUND in — a user theme's component sits next to the user's theme.json, not next
    // to the shipped one.
    readonly property string dir: (root._user && root._user.id) ? (root._userDir + "/themes/" + root.themeId)
                                : (root._ship && root._ship.id) ? (root._shipDir + "/" + root.themeId)
                                : ""
    function componentUrl(surface) {
        var c = root.pkg.components
        var rel = (c && typeof c[surface] === "string") ? c[surface] : ""
        if (rel === "" || root.dir === "") return ""
        return "file://" + root.dir + "/" + rel
    }
    function hasComponent(surface) { return root.componentUrl(surface) !== "" }

    // ── Settings pages ──────────────────────────────────────────────────────────────────────────
    // The third seam. A theme brings its OWN settings pages, so the range of adjustment is that
    // theme's rather than a global one: Console offers a status line and a rail, mirobo offers
    // pills and a bar. Declared the same way components are:
    //
    //   "settings": [ { "key": "console", "title": "Console", "icon": "\udb80\udcb0",
    //                   "group": "Appearance", "page": "settings/ConsoleSection.qml" } ]
    //
    // `group` names one of the settings menu's nav groups; an unknown one lands in "More", which is
    // where anything unplaced already goes.
    readonly property var settingsPages: {
        var out = []
        var ps = root.pkg.settings
        if (!ps || !ps.length) return out
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            if (!p || !p.key || !p.page) continue
            out.push({ "key": "" + p.key, "title": p.title || ("" + p.key),
                       "icon": p.icon || "\u{F0765}", "group": p.group || "Appearance",
                       "url": (root.dir === "") ? "" : ("file://" + root.dir + "/" + p.page) })
        }
        return out
    }

    // A theme's own settings are namespaced. A theme may invent any knob it likes and none of them
    // can collide with a shell key or with another theme's — which is also what makes switching
    // theme and switching back give you your knobs again rather than a reset.
    function settingKey(key) { return "theme_" + root.themeId + "_" + key }
    function setting(key, def) { return VtlConfig.rawSetting(root.settingKey(key), def) }
    // The same values as an object, which is what a settings page and a component bind to. Reading
    // through the function is fine for a one-shot; binding to it is not, because a function call is
    // not a dependency and the control would freeze at whatever it was built with.
    readonly property var settings: VtlConfig.rawPrefix("theme_" + root.themeId + "_")

    // ── The lockscreen ──────────────────────────────────────────────────────────────────────────
    // The lock is NOT personalised any more, and that is deliberate. It used to be a preset registry
    // with an editor behind it, which meant every user built a different lockscreen out of the same
    // parts and none of them was the product. A theme now brings ONE lock and owns how it looks;
    // what stays a user setting is the part that is about you rather than about the look — the
    // weather city, and when the screen locks at all.
    //
    // A theme overrides only what it changes. `layout` names an arrangement in lock/LockContent.qml.
    readonly property var lockDefaults: ({
        "layout":              "breath",
        "reveal":              "bubble",           // bubble | fade | none
        "blur":                0.0,                // 0..1 backdrop blur
        "dim":                 0.0,                // 0..1 backdrop darken
        "blurTarget":          "background",       // background | card
        "cardWallpaper":       true,
        "cardAvatar":          true,
        "uniformWallpaper":    false,              // every screen shows the MAIN monitor's wallpaper
        "cardPos":             "center",           // left | center | right
        "cardWidthPct":        40,
        "cardHeightPct":       40,
        "clockFormat":         "hh:mm",
        "dateFormat":          "dddd, dd MMMM",
        "clockScale":          100,                // 50..200 %
        "clockStyle":          "regular",          // light | regular | bold | spaced
        "weatherForecast":     false,
        "weatherForecastDays": 3,                  // clamped to 1..3 where it is used
        // widget → zone, or "off". Zones: top|bottom × left|center|right. Only the `card` layout
        // uses the zone itself; every other one reads the map as a plain on/off list.
        "widgets": { "media": "bottom-left", "weather": "bottom-center", "battery": "bottom-right",
                     "notifs": "off", "user": "off", "session": "off" }
    })
    readonly property var lock: {
        var out = {}
        var d = root.lockDefaults
        for (var k in d) out[k] = d[k]
        var l = root.pkg.lock
        if (l) for (var k2 in l) out[k2] = l[k2]
        return out
    }
    function lockWidgetZone(name)    { var w = root.lock.widgets; return (w && w[name]) ? w[name] : "off" }
    function lockWidgetEnabled(name) { return root.lockWidgetZone(name) !== "off" }

    // ── The loaded package ──────────────────────────────────────────────────────────────────────
    property var _ship: ({})
    property var _user: ({})
    // User shadows shipped, so a user theme can carry the same id as a builtin and win.
    readonly property var pkg: (root._user && root._user.id) ? root._user
                             : (root._ship && root._ship.id) ? root._ship : ({})

    readonly property string name:   root.pkg.name   || root.themeId
    readonly property string author: root.pkg.author || ""
    readonly property bool   loaded: !!root.pkg.id
    // Which shipped table the theme starts from. Falls back to `ui_style` so the ten looks keep
    // working for a session that has no theme package at all.
    readonly property string base:   root.pkg.base || VtlConfig.uiStyle

    // The effective table: flat, then the named variant, then whatever the theme overrides.
    readonly property var tokens: {
        var out = {}
        var f = root.variantTokens["flat"]
        for (var k in f) out[k] = f[k]
        var v = root.variantTokens[root.base]
        if (v) for (var k2 in v) out[k2] = v[k2]
        var t = root.pkg.tokens
        if (t) for (var k3 in t) out[k3] = t[k3]
        return out
    }

    // ── What is installed ───────────────────────────────────────────────────────────────────────
    // For the picker in Settings -> Style. Read through a tiny CLI because QML cannot list a
    // directory, and a theme is a FOLDER you drop in — there is no registry file to read instead.
    // Read-only on purpose: no save, no duplicate, no delete. A theme arrives and leaves as a
    // folder, which is the whole difference from the preset registry this replaced.
    property var available: []
    property Process _listProc: Process {
        command: ["python3", (Quickshell.env("VELUMERON_DIR") || "") + "/assets/scripts/theme-list.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.available = JSON.parse(("" + this.text).trim()) }
                catch (e) { /* keep the last good list; a broken scan must not empty the picker */ }
            }
        }
    }
    function refresh() { root._listProc.running = false; root._listProc.running = true }
    Component.onCompleted: root.refresh()

    // Switching theme must not leave the previous package's data standing: the new theme may have
    // no user file at all, in which case its FileView never fires and the old table would keep
    // drawing. Clear both, then let whichever files exist load into them.
    onThemeIdChanged: { root._ship = ({}); root._user = ({}) }

    // Keep the last good table on a parse error: an editor saving theme.json in two writes must not
    // blank the shell mid-keystroke. A file that stays broken is not silent though — it warns once
    // per change, and `ipc call theme report` still says loaded:false.
    function _parse(t, into) {
        try {
            var d = JSON.parse("" + t)
            if (d && d.id) { if (into === "user") root._user = d; else root._ship = d }
            else console.warn("theme:", root.themeId, into, "theme.json has no id, ignored")
        } catch (e) {
            console.warn("theme:", root.themeId, into, "theme.json is not valid JSON:", e.message)
        }
    }

    readonly property FileView _shipFv: FileView {
        path: root._shipDir + "/" + root.themeId + "/theme.json"
        watchChanges: true
        printErrors: false                       // a user-only theme has no shipped file, by design
        onLoaded:      root._parse(text(), "ship")
        onFileChanged: reload()
    }
    readonly property FileView _userFv: FileView {
        path: root._userDir + "/themes/" + root.themeId + "/theme.json"
        watchChanges: true
        printErrors: false                       // the usual case is that the user has no theme dir
        onLoaded:      root._parse(text(), "user")
        onFileChanged: reload()
    }
}
