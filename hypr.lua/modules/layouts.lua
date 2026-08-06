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

-- Duo: the endless-scroll pair — one window fills the workspace, two share it
-- 50/50 side by side. More than two only exists transiently while the
-- layout_manager policy is still flowing the overflow to the next workspace;
-- until then they tile as equal columns. Used as layout = "lua:duo".
hl.layout.register("duo", {
    recalculate = function(ctx)
        local n = #ctx.targets
        if n == 0 then return end
        for i, target in ipairs(ctx.targets) do
            target:place(ctx:column(i, n))
        end
    end,
})
