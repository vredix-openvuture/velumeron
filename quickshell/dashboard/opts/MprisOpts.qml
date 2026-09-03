import "../.."
import QtQuick

// Now-playing widget options. Four parts that can each be dropped, because the same widget is a
// record spinning in the corner of a desk and a full player four cells wide, and which parts belong
// is a question about the space it was given rather than about what a player is.
WidgetOpts {
    id: o

    Toggle {
        label: "Cover art"
        sub:   "The record, spinning while something plays"
        on:    o.flag("cover")
        onToggled: o.optSet("cover", !o.flag("cover"))
    }
    Toggle {
        label: "Transport"
        sub:   "Previous / play / next"
        on:    o.flag("transport")
        onToggled: o.optSet("transport", !o.flag("transport"))
    }
    Toggle {
        label: "Progress"
        sub:   "How far into the track"
        on:    o.flag("progress")
        onToggled: o.optSet("progress", !o.flag("progress"))
    }
    Toggle {
        label: "Spectrum"
        sub:   "The audio wave behind the tile"
        on:    o.flag("wave")
        onToggled: o.optSet("wave", !o.flag("wave"))
    }
}
