import "../.."
import QtQuick
import Quickshell
import Quickshell.Io

// Bar settings page — equivalent of the Python WaybarPage.
// Manages Left / Center / Right module slots for the QuickShell bar.
Item {
    id: root

    property var    leftMods:   []
    property var    centerMods: []
    property var    rightMods:  []
    property bool   showingAdd: false
    property string addTarget:  "left"

    Component.onCompleted: _reload()

    // Sync from the live VtlConfig values
    function _reload() {
        leftMods   = VtlConfig.barModulesLeft.slice()
        centerMods = VtlConfig.barModulesCenter.slice()
        rightMods  = VtlConfig.barModulesRight.slice()
        statusTxt.text = ""
    }

    function _slotFor(zone) {
        if (zone === "left")   return leftMods
        if (zone === "center") return centerMods
        return rightMods
    }

    function removeModule(zone, key) {
        var arr = _slotFor(zone).filter(function(m) { return m !== key })
        if      (zone === "left")   leftMods   = arr
        else if (zone === "center") centerMods = arr
        else                        rightMods  = arr
        statusTxt.text = "Unsaved changes"
    }

    function addModule(zone, key) {
        var arr = _slotFor(zone).slice()
        arr.push(key)
        if      (zone === "left")   leftMods   = arr
        else if (zone === "center") centerMods = arr
        else                        rightMods  = arr
        showingAdd     = false
        statusTxt.text = "Unsaved changes"
    }

    function _labelFor(key) {
        for (var i = 0; i < moduleRegistry.length; i++) {
            if (moduleRegistry[i].key === key) return moduleRegistry[i].label
        }
        return key
    }

    // Full module list — mirrors the registry in the old BarSettingsWindow
    readonly property var moduleRegistry: [
        { key: "vuture-icon", label: "Vuture Icon"   },
        { key: "clock",       label: "Clock"          },
        { key: "performance", label: "Performance"    },
        { key: "user",        label: "User"           },
        { key: "workspaces",  label: "Workspaces"     },
        { key: "submap",      label: "Submap"         },
        { key: "mpris",       label: "Media"          },
        { key: "volume",      label: "Volume"         },
        { key: "notiftray",   label: "Notifications"  },
        { key: "battery",     label: "Battery"        },
        { key: "temperature", label: "Temperature"    },
        { key: "network",     label: "Network"        },
        { key: "bluetooth",   label: "Bluetooth"      },
        { key: "vpn",         label: "VPN"            },
    ]

    // ── Page header ──────────────────────────────────────────────────────────
    Rectangle {
        id: pageHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 48
        color:  Colors.bgElement

        Text {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text:           "Bar"
            color:          Colors.fgPrimary
            font.pixelSize: 15
            font.bold:      true
            font.family:    "FantasqueSansM Nerd Font"
        }

        // Bottom border
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 1
            color: Colors.boNormal; opacity: 0.3
        }
    }

    // ── Action bar ───────────────────────────────────────────────────────────
    Rectangle {
        id: actionBar
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 48
        color:  Colors.bgElement

        // Top border
        Rectangle {
            anchors.top: parent.top
            width: parent.width; height: 1
            color: Colors.boNormal; opacity: 0.3
        }

        Row {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 8

            Text {
                id:              statusTxt
                anchors.verticalCenter: parent.verticalCenter
                text:            ""
                color:           Colors.fgMuted
                font.pixelSize:  11
                font.family:     "FantasqueSansM Nerd Font"
            }

            // Reset
            Rectangle {
                width: 72; height: 28; radius: 6
                color: rstHov.containsMouse ? Colors.bgActive : Colors.bgPrimary

                Text {
                    anchors.centerIn: parent
                    text:           "Reset"
                    color:          rstHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                    font.pixelSize: 12
                    font.family:    "FantasqueSansM Nerd Font"
                }
                MouseArea { id: rstHov; anchors.fill: parent; hoverEnabled: true; onClicked: root._reload() }
            }

            // Apply
            Rectangle {
                width: 72; height: 28; radius: 6
                color: applyHov.containsMouse ? Colors.boActive : Colors.bgActive

                Text {
                    anchors.centerIn: parent
                    text:           "Apply"
                    color:          Colors.fgBright
                    font.pixelSize: 12
                    font.bold:      true
                    font.family:    "FantasqueSansM Nerd Font"
                }
                MouseArea { id: applyHov; anchors.fill: parent; hoverEnabled: true; onClicked: root._save() }
            }
        }
    }

    // ── Middle content (zones or add-module view) ────────────────────────────
    Item {
        anchors {
            top: pageHeader.bottom; bottom: actionBar.top
            left: parent.left; right: parent.right
            margins: 12
        }

        // ── Zone layout ──────────────────────────────────────────────────
        Row {
            visible:      !root.showingAdd
            anchors.fill: parent
            spacing:      8

            BarZone {
                zoneId: "left"; label: "LEFT"; modules: root.leftMods
                height: parent.height; width: (parent.width - 16) / 3
                labelFor: root._labelFor
                onRemove:     function(key) { root.removeModule("left",   key) }
                onAddRequest: function()    { root.addTarget = "left";   root.showingAdd = true }
            }
            BarZone {
                zoneId: "center"; label: "CENTER"; modules: root.centerMods
                height: parent.height; width: (parent.width - 16) / 3
                labelFor: root._labelFor
                onRemove:     function(key) { root.removeModule("center", key) }
                onAddRequest: function()    { root.addTarget = "center"; root.showingAdd = true }
            }
            BarZone {
                zoneId: "right"; label: "RIGHT"; modules: root.rightMods
                height: parent.height; width: (parent.width - 16) / 3
                labelFor: root._labelFor
                onRemove:     function(key) { root.removeModule("right",  key) }
                onAddRequest: function()    { root.addTarget = "right";  root.showingAdd = true }
            }
        }

        // ── Add-module view ──────────────────────────────────────────────
        Item {
            visible:      root.showingAdd
            anchors.fill: parent

            // Header with back button
            Row {
                id: addHeader
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 36; spacing: 8

                Rectangle {
                    width: 28; height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    color:  backHov.containsMouse ? Colors.bgElement : "transparent"
                    radius: 6

                    Text {
                        anchors.centerIn: parent
                        text: "←"; color: Colors.fgPrimary
                        font.pixelSize: 14; font.family: "FantasqueSansM Nerd Font"
                    }
                    MouseArea { id: backHov; anchors.fill: parent; hoverEnabled: true; onClicked: root.showingAdd = false }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add to " + (root.addTarget === "left" ? "Left"
                                     : root.addTarget === "center" ? "Center" : "Right")
                    color: Colors.fgPrimary; font.pixelSize: 13; font.bold: true
                    font.family: "FantasqueSansM Nerd Font"
                }
            }

            // Module chips in a flow layout
            Flow {
                anchors { top: addHeader.bottom; topMargin: 12; left: parent.left; right: parent.right }
                spacing: 6

                Repeater {
                    model: root.moduleRegistry
                    delegate: Rectangle {
                        readonly property var mod: root.moduleRegistry[index]
                        width:  modLbl.implicitWidth + 20
                        height: 28
                        radius: 14
                        color:  modHov.containsMouse ? Colors.bgActive : Colors.bgElement

                        Text {
                            id:              modLbl
                            anchors.centerIn: parent
                            text:            mod.label
                            color:           modHov.containsMouse ? Colors.fgBright : Colors.fgPrimary
                            font.pixelSize:  12
                            font.family:     "FantasqueSansM Nerd Font"
                        }

                        MouseArea {
                            id: modHov; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.addModule(root.addTarget, mod.key)
                        }
                    }
                }
            }
        }
    }

    // ── Save to $VELUMERON_USER_DIR/gui/settings.json ───────────────────────
    function _save() {
        var py = "import json,os,sys;" +
            "pu=os.environ.get('VELUMERON_USER_DIR') or " +
              "os.path.join(os.environ.get('XDG_CONFIG_HOME','') or " +
              "os.path.expanduser('~/.config'),'velumeron');" +
            "p=os.path.join(pu,'gui','settings.json');" +
            "os.makedirs(os.path.dirname(p),exist_ok=True);" +
            "d=json.load(open(p)) if os.path.exists(p) else {};" +
            "d['bar_modules_left']=json.loads(sys.argv[1]);" +
            "d['bar_modules_center']=json.loads(sys.argv[2]);" +
            "d['bar_modules_right']=json.loads(sys.argv[3]);" +
            "open(p,'w').write(json.dumps(d,indent=2))"
        saveProc.command = [
            "python3", "-c", py,
            JSON.stringify(leftMods),
            JSON.stringify(centerMods),
            JSON.stringify(rightMods),
        ]
        saveProc.running = false
        saveProc.running = true
        statusTxt.text = "Saved"
        clearTimer.restart()
    }

    Timer    { id: clearTimer; interval: 2500; onTriggered: statusTxt.text = "" }
    Process  { id: saveProc }
}
