use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;

const HYPR_DIR: &str = "/home/vredix/.config/vutureland/hypr";

fn hypr_path(file: &str) -> String {
    format!("{}/{}", HYPR_DIR, file)
}

fn read_file(file: &str) -> String {
    fs::read_to_string(hypr_path(file)).unwrap_or_default()
}

fn write_file(file: &str, content: &str) -> Result<(), String> {
    fs::write(hypr_path(file), content).map_err(|e| e.to_string())
}

/// Parse `$key = value` lines from a conf string into a HashMap
fn parse_vars(content: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for line in content.lines() {
        let line = line.trim();
        if !line.starts_with('$') {
            continue;
        }
        if let Some(eq) = line.find('=') {
            let key = line[1..eq].trim().to_string();
            let val = line[eq + 1..].trim().to_string();
            // strip inline comment
            let val = val.split('#').next().unwrap_or("").trim().to_string();
            map.insert(key, val);
        }
    }
    map
}

// ─── monitors ───────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct MonitorConf {
    pub output: String,
    pub mode: String,
    pub transform: u32,
    pub position: String,
    pub scale: f64,
    pub bitdepth: u32,
    pub supports_hdr: bool,
    pub vrr: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MonitorsConf {
    pub mon1: String,
    pub mon2: Option<String>,
    pub monitors: Vec<MonitorConf>,
}

#[tauri::command]
pub fn read_monitors_conf() -> MonitorsConf {
    let content = read_file("monitors.conf");
    let vars = parse_vars(&content);
    let mon1 = vars.get("mon1").cloned().unwrap_or_default();
    let mon2 = vars.get("mon2").cloned().filter(|s| !s.is_empty());

    let mut monitors = Vec::new();
    let mut current: Option<HashMap<String, String>> = None;
    for line in content.lines() {
        let line = line.trim();
        if line == "monitorv2 {" {
            current = Some(HashMap::new());
        } else if line == "}" {
            if let Some(block) = current.take() {
                let output = block.get("output").cloned().unwrap_or_default();
                if !output.is_empty() {
                    monitors.push(MonitorConf {
                        output,
                        mode: block.get("mode").cloned().unwrap_or_default(),
                        transform: block.get("transform").and_then(|v| v.parse().ok()).unwrap_or(0),
                        position: block.get("position").cloned().unwrap_or_else(|| "0x0".to_string()),
                        scale: block.get("scale").and_then(|v| v.parse().ok()).unwrap_or(1.0),
                        bitdepth: block.get("bitdepth").and_then(|v| v.parse().ok()).unwrap_or(10),
                        supports_hdr: block.get("supports_hdr").map(|v| v == "1").unwrap_or(false),
                        vrr: block.get("vrr").map(|v| v == "on").unwrap_or(false),
                    });
                }
            }
        } else if current.is_some() {
            if let Some(eq) = line.find('=') {
                let k = line[..eq].trim().to_string();
                let v = line[eq + 1..].trim().to_string();
                current.as_mut().unwrap().insert(k, v);
            }
        }
    }

    MonitorsConf { mon1, mon2, monitors }
}

#[tauri::command]
pub fn write_monitors_conf(conf: MonitorsConf) -> Result<(), String> {
    let mut out = String::from("## = = = MONITORS = = = ##\n\n");
    out.push_str(&format!("$mon1 = {}\n", conf.mon1));
    if let Some(ref m2) = conf.mon2 {
        out.push_str(&format!("$mon2 = {}\n", m2));
    }
    for m in &conf.monitors {
        out.push('\n');
        out.push_str("monitorv2 {\n");
        out.push_str(&format!("  output        = {}\n", m.output));
        out.push_str(&format!("  mode          = {}\n", m.mode));
        out.push_str(&format!("  transform     = {}\n", m.transform));
        out.push_str(&format!("  position      = {}\n", m.position));
        out.push_str(&format!("  scale         = {}\n", m.scale));
        out.push_str(&format!("  bitdepth      = {}\n", m.bitdepth));
        out.push_str(&format!("  supports_hdr  = {}\n", if m.supports_hdr { 1 } else { 0 }));
        out.push_str(&format!("  vrr           = {}\n", if m.vrr { "on" } else { "off" }));
        out.push_str("  cm            = auto\n}\n");
    }
    write_file("monitors.conf", &out)
}

