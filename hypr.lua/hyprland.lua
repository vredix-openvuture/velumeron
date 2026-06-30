-- ═══════════════════════════════════════════════════════
-- VELUMERON — Hyprland Lua Configuration
-- https://wiki.hypr.land/Configuring/
-- ═══════════════════════════════════════════════════════

-- Installation paths — set by the entry point (~/.config/hypr/hyprland.lua);
-- fall back to env var or ~/.config/velumeron only if not already provided.
VTL_DIR      = VTL_DIR      or os.getenv("VELUMERON_DIR")      or (os.getenv("HOME") .. "/.config/velumeron")
VTL_USER_DIR = VTL_USER_DIR or os.getenv("VELUMERON_USER_DIR") or (os.getenv("HOME") .. "/.config/velumeron")

-- Colors — wallust writes the live palette to ~/.config/velumeron/hypr.lua/colors.lua.
-- Fall back to the default palette shipped with the package if wallust hasn't
-- run yet (typical on first start, before the user picked a wallpaper).
local function _try_dofile(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    dofile(path)
    return true
end
if not _try_dofile(VTL_USER_DIR .. "/hypr.lua/colors.lua") then
    _try_dofile(VTL_DIR .. "/hypr.lua/colors.lua")
end

-- Device-specific settings (monitors, workspaces, peripherals)
-- Not in git — generated per device. Always lives in the user dir.
_try_dofile(VTL_USER_DIR .. "/hypr.lua/user_settings.lua")

-- Modules (order matters: variables before their consumers)
require("modules.gpu")
require("modules.variables")
require("modules.environment")
require("modules.devices")
require("modules.look_and_feel")

-- Active app theme — the design chosen in the waybar GUI also themes hyprland.
-- The theme.lua overrides design-specific look on top of look_and_feel (it does
-- NOT touch rounding/border_size, which stay user-controlled). A missing file is
-- a no-op (the look_and_feel default stands). Defaults to "miboro".
do
    local theme = "miboro"
    local tf = io.open(VTL_USER_DIR .. "/active-theme", "r")
    if tf then
        local line = tf:read("*l"); tf:close()
        if line then line = line:gsub("%s+", ""); if line ~= "" then theme = line end end
    end
    if not _try_dofile(VTL_USER_DIR .. "/hypr.lua/themes/" .. theme .. ".lua") then
        _try_dofile(VTL_DIR .. "/hypr.lua/themes/" .. theme .. ".lua")
    end
end

require("modules.animations")
require("modules.autostart")
require("modules.layouts")
require("modules.windowrules")
require("modules.workspaces")
require("modules.layerrules")
require("modules.keybinds")



-- ═══════════════════════════════════════════════════════
-- MANUAL OVERRIDES
-- Add device-specific overrides below this line
-- ═══════════════════════════════════════════════════════
 