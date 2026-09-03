import "../.."
import QtQuick

// System glance options: which readings this instance carries, and whether the percentages get
// their gauge. A widget with one reading left is a single gauge, which is a perfectly good thing to
// park in a corner — the module does not insist on being a whole system report.
WidgetOpts {
    id: o

    Toggle {
        label: "CPU"
        on:    o.flag("cpu")
        onToggled: o.optSet("cpu", !o.flag("cpu"))
    }
    Toggle {
        label: "Memory"
        on:    o.flag("mem")
        onToggled: o.optSet("mem", !o.flag("mem"))
    }
    Toggle {
        label: "Temperature"
        sub:   "Package temperature, when the machine reports one"
        on:    o.flag("temp")
        onToggled: o.optSet("temp", !o.flag("temp"))
    }
    Toggle {
        label: "Uptime"
        on:    o.flag("uptime")
        onToggled: o.optSet("uptime", !o.flag("uptime"))
    }
    Toggle {
        label: "Gauges"
        sub:   "A filling bar under each percentage"
        on:    o.flag("bars")
        onToggled: o.optSet("bars", !o.flag("bars"))
    }
}
