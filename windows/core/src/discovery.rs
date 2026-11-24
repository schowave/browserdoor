//! Finding the targets on this computer (SPEC 3, Windows).

use std::collections::HashSet;

use crate::families::{self, ZenSpace};
use crate::paths;
use crate::target::{Target, TargetKind};
use crate::target_id::TargetId;

/// A browser registered under `Software\Clients\StartMenuInternet` (HKCU or HKLM).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegisteredApp {
    /// The `StartMenuInternet` key: the App ID of a registered browser.
    pub app_id: String,
    /// Its display name (the key's default value, else `Capabilities\ApplicationName`).
    pub name: String,
    /// The `.exe` from `shell\open\command`.
    pub exe: String,
}

/// What the file version resource of an `.exe` says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExeInfo {
    /// `FileDescription`, else `ProductName`, else the file name without `.exe`.
    pub name: String,
}

/// Everything discovery needs from the system. The app implements it with the registry and the
/// file system; tests use a fake.
pub trait BrowserEnvironment {
    /// `%LOCALAPPDATA%`
    fn local_app_data(&self) -> String;
    /// `%APPDATA%`
    fn roaming_app_data(&self) -> String;
    /// Browserdoor's own `StartMenuInternet` key, which never becomes a target.
    fn own_app_id(&self) -> String;
    /// HKCU entries first, then HKLM; the first one per App ID wins.
    fn registered_browsers(&self) -> Vec<RegisteredApp>;
    fn contents(&self, path: &str) -> Option<Vec<u8>>;
    /// None if the file doesn't exist.
    fn exe_info(&self, exe: &str) -> Option<ExeInfo>;
}

pub struct Discovery<'a> {
    pub environment: &'a dyn BrowserEnvironment,
    /// From the config's `zen.profilePath`.
    pub zen_profile_override: Option<String>,
    /// Paths of `.exe` files the user added (config `extraApps`).
    pub extra_apps: Vec<String>,
}

