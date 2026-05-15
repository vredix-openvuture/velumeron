-- ═══════════════════════════════════════════════════════
-- VUTURELAND — Hyprland Lua Configuration
-- https://wiki.hypr.land/Configuring/
-- ═══════════════════════════════════════════════════════

-- Colors (defines global color variables)
require(".colors")

-- Device-specific settings (monitors, workspaces, peripherals)
-- Not in git — generated per device.
require("user_settings")

-- Modules (order matters: variables before their consumers)
require("modules.gpu")
require("modules.variables")
require("modules.environment")
require("modules.devices")
require("modules.look_and_feel")
require("modules.animations")
require("modules.autostart")
require("modules.layouts")
require("modules.windowrules")
require("modules.layerrules")
require("modules.keybinds")



-- ═══════════════════════════════════════════════════════
-- MANUAL OVERRIDES
-- Add device-specific overrides below this line
-- ═══════════════════════════════════════════════════════
 