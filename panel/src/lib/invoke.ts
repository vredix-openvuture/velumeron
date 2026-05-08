import { invoke as tauriInvoke } from '@tauri-apps/api/core';

export const invoke = tauriInvoke;

export interface MonitorInfo {
  name: string;
  description: string;
  width: number;
  height: number;
  refreshRate: number;
  x: number;
  y: number;
  scale: number;
  transform: number;
  focused: boolean;
  vrr: boolean;
  availableModes: string[];
}

export interface MonitorConf {
  output: string;
  mode: string;
  transform: number;
  position: string;
  scale: number;
  bitdepth: number;
  supports_hdr: boolean;
  vrr: boolean;
}

export interface MonitorsConf {
  mon1: string;
  mon2: string | null;
  monitors: MonitorConf[];
}

export interface PeripheralsConf {
  cur_theme: string;
  cur_size: number;
  fn_brightness_up: string;
  fn_brightness_down: string;
  fn_play_stop_play: string;
  fn_play_next: string;
  fn_play_prev: string;
  fn_volume_up: string;
  fn_volume_down: string;
  fn_volume_mute: string;
}

export interface WorkspaceEntry {
  num: number;
  monitor: string;
  persistent: boolean;
  default: boolean;
}

export interface VariablesConf {
  desktop_shell: string;
  notify_service: string;
  launcher: string;
  theme_switch: string;
  terminal: string;
  notifications: string;
  screenshot: string;
  on_sleep: string;
  on_lock: string;
  session_menu: string;
}

export interface AutostartConf {
  daemons: string[];
  scripts: string[];
  apps: string[];
  app_workspaces: number[];
}

export interface WindowrulesConf {
  floating_window: string;
  opacity_window: string;
}
