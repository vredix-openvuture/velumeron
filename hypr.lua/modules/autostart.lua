-- ═══════════════════════════════════════════════════════
-- Autostart
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- ═══════════════════════════════════════════════════════

hl.on("hyprland.start", function()

    -- Initialize submap state tracker
    hl.exec_cmd("echo 'normal' > /tmp/hypr-submap")

    -- ── System daemons ────────────────────────────────
    hl.exec_cmd("hypridle -c " .. VTL_DIR .. "/hypr.lua/hypridle.conf")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("nm-applet")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("swaync -c " .. VTL_DIR .. "/swaync/config.json -s " .. VTL_DIR .. "/swaync/style.css")
    hl.exec_cmd("wl-paste --watch clipvault store")
    hl.exec_cmd(VTL_DIR .. "/assets/scripts/float-cascade.sh")

    hl.exec_cmd("[workspace 99 silent] kitty --class no_float -e btop")


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