// ─── peripherals ────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct PeripheralsConf {
    pub cur_theme: String,
    pub cur_size: u32,
    pub fn_brightness_up: String,
    pub fn_brightness_down: String,
    pub fn_play_stop_play: String,
    pub fn_play_next: String,
    pub fn_play_prev: String,
    pub fn_volume_up: String,
    pub fn_volume_down: String,
    pub fn_volume_mute: String,
}

#[tauri::command]
pub fn read_peripherals_conf() -> PeripheralsConf {
    let v = parse_vars(&read_file("peripherals.conf"));
    PeripheralsConf {
        cur_theme: v.get("cur_theme").cloned().unwrap_or_else(|| "oxygen".into()),
        cur_size: v.get("cur_size").and_then(|x| x.parse().ok()).unwrap_or(20),
        fn_brightness_up: v.get("fn_brightness_up").cloned().unwrap_or_else(|| "F2".into()),
        fn_brightness_down: v.get("fn_brighness_down").cloned().unwrap_or_else(|| "F1".into()),
        fn_play_stop_play: v.get("fn_play_stop_play").cloned().unwrap_or_else(|| "F8".into()),
        fn_play_next: v.get("fn_play_next").cloned().unwrap_or_else(|| "F9".into()),
        fn_play_prev: v.get("fn_play_prev").cloned().unwrap_or_else(|| "F7".into()),
        fn_volume_up: v.get("fn_volume_up").cloned().unwrap_or_else(|| "F12".into()),
        fn_volume_down: v.get("fn_volume_down").cloned().unwrap_or_else(|| "F11".into()),
        fn_volume_mute: v.get("fn_volume_mute").cloned().unwrap_or_else(|| "F10".into()),
    }
}

#[tauri::command]
pub fn write_peripherals_conf(conf: PeripheralsConf) -> Result<(), String> {
    let out = format!(
        "## = = = PERIPHERALS = = = ##\n\n\
         # Cursor\n\
         $cur_theme = {}\n\
         $cur_size  = {}\n\n\
         # FN Keys\n\
         $fn_brightness_up  = {}\n\
         $fn_brighness_down = {}\n\
         $fn_play_stop_play = {}\n\
         $fn_play_next      = {}\n\
         $fn_play_prev      = {}\n\
         $fn_volume_up      = {}\n\
         $fn_volume_down    = {}\n\
         $fn_volume_mute    = {}\n",
        conf.cur_theme, conf.cur_size,
        conf.fn_brightness_up, conf.fn_brightness_down,
        conf.fn_play_stop_play, conf.fn_play_next, conf.fn_play_prev,
        conf.fn_volume_up, conf.fn_volume_down, conf.fn_volume_mute,
    );
    write_file("peripherals.conf", &out)
}

// ─── workspaces ─────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct WorkspaceEntry {
    pub num: u32,
    pub monitor: String,
    pub persistent: bool,
    pub default: bool,
}

