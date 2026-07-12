pragma Singleton
import QtQuick

// Shared search matcher for every searchbar in the shell (launcher, clipboard, icon picker, keybind
// help, app/corner/window-rule pickers …). `score(query, text)` returns a relevance number — higher
// is better, -1 means no match; `match()` is the boolean shortcut. It honours the global
// `fuzzy_search` toggle (VtlConfig), so flipping one setting switches every searchbar at once:
//   ON  → an fzf-style subsequence match: the query's characters must appear IN ORDER in the target,
//         scored with bonuses for consecutive runs, word starts, and an early first hit.
//   OFF → a plain case-insensitive substring match (earlier position + word start rank higher).
// Callers that show a ranked list sort by score descending; simple filters just keep score >= 0.
QtObject {
    id: root
    readonly property bool enabled: VtlConfig.fuzzySearch

    // A char that makes the NEXT char read as a word start (so "fm" strongly matches "file-manager").
    function _isBoundary(code) {
        return code === 32 /*space*/ || code === 45 /*-*/ || code === 95 /*_*/ || code === 46 /*.*/
            || code === 47 /*/*/     || code === 44 /*,*/ || code === 58 /*:*/
            || code === 40 /*(*/     || code === 41 /*)*/
    }

    // Relevance score, or -1 for no match. Empty query matches everything (score 0).
    function score(query, text) {
        var q = ("" + (query || "")).toLowerCase()
        var t = ("" + (text  || "")).toLowerCase()
        if (q.length === 0) return 0
        if (t.length === 0) return -1

        if (!root.enabled) {
            // Substring mode: earlier match ranks higher; a match at a word start gets a small bump.
            var idx = t.indexOf(q)
            if (idx < 0) return -1
            var sub = 100 - Math.min(idx, 100)
            if (idx === 0 || root._isBoundary(t.charCodeAt(idx - 1))) sub += 15
            return sub
        }

        // Fuzzy subsequence: walk the target, consuming query chars in order.
        var qi = 0, streak = 0, prev = -2, first = -1, sc = 0
        for (var ti = 0; ti < t.length && qi < q.length; ti++) {
            if (t.charCodeAt(ti) === q.charCodeAt(qi)) {
                if (first < 0) first = ti
                var bonus = 1
                if (ti === prev + 1) { streak += 1; bonus += streak * 3 }   // consecutive run
                else streak = 0
                if (ti === 0 || root._isBoundary(t.charCodeAt(ti - 1))) bonus += 6   // word start
                sc += bonus
                prev = ti
                qi += 1
            }
        }
        if (qi < q.length) return -1        // not every query char was consumed → no match
        sc += Math.max(0, 12 - first)       // reward an early first hit
        sc -= t.length * 0.04               // gently prefer shorter targets on ties
        return sc
    }

    function match(query, text) { return root.score(query, text) >= 0 }
}
