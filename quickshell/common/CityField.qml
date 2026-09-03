import ".."
import QtQuick
import Quickshell
import Quickshell.Io

// City input that names the place back to you.
//
// Two problems sit in one field: a typed name is a guess until something confirms it, and the same
// name can mean several places. So it talks to two services on purpose.
//   - Typing asks city-search.sh (Open-Meteo) for real places and offers them. Picking one stores
//     its coordinates next to the readable name — the only unambiguous answer, because the two
//     German towns called Neustadt are one string but two different fixes.
//   - The committed value then goes through weather-fetch.sh --probe, so the line under the field
//     names the place the WEATHER service landed on. That is the one that ends up on screen.
//
// Emits committed(place, coords); coords is "" when the text was typed rather than picked.
Column {
    id: cityField

    property string value:  ""
    property string coords: ""
    property string placeholder: "Berlin"
    property int    maxSuggestions: 6

    signal committed(string place, string coords)

    width:   parent ? parent.width : 200
    spacing: 4

    readonly property string _scripts: (Quickshell.env("VELUMERON_DIR") ?? "") + "/assets/scripts"
    // What is actually fetched: the picked fix when there is one, the typed name otherwise.
    readonly property string _query: cityField.coords !== "" ? cityField.coords : cityField.value

    property var    _suggestions: []
    property string _probeState:  ""      // "" | busy | ok | notfound | unreachable
    property string _probeName:   ""
    property bool   _searchFailed: false
    // The text the caller already knows about. NOT the same as `value`: a commit is stored
    // asynchronously and only comes back through the binding a moment later, and in that moment
    // losing focus would otherwise look like a second, hand-typed edit — which is what wipes the
    // coordinates a pick had just stored.
    property string _reported: ""

    // `_reported` follows the stored value even while the field has focus: the user's own text is
    // what is in the input, and leaving `_reported` behind would make the next focus loss look like
    // a fresh hand-typed edit and wipe the coordinates a pick had stored.
    onValueChanged: {
        cityField._reported = cityField.value
        if (!input.activeFocus) input.text = cityField.value
    }
    on_QueryChanged: cityField._probe()

    // `value`/`coords` stay the caller's bindings — assigning them here would destroy those
    // bindings, and the field would then ignore every later change to the stored setting. So the
    // commit only reports, and the new value arrives back through the binding once it is stored.
    function _commit(place, fix) {
        debounce.stop()                 // a pick within the debounce window must not still search
        input.text = place
        cityField._reported = place
        cityField._suggestions = []
        cityField._searchFailed = false
        cityField.committed(place, fix)
    }

    function _search() {
        var q = input.text.trim()
        if (q.length < 2) { cityField._suggestions = []; cityField._searchFailed = false; return }
        searchProc.command = ["bash", cityField._scripts + "/city-search.sh", q, "" + cityField.maxSuggestions]
        searchProc.running = false
        searchProc.running = true
    }

    // A picked place needs no probe: the coordinates ARE the answer, and asking wttr.in what sits
    // nearest to them only produces the name of a weather station in the next village, which reads
    // as "it did not understand me". The probe exists for TYPED input, where recognition is the
    // open question.
    function _probe() {
        if (cityField.coords !== "" && cityField.value !== "") {
            probeProc.running = false
            cityField._probeState = "picked"; cityField._probeName = cityField.value
            return
        }
        if (cityField._query === "") {
            // Stop the running one too, or its late answer names a place under an empty field.
            probeProc.running = false
            cityField._probeState = ""; cityField._probeName = ""
            return
        }
        cityField._probeState = "busy"
        probeProc.command = ["bash", cityField._scripts + "/weather-fetch.sh", "--probe", cityField._query]
        probeProc.running = false
        probeProc.running = true
    }

    Component.onCompleted: { cityField._reported = cityField.value; cityField._probe() }

    // One request per pause in typing, not per keystroke — the endpoint is somebody else's.
    Timer {
        id: debounce
        interval: 320
        onTriggered: cityField._search()
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                // A killed run (the next keystroke restarts the process) can flush a half
                // document; keep the list that is on screen rather than blinking it away. A real
                // "nothing found" arrives as valid JSON with an empty results array, and a service
                // that could not be reached as ok:false — which has to say so, or a dead lookup
                // looks exactly like a place that does not exist.
                try {
                    var answer = JSON.parse(("" + text).trim())
                    cityField._searchFailed = answer.ok !== true
                    cityField._suggestions = (answer.results instanceof Array) ? answer.results : []
                } catch (e) { }
            }
        }
    }

    Process {
        id: probeProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var answer = JSON.parse(("" + text).trim())
                    cityField._probeName  = "" + (answer.name ?? "")
                    cityField._probeState = answer.ok ? "ok" : ("" + (answer.error ?? "notfound"))
                } catch (e) {
                    cityField._probeName = ""; cityField._probeState = "unreachable"
                }
            }
        }
    }

    StyledRect {
        width:       parent.width
        height:      Style.ctrlH
        radius:      Style.rControl
        color:       Style.controlFill
        borderWidth: input.activeFocus ? Math.max(1, Style.controlBorderW) : Style.controlBorderW
        borderColor: input.activeFocus ? Style.accent : Style.controlBorderColor

        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.fgBright; font.pixelSize: Style.fsLabel; font.family: Style.font
            clip: true; selectByMouse: true
            text: cityField.value
            onTextEdited: debounce.restart()
            onEditingFinished: if (text.trim() !== cityField._reported) cityField._commit(text.trim(), "")

            Text {
                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                visible: input.text === "" && !input.activeFocus
                text: cityField.placeholder; color: Colors.fgMuted; font: input.font
                elide: Text.ElideRight
            }
        }
    }

    Column {
        visible: input.activeFocus && cityField._suggestions.length > 0
        width:   parent.width
        spacing: 2
        Repeater {
            model: cityField._suggestions
            delegate: StyledRect {
                required property var modelData
                width: cityField.width; height: 28; radius: Style.rTile
                color: rowHover.containsMouse ? Style.controlHover : Style.controlFill
                borderWidth: Style.controlBorderW; borderColor: Style.controlBorderColor
                Text {
                    id: placeName
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: modelData.name; color: Colors.fgPrimary
                    font.pixelSize: 12; font.family: Style.font
                    width: Math.min(implicitWidth, cityField.width * 0.5); elide: Text.ElideRight
                }
                Text {
                    anchors { left: placeName.right; leftMargin: 8; right: parent.right; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    text: modelData.detail; color: Colors.fgMuted
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 10; font.family: Style.font; elide: Text.ElideMiddle
                }
                MouseArea {
                    id: rowHover
                    anchors.fill: parent; hoverEnabled: true
                    onClicked: { cityField._commit(modelData.value, modelData.coords); input.focus = false }
                }
            }
        }
    }

    // Which place the weather service settled on. Wrong town on screen is the failure this line
    // exists to catch, so it names the match instead of just ticking it off.
    SubLabel {
        width:   parent.width
        visible: cityField._probeState !== "" || (cityField._searchFailed && input.activeFocus)
        color:   cityField._probeState === "notfound" ? Colors.fgUrgent : Colors.fgMuted
        text: {
            // While the user is typing, a broken lookup is the more urgent news than a probe of the
            // place they have already left behind.
            if (cityField._searchFailed && input.activeFocus)
                return "No suggestions right now: the place service did not answer."
            switch (cityField._probeState) {
            case "busy":        return "Checking the place…"
            case "picked":      return "Weather for " + cityField._probeName
            case "ok":          return "Weather for " + cityField._probeName
            case "notfound":    return "No such place. Type more of the name and pick a suggestion."
            case "unreachable": return "The weather service did not answer, so the place is unchecked."
            default:            return ""
            }
        }
    }
}