#[tauri::command]
pub fn read_workspaces_conf() -> Vec<WorkspaceEntry> {
    let content = read_file("workspaces.conf");
    let mut entries = Vec::new();
    for line in content.lines() {
        let line = line.trim();
        if !line.starts_with("workspace") {
            continue;
        }
        let parts: Vec<&str> = line.splitn(2, '=').collect();
        if parts.len() < 2 {
            continue;
        }
        let rest = parts[1];
        let fields: Vec<&str> = rest.split(',').map(|s| s.trim()).collect();
        if fields.is_empty() {
            continue;
        }
        let num: u32 = fields[0].trim().parse().unwrap_or(0);
        let monitor = fields.iter()
            .find(|f| f.starts_with("monitor:"))
            .map(|f| f["monitor:".len()..].to_string())
            .unwrap_or_default();
        let persistent = fields.iter().any(|f| *f == "persistent:true");
        let default = fields.iter().any(|f| *f == "default:true");
        entries.push(WorkspaceEntry { num, monitor, persistent, default });
    }
    entries.sort_by_key(|e| e.num);
    entries
}

#[tauri::command]
pub fn write_workspace(entry: WorkspaceEntry) -> Result<(), String> {
    let mut entries = read_workspaces_conf();
    if let Some(existing) = entries.iter_mut().find(|e| e.num == entry.num) {
        *existing = entry;
    } else {
        entries.push(entry);
        entries.sort_by_key(|e| e.num);
    }
    flush_workspaces(&entries)
}

#[tauri::command]
pub fn remove_workspace(num: u32) -> Result<(), String> {
    let entries: Vec<WorkspaceEntry> = read_workspaces_conf()
        .into_iter()
        .filter(|e| e.num != num)
        .collect();
    flush_workspaces(&entries)
}

fn flush_workspaces(entries: &[WorkspaceEntry]) -> Result<(), String> {
    let mut out = String::from("## = = = WORKSPACES = = = ##\n\n");
    let mut prev_mon = String::new();
    for e in entries {
        if e.monitor != prev_mon {
            if !prev_mon.is_empty() {
                out.push('\n');
            }
            out.push_str(&format!("# {}\n", e.monitor));
            prev_mon = e.monitor.clone();
        }
        let mut line = format!("workspace = {},  monitor:{}, persistent:{}", e.num, e.monitor,
                               if e.persistent { "true" } else { "false" });
        if e.default {
            line.push_str(", default:true");
        }
        out.push_str(&line);
        out.push('\n');
    }
    write_file("workspaces.conf", &out)
}

// ─── variables ──────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct VariablesConf {
    pub desktop_shell: String,
    pub notify_service: String,
    pub launcher: String,
    pub theme_switch: String,
    pub terminal: String,
    pub notifications: String,
    pub screenshot: String,
    pub on_sleep: String,
    pub on_lock: String,
    pub session_menu: String,
}

#[tauri::command]
pub fn read_variables_conf() -> VariablesConf {
    let v = parse_vars(&read_file("variables.conf"));
    VariablesConf {
        desktop_shell: v.get("desktop_shell").cloned().unwrap_or_default(),
        notify_service: v.get("notify_service").cloned().unwrap_or_default(),
        launcher: v.get("launcher").cloned().unwrap_or_default(),
        theme_switch: v.get("theme_switch").cloned().unwrap_or_default(),
        terminal: v.get("terminal").cloned().unwrap_or_default(),
        notifications: v.get("notifications").cloned().unwrap_or_default(),
        screenshot: v.get("screenshot").cloned().unwrap_or_default(),
        on_sleep: v.get("on_sleep").cloned().unwrap_or_default(),
        on_lock: v.get("on_lock").cloned().unwrap_or_default(),
        session_menu: v.get("session_menu").cloned().unwrap_or_default(),
    }
}

#[tauri::command]
pub fn write_variables_conf(conf: VariablesConf) -> Result<(), String> {
    let out = format!(
        "## = = = APPLICATION VARIABLES = = = ##\n\n\
         $desktop_shell = {}\n\
         $notify_service = {}\n\n\
         $launcher      = {}\n\
         $theme_switch  = {}\n\
         $terminal      = {}\n\
         $notifications = {}\n\
         $screenshot    = {}\n\n\
         $on_sleep      = {}\n\
         $on_lock       = {}\n\
         $session_menu  = {}\n",
        conf.desktop_shell, conf.notify_service,
        conf.launcher, conf.theme_switch, conf.terminal,
        conf.notifications, conf.screenshot,
        conf.on_sleep, conf.on_lock, conf.session_menu,
    );
    write_file("variables.conf", &out)
}

