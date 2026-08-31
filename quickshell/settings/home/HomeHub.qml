import "../.."
import QtQuick
import Quickshell

// Settings home — the dashboard. It used to be a hardcoded column (greeting, sliders, profile,
// toggles, buttons, now-playing) where every card knew the others by name: the media card sized
// itself by subtracting each sibling's height, so adding or moving anything meant editing that
// sum. Now it's a cell grid: DashGrid places the modules from VtlConfig.dashboardModules,
// dashboard/* holds one file per module type, and DashState owns the polling (gated on what's
// actually placed). What stays fixed is the session bar pinned to the bottom — it's the hub's
// floor, not a module.
//
// The dashboard PAGES, it does not scroll: a wheel tick flips to the next screenful and wraps
// around at the end, the same gesture the settings icon rail already uses. A half-cut module at the
// fold is worse than a clean break, so DashGrid never lets one straddle a page.
//
// Arranging happens in the standalone editor window (dashboard/DashEditor.qml), not here: a
// ~500 px panel has no room for a module list beside the grid. The pencil hands over to it and the
// settings menu hides for the duration. So this file only ever READS the layout.
//
// `navigate(section)` asks Settings.qml to open the Network / Bluetooth sub-pages.
Item {
    id: root
    signal navigate(string section)
    // Page-navigation mode (Settings → Style): collapse the session bar and add the nav gear.
    property bool pageMode: false
    signal openNav()

    // The grid's poll gate — nothing in DashState samples while the hub is off screen.
    onVisibleChanged: DashState.active = root.visible
    Component.onCompleted: DashState.active = root.visible

    // What a theme's dashboard is handed. Rebuilt on the clock tick; the load figures move on their
    // own five-second sampler in ShellFacts, so nothing here polls.
    readonly property var dashContext: {
        var c = Style.themeContext()
        c.w = root.width
        c.h = root.height
        c.now = ShellFacts.now
        c.user = ShellFacts.user
        c.host = ShellFacts.host
        c.kernel = ShellFacts.kernel
        c.uptime = ShellFacts.uptime
        c.load = { "cpu": ShellFacts.cpuPercent, "mem": ShellFacts.memPercent,
                   "disk": ShellFacts.diskPercent }
        c.battery = { "present": ShellFacts.batPresent, "percent": ShellFacts.batPercent,
                      "charging": ShellFacts.batCharging }
        c.media = { "title": ShellFacts.mediaTitle, "artist": ShellFacts.mediaArtist,
                    "playing": ShellFacts.mediaPlaying }
        c.workspaces = ShellFacts.workspacesFor(UiState.menuMon)
        c.notifications = { "count": NotifService.model ? NotifService.model.values.length : 0,
                            "dnd": NotifService.dnd }
        // A dashboard you can only read is a poster. The shell's own is a grid of controls, so a
        // theme's gets the same two halves: what the machine is doing, and the handles to change
        // it. Everything here is already what the shipped tiles drive (DashState), so a theme and
        // a tile can never disagree about the volume.
        c.state = { "volume":     DashState.volume,
                    "muted":      DashState.muted,
                    "brightness": DashState.brightness / 100,
                    "profile":    DashState.profile,
                    "night":      DashState.night,
                    "caffeine":   DashState.caffeine,
                    "dnd":        NotifService.dnd }
        c.actions = {
            "volume":     function (v) { DashState.setVolume(v) },
            "mute":       function ()  { DashState.toggleMute() },
            "brightness": function (v) { DashState.setBrightness(v) },
            "profile":    function (p) { DashState.setProfile("" + p) },
            "night":      function ()  { DashState.toggleNight() },
            "caffeine":   function ()  { DashState.toggleCaffeine() },
            "dnd":        function ()  { NotifService.dnd = !NotifService.dnd },
            "workspace":  function (slot) { Actions.fire({ "type": "dispatch",
                                                           "value": "hl.dsp.focus({ workspace = "
                                                                    + slot + " })" }, UiState.menuMon) },
            // launcher | wallpaper | notifications | cheatsheet | lock | command | app …
            "fire":       function (type, value) {
                Actions.fire({ "type": "" + type, "value": value === undefined ? "" : "" + value },
                             UiState.menuMon)
            },
            "section":    function (name) { root.navigate("" + name) }
        }
        return c
    }

    readonly property var modules: DashModules.resolve(VtlConfig.dashboardModules,
                                                       VtlConfig.dashboardCols, viewport.rowsPerPage)

    // Which screenful is showing. Kept in range when modules leave and the page count drops.
    property int page: 0
    Connections {
        target: grid
        function onPagesChanged() { if (root.page > grid.pages - 1) root.page = Math.max(0, grid.pages - 1) }
    }

    // Page dots. The row ALWAYS reserves its height — if it collapsed on a single-page layout the
    // viewport would grow by 20 px, fit another row, and the editor's page size would disagree with
    // the menu's. Only the dots themselves come and go.
    Row {
        id: dots
        opacity: grid.pages > 1 ? 1 : 0
        height: 14
        anchors { horizontalCenter: parent.horizontalCenter
                  bottom: powerBar.visible ? powerBar.top : pageNav.top; bottomMargin: 2 }
        spacing: 6
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Repeater {
            model: grid.pages
            delegate: Rectangle {
                required property int index
                width: 6; height: 6; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: index === root.page ? Style.accent : Style.tint(Colors.boNormal, 0.6)
                Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
                MouseArea { anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor; onClicked: root.page = index }
            }
        }
    }

    Item {
        id: viewport
        clip: true
        anchors { top: parent.top; left: parent.left; right: parent.right
                  bottom: dots.top; bottomMargin: 2 }

        // The page size is now DECLARED, not measured: the menu is built to fit exactly
        // this many rows (Style.dashGridH), so there is no remainder to leave under the
        // last one. Measuring it was what produced the dead space above the buttons —
        // and centring the grid to hide that space made it judder on open.
        readonly property int rowsPerPage: Math.max(1, VtlConfig.dashboardRows)

        // Publish the viewport LIVE, so the editor can never work from a stale page size — a
        // latched number went out of date the moment the row height changed in the editor itself.
        // The guard is what keeps the old bug away: opening the editor sets dashEditOpen BEFORE the
        // menu starts collapsing, so none of the shrinking intermediate sizes get through.
        onHeightChanged: if (root.visible && !UiState.dashEditOpen && height > 0)
                             UiState.dashHeight = height
        onWidthChanged:  if (root.visible && !UiState.dashEditOpen && width > 0)
                             UiState.dashWidth = width

        // NOT vertically centred, and that is deliberate. Only whole rows fit, so the
        // viewport keeps a remainder — but centring the grid means its y depends on
        // viewport.height, and that value sweeps from nothing to full while the menu
        // morphs open. Every frame of the reveal then moved the widgets, which reads as
        // the dashboard shaking its way onto the screen. Tried twice (once with the page
        // Behavior animating each intermediate value, once without); both juddered. The
        // remainder is the cheaper price.
        // A theme that brings its own dashboard draws the whole thing. Console's is a status report
        // you read rather than a raster of tiles, so there is no grid to restyle — see Theme.qml.
        ThemeSurface {
            anchors.fill: parent
            visible: Theme.hasComponent("dashboard")
            surface: Theme.hasComponent("dashboard") ? "dashboard" : ""
            ctx: root.dashContext
            z: 3
        }

        DashGrid {
            id: grid
            visible: !Theme.hasComponent("dashboard")
            // ITS OWN width (cols x cell width + gaps), NOT the viewport's. Filling the viewport
            // meant the menu size decided how wide a dashboard cell is, so making the menu bigger
            // under Style → Menu grew the dashboard with it. The two carry their own size settings
            // and neither may move the other; a menu wider than the raster simply has room to
            // spare. Left-aligned on purpose: centring it would depend on the viewport width, which
            // sweeps from nothing to full while the menu opens, and the whole grid would slide
            // into place on every reveal.
            width: Style.dashGridW
            height: implicitHeight
            items: root.modules
            rowsPerPage: viewport.rowsPerPage
            y: 2 - grid.pageTop(root.page)
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            onNavigate: section => root.navigate(section)
        }

        // Wheel = page turn, wrapping both ways. A full notch is accumulated like the settings
        // rail's wheel, AND a cooldown swallows everything until the flip has finished: without it
        // the tail of one flick kept firing and the dashboard raced through every page.
        MouseArea {
            id: wheelArea
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            property int  acc: 0
            property bool cooling: false
            Timer { id: coolDown; interval: 320; onTriggered: wheelArea.cooling = false }
            onWheel: wheel => {
                if (grid.pages <= 1) return
                if (wheelArea.cooling) { wheelArea.acc = 0; return }
                if ((wheelArea.acc > 0) !== (wheel.angleDelta.y > 0)) wheelArea.acc = 0
                wheelArea.acc += wheel.angleDelta.y
                if (Math.abs(wheelArea.acc) < 120) return
                root.page = (root.page + (wheelArea.acc < 0 ? 1 : -1) + grid.pages) % grid.pages
                wheelArea.acc = 0
                wheelArea.cooling = true
                coolDown.restart()
            }
        }
    }

    // ── Arrange handoff ────────────────────────────────────────────────────────
    // Deliberately quiet: barely there until the pointer comes near. All it does is open the editor.
    StyledRect {
        id: editBtn
        // Only over the shipped raster. The editor arranges `dashboard_modules`, and a theme that
        // brings its own dashboard does not draw those — Console's is a status report with no grid
        // to arrange — so the pencil would open a page of tiles that appear nowhere. What such a
        // theme offers instead lives on its own settings card (Settings -> Style).
        visible: !Theme.hasComponent("dashboard")
        width: 24; height: 24; radius: Style.rTile
        anchors { top: parent.top; right: parent.right; topMargin: 2 }
        z: 5
        opacity: editHov.containsMouse ? 1 : 0.28
        color: editHov.containsMouse ? Style.tint(Style.accent, 0.25) : "transparent"
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on color   { ColorAnimation  { duration: 140 } }
        Text { anchors.centerIn: parent; text: "󰏫"
               color: editHov.containsMouse ? Colors.fgBright : Colors.fgMuted
               font.pixelSize: 12; font.family: Style.font }
        MouseArea {
            id: editHov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Measure HERE, not from a size-changed handler: opening the editor collapses the menu,
            // and the hub stays visible through that animation — a continuous publisher ends up
            // latching a mid-collapse size, which is what made the editor's preview frame a stub.
            // At the moment of this click the menu is definitively open and settled.
            onClicked: {
                UiState.dashWidth  = viewport.width
                UiState.dashHeight = viewport.height
                UiState.openDashEdit(UiState.menuMon)
            }
        }
    }

    // ── Session actions — always pinned to the bottom of the hub ────────────────
    Column {
        id: powerBar
        visible: !root.pageMode
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 12
        Rectangle { width: parent.width; height: 1
                    color: Style.tint(Colors.boNormal, 0.25) }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
                model: UiState.sessionActions   // canonical shared list (same icons as the session menu)
                delegate: PowerTile {
                    required property var modelData
                    icon: modelData.icon; cmd: modelData.cmd
                }
            }
        }
    }

    // ── Page-navigation cluster (bottom-left, page mode only): a gear that opens the settings
    //    nav list, and the session actions collapsed into one tile that glides its options out on hover.
    Item {
        id: pageNav
        visible: root.pageMode
        height: 48
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 0 }

        StyledRect {
            id: gearBtn
            width: 48; height: 48; radius: Style.rTile
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            color: gearHov.containsMouse ? Style.accent : Style.controlFill
            borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
            Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
            Text { anchors.centerIn: parent; text: "󰒓"
                   color: gearHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                   font.pixelSize: 18; font.family: Style.font }
            MouseArea { id: gearHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: root.openNav() }
        }

        Item {
            id: sessionGlide
            height: 48; clip: true
            anchors { left: gearBtn.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            property bool expanded: sgHover.hovered
            // Collapsed = just the first session tile; hover reveals the rest sliding out.
            width: expanded ? sgRow.width : 48
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Row {
                id: sgRow
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 12
                Repeater {
                    model: UiState.sessionActions
                    delegate: PowerTile { required property var modelData; icon: modelData.icon; cmd: modelData.cmd }
                }
            }
            // Passive hover detection — a HoverHandler doesn't grab events, so the tiles below
            // still receive their own hover (and colour change) while this keeps the row expanded.
            HoverHandler { id: sgHover }
        }
    }

    component PowerTile: StyledRect {
        id: pt
        property string icon: ""
        property string cmd:  ""
        width: 48; height: 48; radius: Style.rTile
        color: ptHov.containsMouse ? Style.accent : Style.controlFill
        borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
        Behavior on color { ColorAnimation { duration: Style.ctrlMs } }
        Text { anchors.centerIn: parent; text: pt.icon; color: ptHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
               font.pixelSize: 18; font.family: Style.font }
        MouseArea { id: ptHov; anchors.fill: parent; hoverEnabled: true
                    onClicked: { Actions.run(pt.cmd); UiState.openDropdown = "" } }
    }
}
