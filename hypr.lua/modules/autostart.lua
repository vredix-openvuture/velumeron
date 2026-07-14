-- ═══════════════════════════════════════════════════════
-- Autostart
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- ═══════════════════════════════════════════════════════

hl.on("hyprland.start", function()

    -- First-boot auto-config: if no monitor has been configured yet (the setup
    -- was never run, so user_settings.lua has no hl.monitor), detect the primary
    -- monitor and assign it scale 1 / best resolution / position 0x0 plus
    -- persistent workspaces 1–5 (ws 1 = default). Writes user_settings.lua and
    -- reloads, so it only runs once — no need to run the setup manually.
    do
        local us = VTL_USER_DIR .. "/hypr.lua/user_settings.lua"
        local configured = false
        local f = io.open(us, "r")
        if f then
            local content = f:read("*a"); f:close()
            if content:find("hl%.monitor") then configured = true end
        end
        if not configured then
            hl.exec_cmd("bash " .. VTL_DIR .. "/.setup/hyprland.sh --autostart")
        end
    end

    -- Initialize submap state tracker
    hl.exec_cmd("echo 'normal' > /tmp/hypr-submap")

    -- ── Device-specific daemons (from user_settings) ──
    for _, cmd in ipairs(exec_once_daemons) do
        if cmd ~= "" then
            hl.exec_cmd(cmd)
        end
    end

    -- ── Cursor, then all Velumeron services ───────────
    -- Every daemon we own (hypridle, nm-applet, hyprpolkitagent, gnome-keyring,
    -- brightness, clipvault, float-cascade) AND the QuickShell shell are started
    -- by one script — the same single source of truth that `velumeron start` /
    -- `velumeron end` drive, so autostart and the CLI can never drift.
    -- (awww-daemon/swaync/Python notify+OSD are retired; wallpapers, notifications
    -- and the OSD are native to quickshell now.)
    hl.exec_cmd("hyprctl setcursor " .. cur_theme .. " " .. tostring(cur_size))
    hl.exec_cmd(VTL_DIR .. "/assets/scripts/velumeron-services.sh start")

    -- The GTK portal backend (xdg-desktop-portal-gtk) draws the file-chooser dialogs that GTK4
    -- apps (zenity → the wallpaper folder picker) delegate to. Activated this early it can cache a
    -- light look before the theme settles and then open every dialog light. Bounce it once the
    -- session is up so its dialogs match the current dark/light mode.
    hl.exec_cmd("bash -c 'sleep 5; " .. VTL_DIR .. "/assets/scripts/apply-app-theme.sh refresh-portals'")

    -- ── Workspace startup apps (from user_settings) ───
    for _, item in ipairs(start_apps) do
        if item.app ~= "" then
            hl.exec_cmd("[workspace " .. tostring(item.ws) .. " silent] " .. item.app)
        end
    end

end)
