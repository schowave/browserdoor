//! Update check of the Scoop build (SPEC 7, Windows): once a day while enabled, and when asked.
//! The newest version is the one in the Scoop manifest; "Update" quits Browserdoor, runs
//! `scoop update browserdoor` in a terminal window and starts it again.

use std::os::windows::process::CommandExt;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use browserdoor_core::update::{self, AppVersion};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
use windows_sys::Win32::System::Threading::CREATE_NEW_CONSOLE;

use crate::app::AppState;
use crate::i18n::{t, tv};
use crate::{settings, system, tray};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Status {
    Idle,
    Checking,
    UpToDate,
    Available { version: String, url: String },
    Failed { message: String },
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn fetch_latest() -> Result<AppVersion, String> {
    let agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(15)))
        .user_agent(format!("Browserdoor/{} (Windows)", system::version()))
        .tls_config(
            ureq::tls::TlsConfig::builder()
                .provider(ureq::tls::TlsProvider::NativeTls)
                .root_certs(ureq::tls::RootCerts::PlatformVerifier)
                .build(),
        )
        .build()
        .new_agent();
    let body = agent
        .get(update::MANIFEST_URL)
        .call()
        .map_err(|e| e.to_string())?
        .body_mut()
        .read_to_vec()
        .map_err(|e| e.to_string())?;
    update::manifest_version(&body).ok_or_else(|| "unexpected manifest".to_string())
}

/// Runs a check; `manual` reports every result, an automatic check only a new version the
/// user hasn't put off. Blocks for the network request: call it off the main thread.
pub fn check(app: &AppHandle, manual: bool) {
    let state = app.state::<AppState>();
    let previous = state.update.lock().map(|s| s.clone()).unwrap_or(Status::Idle);
    set_status(app, Status::Checking);
    let current = system::version();
    match fetch_latest() {
        Ok(latest) => {
            let prefs = {
                let Ok(mut p) = state.prefs.lock() else { return };
                p.update.last_check = Some(now());
                p.save();
                p.update.clone()
            };
            if update::is_update(&latest, current) {
                set_status(app, Status::Available { version: latest.to_string(), url: update::release_page(&latest) });
                if manual || update::should_announce(&latest, current, &prefs) {
                    announce(app, latest);
                }
            } else {
                set_status(app, Status::UpToDate);
                if manual && app.get_webview_window(settings::LABEL).is_none() {
                    let _ = app.dialog().message(t("Browserdoor is up to date.")).title(t("Updates")).blocking_show();
                }
            }
        }
        Err(e) => {
            system::log(&format!("update check failed: {e}"));
            if manual {
                set_status(app, Status::Failed { message: format!("{} ({e})", t("The update check failed.")) });
            } else {
                // A failed background check keeps what was known.
                set_status(app, if previous == Status::Checking { Status::Idle } else { previous });
            }
        }
    }
}

fn set_status(app: &AppHandle, status: Status) {
    if let Ok(mut s) = app.state::<AppState>().update.lock() {
        *s = status;
    }
    let _ = app.emit_to(settings::LABEL, "settings-changed", ());
    tray::refresh(app);
}

fn announce(app: &AppHandle, latest: AppVersion) {
    let h = app.clone();
    let version = latest.to_string();
    app.dialog()
        .message(tv(
            "Browserdoor {v} is available. Scoop installs it in a terminal window; Browserdoor restarts afterwards.",
            &version,
        ))
        .title(t("Updates"))
        .buttons(MessageDialogButtons::OkCancelCustom(t("Update"), t("Later")))
        .show(move |update| {
            if update {
                run_update(&h);
            } else if let Ok(mut p) = h.state::<AppState>().prefs.lock() {
                // "Later": automatic checks don't announce this version again.
                p.update.skipped_version = Some(version.clone());
                p.save();
            }
        });
}

/// Quits Browserdoor, updates it with Scoop in a terminal and starts it again. Without a Scoop
/// installation, opens the release page instead.
pub fn run_update(app: &AppHandle) {
    let state = app.state::<AppState>();
    let status = state.update.lock().map(|s| s.clone()).unwrap_or(Status::Idle);
    if !system::is_scoop_install() {
        if let Status::Available { url, .. } = status {
            system::shell_open(&url);
        }
        return;
    }
    let pid = std::process::id();
    let exe = system::stable_exe().replace('\'', "''");
    let script = format!(
        "$Host.UI.RawUI.WindowTitle = 'Browserdoor update'; \
         Wait-Process -Id {pid} -Timeout 15 -ErrorAction SilentlyContinue; \
         scoop update browserdoor; \
         Start-Process -FilePath '{exe}' -ArgumentList '--background'; \
         Start-Sleep -Seconds 3"
    );
    let spawned = std::process::Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .creation_flags(CREATE_NEW_CONSOLE)
        .spawn();
    match spawned {
        Ok(_) => app.exit(0),
        Err(e) => system::log(&format!("could not start the update: {e}")),
    }
}

/// The daily automatic check: shortly after start, then every hour whether one is due.
pub fn schedule(app: &AppHandle) {
    let h = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(20));
        loop {
            let due = h.state::<AppState>().prefs.lock().map(|p| p.update.is_due(now())).unwrap_or(false);
            if due && update::AppVersion::parse(system::version()).is_some_and(|v| !v.is_dev()) {
                check(&h, false);
            }
            std::thread::sleep(Duration::from_secs(60 * 60));
        }
    });
}
