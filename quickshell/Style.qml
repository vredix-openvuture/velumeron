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
    // Slow-motion switch for inspecting these animations. 1.0 = the real thing; 10.0 runs
    // everything ten times slower, which is the only practical way to see what a 300 ms spring is
    // actually doing. A spring's period goes with 1/sqrt(spring), so N× slower means stiffness ÷N²
    // and damping ÷N — which also leaves the damping RATIO untouched, so it slows down without
    // becoming bouncier. Leave it at 1.0; it is a tool, not a setting.
    readonly property real motionSlow:  1.0

    readonly property real elSpring:    VtlConfig.elasticSpring / (motionSlow * motionSlow)
    readonly property real elDamping:   VtlConfig.elasticDamping / motionSlow

    // Closing takes 20 % longer. DURATION ONLY — the curve, the axis stagger and the overshoot are
    // identical in both directions, so it is still the opening played backwards, just at a calmer
    // pace. (An earlier attempt also gave closing its own ease curve; that made it read as a second,
    // different animation. This does not.)
    //
    // Dividing stiffness by N² and damping by N leaves the DAMPING RATIO untouched — the spring is
    // slower without becoming bouncier, which is the only reason this is safe to do to one direction.
    // BOTH DIRECTIONS RUN ON THE SAME SPRING. That is the spec, stated plainly after a long
    // detour: open and close at equal speed, one Motion slider controlling both, no asymmetry.
    // The direction split below is kept NEUTRAL (both factors 1.0) — the targetValue wiring at the
    // call sites is correct and harmless, and the hooks remain should a deliberate asymmetry ever
    // be wanted again. The detour's lesson is recorded there: selecting a spring from an external
    // open-flag latches stale and runs every animation on the wrong-direction spring.
    readonly property real elOpenBoost:    1.0
    readonly property real elCloseSlow:    1.0
    readonly property real elSpringOpen:   elSpring  * elOpenBoost * elOpenBoost
    readonly property real elDampingOpen:  elDamping * elOpenBoost
    readonly property real elSpringClose:  elSpring  / (elCloseSlow * elCloseSlow)
    readonly property real elDampingClose: elDamping / elCloseSlow
    function springFor(open)  { return open ? elSpringOpen  : elSpringClose }
    function dampingFor(open) { return open ? elDampingOpen : elDampingClose }

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
    // How much of that bow survives on the way OUT. Closing drives the bow from `reveal − target`
    // with a target of 0 — i.e. from the reveal itself — so it is strongest the instant the panel
    // starts to close and eases off from there, rather than appearing only when the spring
    // overshoots. The edges therefore suck inward hard for the whole retreat. Scaling it back keeps
    // the soft-mass character without the panel folding in on itself. 1.0 = as much as opening.
    readonly property real elCloseBow: 0.4
    function elBulge(reveal, target, coeff, dim) {
        var b = Math.min(coeff, dim * elMaxFrac)
        var stiff = (target < 0.5) ? elCloseBow : 1.0
        return -b * (reveal - target) * elG01(reveal) * stiff
    }
    // Size multiplier for the container morph: reveal plus a touch of the spring OVERSHOOT.
    //
    // "Overshoot" means the spring has gone PAST its target — above 1 while opening, below 0 while
    // closing. The old form used the raw error `reveal − target`, which is the same thing while
    // opening but nothing like it while closing: there the target is 0, so the error IS the reveal,
    // and the panel was scaled by (1 + elSizeOver) for the entire retreat. It left the bar 15 %
    // oversized and shrank from there.
    //
    // That was always happening; a fast spring simply hid it. Slow the close down and it becomes
    // the panel visibly ballooning before it goes.
    function elSizeF(reveal, target) {
        var over = (target >= 0.5) ? Math.max(0, reveal - 1.0)   // opening: only past full size
                                   : Math.min(0, reveal)          // closing: only past empty
        return Math.max(0, reveal + elSizeOver * over)
    }

    // ── The two motions, and which surface gets which ─────────────────────────────────────────────
    // Everything that opens in this shell does it in one of exactly two ways, and the difference is
    // not decorative — it says where the thing CAME FROM:
    //
    //   DOCKED   it grew out of the bar. Depth (away from the bar) runs 0 → full, so it emerges
    //            from the bar's inner face and retracts back into it; the length along the bar runs
    //            from a nub to full. Flyout, Settings, NotifCenter, Launcher.
    //   FREE     it belongs to the screen, not the bar, and fades up in place with a slight scale.
    //            Session, clipboard, window switcher, layout switcher, screenshot.
    //
    // Both are driven by the SAME spring, so they feel like one system. What used to differ was
    // everything else: four different start scales (0.94/0.96/0.97/0.97), two dim levels
    // (0.35/0.40), three colour-fade durations (90/110/180) and one surface (the screenshot card)
    // on a plain 180 ms curve instead of the spring at all. Those are now these constants, and a
    // free card is `scale: Style.popScale(reveal); opacity: Style.popFade(reveal)` — nothing else.
    readonly property real popScaleFrom: 0.96
    readonly property real popDim:       0.45    // how heavy the veil behind a free card gets
    readonly property int  popColorMs:   100     // hover/selection colour fades inside any popout
    // Every control-level transition: a switch knob sliding, a row lighting up under the cursor, a
    // chip taking selection. One number, because the eye reads a hover at 90 ms next to a hover at
    // 120 ms as one of them being broken. Controls are NOT sprung — a switch that overshoots reads
    // as a toy — so this stays a plain duration.
    readonly property int  ctrlMs:       Math.round(110 * motionSlow)

    // Size of a DOCKED panel mid-morph. BOTH axes collapse — the panel gathers itself back into the
    // corner it grew from, vertically and horizontally at once.
    //
    //   depth  (away from the bar)  0 → full
    //   length (along the bar)      0 → full
    //
    // Both run to ZERO rather than to a nub, and that is what lets the bar's own border close
    // behind it: the gap the bar leaves for this panel is exactly its length (see Bar.qml's
    // `menuGap`), so a length that never reaches zero leaves a notch in the bar that never shuts.
    // `nub` is kept in the signature so the call sites did not all have to change at once.
    // The two axes do NOT finish together, and that is the point. Running both to zero at the same
    // instant collapses the panel onto a single point, and a rectangle shrinking to a dot reads as
    // being sucked away rather than as closing — it is the last thing left that still looks wrong.
    //
    // So the LENGTH runs out early: it reaches zero while the panel still has depth left, and the
    // remaining depth then plays out against nothing. The panel is gone before the maths is.
    //
    // Length rather than depth, because the gap in the bar's border is exactly this panel's length
    // (Bar.qml's `cut`). Retiring the length first means the border has already closed by the time
    // the panel disappears; the other way round would leave a notch in the bar with nothing in it.
    // The depth finishes early too, just by less. Letting it run the full travel meant the last
    // stretch of the animation was the spring settling against a panel that had already gone — time
    // in which nothing happens on screen. Both axes now retire before the spring does; the LENGTH
    // still leads, which is what keeps the border closing ahead of the panel.
    readonly property real elLengthLead: 0.26     // fraction of the travel the length finishes early
    readonly property real elDepthLead:  0.13     // …and the depth, half as much

    // THE LEAD ONLY APPLIES WHILE CLOSING. It exists so a panel is gone before the spring has
    // finished settling; applied on the way IN it is simply dead time — the first quarter of the
    // travel produces no visible change at all, which is felt as "it opens slowly" no matter how
    // stiff the spring is. Stiffening the spring cannot fix a pause; it only shortens everything
    // else around it.
    readonly property real elEaseGamma: 1.05
    // Optional per-surface `gamma`. Above 1 it makes the SIZE crawl as it approaches zero while
    // the spring runs on unchanged — time slows exactly where the surface meets the bar and
    // nowhere else. The launcher passes a high one for its close, so the melt into the border is
    // readable instead of blinking through the last pixels.
    function _lead(sizeF, lead, target, gamma) {
        var l = (target >= 0.5) ? 0.0 : lead          // opening: no lead, start moving at once
        var g = (gamma === undefined) ? elEaseGamma : gamma
        var v = Math.max(0, (sizeF - l) / (1.0 - l))
        return Math.pow(v, g)
    }
    function elDockW(vert, full, nub, sizeF, target, lenLead, depLead, gamma) {
        var L = (lenLead === undefined) ? elLengthLead : lenLead
        var D = (depLead === undefined) ? elDepthLead  : depLead
        return full * (vert ? _lead(sizeF, D, target, gamma) : _lead(sizeF, L, target, gamma))
    }
    function elDockH(vert, full, nub, sizeF, target, lenLead, depLead, gamma) {
        var L = (lenLead === undefined) ? elLengthLead : lenLead
        var D = (depLead === undefined) ? elDepthLead  : depLead
        return full * (vert ? _lead(sizeF, L, target, gamma) : _lead(sizeF, D, target, gamma))
    }
    // A panel that grows OUT of the bar is part of the bar, so it takes the bar's transparency with
    // it. Anything else looks broken the moment the two are asked to read as one shape: a
    // see-through strip with a solid slab hanging off it is not a bulge in an edge, it is two
    // objects. Pass the monitor so per-monitor bar settings carry across.
    function barPanelColor(base, mon) {
        if (!VtlConfig.barOpacityEnabledFor(mon)) return base
        return Qt.rgba(base.r, base.g, base.b, base.a * VtlConfig.barOpacityValueFor(mon))
    }

    function popScale(reveal) { return popScaleFrom + (1.0 - popScaleFrom) * elG01(reveal) }
    function popFade(reveal)  { return elG01(reveal) }
    // The veil behind a free card — and it is NOT black. The desktop underneath is wallust-tinted,
    // and pure black punches a hole through that tint instead of dimming it; the screenshot overlay
    // had already worked this out for itself while everything else was still laying rgba(0,0,0,·)
    // over the wallpaper. Derived from the scheme's own ground, so the desktop darkens in its own
    // colour. This is also what the session menu now uses in place of its blur.
    function popDimColor(reveal) {
        var c = Qt.darker(Colors.bgPrimary, 1.8)
        return Qt.rgba(c.r, c.g, c.b, popDim * popFade(reveal))
    }
    // Opacity tracks the reveal ONE-TO-ONE, and that matters at the end of a close.
    //
    // This used to be min(1, reveal·4) — opaque for the whole first quarter, so the surface was
    // still fully visible when the spring had already pulled its size most of the way to zero. Size
    // and opacity were then running on different curves, and you could watch it: the panel snapped
    // shut and a leftover sliver faded out behind it. "It plops away and then fades out again."
    //
    // One curve for both, so there is nothing left to fade when the shape is gone.
    function popShellFade(reveal)   { return elG01(reveal) }
    // Content from a QUARTER of the way in, not half. Waiting until 50 % meant the panel spent
    // the first half of every open as an empty box — the other half of "it opens slowly".
    function popContentFade(reveal) { return Math.max(0.0, Math.min(1.0, (reveal - 0.25) / 0.40)) }

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

    // ── Tokens — supplied by the ACTIVE THEME, not decided here ───────────────────
    // Radius, fill, border and spacing used to be one fourteen-deep ternary per token over ten
    // hardcoded variant booleans, so an eleventh look could only exist by editing this file. The
    // tables now live in Theme.variantTokens and a theme package overrides them (see Theme.qml), and
    // this side is a lookup with the flat value as the fallback.
    //
    // Colours arrive as RECIPES rather than values. The palette is wallust's and moves with the
    // wallpaper, so a token names a palette entry and what to do to it; resolving that lives here
    // because tint / lift / liftSolid live here. The dependency runs one way: Style reads Theme,
    // Theme never reads Style.
    //
    // Reactivity is unchanged. A binding that calls these captures every property they read —
    // Theme.tokens, the Colors entry, root.accent, surfaceLift — so switching theme, wallpaper or
    // the surface-contrast knob still re-binds every token in place, with no restart.
    // A broken theme must never blank the shell, so every lookup falls back and keeps drawing — but
    // it says so. The warning fires only when a key is PRESENT and wrong, which is a theme bug and
    // exactly when the noise is wanted; a key a theme simply does not set is silent.
    function _tokNum(key, fallback) {
        var v = Theme.tokens[key]
        if (typeof v === "number") return v
        if (v !== undefined) console.warn("theme:", Theme.themeId, "token", key, "is not a number:", v)
        return fallback
    }
    function _tokBase(name) {
        if (name === "accent")   return root.accent
        if (name === "onAccent") return root.onAccent
        var c = Colors[name]
        if (c !== undefined) return c
        console.warn("theme:", Theme.themeId, "unknown palette entry:", name)
        return root.accent
    }
    function _tokColor(key, fallback) {
        var v = Theme.tokens[key]
        if (v === undefined || v === null) return fallback
        if (typeof v === "string") return (v === "transparent") ? "transparent" : root._tokBase(v)
        var base = root._tokBase(v.base)
        if (v.solid)               return root.liftSolid(base)
        if (v.lift  !== undefined) return root.tint(base, root.lift(v.lift))
        if (v.alpha !== undefined) return root.tint(base, v.alpha)
        return base
    }

    // ── Radii. The theme picks the numbers; the SHAPE of a corner is still keyed off the variant
    //    above (chamfer cuts at 45 degrees, scallop bites inward, wobbly bumps, sketch bows),
    //    because that selects a renderer rather than a value. ───────────────────────
    readonly property int rCard:    root._tokNum("rCard",    14)
    readonly property int rControl: root._tokNum("rControl", 10)
    readonly property int rTile:    root._tokNum("rTile",     8)

    // ── Spacing / density ─────────────────────────────────────────────────────────
    readonly property int cardGap: root._tokNum("cardGap", 16)   // between groups
    readonly property int cardPad: root._tokNum("cardPad", 14)   // inside a group
    readonly property int rowGap:  root._tokNum("rowGap",  10)   // between rows in a group

    // ── Card / group surface ──────────────────────────────────────────────────────
    // The accent tints (and the two solid fills) run through the surface-contrast knob: that is what
    // a token's "lift" means. A token's "alpha" does NOT. On the futuristic and cupertino surfaces
    // the value is translucency for the blur behind the surface, not a lift off the panel, and
    // scaling it would only fog the material.
    readonly property color cardFill:        root._tokColor("cardFill",
                                                 root.tint(root.accent, root.lift(0.06)))
    readonly property int   cardBorderW:     root._tokNum("cardBorderW", 0)
    readonly property color cardBorderColor: root._tokColor("cardBorderColor",
                                                 root.tint(Colors.boNormal, 0.40))

    // ── Control surface (toggle rows, dropdown header, plain rows, tiles) ──────────
    readonly property color controlFill:  root._tokColor("controlFill",
                                              root.tint(root.accent, root.lift(0.12)))
    // Hover follows the same knob, or a raised control fill would swallow its own hover state.
    readonly property color controlHover: root._tokColor("controlHover",
                                              root.tint(root.accent, root.lift(0.22)))
    readonly property int   controlBorderW:     root._tokNum("controlBorderW", 0)
    readonly property color controlBorderColor: root._tokColor("controlBorderColor",
                                                    root.tint(Colors.boNormal, 0.40))

    // ── Selected / active ─────────────────────────────────────────────────────────
    readonly property color selFill:        root._tokColor("selFill", root.accent)
    readonly property color selText:        root._tokColor("selText", root.onAccent)
    readonly property int   selBorderW:     root._tokNum("selBorderW", 0)
    readonly property color selBorderColor: root._tokColor("selBorderColor", Colors.boActive)

    // ── The theme contract ────────────────────────────────────────────────────────
    // What a THEME-SUPPLIED component gets handed. Measured fact behind this: a QML component from
    // outside the shell tree loads and may use Quickshell's own types, but it cannot see the shell's
    // singletons at all — `Style`, `Colors` and `VtlConfig` are simply not defined there. So this is
    // not a convenience wrapper, it is the API boundary. A theme reads its surface's properties and
    // nothing else, which is also what lets the contract be versioned: `contract` says which shape
    // the object has, and a component can refuse a shape it does not know.
    //
    // Everything here is RESOLVED. The recipes a theme.json writes are already colours by the time
    // they reach a component, because the component has no tint/lift to resolve them with.
    //
    // Each surface adds its own state on top; this is the part every surface shares.
    function themeContext() {
        return {
            "contract": Theme.contract,
            "theme":    Theme.themeId,
            "font":     root.font,
            "iconFont": root.iconFont,
            // The theme's OWN namespaced settings, so a component and the settings page that
            // writes them are looking at the same object.
            "settings": Theme.settings,
            "palette": {
                "bgPrimary":   Colors.bgPrimary,   "bgSecondary": Colors.bgSecondary,
                "bgElement":   Colors.bgElement,   "bgActive":    Colors.bgActive,
                "bgHover":     Colors.bgHover,     "boNormal":    Colors.boNormal,
                "boActive":    Colors.boActive,    "fgPrimary":   Colors.fgPrimary,
                "fgMuted":     Colors.fgMuted,     "fgUrgent":    Colors.fgUrgent,
                "fgBright":    Colors.fgBright,
                "accent":      root.accent,        "onAccent":    root.onAccent,
                "panel":       root.panelColor(VtlConfig.barColorful)
            },
            "tokens": {
                "rCard": root.rCard, "rControl": root.rControl, "rTile": root.rTile,
                "cardGap": root.cardGap, "cardPad": root.cardPad, "rowGap": root.rowGap,
                "cardFill": root.cardFill,
                "cardBorderW": root.cardBorderW, "cardBorderColor": root.cardBorderColor,
                "controlFill": root.controlFill, "controlHover": root.controlHover,
                "controlBorderW": root.controlBorderW, "controlBorderColor": root.controlBorderColor,
                "selFill": root.selFill, "selText": root.selText,
                "selBorderW": root.selBorderW, "selBorderColor": root.selBorderColor,
                "fsSection": root.fsSection, "fsLabel": root.fsLabel,
                "fsSub": root.fsSub, "fsValue": root.fsValue
            }
        }
    }

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

    // ── Popout surfaces ────────────────────────────────────────────────────────────────────────
    // The washes every popout is built from, named ONCE. They used to be written out longhand as
    // tint(bgElement, lift(x)) at 47 call sites across twelve files, which meant a variant could
    // restyle the OUTLINE of a panel and never a thing inside it — the shell chamfered its panels
    // and kept a stack of soft round washes in them.
    //
    // Named here, a variant restyles a popout whole. The cut variants take the fills right down and
    // put the definition in a line instead: a hard-cut panel wants edges, not upholstery.
    readonly property bool _hardCut: root.chamfer || isStraight || isOutlined

    readonly property color plateFill: root._hardCut ? root.tint(Colors.bgElement, root.lift(0.05))
                                     : isCupertino   ? Qt.rgba(1, 1, 1, 0.06)
                                                     : root.tint(Colors.bgElement, root.lift(0.10))
    readonly property int   plateBorderW: root._hardCut ? Math.max(1, root.chromeBorderWidth) : 0
    readonly property color plateBorderColor: root.chamfer ? root.tint(root.accent, 0.45)
                                                           : root.tint(Colors.boNormal, 0.7)

    // An inset readout (StatCell): a well in the plate, so one step further in than the plate is out.
    readonly property color wellFill:  root._hardCut ? root.tint(root.accent, root.lift(0.09))
                                                     : root.tint(Colors.bgElement, root.lift(0.10))
    readonly property int   wellBorderW: root._hardCut ? 1 : 0

    // List rows on a plate.
    readonly property color rowFill:   root._hardCut ? "transparent" : root.tint(Colors.bgElement, root.lift(0.07))
    readonly property color rowHover:  root._hardCut ? root.tint(root.accent, root.lift(0.16))
                                                     : root.tint(Colors.bgElement, root.lift(0.16))
    readonly property color rowActive: root._hardCut ? root.tint(root.accent, root.lift(0.24))
                                                     : root.tint(Colors.bgElement, root.lift(0.24))

    // The groove behind a value — a ring's track, a progress bar, a level bed.
    readonly property color trackFill: root._hardCut ? root.tint(root.accent, root.lift(0.20))
                                                     : root.tint(Colors.bgElement, root.lift(0.34))
    // A raised control that is neither plate nor row: a mute pill, a round button, an off disc.
    readonly property color knobFill:  root._hardCut ? root.tint(root.accent, root.lift(0.14))
                                                     : root.tint(Colors.bgElement, root.lift(0.22))
    readonly property color knobHover: root.tint(Colors.bgActive, root.lift(0.30))
    // The highlight down a plate's top edge. A cut panel does not get one — a chamfered surface with
    // a soft sheen on it reads as two different materials arguing.
    readonly property color sheen:     root._hardCut ? "transparent" : root.tint(Colors.fgBright, 0.06)

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
    // The width the BAR's chrome is actually drawn at on `mon` — the user's px value from Settings →
    // Bar → Border once they set one (0 = no outline), the ui_style's own weight otherwise.
    //
    // Every surface that grows out of the bar draws with THIS, not with the style default: a menu,
    // a flyout, a toast and the OSD all continue the bar's own line, and two different widths meet
    // at the seam as a visible step — the bar's 6 px line running into a popout's 1 px one. One
    // knob, one weight, everywhere. (Bar.qml derives the same value; it is the definition.)
    function barBorderW(mon) {
        var v = VtlConfig.barBorderWidthFor(mon)
        return (v === null || v === undefined) ? root.chromeBorderWidth : Math.max(0, v)
    }
    // The offset that puts an axis-aligned chrome line ON a pixel instead of BETWEEN two.
    //
    // A stroke is centred on its path, so an ODD-width line at an integer coordinate straddles two
    // pixel rows and each gets half the ink. That alone is merely soft. What makes it a bug is that
    // Qt's CurveRenderer cannot antialias an axis-aligned run at large coordinates: measured on a
    // 2560x1440 output with a ladder of identical 1px lines, runs at y≤500 split the ink 50/50 as
    // they should and runs from y≈700 down saturate BOTH rows. So one path, one stroke width, one
    // renderer produced a frame twice as heavy along its bottom and right as along its top and left.
    //
    // Nudging every axis-aligned run by this much lands the stroke on exactly one row and takes the
    // antialiaser out of the loop: identical weight at every coordinate, and crisper than the
    // "correct" result was. Curves are unaffected by the renderer bug and keep their AA, so only
    // straight runs need it. An EVEN width already ends on pixel boundaries when centred on an
    // integer, hence 0 — offsetting those would move the line without making it any crisper.
    function hairline(w) { return (Math.round(w) % 2) * 0.5 }
    // A panel that lands within a pixel of the strip's end is treated as FLUSH with it: it drops
    // its concave fillet and the bar hands its line over instead of curving away. That tolerance
    // was only ever read, never enforced — so the panel kept the position it happened to have and
    // the two "continuous" lines ran one pixel apart.
    //
    // Measured on the settings menu (2560x1440, dock with a 15 px side gap): bar border in column
    // 15, panel border in column 16. The panel tracks its ICON, and the icon slot starts inside the
    // bar's own border — icon centre 36, minus half a bar thickness, is 16. One pixel, and it reads
    // as a step at the seam. So snap the position onto the end it claims to be flush with; the
    // tolerance is the same ±1 every flushLo/flushHi uses.
    //
    // `lo`/`hi` are the two extremes of the along-the-bar travel (the strip's span, less the panel).
    // A panel longer than the strip has hi < lo and no end to be flush with — left alone.
    function flushSnap(v, lo, hi) {
        if (hi < lo) return v
        if (v <= lo + 1) return lo
        if (v >= hi - 1) return hi
        return v
    }
    // Free-corner radius for a chrome outline (the bar hole corners, the menu's content corners).
    // Strict/retro variants square them off; the rest keep the user's bar inner-radius. Merge
    // fillets (how a panel flows into the bar) stay governed by the transition-style setting.
    function chromeR(r) { return (isStraight || isNostalgic) ? 0 : r }

    // ── Toggle switch ─────────────────────────────────────────────────────────────
    readonly property color trackOn:  root.accent
    readonly property color trackOff: Colors.bgPrimary
    readonly property color knob:     Colors.fgBright

    // ── Status dot (common/StatusDot.qml) ─────────────────────────────────────────
    // The bar's ONE indicator: unread notifications on the bell, a due task on the clock, a linked
    // device on the phone. It is deliberately sized off the bar's icon size and not off the glyph
    // it happens to sit on — the modules run at different font and icon sizes, so per-glyph sizing
    // is exactly what made three dots of 5, 6 and 7 px read as three different indicators.
    // Sized to be SEEN from a metre away: a 5-6 px dot on a 1440p bar is a speck of dust, not a
    // signal. Roughly two thirds of the icon it marks, with a floor that survives a small bar.
    function dotSize(mon) { return Math.max(8, Math.round(VtlConfig.barIconSizeFor(mon) * 0.62)) }
    readonly property int dotRing: 1   // punches the dot out of whatever it sits on
    // The dot's default meaning-colour. NOT `accent` (= bgActive): that one is a SURFACE colour, so
    // on a dark bar it disappears into the panel it is drawn on. boActive is the palette's
    // "this is live" colour and is picked to sit on top of that surface.
    readonly property color dotTone: Colors.boActive

    // A real red, for FAULT states — the paired phone is gone, the battery is about to die.
    // Colors.fgUrgent is a wallust SLOT, and wallust fills it from the wallpaper: in the current
    // theme it lands on olive green (#6E8B4E), so "urgent" reads as "fine". Whether a fault looks
    // like a fault cannot depend on the wallpaper, so this one colour stays out of the palette.
    readonly property color danger: isCupertino ? "#ff453a" : "#E5484D"
}
