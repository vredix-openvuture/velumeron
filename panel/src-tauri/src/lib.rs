mod config;
mod hypr;

use config::*;
use hypr::*;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            get_monitors,
            get_cursor_themes,
            hypr_keyword,
            hypr_reload,
            hypr_set_cursor,
            read_monitors_conf,
            write_monitors_conf,
            read_peripherals_conf,
            write_peripherals_conf,
            read_workspaces_conf,
            write_workspace,
            remove_workspace,
            read_variables_conf,
            write_variables_conf,
            read_autostart_conf,
            write_autostart_conf,
            read_quickaccess_conf,
            write_quickaccess_conf,
            read_windowrules_conf,
            write_windowrules_conf,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
