//! English and German by the Windows display language (SPEC 2); key = English text. The web
//! views have their own table (windows/ui/src/lib/i18n.ts).

use std::sync::OnceLock;

use windows_sys::Win32::Globalization::GetUserDefaultUILanguage;

fn german() -> bool {
    static GERMAN: OnceLock<bool> = OnceLock::new();
    // SAFETY: plain Win32 call. Primary language ID 0x07 is German.
    *GERMAN.get_or_init(|| (unsafe { GetUserDefaultUILanguage() } & 0x3FF) == 0x07)
}

pub fn t(key: &str) -> String {
    if !german() {
        return key.to_string();
    }
    match key {
        "About Browserdoor" => "Über Browserdoor",
        "Open Link from Clipboard…" => "Link aus der Zwischenablage öffnen…",
        "Make Default Browser…" => "Als Standardbrowser festlegen…",
        "Check for Updates…" => "Nach Updates suchen…",
        "Settings…" => "Einstellungen…",
        "Quit Browserdoor" => "Browserdoor beenden",
        "Browserdoor – not the default browser" => "Browserdoor – nicht der Standardbrowser",
        "Browserdoor Settings" => "Browserdoor-Einstellungen",
        "Make Browserdoor your default browser?" => "Browserdoor als Standardbrowser verwenden?",
        "Browserdoor shows a picker for every link you click. Choose Browserdoor as your default browser in the Windows settings that open next." => {
            "Browserdoor zeigt bei jedem Link, den du anklickst, eine Auswahl. Wähle Browserdoor in den Windows-Einstellungen, die sich gleich öffnen, als Standardbrowser."
        }
        "Open Settings" => "Einstellungen öffnen",
        "Not Now" => "Jetzt nicht",
        "Update" => "Aktualisieren",
        "Later" => "Später",
        "OK" => "OK",
        "Browserdoor is up to date." => "Browserdoor ist aktuell.",
        "The update check failed." => "Die Suche nach Updates ist fehlgeschlagen.",
        "Updates" => "Updates",
        "Browserdoor {v} is available. Scoop installs it in a terminal window; Browserdoor restarts afterwards." => {
            "Browserdoor {v} ist verfügbar. Scoop installiert es in einem Terminalfenster; danach startet Browserdoor neu."
        }
        "A link picker for Zen spaces, browser profiles and browsers." => {
            "Ein Link-Picker für Zen-Spaces, Browserprofile und Browser."
        }
        "Version {v}" => "Version {v}",
        "The clipboard holds no web link." => "In der Zwischenablage ist kein Weblink.",
        other => return other.to_string(),
    }
    .to_string()
}

pub fn tv(key: &str, version: &str) -> String {
    t(key).replace("{v}", version)
}
