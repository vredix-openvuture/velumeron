pragma Singleton
import QtQuick

// Global UI-style tokens. One place decides radius / fill / border / spacing / accent for every shared
// widget in quickshell/common/, driven by the user's chosen variant (Settings → Style → UI STYLE,
// persisted as `ui_style` and read live via VtlConfig). Switching the variant re-binds every token, so
// the whole shell restyles in place — no restart (Colors + VtlConfig already poll live).
//
// Colours stay wallust-driven: the single accent is Colors.bgActive, used ONLY for active/selected
// state — except under `futuristic`, whose HUD look runs a translucent accent through every border,
// and `grimoire`, whose gilded frames do the same at manuscript strength. Surfaces are neutral.
// That kills the old "blue + gold + olive, five radii" mishmash where every settings page rolled
// its own controls.
QtObject {
    id: root

    // flat (default) · cards · outlined · futuristic · grimoire · straight · wobbly · nostalgic · sketch · cupertino
    readonly property string variant:      VtlConfig.uiStyle
    readonly property bool   isCards:      variant === "cards"
    readonly property bool   isOutlined:   variant === "outlined"
    readonly property bool   isFuturistic: variant === "futuristic"
    readonly property bool   isGrimoire:   variant === "grimoire"
    readonly property bool   isStraight:   variant === "straight"
    readonly property bool   isWobbly:     variant === "wobbly"
    readonly property bool   isNostalgic:  variant === "nostalgic"
    readonly property bool   isSketch:     variant === "sketch"
    readonly property bool   isCupertino:  variant === "cupertino"
    readonly property bool   isFlat:       !isCards && !isOutlined && !isFuturistic && !isGrimoire
                                          && !isStraight && !isWobbly && !isNostalgic && !isSketch
                                          && !isCupertino                                           // unknown → flat

    // Corner/edge shape switches keyed off the variant. StyledRect and every chrome path builder read
    // these: chamfer cuts corners at 45° (futuristic); scallop bites them inward (grimoire); wobbly
    // draws a cloud of outward bumps; sketch bows the outline like a hand-drawn line; nostalgic drops
    // the outline for a two-tone raised bevel. Straight/flat/cards/outlined stay plain rectangles.
    readonly property bool chamfer:   isFuturistic
    readonly property bool scallop:   isGrimoire
    readonly property bool wobbly:    isWobbly
    readonly property bool sketch:    isSketch
    readonly property bool nostalgic: isNostalgic

    // Convex-corner SVG segment for hand-rolled path builders (Bar.qml, StyledRect): a clockwise
    // arc normally, the straight 45° cut when chamfered, the inward bite when scalloped.
    // (x,y) is the segment endpoint. (wobbly/sketch/nostalgic use their own StyledRect renderers.)
    function cornerSeg(r, x, y) {
        return root.chamfer ? "L" + x + "," + y
             : root.scallop ? "A" + r + "," + r + " 0 0 0 " + x + "," + y
                            : "A" + r + "," + r + " 0 0 1 " + x + "," + y
    }

    // Corner segment for the dock-chrome builders (Settings/Osd/Flyout/…): they mix convex free
    // corners (w=1) with concave merge fillets (w=0) and mirror the sweep when the dock edge
    // flips. Only convex corners restyle — straight cut under chamfer, inward bite under scallop;
    // merge fillets always stay true arcs so panels still flow into the bar.
    function pathCorner(r, w, flip, xy) {
        if (r <= 0 || (w === 1 && root.chamfer)) return " L" + xy
        var ww = (w === 1 && root.scallop) ? 0 : w
        return " A" + r + "," + r + " 0 0 " + (flip ? (1 - ww) : ww) + " " + xy
    }

    // Single accent from the live palette. tint() is the one helper for translucent surfaces.
    readonly property color accent: Colors.bgActive
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── Typography ──────────────────────────────────────────────────────────────
    // The main display font — per-template (ui_font) with a manual override, blank = the default.
    // Nerd-font icons keep rendering under any display font: a shipped fontconfig rule pins
    // `iconFont` as the glyph fallback for the bundled UI fonts, so icons never depend on the
    // chosen face. iconFont is also exposed for anywhere that wants the glyph font explicitly.
    readonly property string iconFont:  "FantasqueSansM Nerd Font"
    readonly property string font:      (VtlConfig.uiFont && VtlConfig.uiFont !== "") ? VtlConfig.uiFont
                                                                                      : root.iconFont
    readonly property int    fsSection: 15   // group header — deliberately above body size (fsLabel)
    readonly property int    fsLabel:   13   // row / control label
    readonly property int    fsSub:     11   // secondary caption (bumped from 10 — reads small in Fredoka)
    readonly property int    fsValue:   13   // stepper value

    // True when the display font is NOT itself a Nerd Font, so inline glyphs render via the icon-font
    // fallback with mismatched (tight) metrics. Icon+label components split the glyph out and space
    // it themselves in that case; when the font already carries the glyphs, no split is needed.
    readonly property bool   splitIcons: VtlConfig.uiFont && VtlConfig.uiFont !== ""
    // First code point is a Nerd-Font / Private-Use-Area glyph (an inline icon at the start of a label).
    function leadIcon(s) {
        if (!s || s.length === 0) return ""
        var c = s.codePointAt(0)
        return ((c >= 0xE000 && c <= 0xF8FF) || (c >= 0xF0000 && c <= 0xFFFFD)) ? String.fromCodePoint(c) : ""
    }
    // The label with its leading icon glyph (and following spaces) stripped.
    function stripIcon(s) {
        var g = leadIcon(s); if (g === "") return s
        return ("" + s).slice(g.length).replace(/^\s+/, "")
    }

    // ── Radii (chamfer cut sizes under futuristic, bite sizes under grimoire, bump radius under
    //    wobbly). Straight/nostalgic are hard-cornered; sketch keeps a small radius. ───
    readonly property int rCard:    isCards ? 16 : isOutlined ? 8 : isFuturistic ? 10 : isGrimoire ? 12
                                  : isStraight ? 0 : isNostalgic ? 0 : isWobbly ? 9 : isSketch ? 7
                                  : isCupertino ? 18 : 14
    readonly property int rControl: isCards ? 12 : isOutlined ? 6 : isFuturistic ? 8  : isGrimoire ? 6
                                  : isStraight ? 0 : isNostalgic ? 0 : isWobbly ? 7 : isSketch ? 6
                                  : isCupertino ? 12 : 10
    readonly property int rTile:    isCards ? 12 : isOutlined ? 6 : isFuturistic ? 6  : isGrimoire ? 5
                                  : isStraight ? 0 : isNostalgic ? 0 : isWobbly ? 6 : isSketch ? 5
                                  : isCupertino ? 10 : 8

    // ── Spacing / density ─────────────────────────────────────────────────────────
    readonly property int cardGap: isOutlined ? 12 : (isCards || isCupertino) ? 14 : (isGrimoire || isWobbly || isSketch) ? 18
                                 : (isStraight || isNostalgic) ? 10 : 16                   // between groups
    readonly property int cardPad: isOutlined ? 12 : (isGrimoire || isWobbly || isCupertino) ? 16
                                 : isNostalgic ? 12 : 14                                   // inside a group
    readonly property int rowGap:  (isFlat || isGrimoire || isWobbly || isSketch || isCupertino) ? 10 : 8 // between rows in a group

    // ── Card / group surface ──────────────────────────────────────────────────────
    readonly property color cardFill: isCards      ? Colors.bgElement
                                     : isOutlined   ? "transparent"
                                     : isFuturistic ? root.tint(Colors.bgPrimary, 0.45)
                                     : isGrimoire   ? root.tint(root.accent, 0.07)
                                     : isNostalgic  ? Colors.bgElement
                                     : isStraight   ? root.tint(root.accent, 0.04)
                                     : isWobbly     ? root.tint(root.accent, 0.09)
                                     : isSketch     ? root.tint(root.accent, 0.05)
                                     : isCupertino  ? root.tint(Colors.bgElement, 0.55)
                                                    : root.tint(root.accent, 0.06)
    readonly property int   cardBorderW:     isNostalgic ? 2 : isFlat ? 0 : 1
    readonly property color cardBorderColor: isOutlined   ? Colors.boNormal
                                            : isFuturistic ? root.tint(root.accent, 0.50)
                                            : isGrimoire   ? root.tint(root.accent, 0.55)
                                            : isStraight   ? Colors.boNormal
                                            : isNostalgic  ? Colors.boNormal
                                            : isWobbly     ? root.tint(root.accent, 0.42)
                                            : isSketch     ? root.tint(Colors.fgMuted, 0.85)
                                            : isCupertino  ? root.tint(Colors.boNormal, 0.35)
                                                           : root.tint(Colors.boNormal, 0.40)

    // ── Control surface (toggle rows, dropdown header, plain rows, tiles) ──────────
    readonly property color controlFill:  isCards      ? Colors.bgPrimary
                                         : isOutlined   ? "transparent"
                                         : isFuturistic ? root.tint(root.accent, 0.05)
                                         : isGrimoire   ? root.tint(root.accent, 0.10)
                                         : isNostalgic  ? Colors.bgElement
                                         : isStraight   ? root.tint(root.accent, 0.07)
                                         : isWobbly     ? root.tint(root.accent, 0.12)
                                         : isSketch     ? root.tint(root.accent, 0.07)
                                         : isCupertino  ? root.tint(Colors.bgPrimary, 0.55)
                                                        : root.tint(root.accent, 0.12)
    readonly property color controlHover: isOutlined   ? root.tint(root.accent, 0.12)
                                         : isCards      ? root.tint(root.accent, 0.18)
                                         : isFuturistic ? root.tint(root.accent, 0.16)
                                         : isCupertino  ? root.tint(root.accent, 0.16)
                                                        : root.tint(root.accent, 0.22)
    readonly property int   controlBorderW:     isNostalgic ? 2 : isFlat ? 0 : 1
    readonly property color controlBorderColor: isOutlined   ? Colors.boNormal
                                               : isFuturistic ? root.tint(root.accent, 0.45)
                                               : isGrimoire   ? root.tint(root.accent, 0.35)
                                               : isStraight   ? Colors.boNormal
                                               : isNostalgic  ? Colors.boNormal
                                               : isWobbly     ? root.tint(root.accent, 0.35)
                                               : isSketch     ? root.tint(Colors.fgMuted, 0.70)
                                               : isCupertino  ? root.tint(Colors.boNormal, 0.35)
                                                              : root.tint(Colors.boNormal, 0.40)

    // ── Selected / active ─────────────────────────────────────────────────────────
    readonly property color selFill:        isOutlined   ? "transparent"
                                           : isFuturistic ? root.tint(root.accent, 0.28)
                                                          : root.accent
    readonly property color selText:        isOutlined ? root.accent    : Colors.fgBright
    readonly property int   selBorderW:     isNostalgic ? 2 : isFlat ? 0 : 1
    readonly property color selBorderColor: (isOutlined || isFuturistic) ? root.accent : Colors.boActive

    // ── Panel surface (menu / flyout / notification-center / dock fills) ──────────
    // All bar-grown panels share one fill. Cupertino goes frosted: desaturated toward neutral
    // grey and translucent, so the compositor blur (global quickshell layer rule, ignore_alpha
    // 0.1 + xray) shows the wallpaper through — panels take colour from the blur, not the theme.
    // Desaturate a colour toward neutral grey under cupertino (frosted surfaces read neutral,
    // the blurred wallpaper provides the colour) — identity for every other variant.
    function frost(c) {
        if (!isCupertino) return c
        var g = 0.30 * c.r + 0.59 * c.g + 0.11 * c.b
        return Qt.rgba(c.r * 0.35 + g * 0.65, c.g * 0.35 + g * 0.65, c.b * 0.35 + g * 0.65, c.a)
    }
    function panelColor(colorful) {
        var t = colorful ? 0.12 : 0.0
        var c = root.frost(Qt.rgba(Colors.bgPrimary.r * (1 - t) + Colors.bgActive.r * t,
                                   Colors.bgPrimary.g * (1 - t) + Colors.bgActive.g * t,
                                   Colors.bgPrimary.b * (1 - t) + Colors.bgActive.b * t, 1))
        // Same translucency as the macos bar (bar_opacity 0.55) so strip + panels read as ONE
        // material — a panel lighter than the bar looks like a foreign surface.
        return isCupertino ? Qt.rgba(c.r, c.g, c.b, 0.55) : c
    }
    // Free-corner radius for those panels: cupertino rounds generously regardless of the bar's
    // inner radius; everyone else follows chromeR (squared for the strict variants).
    function panelR(r) { return isCupertino ? Math.max(r, 16) : chromeR(r) }
    // Menu-body row surfaces (device lists, network rows, …) — neutral frosted rows under
    // cupertino instead of the theme's element colour, so lists read like macOS panes.
    readonly property color menuRowFill:   isCupertino ? Qt.rgba(1, 1, 1, 0.07) : Colors.bgElement
    readonly property color menuRowHover:  isCupertino ? Qt.rgba(1, 1, 1, 0.13) : root.tint(Colors.bgActive, 0.16)
    readonly property color menuRowActive: isCupertino ? root.tint(root.accent, 0.40) : root.tint(Colors.bgActive, 0.28)

    // ── Chrome outline (bar / flyout / OSD / notification Shape strokes) ──────────
    // Colour, width and free-corner shape all follow the variant, so the bar and every panel
    // outline restyle with the shell. (Corner CUTS/BITES already flow through cornerSeg; here the
    // strict variants additionally square the free corners, and the bold variants thicken the line.)
    readonly property color chromeBorder: isFuturistic ? root.tint(root.accent, 0.55)
                                        : isGrimoire   ? root.tint(root.accent, 0.50)
                                        : isWobbly     ? root.tint(root.accent, 0.45)
                                        : isSketch     ? root.tint(Colors.fgMuted, 0.70)
                                        : isNostalgic  ? root.tint(Colors.fgBright, 0.55)
                                        : isCupertino  ? root.tint(Colors.fgBright, 0.16)
                                        : isStraight   ? Colors.boNormal
                                                       : Colors.boNormal
    readonly property int chromeBorderWidth: (isFuturistic || isGrimoire || isNostalgic) ? 2 : 1
    // Free-corner radius for a chrome outline (the bar hole corners, the menu's content corners).
    // Strict/retro variants square them off; the rest keep the user's bar inner-radius. Merge
    // fillets (how a panel flows into the bar) stay governed by the transition-style setting.
    function chromeR(r) { return (isStraight || isNostalgic) ? 0 : r }

    // ── Toggle switch ─────────────────────────────────────────────────────────────
    readonly property color trackOn:  root.accent
    readonly property color trackOff: Colors.bgPrimary
    readonly property color knob:     Colors.fgBright
}