impl Discovery<'_> {
    /// All targets in default order: Zen spaces, Chromium profiles, Firefox profiles, then the
    /// other browsers and the added apps A–Z.
    pub fn discover(&self) -> Vec<Target> {
        let own = self.environment.own_app_id();
        let mut seen_ids = HashSet::new();
        let mut seen_exes = HashSet::new();
        let apps: Vec<RegisteredApp> = self
            .environment
            .registered_browsers()
            .into_iter()
            .filter(|a| a.app_id != own && !a.exe.is_empty())
            .filter(|a| seen_ids.insert(a.app_id.clone()) && seen_exes.insert(paths::normalized(&a.exe)))
            .collect();

        let mut zen = vec![];
        let mut chromium: Vec<(usize, Vec<Target>)> = vec![];
        let mut firefox = vec![];
        let mut others = vec![];
        for app in &apps {
            if paths::file_name(&app.exe).eq_ignore_ascii_case(families::ZEN_EXE_NAME) && zen.is_empty() {
                zen = self.zen_targets(app);
            } else if let Some(i) =
                families::CHROMIUM_BROWSERS.iter().position(|b| paths::ends_with(&app.exe, b.exe_suffix))
            {
                chromium.push((i, self.chromium_targets(app, &families::CHROMIUM_BROWSERS[i])));
            } else if paths::ends_with(&app.exe, families::FIREFOX_EXE_SUFFIX) && firefox.is_empty() {
                firefox = self.firefox_targets(app);
            } else {
                others.push(plain(&app.app_id, &app.name, &app.exe));
            }
        }
        chromium.sort_by_key(|(i, _)| *i);

        let registered: HashSet<String> = apps.iter().map(|a| paths::normalized(&a.exe)).collect();
        for exe in &self.extra_apps {
            if registered.contains(&paths::normalized(exe)) {
                continue;
            }
            if let Some(info) = self.environment.exe_info(exe) {
                others.push(plain(exe, &info.name, exe));
            }
        }
        others.sort_by_key(|t| t.name.to_lowercase());

        let mut seen = HashSet::new();
        zen.into_iter()
            .chain(chromium.into_iter().flat_map(|(_, t)| t))
            .chain(firefox)
            .chain(others)
            .filter(|t| seen.insert(t.id.clone()))
            .collect()
    }

    fn text(&self, path: &str) -> Option<String> {
        self.environment.contents(path).and_then(|d| String::from_utf8(d).ok())
    }

    /// One target per profile from `Local State`; one profile shows only the app name; an
    /// unreadable `Local State` gives one plain entry.
    fn chromium_targets(&self, app: &RegisteredApp, browser: &families::ChromiumBrowser) -> Vec<Target> {
        let local_state =
            paths::join(&paths::join(&self.environment.local_app_data(), browser.data_directory), "Local State");
        let profiles = self
            .environment
            .contents(&local_state)
            .and_then(|d| families::parse_chromium_local_state(&d))
            .unwrap_or_default();
        if profiles.is_empty() {
            return vec![plain(&app.app_id, &app.name, &app.exe)];
        }
        let single = profiles.len() == 1;
        profiles
            .into_iter()
            .map(|p| Target {
                id: TargetId::Chromium { app_id: app.app_id.clone(), profile_directory: p.directory.clone() }
                    .to_string(),
                name: if single { app.name.clone() } else { format!("{} › {}", app.name, p.name) },
                kind: TargetKind::ChromiumProfile { exe: app.exe.clone(), profile_directory: p.directory },
            })
            .collect()
    }

    /// One target per profile from `profiles.ini` and profile group databases; at most one
    /// profile stays a plain entry.
    fn firefox_targets(&self, app: &RegisteredApp) -> Vec<Target> {
        let root = paths::join(&self.environment.roaming_app_data(), families::FIREFOX_DATA_DIRECTORY);
        let groups = paths::join(&root, families::FIREFOX_GROUPS_DIRECTORY);
        let store = |id: &str| {
            let database = paths::join(&groups, &format!("{id}.sqlite"));
            let data = self.environment.contents(&database)?;
            let wal = self.environment.contents(&format!("{database}-wal"));
            families::parse_firefox_store(&data, wal.as_deref())
        };
        let profiles = self
            .text(&paths::join(&root, "profiles.ini"))
            .map(|ini| families::parse_firefox_profiles(&ini, &store))
            .unwrap_or_default();
        if profiles.len() <= 1 {
            return vec![plain(&app.app_id, &app.name, &app.exe)];
        }
        profiles
            .into_iter()
            .map(|p| Target {
                id: TargetId::Firefox { app_id: app.app_id.clone(), profile_path: p.path.clone() }.to_string(),
                name: format!("{} › {}", app.name, p.name),
                kind: TargetKind::FirefoxProfile { exe: app.exe.clone(), profile: p.directory(&root) },
            })
            .collect()
    }

    /// One target per space of the configured or default profile. Older Zen (from
    /// `application.ini`), an unreadable session or no spaces: one plain entry.
    fn zen_targets(&self, app: &RegisteredApp) -> Vec<Target> {
        let fallback = || vec![plain(&app.app_id, &app.name, &app.exe)];
        let version = self
            .text(&paths::join(paths::parent(&app.exe), "application.ini"))
            .and_then(|ini| families::gecko_app_version(&ini));
        if !families::version_at_least(version.as_deref(), &families::ZEN_MINIMUM_SPACE_VERSION) {
            return fallback();
        }
        let Some(spaces) = self.zen_spaces() else { return fallback() };
        if spaces.is_empty() {
            return fallback();
        }
        spaces
            .into_iter()
            .map(|s| Target {
                id: TargetId::Zen { uuid: s.uuid.clone() }.to_string(),
                name: s.name.clone(),
                kind: TargetKind::ZenSpace {
                    exe: app.exe.clone(),
                    uuid: s.uuid.clone(),
                    profile: self.zen_profile_override.clone(),
                    icon: s.emoji_icon().map(str::to_string),
                    color: s.color,
                },
            })
            .collect()
    }

    fn zen_spaces(&self) -> Option<Vec<ZenSpace>> {
        let profile = match &self.zen_profile_override {
            Some(p) => p.clone(),
            None => {
                let root = paths::join(&self.environment.roaming_app_data(), families::ZEN_DATA_DIRECTORY);
                families::zen_default_profile(&self.text(&paths::join(&root, "profiles.ini"))?, &root)?
            }
        };
        families::zen_spaces_from_session_file(
            &self.environment.contents(&paths::join(&profile, families::ZEN_SESSION_FILE))?,
        )
    }
}

fn plain(app_id: &str, name: &str, exe: &str) -> Target {
    Target {
        id: TargetId::App { app_id: app_id.to_string() }.to_string(),
        name: name.to_string(),
        kind: TargetKind::App { exe: exe.to_string() },
    }
}
