import "../.."
import QtQuick

// System glance options: which readings this instance carries, and whether the percentages get
// their gauge. A widget with one reading left is a single gauge, which is a perfectly good thing to
// park in a corner — the module does not insist on being a whole system report.
WidgetOpts {
    id: o

    FieldLabel { text: "Look" }
    Segmented {
        width: parent.width
        equal: true
        current: "" + o.val("style", "ring")
        segments: [{ key: "ring", label: "Gauges", hint: "An arc per reading, the value inside it" },
                   { key: "bars", label: "Bars",   hint: "The reading as a number with a filling bar under it" }]
        onPicked: o.optSet("style", key)
    }
    // Both faces fall back to a row of chips when the widget is too small to draw them — a ring
    // with an illegible number in it is worse than the number on its own.

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
        visible: ("" + o.val("style", "ring")) === "bars"
        label: "Filling bar"
        sub:   "The bar under each percentage. The gauge look is the bar."
        on:    o.flag("bars")
        onToggled: o.optSet("bars", !o.flag("bars"))
    }
}
