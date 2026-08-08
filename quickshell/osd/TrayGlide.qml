import ".."
import QtQuick

// The system-tray icons gliding out of the bar on hover of the collapsed tray glyph — the same pill
// every other hover menu uses, instead of the icons pushing the bar apart from the inside.
// Interactive (the icons are clickable) + keepOpenOnHover so the cursor can travel from the glyph
// into the pill to reach them. One per screen.
BarGlide {
    id: g
    mine:            UiState.trayMon === g.mon && g.mon !== ""
    shown:           UiState.trayHover || g._menuOpen
    edge:            UiState.trayEdge
    anchorX:         UiState.trayAnchorX
    anchorY:         UiState.trayAnchorY
    interactive:     true
    keepOpenOnHover: true

    // A tray context menu is a full-screen overlay: the moment it opens it covers the pill and takes
    // the pointer, so keepOpenOnHover alone would pull the pill out from under the menu that was just
    // opened from it. Latch it open until that menu goes away again. Only menus opened from THIS
    // pill count — the inline strip in the bar opens its menus without ever showing a pill.
    property bool _menuFromHere: false
    readonly property bool _menuOpen: g._menuFromHere && UiState.trayMenuOpen
                                      && UiState.trayMenuMon === g.mon
    Connections {
        target: UiState
        function onTrayMenuOpenChanged() { if (!UiState.trayMenuOpen) g._menuFromHere = false }
    }

    TrayIcons {
        spacing:  10
        iconSize: Math.max(16, VtlConfig.moduleIconSizeFor("tray", g.mon))
        barEdge:  UiState.trayEdge
        barMon:   g.mon
        onMenuOpened: g._menuFromHere = true
    }
}
