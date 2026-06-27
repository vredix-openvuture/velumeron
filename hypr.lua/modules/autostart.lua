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

    -- ── System daemons ────────────────────────────────
    -- hypridle reads ~/.config/hypr/hypridle.conf (symlink seeded by setup);
    -- older versions also accepted -c <path> but some recent builds ignore it.
    hl.exec_cmd("hypridle")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd(VTL_DIR .. "/bin/vutureland --notify --daemon")
    hl.exec_cmd(VTL_DIR .. "/assets/scripts/launch-osd.sh")
    hl.exec_cmd(VTL_DIR .. "/assets/scripts/brightness.sh warm")
    hl.exec_cmd("wl-paste --watch clipvault store")
    hl.exec_cmd(VTL_DIR .. "/assets/scripts/float-cascade.sh")


    -- ── Device-specific daemons (from user_settings) ──
    for _, cmd in ipairs(exec_once_daemons) do
        if cmd ~= "" then
            hl.exec_cmd(cmd)
        end
    end

    -- ── Cursor and shell ──────────────────────────────
    hl.exec_cmd("hyprctl setcursor " .. cur_theme .. " " .. tostring(cur_size))
    hl.exec_cmd(desktop_shell)
    hl.exec_cmd(VTL_DIR .. "/bin/vutureland --daemon")

    -- ── Workspace startup apps (from user_settings) ───
    for _, item in ipairs(start_apps) do
        if item.app ~= "" then
            hl.exec_cmd("[workspace " .. tostring(item.ws) .. " silent] " .. item.app)
        end
    end

end)
