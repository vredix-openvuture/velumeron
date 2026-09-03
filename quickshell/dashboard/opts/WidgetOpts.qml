import "../.."
import QtQuick

// Base for one widget type's option panel in the layout editor.
//
// A widget's options are stored on the PLACED ENTRY (`opts`), not under a settings key for the
// type: two clocks on one desk are two different clocks, and the whole point of the desk is that
// the same module can be put down twice and answer differently. So a panel never writes settings
// itself — it emits `optSet(key, value)` and DashEditor, which owns every write to the layout,
// folds it into the entry.
//
// `val()` is the only way a panel reads: an option that was never set has no key at all, so every
// read carries the default with it and a layout written by an older version keeps working.
Column {
    id: op

    property var entry: null                 // the placed entry being edited
    signal optSet(string key, var value)

    width: parent ? parent.width : 0
    spacing: 6

    function val(key, def) {
        var o = op.entry ? op.entry.opts : null
        if (!o) return def
        var v = o[key]
        return (v === undefined || v === null) ? def : v
    }
    // Booleans default to ON: every option here switches a part of the widget OFF, so a widget with
    // no options set is the whole widget.
    function flag(key) { return op.val(key, true) !== false }
}