// ─── autostart ──────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct AutostartConf {
    pub daemons: Vec<String>,
    pub scripts: Vec<String>,
    pub apps: Vec<String>,
    pub app_workspaces: Vec<u32>,
}

#[tauri::command]
pub fn read_autostart_conf() -> AutostartConf {
    let content = read_file("autostart.conf");
    let vars = parse_vars(&content);
    let mut daemons = Vec::new();
    let mut scripts = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        if let Some(cmd) = line.strip_prefix("exec-once = ") {
            if cmd.contains("sleep") && cmd.contains("&&") {
                scripts.push(cmd.to_string());
            } else {
                daemons.push(cmd.to_string());
            }
        }
    }

    let mut apps = Vec::new();
    let mut app_workspaces = Vec::new();
    for i in 1..=10 {
        apps.push(vars.get(&format!("start_app{}", i)).cloned().unwrap_or_default());
        app_workspaces.push(
            vars.get(&format!("start_app{}_ws", i))
                .and_then(|v| v.parse().ok())
                .unwrap_or(i as u32),
        );
    }

    AutostartConf { daemons, scripts, apps, app_workspaces }
}

#[tauri::command]
pub fn write_autostart_conf(conf: AutostartConf) -> Result<(), String> {
    let mut out = String::from("## = = = AUTOSTART = = = ##\n\n# Daemons\n");
    for d in &conf.daemons {
        out.push_str(&format!("exec-once = {}\n", d));
    }
    out.push_str("\n# Scripts\n");
    for s in &conf.scripts {
        out.push_str(&format!("exec-once = {}\n", s));
    }
    out.push_str("\n# Workspace apps\n");
    for (i, (app, ws)) in conf.apps.iter().zip(conf.app_workspaces.iter()).enumerate() {
        let n = i + 1;
        out.push_str(&format!("$start_app{}    = {}\n", n, app));
        out.push_str(&format!("$start_app{}_ws = {}\n", n, ws));
    }
    write_file("autostart.conf", &out)
}

// ─── quickaccess ────────────────────────────────────────────────────────────

#[tauri::command]
pub fn read_quickaccess_conf() -> Vec<String> {
    let v = parse_vars(&read_file("quickaccess.conf"));
    (1..=10)
        .map(|i| v.get(&format!("quick_app{}", i)).cloned().unwrap_or_default())
        .collect()
}

#[tauri::command]
pub fn write_quickaccess_conf(apps: Vec<String>) -> Result<(), String> {
    let mut out = String::from("## = = = QUICK ACCESS = = = ##\n\n");
    for (i, app) in apps.iter().enumerate() {
        out.push_str(&format!("$quick_app{} = {}\n", i + 1, app));
    }
    write_file("quickaccess.conf", &out)
}

// ─── windowrules ────────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct WindowrulesConf {
    pub floating_window: String,
    pub opacity_window: String,
}

#[tauri::command]
pub fn read_windowrules_conf() -> WindowrulesConf {
    let v = parse_vars(&read_file("windowrules.conf"));
    WindowrulesConf {
        floating_window: v.get("floating_window").cloned().unwrap_or_default(),
        opacity_window: v.get("opacity_window").cloned().unwrap_or_default(),
    }
}

#[tauri::command]
pub fn write_windowrules_conf(conf: WindowrulesConf) -> Result<(), String> {
    let out = format!(
        "## = = = WINDOW RULE VARIABLES = = = ##\n\n\
         $floating_window = {}\n\
         $opacity_window  = {}\n",
        conf.floating_window, conf.opacity_window,
    );
    write_file("windowrules.conf", &out)
}
