-- ═══════════════════════════════════════════════════════
-- VUTURELAND — Hyprland Lua Configuration
-- https://wiki.hypr.land/Configuring/
-- ═══════════════════════════════════════════════════════

-- Installation paths — set by the entry point (~/.config/hypr/hyprland.lua);
-- fall back to env var or ~/.config/vutureland only if not already provided.
VTL_DIR      = VTL_DIR      or os.getenv("VUTURELAND_DIR")      or (os.getenv("HOME") .. "/.config/vutureland")
VTL_USER_DIR = VTL_USER_DIR or os.getenv("VUTURELAND_USER_DIR") or (os.getenv("HOME") .. "/.config/vutureland")

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
 