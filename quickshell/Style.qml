pragma Singleton
import QtQuick

// Global UI-style tokens. One place decides radius / fill / border / spacing / accent for every shared
// widget in quickshell/common/, driven by the user's chosen variant (Settings → Style → UI STYLE,
// persisted as `ui_style` and read live via VtlConfig). Switching the variant re-binds every token, so
// the whole shell restyles in place — no restart (Colors + VtlConfig already poll live).
//
// Colours stay wallust-driven: the single accent is Colors.bgActive, used ONLY for active/selected
// state. Surfaces are neutral. That kills the old "blue + gold + olive, five radii" mishmash where every
// settings page rolled its own controls.
QtObject {
    id: root

    // flat (default) · cards · outlined
    readonly property string variant:    VtlConfig.uiStyle
    readonly property bool   isFlat:      variant !== "cards" && variant !== "outlined"
    readonly property bool   isCards:     variant === "cards"
    readonly property bool   isOutlined:  variant === "outlined"

    // Single accent from the live palette. tint() is the one helper for translucent surfaces.
    readonly property color accent: Colors.bgActive
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── Typography ──────────────────────────────────────────────────────────────
    readonly property string font:      "FantasqueSansM Nerd Font"
    readonly property int    fsSection: 10   // small-caps group header
    readonly property int    fsLabel:   13   // row / control label
    readonly property int    fsSub:     10   // secondary caption
    readonly property int    fsValue:   13   // stepper value

    // ── Radii ───────────────────────────────────────────────────────────────────
    readonly property int rCard:    isCards ? 16 : isOutlined ? 8 : 14
    readonly property int rControl: isCards ? 12 : isOutlined ? 6 : 10
    readonly property int rTile:    isCards ? 12 : isOutlined ? 6 : 8

    // ── Spacing / density ─────────────────────────────────────────────────────────
    readonly property int cardGap: isOutlined ? 12 : isCards ? 14 : 16   // between groups
    readonly property int cardPad: isOutlined ? 12 : 14                  // inside a group
    readonly property int rowGap:  isFlat ? 10 : 8                       // between rows in a group

    // ── Card / group surface ──────────────────────────────────────────────────────
    readonly property color cardFill: isCards    ? Colors.bgElement
                                     : isOutlined ? "transparent"
                                                  : root.tint(root.accent, 0.06)
    readonly property int   cardBorderW:     isFlat ? 0 : 1
    readonly property color cardBorderColor: isOutlined ? Colors.boNormal
                                                        : root.tint(Colors.boNormal, 0.40)

    // ── Control surface (toggle rows, dropdown header, plain rows, tiles) ──────────
    readonly property color controlFill:  isCards    ? Colors.bgPrimary
                                         : isOutlined ? "transparent"
                                                      : root.tint(root.accent, 0.12)
    readonly property color controlHover: isOutlined ? root.tint(root.accent, 0.12)
                                         : isCards    ? root.tint(root.accent, 0.18)
                                                      : root.tint(root.accent, 0.22)
    readonly property int   controlBorderW:     isFlat ? 0 : 1
    readonly property color controlBorderColor: isOutlined ? Colors.boNormal
                                                           : root.tint(Colors.boNormal, 0.40)

    // ── Selected / active ─────────────────────────────────────────────────────────
    readonly property color selFill:        isOutlined ? "transparent" : root.accent
    readonly property color selText:        isOutlined ? root.accent    : Colors.fgBright
    readonly property int   selBorderW:     isFlat ? 0 : 1
    readonly property color selBorderColor: isOutlined ? root.accent : Colors.boActive

    // ── Toggle switch ─────────────────────────────────────────────────────────────
    readonly property color trackOn:  root.accent
    readonly property color trackOff: Colors.bgPrimary
    readonly property color knob:     Colors.fgBright
}
