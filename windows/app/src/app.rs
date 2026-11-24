//! Startup: what a launch does before any window (SPEC 8, Windows), and the resident instance.

use std::sync::Mutex;

use browserdoor_core::{TargetCatalog, listing, url_policy};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

use crate::{i18n::t, icons, ipc, picker, prefs, registry, settings, system, tray, updates};

/// What a launch hands the resident instance.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Launch {
    /// Links from the command line, already filtered by the URL policy.
    pub links: Vec<String>,
    /// Started at login (`--background`): no window.
    pub background: bool,
    /// `--quit`: the resident instance should end (uninstall, update).
    pub quit: bool,
}

pub struct AppState {
    pub picker: Mutex<picker::PickerState>,
    pub catalog: Mutex<Option<browserdoor_core::CatalogState>>,
    pub prefs: Mutex<prefs::Prefs>,
    pub update: Mutex<updates::Status>,
    pub icons: icons::IconCache,
}

pub fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let flag = |f: &str| args.iter().any(|a| a.eq_ignore_ascii_case(f));

    if flag("--list-targets") {
        system::attach_console();
        let env = system::WinEnv::new();
        let state = TargetCatalog { environment: &env, config_path: prefs::config_path() }.load();
        println!("{}", listing::listing(&state, &|exe| system::is_running(exe)));
        return;
    }
    if flag("--unregister") {
        // Scoop's uninstaller: end the resident instance, then remove what Browserdoor registered.
        let _ = ipc::forward(&Launch { quit: true, ..Default::default() });
        registry::unregister();
        return;
    }

    let launch = Launch {
        links: args.iter().filter_map(|a| url_policy::link_from_argument(a)).collect(),
        background: flag("--background"),
        quit: flag("--quit"),
    };
    let Some(server) = ipc::claim(&launch) else { return };
    if launch.quit {
        return;
    }
    run(server, launch);
}

fn run(server: ipc::Server, first: Launch) {
    let prefs = prefs::Prefs::load();
    let state = AppState {
        picker: Mutex::new(picker::PickerState::default()),
        catalog: Mutex::new(None),
        prefs: Mutex::new(prefs),
        update: Mutex::new(updates::Status::Idle),
        icons: icons::IconCache::default(),
    };
    let result = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            picker::picker_state,
            picker::picker_input,
            picker::picker_resize,
            settings::settings_state,
            settings::settings_rename,
            settings::settings_set_hotkey,
            settings::settings_set_hidden,
            settings::settings_toggle_default,
            settings::settings_move_row,
            settings::settings_add_extra_app,
            settings::settings_remove_extra_app,
            settings::settings_set_zen_profile,
            settings::settings_pick_zen_profile,
            settings::settings_reveal_config,
            settings::settings_make_default,
            settings::settings_set_autostart,
            settings::settings_set_show_in_tray,
            settings::settings_set_check_automatically,
            settings::settings_check_for_updates,
            settings::settings_update,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            startup(&handle);
            picker::create_window(&handle)?;
            tray::create(&handle)?;
            let h = handle.clone();
            server.serve(move |launch| {
                let h2 = h.clone();
                let _ = h.run_on_main_thread(move || handle_launch(&h2, launch));
            });
            handle_launch(&handle, first.clone());
            updates::schedule(&handle);
            Ok(())
        })
        .build(tauri::generate_context!());
    match result {
        Ok(app) => app.run(|_, event| {
            // The resident instance stays when its windows close.
            if let tauri::RunEvent::ExitRequested { api, code: None, .. } = event {
                api.prevent_exit();
            }
        }),
        Err(e) => system::fatal(&format!("Browserdoor could not start: {e}")),
    }
}

/// Every launch of the resident instance (SPEC 8.1, Windows): keep the registration pointing at
/// the stable path, and on the first launch turn on autostart and offer the default browser.
fn startup(app: &AppHandle) {
    let exe = system::stable_exe();
    if system::is_release_build() {
        registry::register(&exe);
    }
    let state = app.state::<AppState>();
    let first = {
        let mut prefs = state.prefs.lock().unwrap_or_else(|e| e.into_inner());
        let first = !prefs.onboarded;
        if first {
            prefs.onboarded = true;
            prefs.save();
        }
        first
    };
    if first && system::is_release_build() {
        let _ = registry::set_autostart(&exe, true);
        if !registry::is_default_browser() {
            use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
            let h = app.clone();
            app.dialog()
                .message(t("Browserdoor shows a picker for every link you click. Choose Browserdoor as your default browser in the Windows settings that open next."))
                .title(t("Make Browserdoor your default browser?"))
                .buttons(MessageDialogButtons::OkCancelCustom(t("Open Settings"), t("Not Now")))
                .show(move |ok| {
                    if ok {
                        registry::open_default_apps_settings();
                    }
                    tray::refresh(&h);
                });
        }
    }
}

/// A launch that reached the resident instance: links open the picker, a plain start shows the
/// settings (SPEC 6.3), `--quit` ends it.
pub fn handle_launch(app: &AppHandle, launch: Launch) {
    if launch.quit {
        app.exit(0);
        return;
    }
    if !launch.links.is_empty() {
        picker::present(app, launch.links);
    } else if !launch.background {
        settings::show(app, None);
    }
}
