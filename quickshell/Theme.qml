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

    // ── Arrangement ─────────────────────────────────────────────────────────────────────────────
    // Tokens restyle a surface; ARRANGEMENT decides where the surfaces are. Console does not want
    // mirobo's bar in a different colour, it wants a status line along the bottom — and no token
    // can say that. So a theme carries plain settings.json keys and they are applied when you pick
    // it, which is the honest reading of "a theme is a whole desktop".
    //
    //   "arrangement": { "bar_position": "bottom", "bar_thickness": 26, ... }
    //
    // Applied, not merged live: these are the user's own keys and stay editable afterwards. Picking
    // the theme again puts them back.
    readonly property var arrangement: root.pkg.arrangement || ({})

    // ── Wallpaper transitions ───────────────────────────────────────────────────────────────────
    // Four per theme, rolled per change when `wallpaper_transition` is "theme". A wallpaper swap is
    // the biggest thing that ever happens on the screen, and having it dissolve the same way under
    // every look made the theme stop at the panels. Names come from the shipped set in
    // WallpaperWindow: fade · slide · push · zoom · cut · wipe · flicker.
    readonly property var transitions: Array.isArray(root.pkg.transitions) ? root.pkg.transitions : []

    // ── The theme's own settings ────────────────────────────────────────────────────────────────
    // The third seam. A theme brings its OWN controls, so the range of adjustment is that theme's
    // rather than a global one: Console offers a scanline grid and a lockscreen rail, mirobo offers
    // nothing of the sort. Declared the same way components are:
    //
    //   "settings": [ { "key": "console", "title": "Console",
    //                   "page": "settings/ConsoleSection.qml" } ]
    //
    // `title` names the card the shell builds for it on Settings -> Style; `key` only has to be
    // unique within the theme.
    readonly property var settingsPages: {
        var out = []
        var ps = root.pkg.settings
        if (!ps || !ps.length) return out
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            if (!p || !p.key || !p.page) continue
            out.push({ "key": "" + p.key, "title": p.title || ("" + p.key),
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

    // Did the active theme have an OPINION about this token, or is the value only the shipped
    // table's? Some surfaces are drawn to match something else by default — a notification toast
    // reads as a bar module rather than as a card, on purpose — and should follow the theme instead
    // only where the theme actually said something. Asking `tokens` cannot answer that: it always
    // has a value.
    function declares(token) {
        var t = root.pkg.tokens
        return !!t && t[token] !== undefined
    }

    // The effective table for ANY theme: flat, then the named variant, then that theme's overrides.
    // The picker resolves one of these per installed theme so a card can look like what it offers.
    function tableFor(base, overrides) {
        var out = {}
        var f = root.variantTokens["flat"]
        for (var k in f) out[k] = f[k]
        var v = root.variantTokens[base]
        if (v) for (var k2 in v) out[k2] = v[k2]
        if (overrides) for (var k3 in overrides) out[k3] = overrides[k3]
        return out
    }

    // The effective table: flat, then the named variant, then whatever the theme overrides.
    readonly property var tokens: root.tableFor(root.base, root.pkg.tokens)

    // ── What is installed ───────────────────────────────────────────────────────────────────────
    // For the picker in Settings -> Style. Read through a tiny CLI because QML cannot list a
    // directory, and a theme is a FOLDER you drop in — there is no registry file to read instead.
    // The list carries what the picker's preview card draws (bar_mode / bar_position / ui_font /
    // wallpaper), so a card is the theme's own arrangement rather than a guess.
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

    // ── Wearing one ─────────────────────────────────────────────────────────────────────────────
    // A theme is more than its id: the ARRANGEMENT in its package says where the surfaces go, and
    // no token can say "the bar is a status line along the bottom". Applying it lives here rather
    // than in the settings page, so a keybind, the CLI (`ipc call theme wear <id>`) and the picker
    // all switch the same way.
    //
    // The keys go through SettingsStore like any other setting, so they stay yours to change
    // afterwards — wearing the theme again puts them back. The arrangement is read from the package
    // this singleton has already loaded, which is why wear() waits for the new theme.json to arrive
    // instead of shelling out to read a file the shell is holding open anyway.
    property string _wanted: ""
    function wear(id) {
        if (!id || id === "") return
        // Curtain first, but only for a real switch: the shell is about to rewrite ~80 settings and
        // swap every component the new theme brings, and the reassembly is not a thing to watch.
        // Re-picking the theme you already wear only puts its arrangement back, which is instant.
        if (id !== root.themeId) {
            SplashState.cover()
            root._snapshotCurrent()      // keep what you made of the theme you are leaving
        }
        root._wanted = id
        SettingsStore.set("theme", id)
        if (root.pkg.id === id) root._applyArrangement()     // already loaded (re-picking it)
        // The WINDOW frames follow the theme too: hyprland.lua reads <USER_DIR>/active-theme and
        // dofiles hypr.lua/themes/<name>.lua, so handing it the id is what makes a switch reach the
        // compositor instead of stopping at the shell's own surfaces.
        root._frameProc.command = ["bash", (Quickshell.env("VELUMERON_DIR") || "")
                                   + "/assets/scripts/apply-ui-style.sh", id]
        root._frameProc.running = false
        root._frameProc.running = true
    }
    // Settings that describe THIS MACHINE rather than a look. A theme has no business naming them,
    // and the shipped packages do not — but a theme is a folder anyone can drop in, and one that
    // rewrote your wallpaper folders or your bluetooth aliases on a switch would be a nasty
    // surprise. Same list as the one a restore preserves (assets/scripts/settings-backup.py).
    // Per-monitor bars count as this desk: `bar_monitors` holds one block per monitor NAME, and
    // `bar_per_monitor` is the switch that turns those blocks on. A theme that flipped it off would
    // silently flatten a bar the user arranged screen by screen — so on a machine with per-monitor
    // bars, a theme's bar_position lands in the global keys and the blocks keep winning. That is
    // the trade: the setup you built by hand outranks the one a theme suggests.
    readonly property var deviceKeys: ["theme", "wallpaper_dirs", "wallpaper_sets", "bt_aliases",
                                       "bt_groups", "bar_per_monitor", "bar_monitors",
                                       "taskbar_pinned", "lock_weather_city", "lock_weather_unit"]
    // And the ones that are simply YOURS, whatever theme is on: which modules sit where, how big
    // the bar is, how big its type is. A theme decides the shape of the desktop; it does not get to
    // rearrange the bar you built or resize it under you. This is a rule, not a default — there is
    // no theme that may write these.
    // `bar_mode`, `bar_edges` and `bar_position` are in here too, and that is the whole point rather
    // than an oversight: a module arrangement is filed per edge COMBINATION, so a theme that moves
    // the bar re-keys the layout and the modules you placed are simply not what the bar reads any
    // more. The bar is yours — where it sits, how big it is, what is on it.
    readonly property var userKeys: ["bar_thickness", "bar_font_size", "bar_icon_size",
                                     "bar_mode", "bar_edges", "bar_position",
                                     "bar_module_bg", "bar_module_bg_radius", "bar_module_bg_opacity",
                                     "bar_module_spacing", "bar_module_margin",
                                     "bar_modules", "bar_modules_m", "bar_modules_left",
                                     "bar_modules_center", "bar_modules_right"]
    function themeMayWrite(key) {
        return root.deviceKeys.indexOf(key) < 0 && root.userKeys.indexOf(key) < 0
               && key.indexOf("theme_") !== 0
    }
    // ── Your version of a theme ─────────────────────────────────────────────────────────────────
    // A theme ships an arrangement; what you do with it afterwards is yours. Wearing a theme you
    // have worn before therefore restores YOUR version of it, not the shipped one — leaving a theme
    // snapshots the keys it owns, and coming back plays that snapshot instead of the package.
    // Without this, moving the bar and then trying another look threw the move away, which made the
    // picker feel like a trap rather than like a wardrobe.
    //
    // `resetArrangement` is the way back to the shipped state, and it is the only thing that
    // forgets a snapshot.
    readonly property var savedArrangements: VtlConfig.rawSetting("theme_arrangements", ({})) || ({})
    function arrangementFor(id) {
        var s = root.savedArrangements[id]
        return (s && typeof s === "object") ? s : null
    }
    function _snapshotCurrent() {
        var a = root.pkg.arrangement
        var id = root.pkg.id
        if (!a || !id) return
        var snap = {}
        for (var k in a)
            if (root.themeMayWrite(k)) snap[k] = VtlConfig.rawSetting(k, a[k])
        var all = {}
        for (var t in root.savedArrangements) all[t] = root.savedArrangements[t]
        all[id] = snap
        SettingsStore.set("theme_arrangements", all)
    }
    function resetArrangement(id) {
        var all = {}
        for (var t in root.savedArrangements) if (t !== id) all[t] = root.savedArrangements[t]
        SettingsStore.set("theme_arrangements", all)
        if (id === root.pkg.id) root._applyPackageArrangement()
    }
    function _applyPackageArrangement() {
        var a = root.pkg.arrangement
        if (!a) return
        var out = {}
        for (var k in a) if (root.themeMayWrite(k)) out[k] = a[k]
        SettingsStore.setAll(out)
    }
    function _applyArrangement() {
        root._wanted = ""
        var mine = root.arrangementFor(root.pkg.id)
        if (mine) SettingsStore.setAll(mine)
        else      root._applyPackageArrangement()
    }
    // The package arrives asynchronously (FileView), so the arrangement is applied when it lands.
    onPkgChanged: if (root._wanted !== "" && root.pkg.id === root._wanted) root._applyArrangement()
    readonly property Process _frameProc: Process {}

    // ── Themes of your own ──────────────────────────────────────────────────────────────────────
    // A shipped theme stays a folder that only ever arrives and leaves. What a picker does need is
    // the fork: take the theme you are running plus the settings you have actually made, and keep
    // them as yours. theme-fork.py writes under the user directory and nowhere else.
    signal forked(string id)
    function fork(id, name)   { root._write(["fork", id, name || ""]) }
    function rename(id, name) { root._write(["rename", id, name]) }
    function remove(id)       { root._write(["delete", id]) }
    function _write(args) {
        root._forkProc.command = ["python3", (Quickshell.env("VELUMERON_DIR") || "")
                                  + "/assets/scripts/theme-fork.py"].concat(args)
        root._forkProc.running = false
        root._forkProc.running = true
    }
    readonly property Process _forkProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var line = ("" + this.text).trim()
                if (line.indexOf("fork:") === 0) root.forked(line.slice(5))
                else if (line.indexOf(":ok") < 0) console.warn("theme:", line)
            }
        }
        onRunningChanged: if (!running) root.refresh()
    }

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
