-- ═══════════════════════════════════════════════════════
-- Custom Layouts
-- https://wiki.hypr.land/Configuring/Layouts/Custom-Layouts/
-- ═══════════════════════════════════════════════════════

-- Vertical stack: every new window goes below the previous one, never beside.
-- Use as layout = "lua:vstack" in workspace rules.
hl.layout.register("vstack", {
    recalculate = function(ctx)
        local n = #ctx.targets
        if n == 0 then return end
        for i, target in ipairs(ctx.targets) do
            target:place(ctx:row(i, n))
        end
    end,
})
