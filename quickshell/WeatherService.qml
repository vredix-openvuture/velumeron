pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The weather, as one piece of state the whole shell reads.
//
// It used to be the lockscreen's private business: shell.qml ran weather-fetch.sh whenever the lock
// widget was on, and lock/LockContent.qml was the only reader of weather.json. The bar module needs
// the same reading, and a second fetcher writing the same file would race the first — so ownership
// moves here. Both surfaces read this; the fetch runs when EITHER of them wants it.
//
// One city for the whole shell. The two surfaces share one weather.json, so two cities would mean
// two fetchers overwriting each other's answer; the module's own city (Settings -> Bar -> Weather)
// wins when it is set, and the lockscreen's field is the fallback it has always been.
Singleton {
    id: root

    readonly property string _dir: (Quickshell.env("VELUMERON_USER_DIR")
                                    || (Quickshell.env("HOME") + "/.config/velumeron"))

    // ── The reading ─────────────────────────────────────────────────────────────────────────────
    property var data: null
    readonly property bool   ok:    root.data !== null && root.data.ok === true
    readonly property string temp:  root.ok ? ("" + (root.data.temp ?? "")) : ""
    readonly property string unit:  root.ok ? ("" + (root.data.unit ?? "")) : ""
    readonly property string desc:  root.ok ? ("" + (root.data.desc ?? "")) : ""
    // The sky as a key, not as a glyph — common/WeatherIcon.qml paints it, and the compact readouts
    // that sit inline with text use glyphFor() below.
    readonly property string cond:  root.ok ? ("" + (root.data.cond ?? "cloudy")) : "cloudy"
    // UTC, because the sun times belong to the place, not to this desk — see weather-fetch.sh.
    readonly property string sunriseUtc: root.ok ? ("" + (root.data.sunrise_utc ?? "")) : ""
    readonly property string sunsetUtc:  root.ok ? ("" + (root.data.sunset_utc  ?? "")) : ""
    // The place to PRINT. With coordinates the user picked a town and that town is the answer;
    // wttr.in reports whichever station is nearest to the fix, and being told "Oberberging" after
    // asking for Teisnach reads as a bug. Only a typed name defers to what the service resolved.
    readonly property string place: {
        if (!root.ok) return ""
        var picked   = "" + (root.data.city  ?? "")
        var resolved = "" + (root.data.place ?? "")
        return (root.data.exact === true && picked !== "") ? picked : (resolved || picked)
    }
    readonly property var    days:  (root.ok && root.data.days instanceof Array) ? root.data.days : []
    // "18°C" — the one string both the bar and the lock print.
    readonly property string reading: root.ok ? (root.temp + root.unit) : ""

    // Daylight, decided when it is READ rather than when it was fetched: the reading is half an
    // hour old at worst, but the panel may well be opened after dark. Falls back to daytime when
    // the fetch brought no sun times, because a sun is the less surprising of the two mistakes.
    //
    // Everything here is UTC. In that frame a day in Tokyo runs 20:17 → 09:08, so the interval
    // wraps midnight for most of the world and the comparison has to allow for it — read the other
    // way round, Tokyo would be in permanent darkness.
    property string _nowUtc: "12:00"
    readonly property Timer _clock: Timer {
        interval: 60000; repeat: true; triggeredOnStart: true
        running: root.wanted                       // nobody asking for weather, nobody asking for the hour
        onTriggered: {
            var t = new Date()
            root._nowUtc = ("0" + t.getUTCHours()).slice(-2) + ":" + ("0" + t.getUTCMinutes()).slice(-2)
        }
    }
    readonly property bool daytime: {
        var rise = root.sunriseUtc, set = root.sunsetUtc
        if (rise === "" || set === "") return true
        return (rise <= set) ? (root._nowUtc >= rise && root._nowUtc < set)
                             : (root._nowUtc >= rise || root._nowUtc < set)
    }

    // Nerd Font stand-ins for the places where the icon sits inline with text and a drawn sky would
    // only be noise: the bar module and the lockscreen's compact widget row. Codepoints verified
    // against the bundled FantasqueSansM Nerd Font, Material Design Icons block.
    function glyphFor(cond, night) {
        switch (cond) {
        case "clear":   return night ? "\u{F0594}" : "\u{F0599}"   // moon / sun
        case "partly":  return night ? "\u{F0594}" : "\u{F0595}"   // moon / sun behind cloud
        case "fog":     return "\u{F0591}"
        case "rain":    return "\u{F0597}"
        case "snow":    return "\u{F0598}"
        case "thunder": return "\u{F0593}"
        default:        return "\u{F0590}"                          // overcast
        }
    }
    readonly property string glyph: root.glyphFor(root.cond, !root.daytime)

    readonly property FileView _file: FileView {
        path: root._dir + "/quickshell/weather.json"
        watchChanges: true
        onLoaded:      { try { root.data = JSON.parse(text()) } catch (e) { root.data = null } }
        onFileChanged: reload()
    }

    // ── Who wants it, and for what ──────────────────────────────────────────────────────────────
    readonly property bool wantedByLock: Theme.lockWidgetEnabled("weather")
    // Not just "is the weather module placed": any module can be pointed at the weather popout, and
    // a panel that opens onto a reading nobody fetched is worse than no button at all.
    readonly property bool wantedByBar:  Popouts.inUse("weather")
    // …and a weather widget on a desk that is actually showing. Published by the desks themselves
    // rather than read out of the settings, because a desk can be switched off or scoped to another
    // workspace — see UiState.deskKeys.
    readonly property bool wantedByDesk: UiState.deskWants("weather")
    readonly property string city: VtlConfig.weatherCity
    // Coordinates of the place the user picked in the city field, empty when the name was typed.
    // The fetch prefers them: "Neustadt, Germany" is several towns, one fix is one town.
    readonly property string coords: VtlConfig.weatherCoords
    readonly property string unitKey: VtlConfig.weatherUnit
    // How far ahead to fetch. wttr.in ships three days; the lock widget and the bar popout each ask
    // for their own number of them, and the fetch takes the larger — a file with more days in it
    // costs nothing to the surface that only reads the first.
    readonly property int forecastDays: {
        var l = (root.wantedByLock && Theme.lock.weatherForecast)
              ? Math.max(1, Math.min(3, Theme.lock.weatherForecastDays)) : 0
        var b = root.wantedByBar ? Math.max(0, Math.min(3, VtlConfig.moduleSetting("weather", "forecast_days", 3))) : 0
        // A desk widget asks for the full three: which of them it draws is its own option, and the
        // file costing the same either way is the whole reason this is a max and not a per-reader
        // fetch.
        var d = root.wantedByDesk ? 3 : 0
        return Math.max(l, Math.max(b, d))
    }
    readonly property bool wanted: (root.wantedByLock || root.wantedByBar || root.wantedByDesk)
                                   && root.city !== ""

    // A fetch that dies is otherwise completely silent: the surface keeps showing the last reading
    // (or a dash) and nothing anywhere names the input or the failure.
    readonly property Process _proc: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                var msg = ("" + text).trim()
                if (msg !== "") console.warn("weather: fetch stderr for", root.city, "—", msg)
            }
        }
        onExited: (code) => { if (code !== 0) console.warn("weather: fetch for", root.city, "exited", code) }
    }
    // One write to the config can move several of these at once — picking a city sets the name and
    // its coordinates together — and each handler below would otherwise kill the fetch the previous
    // one just started. Killing bash does not kill the curl underneath it, so those runs finish
    // anyway and race each other for weather.json. Collapse them into one run per tick instead.
    function refresh() {
        if (!root.wanted) return
        Qt.callLater(root._fetch)
    }
    function _fetch() {
        if (!root.wanted) return
        var query = root.coords !== "" ? root.coords : root.city
        root._proc.command = ["bash", (Quickshell.env("VELUMERON_DIR") ?? "") + "/assets/scripts/weather-fetch.sh",
                              query, root.unitKey, "" + root.forecastDays, root.city]
        root._proc.running = false
        root._proc.running = true
    }

    // Every 30 min, once at startup, and immediately whenever the place, the unit or the number of
    // days changes — the answer on screen is stale the moment any of them does.
    readonly property Timer _poll: Timer {
        interval: 30 * 60000
        repeat: true
        triggeredOnStart: true
        running: root.wanted
        onTriggered: root.refresh()
    }
    onCityChanged:         root.refresh()
    onCoordsChanged:       root.refresh()
    onUnitKeyChanged:      root.refresh()
    onForecastDaysChanged: root.refresh()
}
