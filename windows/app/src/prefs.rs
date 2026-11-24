//! What the app remembers besides the config (which is the user's): onboarding, the tray icon
//! and the update check. `%APPDATA%\Browserdoor\state.json`.

use std::path::PathBuf;

use browserdoor_core::update::UpdatePreferences;
use serde::{Deserialize, Serialize};

use crate::system::app_data_dir;

/// `%APPDATA%\Browserdoor\config.json` (SPEC 5, Windows).
pub fn config_path() -> PathBuf {
    app_data_dir().join("config.json")
}

fn state_path() -> PathBuf {
    app_data_dir().join("state.json")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prefs {
    #[serde(default)]
    pub onboarded: bool,
    #[serde(rename = "showInTray", default = "yes")]
    pub show_in_tray: bool,
    #[serde(default)]
    pub update: UpdatePreferences,
}

fn yes() -> bool {
    true
}

impl Default for Prefs {
    fn default() -> Self {
        Prefs { onboarded: false, show_in_tray: true, update: UpdatePreferences::default() }
    }
}

impl Prefs {
    pub fn load() -> Prefs {
        std::fs::read(state_path()).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default()
    }

    pub fn save(&self) {
        let path = state_path();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(text) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(path, text);
        }
    }
}
