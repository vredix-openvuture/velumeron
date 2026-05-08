use serde::{Deserialize, Serialize};
use std::process::Command;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct MonitorInfo {
    pub name: String,
    pub description: String,
    pub width: u32,
    pub height: u32,
    #[serde(rename = "refreshRate")]
    pub refresh_rate: f64,
    pub x: i32,
    pub y: i32,
    pub scale: f64,
    pub transform: u32,
    pub focused: bool,
    pub vrr: bool,
    #[serde(rename = "availableModes")]
    pub available_modes: Vec<String>,
}

#[tauri::command]
pub fn get_monitors() -> Result<Vec<MonitorInfo>, String> {
    let out = Command::new("hyprctl")
        .args(["monitors", "-j"])
        .output()
        .map_err(|e| e.to_string())?;
    serde_json::from_slice(&out.stdout).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn get_cursor_themes() -> Vec<String> {
    let base = std::path::Path::new("/usr/share/icons");
    let mut themes = Vec::new();
    if let Ok(entries) = std::fs::read_dir(base) {
        for entry in entries.flatten() {
            let cursor_dir = entry.path().join("cursors");
            if cursor_dir.is_dir() {
                if let Some(name) = entry.file_name().to_str() {
                    themes.push(name.to_string());
                }
            }
        }
    }
    themes.sort();
    themes
}

#[tauri::command]
pub fn hypr_keyword(keyword: String, value: String) -> Result<(), String> {
    let out = Command::new("hyprctl")
        .args(["keyword", &keyword, &value])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).to_string())
    }
}

#[tauri::command]
pub fn hypr_reload() -> Result<(), String> {
    Command::new("hyprctl")
        .arg("reload")
        .output()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn hypr_set_cursor(theme: String, size: u32) -> Result<(), String> {
    Command::new("hyprctl")
        .args(["setcursor", &theme, &size.to_string()])
        .output()
        .map_err(|e| e.to_string())?;
    Ok(())
}
