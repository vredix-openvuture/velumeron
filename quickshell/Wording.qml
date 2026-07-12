pragma Singleton
import QtQuick

// Per-style wording ("persona"): the ui_style doesn't just reshape the shell, it re-voices it.
// Grimoire speaks like an illuminated manuscript, futuristic like a mission briefing, nostalgic
// like a DOS prompt. `s(key)` resolves a string for the active variant, falling back to the
// neutral `_base` table (the shell's stock English strings), then to the key itself — so persona
// tables may stay sparse and unknown variants (flat/cards/outlined) read neutral. Bindings that
// call s()/greeting() re-evaluate live on style switches because the lookup reads VtlConfig.uiStyle.
QtObject {
    id: root

    // Neutral strings — exactly what the shell said before personas existed.
    readonly property var _base: ({
        "greet.night":       "Good night",
        "greet.morning":     "Good morning",
        "greet.afternoon":   "Good afternoon",
        "greet.evening":     "Good evening",
        "notif.title":       "Notifications",
        "notif.empty":       "No notifications",
        "launcher.search":   "Search apps…",
        "launcher.noMatches":"No matches",
        "clipboard.search":  "Search clipboard…",
        "mpris.nothing":     "Nothing playing",
        "bt.noPaired":       "No paired devices",
        "bt.noneFound":      "No devices found — tap scan",
        "bt.scanning":       "Scanning…",
        "net.noneFound":     "No networks found",
        "windows.none":      "No open windows",
        "hint.info":         "System information.",
        "group.empty":       "Empty group — add modules in Settings → Bar"
    })

    readonly property var _tables: ({
        futuristic: {
            "greet.night":       "Night ops",
            "greet.morning":     "Briefing ready",
            "greet.afternoon":   "Mission in progress",
            "greet.evening":     "Evening watch",
            "notif.title":       "Transmissions",
            "notif.empty":       "No incoming transmissions",
            "launcher.search":   "Query database…",
            "launcher.noMatches":"No records found",
            "clipboard.search":  "Search buffer…",
            "mpris.nothing":     "No signal on audio channel",
            "bt.noPaired":       "No linked devices",
            "bt.noneFound":      "No contacts on scan — retry",
            "bt.scanning":       "Scanning sector…",
            "net.noneFound":     "No uplinks detected",
            "windows.none":      "No active viewports",
            "hint.info":         "Systems diagnostic.",
            "group.empty":       "Cluster unassigned — assign modules in Settings → Bar"
        },
        grimoire: {
            "greet.night":       "The hour is late",
            "greet.morning":     "Well met this morn",
            "greet.afternoon":   "Well met",
            "greet.evening":     "Good eventide",
            "notif.title":       "Tidings",
            "notif.empty":       "The raven brings no tidings",
            "launcher.search":   "Seek a tome…",
            "launcher.noMatches":"Naught was found",
            "clipboard.search":  "Search the scrolls…",
            "mpris.nothing":     "The minstrels are silent",
            "bt.noPaired":       "No bonded artifacts",
            "bt.noneFound":      "Naught answers the call — scry anew",
            "bt.scanning":       "Scrying…",
            "net.noneFound":     "No roads to distant realms",
            "windows.none":      "No windows stand open",
            "hint.info":         "The chronicle of this machine.",
            "group.empty":       "This satchel is empty — fill it in Settings → Bar"
        },
        nostalgic: {
            "greet.night":       "NIGHT SHIFT",
            "greet.morning":     "SYSTEM BOOTED",
            "greet.afternoon":   "SYSTEM READY",
            "greet.evening":     "END OF DAY",
            "notif.title":       "MESSAGES",
            "notif.empty":       "0 NEW MESSAGES",
            "launcher.search":   "RUN>",
            "launcher.noMatches":"BAD COMMAND OR FILE NAME",
            "clipboard.search":  "SEARCH BUFFER>",
            "mpris.nothing":     "NO MEDIA LOADED",
            "bt.noPaired":       "NO PAIRED UNITS",
            "bt.noneFound":      "NO UNITS FOUND — RESCAN",
            "bt.scanning":       "SCANNING…",
            "net.noneFound":     "NO CARRIER",
            "windows.none":      "NO TASKS RUNNING",
            "hint.info":         "SYSTEM INFORMATION.",
            "group.empty":       "EMPTY GROUP — ADD MODULES IN SETTINGS"
        },
        sketch: {
            "greet.night":       "Up late, huh",
            "greet.morning":     "Mornin'",
            "greet.afternoon":   "Heya",
            "greet.evening":     "Evenin'",
            "notif.title":       "Notes",
            "notif.empty":       "Nothing scribbled here",
            "launcher.search":   "Doodle a search…",
            "launcher.noMatches":"Hmm, nothing",
            "clipboard.search":  "Rummage the clippings…",
            "mpris.nothing":     "No tunes right now",
            "bt.noPaired":       "Nothing pencilled in yet",
            "bt.noneFound":      "Nobody around — scan again",
            "bt.scanning":       "Looking around…",
            "net.noneFound":     "No signals sketched",
            "windows.none":      "Blank page — no windows",
            "hint.info":         "Scribbles about this machine.",
            "group.empty":       "Empty pocket — toss modules in via Settings → Bar"
        },
        wobbly: {
            "greet.night":       "Psst, it's late",
            "greet.morning":     "Boing! Morning",
            "greet.afternoon":   "Hello hello",
            "greet.evening":     "Cozy evening",
            "notif.title":       "Blips",
            "notif.empty":       "All quiet, no blips",
            "launcher.search":   "Bounce a search…",
            "launcher.noMatches":"Nothing bounced back",
            "clipboard.search":  "Fish the clipboard…",
            "mpris.nothing":     "The jukebox naps",
            "bt.noPaired":       "No buddies paired",
            "bt.noneFound":      "No buddies nearby — scan again",
            "bt.scanning":       "Wiggling antennas…",
            "net.noneFound":     "No waves caught",
            "windows.none":      "No windows wobbling",
            "hint.info":         "The squishy details.",
            "group.empty":       "This bubble is empty — add modules in Settings → Bar"
        },
        straight: {
            "greet.night":       "Night",
            "greet.morning":     "Morning",
            "greet.afternoon":   "Afternoon",
            "greet.evening":     "Evening",
            "notif.empty":       "None",
            "launcher.search":   "Search…",
            "launcher.noMatches":"No results",
            "clipboard.search":  "Search…",
            "mpris.nothing":     "Idle",
            "bt.noPaired":       "None paired",
            "bt.noneFound":      "None found",
            "bt.scanning":       "Scanning",
            "net.noneFound":     "None found",
            "windows.none":      "None open",
            "group.empty":       "Empty"
        },
        cupertino: {
            "greet.night":       "Good Night",
            "greet.morning":     "Good Morning",
            "greet.afternoon":   "Good Afternoon",
            "greet.evening":     "Good Evening",
            "notif.title":       "Notification Center",
            "notif.empty":       "No New Notifications",
            "launcher.search":   "Spotlight Search",
            "launcher.noMatches":"No Results",
            "clipboard.search":  "Search Clipboard",
            "mpris.nothing":     "Not Playing",
            "bt.noPaired":       "No Devices",
            "bt.noneFound":      "No Devices Found",
            "bt.scanning":       "Searching…",
            "net.noneFound":     "No Networks Found",
            "windows.none":      "No Open Windows",
            "hint.info":         "About this system.",
            "group.empty":       "No Modules in This Group"
        }
    })

    function s(key) {
        var t = root._tables[VtlConfig.uiStyle]
        if (t && t[key] !== undefined) return t[key]
        return root._base[key] !== undefined ? root._base[key] : key
    }

    function greeting(h) {
        return root.s(h < 5 ? "greet.night" : h < 12 ? "greet.morning"
                    : h < 18 ? "greet.afternoon" : "greet.evening")
    }
}
