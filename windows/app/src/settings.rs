//! The settings window (SPEC 6.3, Windows): General, Targets, Advanced. Every edit goes through
//! the target catalog and is saved at once.

use browserdoor_core::{CatalogState, TargetCatalog};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_dialog::DialogExt;

use crate::app::AppState;
use crate::i18n::t;
use crate::views::{self, SettingsView};
use crate::{prefs, registry, system, tray, updates};

pub const LABEL: &str = "settings";

pub fn show(app: &AppHandle, tab: Option<&str>) {
    if let Some(window) = app.get_webview_window(LABEL) {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
        let _ = window.emit_to(LABEL, "settings-changed", ());
        if let Some(tab) = tab {
            let _ = window.emit_to(LABEL, "settings-tab", tab);
        }
        return;
    }
    let url = match tab {
        Some(tab) => format!("settings.html#{tab}"),
        None => "settings.html".to_string(),
    };
    let built = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::App(url.into()))
        .title(t("Browserdoor Settings"))
        .inner_size(640.0, 560.0)
        .min_inner_size(520.0, 420.0)
        .center()
        .transparent(true)
        .effects(tauri::window::EffectsBuilder::new().effect(tauri::window::Effect::Mica).build())
        .build();
    match built {
        Ok(window) => {
            let handle = app.clone();
            let tab = tab.map(str::to_string);
            window.on_window_event(move |event| match event {
                // Back in front: the default browser or the config may have changed meanwhile.
                WindowEvent::Focused(true) => {
                    let _ = handle.emit_to(LABEL, "settings-changed", ());
                }
                WindowEvent::Destroyed => {
                    if let Ok(mut c) = handle.state::<AppState>().catalog.lock() {
                        *c = None;
                    }
                }
                _ => {}
            });
            if let Some(tab) = tab {
                let h = app.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_millis(400));
                    let _ = h.emit_to(LABEL, "settings-tab", tab);
                });
            }
        }
        Err(e) => system::log(&format!("settings window: {e}")),
    }
}

fn env() -> system::WinEnv {
    system::WinEnv::new()
}

/// The catalog being edited; loaded fresh when the window opens or after a reload.
fn with_catalog<R>(app: &AppHandle, f: impl FnOnce(&mut CatalogState) -> R) -> R {
    let state = app.state::<AppState>();
    let mut guard = state.catalog.lock().unwrap_or_else(|e| e.into_inner());
    let env = env();
    let catalog =
        guard.get_or_insert_with(|| TargetCatalog { environment: &env, config_path: prefs::config_path() }.load());
    f(catalog)
}

fn view(app: &AppHandle, autostart_error: Option<String>) -> SettingsView {
    let state = app.state::<AppState>();
    with_catalog(app, |c| views::settings(&state, c, autostart_error))
}

/// Applies an edit and saves it.
fn edit(app: &AppHandle, f: impl FnOnce(&mut CatalogState)) -> SettingsView {
    with_catalog(app, |c| {
        f(c);
        let env = env();
        match (TargetCatalog { environment: &env, config_path: prefs::config_path() }).save(c) {
            Ok(saved) => *c = saved,
            Err(e) => system::log(&format!("saving the config failed: {e}")),
        }
    });
    view(app, None)
}

#[tauri::command]
pub fn settings_state(app: AppHandle) -> SettingsView {
    // A fresh look at the system each time the window asks (it asks when it comes to the front).
    if let Ok(mut c) = app.state::<AppState>().catalog.lock() {
        *c = None;
    }
    view(&app, None)
}

#[tauri::command]
pub fn settings_rename(app: AppHandle, id: String, name: String) -> SettingsView {
    edit(&app, |c| c.rename(&id, &name))
}

#[derive(Serialize)]
pub struct HotkeyResult {
    view: SettingsView,
    previous: Option<String>,
}

#[tauri::command]
pub fn settings_set_hotkey(app: AppHandle, id: String, typed: String) -> HotkeyResult {
    let mut previous = None;
    let view = edit(&app, |c| previous = c.set_hotkey(&id, &typed));
    HotkeyResult { view, previous }
}

#[tauri::command]
pub fn settings_set_hidden(app: AppHandle, id: String, hidden: bool) -> SettingsView {
    edit(&app, |c| c.set_hidden(&id, hidden))
}

#[tauri::command]
pub fn settings_toggle_default(app: AppHandle, id: String) -> SettingsView {
    edit(&app, |c| c.toggle_default(&id))
}

#[tauri::command]
pub fn settings_move_row(app: AppHandle, from: usize, to: usize) -> SettingsView {
    edit(&app, |c| c.move_row(from, to))
}

/// `+`: pick an `.exe` (it becomes an extra app, its path the App ID).
#[tauri::command]
pub async fn settings_add_extra_app(app: AppHandle) -> SettingsView {
    let picked = app.dialog().file().add_filter("Programs", &["exe"]).blocking_pick_file();
    match picked.and_then(|p| p.into_path().ok()) {
        Some(path) => edit(&app, |c| c.add_extra_apps(&[path.display().to_string()])),
        None => view(&app, None),
    }
}

#[tauri::command]
pub fn settings_remove_extra_app(app: AppHandle, exe: String) -> SettingsView {
    edit(&app, |c| c.remove_extra_app(&exe))
}

#[tauri::command]
pub fn settings_set_zen_profile(app: AppHandle, path: Option<String>) -> SettingsView {
    edit(&app, |c| c.set_zen_profile(path.as_deref()))
}

#[tauri::command]
pub async fn settings_pick_zen_profile(app: AppHandle) -> SettingsView {
    let start = std::env::var("APPDATA").map(|a| std::path::PathBuf::from(a).join("zen").join("Profiles")).ok();
    let mut dialog = app.dialog().file();
    if let Some(dir) = start.filter(|d| d.is_dir()) {
        dialog = dialog.set_directory(dir);
    }
    match dialog.blocking_pick_folder().and_then(|p| p.into_path().ok()) {
        Some(path) => edit(&app, |c| c.set_zen_profile(Some(&path.display().to_string()))),
        None => view(&app, None),
    }
}

#[tauri::command]
pub fn settings_reveal_config(app: AppHandle) {
    let path = prefs::config_path();
    if !path.exists() {
        // Write the current settings, so there is a file to show.
        let _ = edit(&app, |_| {});
    }
    system::reveal_in_explorer(&path.display().to_string());
}

#[tauri::command]
pub fn settings_make_default() {
    registry::open_default_apps_settings();
}

#[tauri::command]
pub fn settings_set_autostart(app: AppHandle, on: bool) -> SettingsView {
    let error = registry::set_autostart(&system::stable_exe(), on).err();
    view(&app, error)
}

#[tauri::command]
pub fn settings_set_show_in_tray(app: AppHandle, on: bool) -> SettingsView {
    if let Ok(mut p) = app.state::<AppState>().prefs.lock() {
        p.show_in_tray = on;
        p.save();
    }
    tray::refresh(&app);
    view(&app, None)
}

#[tauri::command]
pub fn settings_set_check_automatically(app: AppHandle, on: bool) -> SettingsView {
    if let Ok(mut p) = app.state::<AppState>().prefs.lock() {
        p.update.check_automatically = on;
        p.save();
    }
    view(&app, None)
}

#[tauri::command]
pub async fn settings_check_for_updates(app: AppHandle) -> SettingsView {
    updates::check(&app, true);
    view(&app, None)
}

#[tauri::command]
pub fn settings_update(app: AppHandle) {
    updates::run_update(&app);
}
