//! The tray icon and its menu (SPEC 6.1/6.2, Windows): a door, with a dot while Browserdoor isn't
//! the default browser; white or dark to match the taskbar. The menu is rebuilt from cheap queries
//! when the pointer reaches the icon, every 60 s and after actions.

use std::time::Duration;

use browserdoor_core::{links, url_policy};
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{TrayIcon, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;

use crate::app::AppState;
use crate::i18n::{t, tv};
use crate::{picker, registry, settings, system, updates};

const ID: &str = "browserdoor";

fn icon(is_default: bool) -> Option<Image<'static>> {
    let bytes: &'static [u8] = match (registry::taskbar_is_light(), is_default) {
        (false, true) => include_bytes!("../icons/tray-dark.png"),
        (false, false) => include_bytes!("../icons/tray-dark-dot.png"),
        (true, true) => include_bytes!("../icons/tray-light.png"),
        (true, false) => include_bytes!("../icons/tray-light-dot.png"),
    };
    Image::from_bytes(bytes).ok()
}

fn menu(app: &AppHandle, is_default: bool) -> tauri::Result<Menu<tauri::Wry>> {
    let status = app.state::<AppState>().update.lock().map(|s| s.clone()).unwrap_or(updates::Status::Idle);
    let menu = Menu::new(app)?;
    menu.append(&MenuItem::with_id(app, "about", t("About Browserdoor"), true, None::<&str>)?)?;
    menu.append(&PredefinedMenuItem::separator(app)?)?;
    menu.append(&MenuItem::with_id(app, "clipboard", t("Open Link from Clipboard…"), true, None::<&str>)?)?;
    if !is_default {
        menu.append(&MenuItem::with_id(
            app,
            "default",
            format!("⚠ {}", t("Make Default Browser…")),
            true,
            None::<&str>,
        )?)?;
    }
    let update_label = match &status {
        updates::Status::Available { version, .. } => format!("Update to Browserdoor {version}…"),
        _ => t("Check for Updates…"),
    };
    menu.append(&MenuItem::with_id(app, "update", update_label, status != updates::Status::Checking, None::<&str>)?)?;
    menu.append(&MenuItem::with_id(app, "settings", t("Settings…"), true, None::<&str>)?)?;
    menu.append(&PredefinedMenuItem::separator(app)?)?;
    menu.append(&MenuItem::with_id(app, "quit", t("Quit Browserdoor"), true, None::<&str>)?)?;
    Ok(menu)
}

pub fn create(app: &AppHandle) -> tauri::Result<()> {
    let is_default = registry::is_default_browser();
    let mut builder = TrayIconBuilder::with_id(ID)
        .tooltip(tooltip(is_default))
        .menu(&menu(app, is_default)?)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| on_menu(app, event.id().as_ref()))
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Enter { .. } = event {
                refresh(tray.app_handle());
            }
        });
    if let Some(i) = icon(is_default) {
        builder = builder.icon(i);
    }
    let tray: TrayIcon = builder.build(app)?;
    let visible = app.state::<AppState>().prefs.lock().map(|p| p.show_in_tray).unwrap_or(true);
    let _ = tray.set_visible(visible);
    let h = app.clone();
    std::thread::spawn(move || {
        loop {
            std::thread::sleep(Duration::from_secs(60));
            let h2 = h.clone();
            let _ = h.run_on_main_thread(move || refresh(&h2));
        }
    });
    Ok(())
}

fn tooltip(is_default: bool) -> String {
    if is_default { "Browserdoor".to_string() } else { t("Browserdoor – not the default browser") }
}

/// Rebuilds icon, tooltip and menu, and shows or hides the icon per the setting.
pub fn refresh(app: &AppHandle) {
    let Some(tray) = app.tray_by_id(ID) else { return };
    let is_default = registry::is_default_browser();
    let _ = tray.set_icon(icon(is_default));
    let _ = tray.set_tooltip(Some(tooltip(is_default)));
    if let Ok(m) = menu(app, is_default) {
        let _ = tray.set_menu(Some(m));
    }
    let visible = app.state::<AppState>().prefs.lock().map(|p| p.show_in_tray).unwrap_or(true);
    let _ = tray.set_visible(visible);
}

fn on_menu(app: &AppHandle, id: &str) {
    match id {
        "about" => {
            let text = format!(
                "{}\n\n{}\n\nhttps://github.com/schowave/browserdoor\nMIT License",
                tv("Version {v}", system::version()),
                t("A link picker for Zen spaces, browser profiles and browsers.")
            );
            app.dialog().message(text).title("Browserdoor").show(|_| {});
        }
        "clipboard" => {
            let text = app.clipboard().read_text().unwrap_or_default();
            let found: Vec<String> =
                links::urls_in_text(&text).into_iter().filter(|l| url_policy::is_allowed(l)).collect();
            if found.is_empty() {
                app.dialog().message(t("The clipboard holds no web link.")).title("Browserdoor").show(|_| {});
            } else {
                picker::present(app, found);
            }
        }
        "default" => registry::open_default_apps_settings(),
        "update" => {
            let available = matches!(
                app.state::<AppState>().update.lock().map(|s| s.clone()),
                Ok(updates::Status::Available { .. })
            );
            if available {
                updates::run_update(app);
            } else {
                let h = app.clone();
                std::thread::spawn(move || updates::check(&h, true));
            }
        }
        "settings" => settings::show(app, None),
        "quit" => app.exit(0),
        _ => {}
    }
}
