import "../.."
import QtQuick

// Weather widget options. The city and the unit are NOT here: one shell, one reading, one fetch —
// they live in Settings → Bar → Weather and every surface shares them (see WeatherService). What
// this instance decides is how much of that reading it draws.
WidgetOpts {
    id: o

    Toggle {
        label: "Place"
        sub:   "The town the reading is for"
        on:    o.flag("place")
        onToggled: o.optSet("place", !o.flag("place"))
    }
    Toggle {
        label: "Description"
        sub:   "\"Cloudy\", under the temperature"
        on:    o.flag("desc")
        onToggled: o.optSet("desc", !o.flag("desc"))
    }
    Toggle {
        label: "Animate the sky"
        sub:   "The sun turns and the clouds drift. Off by default: the desk is on screen all day"
        on:    o.val("motion", false) === true
        onToggled: o.optSet("motion", !(o.val("motion", false) === true))
    }
    Stepper {
        label: "Forecast days"; labelWidth: 120
        value: o.val("days", 3); step: 1; min: 0; max: 3
        onChanged: v => o.optSet("days", v)
    }
    SubLabel {
        width: parent.width
        text: "The forecast row needs a widget of about 4x4 cells; below that only the current "
            + "reading is drawn. City and unit are shared with the bar module."
    }
}
