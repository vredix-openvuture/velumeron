import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
// Velumeron.Mpv is isolated in wallpaper/VideoSurface.qml (loaded via Loader) so a missing plugin
// can never stop the shell from loading.

// Native wallpaper surface — one per monitor, on the background layer (below the bar at Bottom). Reads
// this monitor's wallpaper from a watched wallpapers.json and transitions between two stacked slots on
// change. Transitions are TRANSFORM/OPACITY based (fade/slide/push/zoom) — no GPU masking, which proved
// unreliable in this Quickshell build. Each slot shows a static Image or a live MpvVideo by type.
PanelWindow {
    id: root

    property var monitor: Compositor.monitorFor(root.screen)
    readonly property string mon: monitor?.name ?? ""

    WlrLayershell.layer:     WlrLayer.Background
    WlrLayershell.namespace: "velumeron-wallpaper"
    // -1 = ignore every exclusive zone so the wallpaper spans the FULL monitor, including under the
    // bar and its rounded inner corners. With 0 it respected the bar's reservations and got inset by
    // the bar thickness, leaving the strip under the bar black. The bar sits above us at Bottom layer.
    exclusiveZone: -1
    anchors { top: true; left: true; right: true; bottom: true }
    color: "black"

    // ── State: wallpapers.json = { "<mon>": { "path": "...", "type": "image|video" } } ──────────
    property var all: ({})
    function _parse(t) { try { if (t && ("" + t).trim() !== "") root.all = JSON.parse(t) } catch (e) { /* keep last good */ } }
    readonly property FileView _fv: FileView {
        path: (Quickshell.env("VELUMERON_USER_DIR") || (Quickshell.env("HOME") + "/.config/velumeron")) + "/quickshell/wallpapers.json"
        watchChanges: true
        onLoaded:      root._parse(text())
        onFileChanged: reload()
    }

    // ── Dual-slot transition ───────────────────────────────────────────────────────────────────
    property int shown: 0
    function _swap(path, type) {
        root._planTransition()
        var idle = (root.shown === 0) ? slotB : slotA
        idle.set(path, type)
        root.shown = (root.shown === 0) ? 1 : 0
    }
    property string _lastPath: ""
    function _apply() {
        var e = root.all[root.mon]
        if (!e || !e.path || e.path === root._lastPath) return
        root._lastPath = e.path
        root._swap(e.path, e.type || "image")
    }
    onAllChanged:  _apply()
    onMonChanged:  _apply()
    Component.onCompleted: _apply()

    // ── Transition plan (Settings → Wallpaper → gear). `random` rolls type + params per change. ─────
    readonly property string transition:   VtlConfig.wallpaperTransition
    readonly property int    transitionMs: Math.max(150, VtlConfig.wallpaperTransitionMs)
    property var effPlan: ({ type: "fade", slideDir: "left" })
    function _rand(a) { return a[Math.floor(Math.random() * a.length)] }
    function _planTransition() {
        var t = root.transition
        var rnd = (t === "random")
        if (rnd) t = root._rand(["fade", "slide", "push", "zoom"])
        root.effPlan = {
            type:     t,
            slideDir: rnd ? root._rand(["left", "right", "up", "down"]) : VtlConfig.wallpaperSlideDir
        }
    }
    onTransitionChanged: if (root.transition !== "random") root._planTransition()

    // ── Live-wallpaper plugin failed to load ───────────────────────────────────────────────────
    // Velumeron.Mpv is a COMPILED QML module and is not in git — launch-quickshell.sh builds it on
    // demand. Start the shell any other way (a bare `quickshell -p`, an editor, a session that
    // doesn't go through the launcher) and a missing or half-built plugin is never noticed:
    // VideoSurface can't import it, the Loader errors, and the slot simply stays black. Silently,
    // and identically after every reboot, because each boot repeats the same launch.
    //
    // So the shell says so itself and builds it in the background. That cannot rescue the running
    // process — a failed QML import is cached for the lifetime of the engine — but the next start
    // has it, which is the difference between "broken forever" and "restart the shell".
    // flock: one build even though every monitor has its own surface and its own two slots.
    property bool _mpvRepairTried: false
    function _videoPluginFailed(path) {
        if (root._mpvRepairTried) return
        root._mpvRepairTried = true
        console.warn("wallpaper: cannot play " + path + " — the Velumeron.Mpv plugin failed to load"
                     + " (built by assets/scripts/build-mpv-plugin.sh). Building it now.")
        mpvRepair.running = true
    }
    Process {
        id: mpvRepair
        command: ["bash", "-c",
            "flock -n -E 99 /tmp/velumeron-mpv-build.lock bash \"$1\"/assets/scripts/build-mpv-plugin.sh",
            "vtl", Quickshell.env("VELUMERON_DIR")]
        onExited: (code) => {
            if (code === 99) return         // -E 99: another monitor's surface holds the lock
            console.warn(code === 0
                ? "wallpaper: Velumeron.Mpv built — restart the shell to get live wallpapers back"
                : "wallpaper: Velumeron.Mpv build FAILED (run build-mpv-plugin.sh to see why)")
            notify.command = ["notify-send", "-a", "Velumeron", "-i", "video-x-generic",
                              code === 0 ? "Live wallpaper repaired" : "Live wallpaper unavailable",
                              code === 0 ? "The video plugin was missing and has been rebuilt. Restart the shell to use it."
                                         : "The video plugin is missing and could not be built — run assets/scripts/build-mpv-plugin.sh."]
            notify.running = true
        }
    }
    Process { id: notify }

    WallSlot { id: slotA; anchors.fill: parent; active: root.shown === 0 }
    WallSlot { id: slotB; anchors.fill: parent; active: root.shown === 1 }

    component WallSlot: Item {
        id: slot
        property var  item: ({ path: "", type: "image" })
        property bool active: false
        property bool everVideo: false
        function set(p, t) { slot.item = { path: p, type: t } }
        onItemChanged: if (slot.item.type === "video") slot.everVideo = true

        readonly property var    plan: root.effPlan
        readonly property string tt:   plan.type

        // reveal 0 (hidden) → 1 (shown); drives every transition.
        property real reveal: active ? 1 : 0
        Behavior on reveal { NumberAnimation { id: revAnim; duration: root.transitionMs; easing.type: Easing.InOutQuad } }
        readonly property bool animating: revAnim.running

        z: active ? 1 : 0   // incoming on top of the outgoing

        // Direction offset for slide/push (the side the NEW wallpaper enters from).
        readonly property real _dx: plan.slideDir === "left" ? -width  : plan.slideDir === "right" ? width  : 0
        readonly property real _dy: plan.slideDir === "up"   ? -height : plan.slideDir === "down"  ? height : 0
        readonly property real _tx: tt === "slide" ? (active ? (1 - reveal) * _dx : 0)
                                  : tt === "push"  ? (active ? (1 - reveal) * _dx : -reveal * _dx) : 0
        readonly property real _ty: tt === "slide" ? (active ? (1 - reveal) * _dy : 0)
                                  : tt === "push"  ? (active ? (1 - reveal) * _dy : -reveal * _dy) : 0
        readonly property real _sc: (tt === "zoom" && active) ? (0.72 + 0.28 * reveal) : 1.0

        opacity: tt === "fade" ? reveal
               : tt === "zoom" ? (active ? reveal : (animating ? 1.0 : 0.0))
               : (active ? 1.0 : (animating ? 1.0 : 0.0))   // slide / push

        transform: [
            Translate { x: slot._tx; y: slot._ty },
            Scale { origin.x: slot.width / 2; origin.y: slot.height / 2; xScale: slot._sc; yScale: slot._sc }
        ]

        // Static image — source gated on type so it never tries to decode a video file.
        Image {
            anchors.fill: parent
            visible:  slot.item.type === "image"
            source:   (slot.item.type === "image" && slot.item.path !== "") ? "file://" + slot.item.path : ""
            fillMode: Image.PreserveAspectCrop
            cache:    false
            asynchronous: true
            smooth:   true
            // Cap the DECODE near the monitor size (long edge × 1.25 for crop headroom): a 4K+
            // file otherwise sits fully decoded in RAM — w×h×4 bytes per slot, per monitor.
            // Only one dimension is set so the aspect ratio survives (0 = auto).
            sourceSize.width:  root.height > root.width ? 0 : Math.round(root.width * 1.25)
            sourceSize.height: root.height > root.width ? Math.round(root.height * 1.25) : 0
        }
        // Live video — isolated MpvVideo, kept alive once created; shown only for video entries.
        Loader {
            id: vid
            anchors.fill: parent
            active:  slot.everVideo
            visible: slot.item.type === "video"
            source:  Qt.resolvedUrl("wallpaper/VideoSurface.qml")
            // The isolation is on purpose (a broken plugin must not take the shell down), but it
            // also swallowed the failure whole — this is where the black surface gets a reason.
            onStatusChanged: if (vid.status === Loader.Error) root._videoPluginFailed(slot.item.path)
        }
        Binding { target: vid.item; property: "source"; when: vid.status === Loader.Ready
                  value: slot.item.type === "video" ? slot.item.path : "" }
        Binding { target: vid.item; property: "paused"; when: vid.status === Loader.Ready
                  value: !(slot.item.type === "video" && slot.active) }
    }
}
