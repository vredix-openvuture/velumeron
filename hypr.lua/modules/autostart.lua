-- ═══════════════════════════════════════════════════════
-- Autostart
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- ═══════════════════════════════════════════════════════

hl.on("hyprland.start", function()

    -- Initialize submap state tracker
    hl.exec_cmd("echo 'normal' > /tmp/hypr-submap")

    -- ── System daemons ────────────────────────────────
    hl.exec_cmd("hypridle")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("nextcloud --background")
    hl.exec_cmd("localsend --hidden")
    hl.exec_cmd("swaync")
    hl.exec_cmd("~/.config/vutureland/assets/scripts/float-cascade.sh")

    -- ── Device-specific daemons (from user_settings) ──
    for _, cmd in ipairs(exec_once_daemons) do
        if cmd ~= "" then
            hl.exec_cmd(cmd)
        end
    end

    -- ── Cursor and shell ──────────────────────────────
    hl.exec_cmd("hyprctl setcursor " .. cur_theme .. " " .. tostring(cur_size))
    hl.exec_cmd(desktop_shell)

    -- ── Workspace startup apps (from user_settings) ───
    for _, item in ipairs(start_apps) do
        if item.app ~= "" then
            hl.exec_cmd("[workspace " .. tostring(item.ws) .. " silent] " .. item.app)
        end
    end

end)
