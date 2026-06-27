-- ═══════════════════════════════════════════════════════
-- Animations
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- ═══════════════════════════════════════════════════════

hl.config({
    animations = { enabled = true },
})

-- Bezier curves
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("rubber",         { type = "spring", mass = 1, stiffness = 70, dampening = 10 } )

-- Animations
hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default"      })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })

hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, bezier = "easeOutQuint" , style = "slidefade"     })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  bezier = "easeOutQuint",  style = "slide top 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.4,  bezier = "linear",        style = "slide top 90%" })

hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03,   bezier = "quick"         })
hl.animation({ leaf = "layers",        enabled = true,  speed = 1.4,    bezier = "quick"         })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.4,    bezier = "quick"         })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39,   bezier = "almostLinear"  })

hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "slidefade"  })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 2.2,  bezier = "almostLinear", style = "slidefade " })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 2.8,  bezier = "almostLinear", style = "fade"       })

hl.animation({ leaf = "specialWorkspace",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "slidefade"            })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true,  speed = 2.2,  bezier = "almostLinear", style = "slidefade top 80%"    })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true,  speed = 2.8,  bezier = "almostLinear", style = "slidefade bottom 90%" })

hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick"         })
