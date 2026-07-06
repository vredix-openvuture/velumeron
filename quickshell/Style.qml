pragma Singleton
import QtQuick

// Global UI-style tokens. One place decides radius / fill / border / spacing / accent for every shared
// widget in quickshell/common/, driven by the user's chosen variant (Settings → Style → UI STYLE,
// persisted as `ui_style` and read live via VtlConfig). Switching the variant re-binds every token, so
// the whole shell restyles in place — no restart (Colors + VtlConfig already poll live).
//
// Colours stay wallust-driven: the single accent is Colors.bgActive, used ONLY for active/selected
// state — except under `futuristic`, whose HUD look runs a translucent accent through every border.
// Surfaces are neutral. That kills the old "blue + gold + olive, five radii" mishmash where every
// settings page rolled its own controls.
QtObject {
    id: root

    // flat (default) · cards · outlined · futuristic
    readonly property string variant:      VtlConfig.uiStyle
    readonly property bool   isCards:      variant === "cards"
    readonly property bool   isOutlined:   variant === "outlined"
    readonly property bool   isFuturistic: variant === "futuristic"
    readonly property bool   isFlat:       !isCards && !isOutlined && !isFuturistic   // unknown → flat

    // Futuristic cuts corners at 45° instead of rounding them. StyledRect and every
    // chrome path builder key off this single switch.
    readonly property bool chamfer: isFuturistic

    // Convex-corner SVG segment for hand-rolled path builders (Bar.qml): a clockwise arc
    // normally, the straight 45° cut when chamfered. (x,y) is the segment endpoint.
    function cornerSeg(r, x, y) {
        return root.chamfer ? "L" + x + "," + y
                            : "A" + r + "," + r + " 0 0 1 " + x + "," + y
    }

    // Single accent from the live palette. tint() is the one helper for translucent surfaces.
    readonly property color accent: Colors.bgActive
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── Typography ──────────────────────────────────────────────────────────────
    readonly property string font:      "FantasqueSansM Nerd Font"
    readonly property int    fsSection: 10   // small-caps group header
    readonly property int    fsLabel:   13   // row / control label
    readonly property int    fsSub:     10   // secondary caption
    readonly property int    fsValue:   13   // stepper value

    // ── Radii (chamfer cut sizes under futuristic) ──────────────────────────────
    readonly property int rCard:    isCards ? 16 : isOutlined ? 8 : isFuturistic ? 10 : 14
    readonly property int rControl: isCards ? 12 : isOutlined ? 6 : isFuturistic ? 8  : 10
    readonly property int rTile:    isCards ? 12 : isOutlined ? 6 : isFuturistic ? 6  : 8

    // ── Spacing / density ─────────────────────────────────────────────────────────
    readonly property int cardGap: isOutlined ? 12 : isCards ? 14 : 16   // between groups
    readonly property int cardPad: isOutlined ? 12 : 14                  // inside a group
    readonly property int rowGap:  isFlat ? 10 : 8                       // between rows in a group

    // ── Card / group surface ──────────────────────────────────────────────────────
    readonly property color cardFill: isCards      ? Colors.bgElement
                                     : isOutlined   ? "transparent"
                                     : isFuturistic ? root.tint(Colors.bgPrimary, 0.45)
                                                    : root.tint(root.accent, 0.06)
    readonly property int   cardBorderW:     isFlat ? 0 : 1
    readonly property color cardBorderColor: isOutlined   ? Colors.boNormal
                                            : isFuturistic ? root.tint(root.accent, 0.50)
                                                           : root.tint(Colors.boNormal, 0.40)

    // ── Control surface (toggle rows, dropdown header, plain rows, tiles) ──────────
    readonly property color controlFill:  isCards      ? Colors.bgPrimary
                                         : isOutlined   ? "transparent"
                                         : isFuturistic ? root.tint(root.accent, 0.05)
                                                        : root.tint(root.accent, 0.12)
    readonly property color controlHover: isOutlined   ? root.tint(root.accent, 0.12)
                                         : isCards      ? root.tint(root.accent, 0.18)
                                         : isFuturistic ? root.tint(root.accent, 0.16)
                                                        : root.tint(root.accent, 0.22)
    readonly property int   controlBorderW:     isFlat ? 0 : 1
    readonly property color controlBorderColor: isOutlined   ? Colors.boNormal
                                               : isFuturistic ? root.tint(root.accent, 0.45)
                                                              : root.tint(Colors.boNormal, 0.40)

    // ── Selected / active ─────────────────────────────────────────────────────────
    readonly property color selFill:        isOutlined   ? "transparent"
                                           : isFuturistic ? root.tint(root.accent, 0.28)
                                                          : root.accent
    readonly property color selText:        isOutlined ? root.accent    : Colors.fgBright
    readonly property int   selBorderW:     isFlat ? 0 : 1
    readonly property color selBorderColor: (isOutlined || isFuturistic) ? root.accent : Colors.boActive

    // ── Chrome outline (bar / flyout / OSD / notification Shape strokes) ──────────
    readonly property color chromeBorder: isFuturistic ? root.tint(root.accent, 0.55) : Colors.boNormal

    // ── Toggle switch ─────────────────────────────────────────────────────────────
    readonly property color trackOn:  root.accent
    readonly property color trackOff: Colors.bgPrimary
    readonly property color knob:     Colors.fgBright
}
