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
