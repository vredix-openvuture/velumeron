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

    // ── Elastic emergence ("soft mass") — shell-wide motion, tunable (Settings → Style → Motion) ──
    // Panels spring open PAST their target and ring back; the free edges bow by the live spring
    // error `over = reveal − target`, scaled by how grown we are so a sliver doesn't fold in on
    // itself. Every emerging surface reads these + the two helpers, so one slider retunes them all.
    readonly property real elSpring:    VtlConfig.elasticSpring
    readonly property real elDamping:   VtlConfig.elasticDamping
    readonly property real elTopBulge:  VtlConfig.elasticTopBulge
    readonly property real elSideBulge: VtlConfig.elasticSideBulge
    readonly property real elSizeOver:  VtlConfig.elasticSizeOver
    function elG01(reveal)                { return Math.max(0, Math.min(1, reveal)) }
    // Cap the bulge at a fraction of the element's short side, so a small surface (OSD, pill,
    // notification toast) bows by the SAME PROPORTION as a big panel instead of ballooning — 144 px
    // on a 48 px OSD was grotesque, and 0.35 still read as a fat lobe on a ~100 px toast corner.
    // Calibrated so a normal-sized menu (short side ≳ 420) is never clipped (0.18·420 ≈ 76 < 144).
    readonly property real elMaxFrac: 0.18
    // px an edge bows: 0 at rest (→ straight edge). Sign is flipped from the raw spring error so the
    // panel bows OUTWARD (convex) as it emerges and INWARD (concave) as it retracts — the mass pushes
    // out on the way in, sucks in on the way out. coeff = elTopBulge (content edge) or elSideBulge;
    // dim = the element's short side (min of its width/height), used for the proportional cap.
    function elBulge(reveal, target, coeff, dim) {
        var b = Math.min(coeff, dim * elMaxFrac)
        return -b * (reveal - target) * elG01(reveal)
    }
    // size multiplier for the container morph: reveal plus a touch of the spring error.
    function elSizeF(reveal, target)      { return Math.max(0, reveal + elSizeOver * (reveal - target)) }

    // Rounded-rectangle outline whose FREE edges bow outward by the elastic bulge — for surfaces NOT
    // built in the panels' (a,d) dock space (launcher, free notification toasts). Returns
    // [borderOpen, fillClosed]. bT bows the content edge (opposite the dock), bS the side edges.
    // `dockEdge` ("top|bottom|left|right") reproduces the SAME dock transition the menus use: the two
    // dock corners are concave fillets (radius `f`) that flare into the bar, the fill runs a `seam`
    // into it (borderless merge), the far corners are convex rounds (radius `r`) and the three free
    // edges bow. "" = free-floating: all corners round, all four edges bow. Coords are element-local +
    // `pad`; at rest (bT=bS=0) every quad degenerates to a straight line → an ordinary rounded rect.
    function elRectPaths(W, H, r, f, bT, bS, dockEdge, seam, pad) {
        // ── Free-floating: plain rounded rect, all four edges bow (bT top/bottom, bS sides). ──
        if (dockEdge === "") {
            function xyf(x, y) { return (x + pad) + "," + (y + pad) }
            var e0 = Math.max(0, Math.min(r, W / 3, H / 3))
            var p = "M" + xyf(e0, 0)
                + " Q" + xyf(W / 2, -bT)     + " " + xyf(W - e0, 0) + pathCorner(e0, 1, false, xyf(W, e0))
                + " Q" + xyf(W + bS, H / 2)  + " " + xyf(W, H - e0) + pathCorner(e0, 1, false, xyf(W - e0, H))
                + " Q" + xyf(W / 2, H + bT)  + " " + xyf(e0, H)     + pathCorner(e0, 1, false, xyf(0, H - e0))
                + " Q" + xyf(-bS, H / 2)     + " " + xyf(0, e0)     + pathCorner(e0, 1, false, xyf(e0, 0))
                + " Z"
            return [p, p]
        }
        // ── Docked: free-tab with concave fillets flaring into the bar (mirrors bar/Flyout.qml). ──
        var horiz = (dockEdge === "top" || dockEdge === "bottom")
        var A = horiz ? W : H        // extent along the dock edge
        var D = horiz ? H : W        // depth away from it (dock edge at d = 0)
        var e  = Math.max(0, Math.min(r, A / 3, D / 3))
        var ff = Math.max(0, Math.min(f, A / 3, D / 3))
        var s  = seam
        var flip = (dockEdge === "bottom" || dockEdge === "left")
        function XY(a, d) {
            var x, y
            if      (dockEdge === "bottom") { x = a;     y = H - d }
            else if (dockEdge === "left")   { x = d;     y = a     }
            else if (dockEdge === "right")  { x = W - d; y = a     }
            else                            { x = a;     y = d     }   // top
            return (x + pad) + "," + (y + pad)
        }
        var cur = [0, 0]
        function L(a, d)     { cur = [a, d]; return " L" + XY(a, d) }
        function A_(rr, a, d, w) { cur = [a, d]; return pathCorner(rr, w, flip, XY(a, d)) }
        function LB(a, d, na, nd, b) {
            var ma = (cur[0] + a) / 2 + na * b, md = (cur[1] + d) / 2 + nd * b
            cur = [a, d]; return " Q" + XY(ma, md) + " " + XY(a, d)
        }
        var bd = "M" + XY(A + ff, 0) + A_(ff, A, ff, 0)          // concave fillet into the bar (far corner)
               + LB(A, D - e,  1, 0, bS) + A_(e, A - e, D, 1)    // free side → convex round
               + LB(e, D,      0, 1, bT) + A_(e, 0, D - e, 1)    // content edge → convex round
               + LB(0, ff,    -1, 0, bS) + A_(ff, -ff, 0, 0)     // free side → concave fillet into the bar
        var close = L(-ff, -s) + L(A + ff, -s) + " Z"           // seam back through the bar
        return [bd, bd + close]
    }

    // Single accent from the live palette. tint() is the one helper for translucent surfaces.
    readonly property color accent: Colors.bgActive
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── Surface contrast ──────────────────────────────────────────────────────────
    // How far a card / row lifts off the panel behind it (Settings → Style → Build a theme →
    // Menus). The alphas written into the fills below are the "normal" values; this scales them
    // all at once so the whole hierarchy — panel < card < control < hover — keeps its order.
    // Deliberately NOT a palette job: the step is a fraction of the accent, so whether it reads
    // depends on which colour the wallpaper happens to yield (measured across wallpapers, no
    // wallust dial moves it reliably) — the alpha is the knob that always works.
    readonly property real surfaceLift: VtlConfig.surfaceContrast === "subtle" ? 0.60
                                      : VtlConfig.surfaceContrast === "strong" ? 1.75 : 1.0
    function lift(a) { return Math.min(1.0, a * root.surfaceLift) }
    // Same knob for the variants whose surfaces are SOLID palette colours (cards, nostalgic, and
    // the menu list rows): there is no alpha to scale, so nudge the fill toward the palette's
    // bright end instead — or back down into the panel when the setting is "subtle".
    function liftSolid(c) {
        var k = (root.surfaceLift - 1.0) * 0.075
        if (Math.abs(k) < 0.002) return c
        var t = k > 0 ? Colors.fgBright : Colors.bgPrimary
        var a = Math.min(0.14, Math.abs(k))
        return Qt.rgba(c.r * (1 - a) + t.r * a, c.g * (1 - a) + t.g * a, c.b * (1 - a) + t.b * a, c.a)
    }

    // WCAG relative luminance of a color (sRGB → linear → weighted). Used to pick readable text.
    function _lin(c) { return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
    function luminance(col) { return 0.2126 * _lin(col.r) + 0.7152 * _lin(col.g) + 0.0722 * _lin(col.b) }
    // Readable text/glyph colour to sit ON the accent (or any fill): black once the fill is light
    // enough that black beats white on contrast (the crossover is L ≈ 0.179), else near-white. Fixes
    // near-white-on-mid-accent (e.g. Solarized blue gave 2.2:1) everywhere the accent carries text.
    function onColor(fill) { return luminance(fill) > 0.179 ? "#0c0c0c" : "#ffffff" }
    readonly property color onAccent: root.onColor(root.accent)

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
    // The accent tints (and the two solid fills) run through the surface-contrast knob; the
    // futuristic/cupertino alphas do NOT — there the value is translucency for the blur behind
    // the surface, not a lift off the panel, so scaling it would just fog the material.
    readonly property color cardFill: isCards      ? root.liftSolid(Colors.bgElement)
                                     : isOutlined   ? "transparent"
                                     : isFuturistic ? root.tint(Colors.bgPrimary, 0.45)
                                     : isGrimoire   ? root.tint(root.accent, root.lift(0.07))
                                     : isNostalgic  ? root.liftSolid(Colors.bgElement)
                                     : isStraight   ? root.tint(root.accent, root.lift(0.04))
                                     : isWobbly     ? root.tint(root.accent, root.lift(0.09))
                                     : isSketch     ? root.tint(root.accent, root.lift(0.05))
                                     : isCupertino  ? root.tint(Colors.bgElement, 0.55)
                                                    : root.tint(root.accent, root.lift(0.06))
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
                                         : isFuturistic ? root.tint(root.accent, root.lift(0.05))
                                         : isGrimoire   ? root.tint(root.accent, root.lift(0.10))
                                         : isNostalgic  ? Colors.bgElement
                                         : isStraight   ? root.tint(root.accent, root.lift(0.07))
                                         : isWobbly     ? root.tint(root.accent, root.lift(0.12))
                                         : isSketch     ? root.tint(root.accent, root.lift(0.07))
                                         : isCupertino  ? root.tint(Colors.bgPrimary, 0.55)
                                                        : root.tint(root.accent, root.lift(0.12))
    // Hover follows the same knob, or a raised control fill would swallow its own hover state.
    readonly property color controlHover: isOutlined   ? root.tint(root.accent, root.lift(0.12))
                                         : isCards      ? root.tint(root.accent, root.lift(0.18))
                                         : isFuturistic ? root.tint(root.accent, root.lift(0.16))
                                         : isCupertino  ? root.tint(root.accent, 0.16)
                                                        : root.tint(root.accent, root.lift(0.22))
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
    readonly property color selText:        isOutlined ? root.accent    : root.onAccent
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
    // ── Menu size, derived from the dashboard raster ─────────────────────────────
    // The settings menu is exactly as big as its dashboard page needs, so no row is ever
    // half-visible and nothing is left over under the last one. It lives here rather than
    // in VtlConfig because the gap between cells is a STYLE value (cardGap), and VtlConfig
    // cannot import Style without a cycle.
    readonly property int dashGridW: VtlConfig.dashboardCols * VtlConfig.dashboardCellW
                                   + (VtlConfig.dashboardCols - 1) * root.cardGap
    readonly property int dashGridH: VtlConfig.dashboardRows * VtlConfig.dashboardCellH
                                   + (VtlConfig.dashboardRows - 1) * root.cardGap
    // What the hub puts BELOW the grid — the page dots, their margins and the bottom
    // cluster (session tiles, or the gear/lock pair in page mode) — plus the content
    // area's own top+bottom margins. Mirrors settings/home/HomeHub.qml and Settings.qml's
    // content anchors; change the layout there and this has to follow.
    readonly property int dashChromeH: (VtlConfig.settingsNavMode === "page" ? 66 : 79) + 30
    // Content width = grid + the content area's left/right margins (18 each).
    readonly property int menuContentW: root.dashGridW + 36

    // Free-corner radius for those panels: cupertino rounds generously regardless of the bar's
    // inner radius; everyone else follows chromeR (squared for the strict variants).
    function panelR(r) { return isCupertino ? Math.max(r, 16) : chromeR(r) }
    // Menu-body row surfaces (device lists, network rows, …) — neutral frosted rows under
    // cupertino instead of the theme's element colour, so lists read like macOS panes.
    // Rows sit on a panel exactly like cards do, so they follow the surface-contrast knob too.
    readonly property color menuRowFill:   isCupertino ? Qt.rgba(1, 1, 1, 0.07) : root.liftSolid(Colors.bgElement)
    readonly property color menuRowHover:  isCupertino ? Qt.rgba(1, 1, 1, 0.13) : root.tint(Colors.bgActive, root.lift(0.16))
    readonly property color menuRowActive: isCupertino ? root.tint(root.accent, 0.40) : root.tint(Colors.bgActive, root.lift(0.28))

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
