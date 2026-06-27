pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    // IPC: toggle / open / close the corner menu from outside (e.g. a Hyprland keybind):
    //   qs -p <this-dir> ipc call menu toggle
    IpcHandler {
        target: "menu"
        function toggle(): void { UiState.openDropdown = UiState.openDropdown === "vuture-icon" ? "" : "vuture-icon" }
        function open():   void { UiState.openDropdown = "vuture-icon" }
        function close():  void { UiState.openDropdown = "" }
    }

    // Bar visual: full-screen transparent surface, no exclusive zone (dynamic, multi-edge)
    Variants {
        model: Quickshell.screens
        delegate: Bar {
            required property var modelData
            screen: modelData
        }
    }

    // Exclusive zones: one invisible reserving surface per screen × edge. Each only
    // reserves space when the bar actually occupies that edge (driven by VtlConfig).
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "top" }
    }
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "bottom" }
    }
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "left" }
    }
    Variants {
        model: Quickshell.screens
        delegate: EdgeExclusiveZone { required property var modelData; screen: modelData; edge: "right" }
    }

    // Settings menu: one per screen, shown via UiState.openDropdown === "vuture-icon"
    Variants {
        model: Quickshell.screens
        delegate: Settings {
            required property var modelData
            screen: modelData
        }
    }

    // GUI panel: single shared instance, shown via UiState.guiPanelOpen
    GuiPanel {}
}
