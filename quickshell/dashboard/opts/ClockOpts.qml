import "../.."
import QtQuick

// Clock widget options. Formats are offered as NAMED choices rather than as a format field: the
// Qt format string is the implementation, and a picker that says "24-hour · seconds" is the same
// choice without asking anybody to remember what `hh:mm:ss` spells. "Follow the bar clock" is the
// default and writes an empty string, which is what keeps a fresh widget agreeing with the bar.
WidgetOpts {
    id: o

    readonly property var timeFormats: [
        { key: "",          label: "Follow the bar clock" },
        { key: "hh:mm",     label: "24-hour" },
        { key: "hh:mm:ss",  label: "24-hour, seconds" },
        { key: "h:mm AP",   label: "12-hour" },
        { key: "h:mm:ss AP", label: "12-hour, seconds" }
    ]
    readonly property var dateFormats: [
        { key: "",                 label: "Follow the bar clock" },
        { key: "dddd, dd MMMM",    label: "Monday, 02 September" },
        { key: "ddd dd MMM",       label: "Mon 02 Sep" },
        { key: "dddd",             label: "Monday" },
        { key: "dd.MM.yyyy",       label: "02.09.2026" },
        { key: "d MMMM yyyy",      label: "2 September 2026" }
    ]

    function _label(list, key) {
        for (var i = 0; i < list.length; i++) if (list[i].key === key) return list[i].label
        return key
    }
    function _options(list, cur) {
        return list.map(function (e) { return { label: e.label, key: e.key, on: e.key === cur } })
    }

    FieldLabel { text: "Arrangement" }
    Segmented {
        width: parent.width
        equal: true
        current: "" + o.val("layout", "stack")
        segments: [{ key: "stack", label: "Stacked", hint: "Date under the time" },
                   { key: "row",   label: "Side by side", hint: "One line — the shape for a strip along an edge" }]
        onPicked: o.optSet("layout", key)
    }

    FieldLabel { text: "Alignment" }
    Segmented {
        width: parent.width
        equal: true
        current: "" + o.val("align", "center")
        segments: [{ key: "left", label: "Left" }, { key: "center", label: "Centre" },
                   { key: "right", label: "Right" }]
        onPicked: o.optSet("align", key)
    }

    FieldLabel { text: "Time" }
    Dropdown {
        summary: o._label(o.timeFormats, "" + o.val("time_format", ""))
        options: o._options(o.timeFormats, "" + o.val("time_format", ""))
        onPicked: o.optSet("time_format", key)
    }

    FieldLabel { text: "Weight" }
    Segmented {
        width: parent.width
        equal: true
        current: "" + o.val("weight", "medium")
        segments: [{ key: "light", label: "Light" }, { key: "normal", label: "Normal" },
                   { key: "medium", label: "Medium" }, { key: "bold", label: "Bold" }]
        onPicked: o.optSet("weight", key)
    }

    FieldLabel { text: "Date" }
    Segmented {
        width: parent.width
        equal: true
        current: "" + o.val("date", "auto")
        segments: [{ key: "auto", label: "Auto", hint: "Shown once the widget is tall enough to carry it" },
                   { key: "on",   label: "Always" },
                   { key: "off",  label: "Never" }]
        onPicked: o.optSet("date", key)
    }
    Dropdown {
        visible: "" + o.val("date", "auto") !== "off"
        summary: o._label(o.dateFormats, "" + o.val("date_format", ""))
        options: o._options(o.dateFormats, "" + o.val("date_format", ""))
        onPicked: o.optSet("date_format", key)
    }
}
