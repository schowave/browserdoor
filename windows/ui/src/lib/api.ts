// The data the Rust side hands the windows, and the commands they call. Mirrors
// windows/app/src/views.rs; the domain lives in windows/core.
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export interface Rgb {
  r: number;
  g: number;
  b: number;
}

/** What a target shows as its icon: the app's icon, or for a Zen space its emoji or initial on its color. */
export interface TargetIconView {
  image: string | null;
  emoji: string | null;
  initial: string | null;
  color: Rgb | null;
  badge: { letter: string; color: Rgb } | null;
}

export interface LinkView {
  primary: string;
  secondary: string;
  line: string;
}

export interface PickerEntryView {
  id: string;
  label: string;
  hotkey: string | null;
  icon: TargetIconView;
}

export interface PickerView {
  links: LinkView[];
  entries: PickerEntryView[];
  selection: number;
  defaultRow: number | null;
  copied: boolean;
  configUnreadable: boolean;
  accent: string;
}

export interface TargetRowView {
  id: string;
  name: string;
  label: string | null;
  displayName: string;
  hotkey: string | null;
  effectiveKey: string | null;
  hidden: boolean;
  isDefault: boolean;
  extraApp: string | null;
  icon: TargetIconView;
}

export type UpdateStatus =
  | { kind: "idle" }
  | { kind: "checking" }
  | { kind: "upToDate" }
  | { kind: "available"; version: string; url: string }
  | { kind: "failed"; message: string };

export interface SettingsView {
  version: string;
  isDefaultBrowser: boolean;
  autostart: boolean;
  autostartError: string | null;
  showInTray: boolean;
  checkAutomatically: boolean;
  update: UpdateStatus;
  rows: TargetRowView[];
  unlistedExtraApps: { exe: string; name: string }[];
  zenProfilePath: string | null;
  configPath: string;
  configUnreadable: boolean;
  accent: string;
}

export type PickerInput =
  | { type: "key"; key: string; ctrl: boolean; alt: boolean; shift: boolean; meta: boolean }
  | { type: "click"; row: number }
  | { type: "hover"; row: number; x: number; y: number }
  | { type: "copyButton" }
  | { type: "settingsButton" };

export const picker = {
  state: () => invoke<PickerView | null>("picker_state"),
  input: (input: PickerInput) => invoke<PickerView | null>("picker_input", { input }),
  resize: (height: number) => invoke<void>("picker_resize", { height }),
  onState: (f: (v: PickerView) => void): Promise<UnlistenFn> => listen<PickerView>("picker-state", (e) => f(e.payload)),
};

export interface HotkeyResult {
  view: SettingsView;
  previous: string | null;
}

export const settings = {
  state: () => invoke<SettingsView>("settings_state"),
  rename: (id: string, name: string) => invoke<SettingsView>("settings_rename", { id, name }),
  setHotkey: (id: string, typed: string) => invoke<HotkeyResult>("settings_set_hotkey", { id, typed }),
  setHidden: (id: string, hidden: boolean) => invoke<SettingsView>("settings_set_hidden", { id, hidden }),
  toggleDefault: (id: string) => invoke<SettingsView>("settings_toggle_default", { id }),
  moveRow: (from: number, to: number) => invoke<SettingsView>("settings_move_row", { from, to }),
  addExtraApp: () => invoke<SettingsView>("settings_add_extra_app"),
  removeExtraApp: (exe: string) => invoke<SettingsView>("settings_remove_extra_app", { exe }),
  setZenProfile: (path: string | null) => invoke<SettingsView>("settings_set_zen_profile", { path }),
  pickZenProfile: () => invoke<SettingsView>("settings_pick_zen_profile"),
  revealConfig: () => invoke<void>("settings_reveal_config"),
  makeDefault: () => invoke<void>("settings_make_default"),
  setAutostart: (on: boolean) => invoke<SettingsView>("settings_set_autostart", { on }),
  setShowInTray: (on: boolean) => invoke<SettingsView>("settings_set_show_in_tray", { on }),
  setCheckAutomatically: (on: boolean) => invoke<SettingsView>("settings_set_check_automatically", { on }),
  checkForUpdates: () => invoke<SettingsView>("settings_check_for_updates"),
  update: () => invoke<void>("settings_update"),
  onChanged: (f: () => void): Promise<UnlistenFn> => listen("settings-changed", () => f()),
  onShowTab: (f: (tab: string) => void): Promise<UnlistenFn> => listen<string>("settings-tab", (e) => f(e.payload)),
};

export function css(c: Rgb): string {
  return `rgb(${c.r} ${c.g} ${c.b})`;
}

/** Text on a color: black or white, whichever reads better. */
export function onColor(c: Rgb): string {
  return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b > 160 ? "#000" : "#fff";
}
