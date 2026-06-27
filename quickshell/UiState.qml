pragma Singleton
import QtQuick

QtObject {
    id: ui

    property bool   guiPanelOpen:   false
    property bool   barSettingsOpen: false  // kept for compat; gui panel supersedes it
    property string openDropdown:   ""      // key of the currently open module dropdown

    // True while a native dialog (e.g. the zenity folder picker) is open: the
    // corner menu drops its full-screen input grab + keyboard focus so the dialog
    // underneath is interactive, but stays visually open.
    property bool   pickerOpen:     false

    // Where the corner menu should attach: the edge the vuture-icon sits on, and the
    // icon's position along that edge (window/screen coords). Set by VutureIcon on open.
    property string menuEdge:       "top"   // top | left | bottom | right
    property string menuGroup:      "start" // start | center | end (shapes the L / fluid form)
    property real   menuStart:      0       // along-edge coordinate of the icon centre

    // ── Corner-menu morph progress ────────────────────────────────────────────
    // 0 = fully closed, 1 = fully open. Animated centrally so the menu panel (CornerMenu)
    // and the L-bar inner border opening (LBar) grow out of the corner in lockstep.
    readonly property bool cornerMenuOpen: openDropdown === "vuture-icon"
    property real menuReveal: cornerMenuOpen ? 1.0 : 0.0
    Behavior on menuReveal {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
}
