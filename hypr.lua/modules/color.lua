-- ═══════════════════════════════════════════════════════
-- Palette helpers for the theme files
-- ═══════════════════════════════════════════════════════
--
-- A theme wants shades the palette does not name: "the accent, but dimmed to a hint" for an
-- unfocused frame, "the accent, but burning" for a focused one. Deriving them here keeps every
-- theme on the SAME accent as the shell (color3 = Colors.bgActive, color5 = Colors.boNormal)
-- instead of hunting the palette for a slot that happens to look brighter.
--
-- Two input shapes have to parse: wallust renders colors.lua as "#rrggbb" and the
-- hyprland_lua-colors.sh hook rewrites it to "rgb(r,g,b)", but colors.default.lua — the fallback a
-- fresh box runs on until its first wallpaper — is never rewritten and stays hex.
--
-- Anything unparseable comes back unchanged: a broken palette must not take the config down with
-- it, and Hyprland's own parser gets the final word on the value either way.

local function _rgb(c)
    if type(c) ~= "string" then return nil end
    local r, g, b = c:match("^rgba?%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    if r then return tonumber(r), tonumber(g), tonumber(b) end
    local hex = c:match("^#?(%x%x%x%x%x%x)$")
    if hex then
        return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    end
    return nil
end

local function _fmt(r, g, b)
    local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
    return string.format("rgb(%d,%d,%d)", clamp(r), clamp(g), clamp(b))
end

-- Toward black. factor 1 keeps the colour, 0 is black. Scaling (not mixing with black) keeps the
-- hue and the saturation, which is what makes a dimmed border still read as "the same colour".
function VTL_darken(color, factor)
    local r, g, b = _rgb(color)
    if not r then return color end
    return _fmt(r * factor, g * factor, b * factor)
end

-- Toward the colour's own ceiling: every channel scaled until the brightest one reaches 255.
-- amount 0 keeps the colour, 1 puts it at full luminance. Mixing with white would have washed the
-- hue out on the way up; scaling keeps the accent recognisably itself and only makes it burn.
function VTL_brighten(color, amount)
    local r, g, b = _rgb(color)
    if not r then return color end
    local peak = math.max(r, g, b)
    if peak == 0 then return color end
    local scale = 1 + (255 / peak - 1) * amount
    return _fmt(r * scale, g * scale, b * scale)
end
