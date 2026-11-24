//! Browser families: browsers whose apps split into several targets (Zen spaces, Chromium and
//! Firefox profiles), with the parsers for their data files. Windows locations, SPEC 3.

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::{ini, mozlz4, paths, target::Rgb};

// ---------------------------------------------------------------------------------------------
// Chromium

/// A Chromium browser Browserdoor lists by profile: matched by the end of its `.exe` path, with
/// its data directory under `%LOCALAPPDATA%`.
#[derive(Debug, Clone, Copy)]
pub struct ChromiumBrowser {
    pub exe_suffix: &'static str,
    pub data_directory: &'static str,
}

pub const CHROMIUM_BROWSERS: &[ChromiumBrowser] = &[
    ChromiumBrowser {
        exe_suffix: r"\Google\Chrome\Application\chrome.exe",
        data_directory: r"Google\Chrome\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\Google\Chrome Beta\Application\chrome.exe",
        data_directory: r"Google\Chrome Beta\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\Google\Chrome Dev\Application\chrome.exe",
        data_directory: r"Google\Chrome Dev\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\Google\Chrome SxS\Application\chrome.exe",
        data_directory: r"Google\Chrome SxS\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\BraveSoftware\Brave-Browser\Application\brave.exe",
        data_directory: r"BraveSoftware\Brave-Browser\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\Microsoft\Edge\Application\msedge.exe",
        data_directory: r"Microsoft\Edge\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\Microsoft\Edge Beta\Application\msedge.exe",
        data_directory: r"Microsoft\Edge Beta\User Data",
    },
    ChromiumBrowser {
        exe_suffix: r"\Microsoft\Edge Dev\Application\msedge.exe",
        data_directory: r"Microsoft\Edge Dev\User Data",
    },
    ChromiumBrowser { exe_suffix: r"\Vivaldi\Application\vivaldi.exe", data_directory: r"Vivaldi\User Data" },
    ChromiumBrowser { exe_suffix: r"\Chromium\Application\chrome.exe", data_directory: r"Chromium\User Data" },
];

pub fn chromium_browser(exe: &str) -> Option<&'static ChromiumBrowser> {
    CHROMIUM_BROWSERS.iter().find(|b| paths::ends_with(exe, b.exe_suffix))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChromiumProfile {
    /// Directory name, e.g. `Default` or `Profile 2`: the value for `--profile-directory`.
    pub directory: String,
    pub name: String,
}

/// Profiles from `Local State`: `profile.profiles_order` first, then the rest sorted naturally.
pub fn parse_chromium_local_state(data: &[u8]) -> Option<Vec<ChromiumProfile>> {
    #[derive(Deserialize)]
    struct LocalState {
        profile: Option<Profile>,
    }
    #[derive(Deserialize)]
    struct Profile {
        info_cache: Option<HashMap<String, Info>>,
        profiles_order: Option<Vec<String>>,
    }
    #[derive(Deserialize)]
    struct Info {
        name: Option<String>,
    }
    let state: LocalState = serde_json::from_slice(data).ok()?;
    let Some(profile) = state.profile else { return Some(vec![]) };
    let Some(cache) = profile.info_cache else { return Some(vec![]) };
    let order = profile.profiles_order.unwrap_or_default();
    let mut dirs: Vec<String> = order.iter().filter(|d| cache.contains_key(*d)).cloned().collect();
    let mut rest: Vec<String> = cache.keys().filter(|k| !order.contains(k)).cloned().collect();
    rest.sort_by(|a, b| natural_cmp(a, b));
    dirs.extend(rest);
    Some(
        dirs.into_iter()
            .map(|dir| {
                let name = cache[&dir].name.clone().filter(|n| !n.is_empty()).unwrap_or_else(|| dir.clone());
                ChromiumProfile { directory: dir, name }
            })
            .collect(),
    )
}

/// "Profile 2" before "Profile 10", case-insensitive.
pub fn natural_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    fn chunks(s: &str) -> Vec<(bool, String)> {
        let mut out: Vec<(bool, String)> = vec![];
        for c in s.chars() {
            let digit = c.is_ascii_digit();
            match out.last_mut() {
                Some((d, buf)) if *d == digit => buf.push(c),
                _ => out.push((digit, c.to_string())),
            }
        }
        out
    }
    let (ca, cb) = (chunks(a), chunks(b));
    for (x, y) in ca.iter().zip(cb.iter()) {
        let ord = match (x.0, y.0) {
            (true, true) => {
                let (nx, ny) = (x.1.trim_start_matches('0'), y.1.trim_start_matches('0'));
                nx.len().cmp(&ny.len()).then_with(|| nx.cmp(ny))
            }
            _ => x.1.to_lowercase().cmp(&y.1.to_lowercase()),
        };
        if ord != std::cmp::Ordering::Equal {
            return ord;
        }
    }
    ca.len().cmp(&cb.len())
}

// ---------------------------------------------------------------------------------------------
// Firefox

/// Release Firefox: `…\Mozilla Firefox\firefox.exe`, data in `%APPDATA%\Mozilla\Firefox`.
/// Developer Edition and Nightly share that directory and stay single entries; otherwise every
/// profile would be listed three times.
pub const FIREFOX_EXE_SUFFIX: &str = r"\Mozilla Firefox\firefox.exe";
pub const FIREFOX_DATA_DIRECTORY: &str = r"Mozilla\Firefox";
pub const FIREFOX_GROUPS_DIRECTORY: &str = "Profile Groups";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FirefoxProfile {
    /// As Firefox stores it: relative to the data directory (`Profiles/x1y2.default-release`) or absolute.
    pub path: String,
    pub name: String,
}

impl FirefoxProfile {
    pub fn directory(&self, root: &str) -> String {
        if paths::is_absolute(&self.path) { self.path.clone() } else { paths::join(root, &self.path) }
    }
}

/// Profiles from `profiles.ini`: the ones an installation opens by default first, then the others
/// in section order. A `StoreID` entry is replaced by its profile group (`store` returns it; None
/// keeps the ini entry). The empty `default` profile next to `default-release` is dropped unless an
/// installation uses it.
pub fn parse_firefox_profiles(
    profiles_ini: &str,
    store: &dyn Fn(&str) -> Option<Vec<FirefoxProfile>>,
) -> Vec<FirefoxProfile> {
    let sections = ini::parse(profiles_ini);
    let install_defaults: HashSet<String> = sections
        .iter()
        .filter(|s| s.name.starts_with("Install"))
        .filter_map(|s| s.get("Default").map(str::to_string))
        .collect();
    let mut entries: Vec<(u32, &ini::Section)> = sections
        .iter()
        .filter_map(|s| {
            let n = s.name.strip_prefix("Profile")?.parse::<u32>().ok()?;
            s.get("Path").map(|_| (n, s))
        })
        .collect();
    entries.sort_by_key(|(n, _)| *n);

    let mut result: Vec<FirefoxProfile> = vec![];
    for (_, section) in entries {
        let path = section.get("Path").unwrap_or_default().to_string();
        let legacy_default = section.get("Name") == Some("default") && !install_defaults.contains(&path);
        if let Some(group) = section.get("StoreID").and_then(store).filter(|g| !g.is_empty()) {
            result.extend(group);
        } else if !legacy_default {
            let name = section.get("Name").map(str::to_string).unwrap_or_else(|| path.clone());
            result.push(FirefoxProfile { path, name });
        }
    }
    let mut seen = HashSet::new();
    let unique: Vec<FirefoxProfile> = result.into_iter().filter(|p| seen.insert(p.path.clone())).collect();
    let (mut preferred, rest): (Vec<_>, Vec<_>) = unique.into_iter().partition(|p| install_defaults.contains(&p.path));
    preferred.extend(rest);
    preferred
}

/// Profiles in a profile group database (table `Profiles`: `id`, `path`, `name`), by id. Firefox
/// keeps it in WAL mode, so the database is read from a private copy with its `-wal` file.
pub fn parse_firefox_store(database: &[u8], wal: Option<&[u8]>) -> Option<Vec<FirefoxProfile>> {
    let dir = std::env::temp_dir().join(format!("browserdoor-{}-{}", std::process::id(), unique_suffix()));
    std::fs::create_dir_all(&dir).ok()?;
    let result = (|| {
        let file = dir.join("store.sqlite");
        std::fs::write(&file, database).ok()?;
        if let Some(wal) = wal {
            std::fs::write(dir.join("store.sqlite-wal"), wal).ok()?;
        }
        let db = rusqlite::Connection::open(&file).ok()?;
        let mut statement = db.prepare("SELECT path, name FROM Profiles ORDER BY id").ok()?;
        let rows = statement.query_map([], |row| Ok(FirefoxProfile { path: row.get(0)?, name: row.get(1)? })).ok()?;
        Some(rows.filter_map(Result::ok).collect())
    })();
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn unique_suffix() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    N.fetch_add(1, Ordering::Relaxed)
}

// ---------------------------------------------------------------------------------------------
// Zen

pub const ZEN_EXE_NAME: &str = "zen.exe";
/// `%APPDATA%\zen`
pub const ZEN_DATA_DIRECTORY: &str = "zen";
pub const ZEN_SESSION_FILE: &str = "zen-sessions.jsonlz4";
/// First Zen version shipping `--space` (zen-browser/desktop#15074).
pub const ZEN_MINIMUM_SPACE_VERSION: [u32; 2] = [1, 24];

/// A Zen space as stored in `zen-sessions.jsonlz4`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ZenSpace {
    /// UUID with braces, exactly as Zen stores it.
    pub uuid: String,
    pub name: String,
    /// `chrome://…/selectable/<name>.svg`, an emoji, or None.
    pub icon: Option<String>,
    /// Primary theme color, if the space has one.
    pub color: Option<Rgb>,
}

impl ZenSpace {
    /// `icon` if it is an emoji (or any non-URL text).
    pub fn emoji_icon(&self) -> Option<&str> {
        self.icon.as_deref().filter(|i| !i.is_empty() && !i.contains("://"))
    }
}

/// `spaces[]` of the decompressed session JSON; a session without `spaces` has none.
pub fn parse_zen_spaces(session_json: &[u8]) -> Option<Vec<ZenSpace>> {
    #[derive(Deserialize)]
    struct Session {
        #[serde(default)]
        spaces: Vec<Space>,
    }
    #[derive(Deserialize)]
    struct Space {
        uuid: String,
        name: String,
        icon: Option<String>,
        theme: Option<Theme>,
    }
    #[derive(Deserialize)]
    struct Theme {
        #[serde(rename = "gradientColors")]
        gradient_colors: Option<Vec<GradientColor>>,
    }
    #[derive(Deserialize)]
    struct GradientColor {
        c: Vec<i64>,
        #[serde(rename = "isPrimary")]
        is_primary: Option<bool>,
    }
    let session: Session = serde_json::from_slice(session_json).ok()?;
    Some(
        session
            .spaces
            .into_iter()
            .map(|s| {
                let colors = s.theme.and_then(|t| t.gradient_colors).unwrap_or_default();
                let primary = colors.iter().find(|c| c.is_primary == Some(true)).or(colors.first());
                let color = primary.filter(|p| p.c.len() == 3).map(|p| Rgb {
                    r: p.c[0].clamp(0, 255) as u8,
                    g: p.c[1].clamp(0, 255) as u8,
                    b: p.c[2].clamp(0, 255) as u8,
                });
                ZenSpace { uuid: s.uuid, name: s.name, icon: s.icon.filter(|i| !i.is_empty()), color }
            })
            .collect(),
    )
}

/// The spaces in a profile's `zen-sessions.jsonlz4` file contents.
pub fn zen_spaces_from_session_file(data: &[u8]) -> Option<Vec<ZenSpace>> {
    parse_zen_spaces(&mozlz4::decompress(data).ok()?)
}

/// The default profile directory from Zen's `profiles.ini`: `Default=` of the first `[Install…]`
/// section, then the `[Profile…]` with `Default=1`, then the only profile.
pub fn zen_default_profile(profiles_ini: &str, root: &str) -> Option<String> {
    let sections = ini::parse(profiles_ini);
    if let Some(path) = sections.iter().find(|s| s.name.starts_with("Install")).and_then(|s| s.get("Default"))
        && !path.is_empty()
    {
        return Some(resolve(path, !paths::is_absolute(path), root));
    }
    let profiles: Vec<&ini::Section> =
        sections.iter().filter(|s| s.name.starts_with("Profile") && s.get("Path").is_some()).collect();
    let chosen = profiles.iter().find(|s| s.get("Default") == Some("1")).or(if profiles.len() == 1 {
        profiles.first()
    } else {
        None
    })?;
    Some(resolve(chosen.get("Path")?, chosen.get("IsRelative") != Some("0"), root))
}

fn resolve(path: &str, relative: bool, root: &str) -> String {
    if relative { paths::join(root, path) } else { path.to_string() }
}

/// The app version from the `application.ini` next to a Gecko browser's `.exe` (`[App] Version`).
pub fn gecko_app_version(application_ini: &str) -> Option<String> {
    ini::parse(application_ini).into_iter().find(|s| s.name == "App")?.get("Version").map(str::to_string)
}

/// Compares the leading numeric components of a version like `1.24.1b`.
pub fn version_at_least(version: Option<&str>, minimum: &[u32]) -> bool {
    let Some(version) = version else { return false };
    let parts: Vec<u32> = version
        .split('.')
        .map(|c| c.chars().take_while(char::is_ascii_digit).collect::<String>().parse().unwrap_or(0))
        .collect();
    for (i, min) in minimum.iter().enumerate() {
        let value = parts.get(i).copied().unwrap_or(0);
        if value != *min {
            return value > *min;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chromium_local_state_order() {
        let json = br#"{"profile":{"info_cache":{"Profile 10":{"name":"Ten"},"Default":{"name":"Me"},"Profile 2":{"name":""},"Profile 3":{"name":"Work"}},"profiles_order":["Profile 3","Gone"]}}"#;
        let p = parse_chromium_local_state(json).unwrap();
        let dirs: Vec<&str> = p.iter().map(|p| p.directory.as_str()).collect();
        assert_eq!(dirs, ["Profile 3", "Default", "Profile 2", "Profile 10"]);
        assert_eq!(p[2].name, "Profile 2");
        assert_eq!(parse_chromium_local_state(b"{}"), Some(vec![]));
        assert_eq!(parse_chromium_local_state(b"not json"), None);
    }

    #[test]
    fn chromium_browsers_by_exe() {
        assert_eq!(
            chromium_browser(r"C:\Program Files\Google\Chrome\Application\chrome.exe").unwrap().data_directory,
            r"Google\Chrome\User Data"
        );
        assert_eq!(
            chromium_browser(r"C:\Users\a\AppData\Local\Google\Chrome SxS\Application\chrome.exe")
                .unwrap()
                .data_directory,
            r"Google\Chrome SxS\User Data"
        );
        assert!(chromium_browser(r"C:\Program Files\Opera\opera.exe").is_none());
    }

    #[test]
    fn firefox_profiles_ini() {
        let ini = "[Profile1]\nName=default\nIsRelative=1\nPath=Profiles/b.default\n\n[Profile0]\nName=default-release\nIsRelative=1\nPath=Profiles/a.default-release\n\n[Profile2]\nName=Work\nIsRelative=1\nPath=Profiles/c.work\n\n[Install308046B0AF4A39CB]\nDefault=Profiles/c.work\n";
        let p = parse_firefox_profiles(ini, &|_| None);
        let names: Vec<&str> = p.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, ["Work", "default-release"]);
        assert_eq!(p[0].directory(r"C:\ff"), r"C:\ff\Profiles\c.work");
    }

    #[test]
    fn firefox_profile_group_replaces_its_entry() {
        let ini = "[Profile0]\nName=Original\nPath=Profiles/a\nStoreID=abc\n[Profile1]\nName=Other\nPath=Profiles/z\n";
        let p = parse_firefox_profiles(ini, &|id| {
            assert_eq!(id, "abc");
            Some(vec![
                FirefoxProfile { path: "Profiles/a".into(), name: "One".into() },
                FirefoxProfile { path: "Profiles/b".into(), name: "Two".into() },
            ])
        });
        let names: Vec<&str> = p.iter().map(|p| p.name.as_str()).collect();
        assert_eq!(names, ["One", "Two", "Other"]);
    }

    #[test]
    fn firefox_store_reads_sqlite_with_wal() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("s.sqlite");
        let db = rusqlite::Connection::open(&file).unwrap();
        db.execute_batch(
            "PRAGMA journal_mode=WAL; CREATE TABLE Profiles (id INTEGER PRIMARY KEY, path TEXT, name TEXT);
             INSERT INTO Profiles VALUES (2,'Profiles/b','Two'),(1,'Profiles/a','One');",
        )
        .unwrap();
        let data = std::fs::read(&file).unwrap();
        let wal = std::fs::read(dir.path().join("s.sqlite-wal")).ok();
        let p = parse_firefox_store(&data, wal.as_deref()).unwrap();
        drop(db);
        assert_eq!(p.iter().map(|p| p.name.as_str()).collect::<Vec<_>>(), ["One", "Two"]);
        assert_eq!(parse_firefox_store(b"garbage", None), None);
    }

    #[test]
    fn zen_spaces_and_colors() {
        let json = br#"{"spaces":[{"uuid":"{a}","name":"Work","icon":"chrome://browser/skin/zen-icons/selectable/star.svg","theme":{"gradientColors":[{"c":[1,2,3]},{"c":[9,8,7],"isPrimary":true}]}},{"uuid":"{b}","name":"Home","icon":"","theme":{"gradientColors":[]}}]}"#;
        let s = parse_zen_spaces(json).unwrap();
        assert_eq!(s[0].color, Some(Rgb { r: 9, g: 8, b: 7 }));
        assert_eq!(s[0].emoji_icon(), None);
        assert_eq!(s[1].icon, None);
        assert_eq!(parse_zen_spaces(br#"{"tabs":[]}"#), Some(vec![]));
    }

    #[test]
    fn zen_default_profile_resolution() {
        let root = r"C:\Users\a\AppData\Roaming\zen";
        let ini = "[Profile0]\nName=Default (release)\nIsRelative=1\nPath=Profiles/x.Default (release)\nDefault=1\n[Install1]\nDefault=Profiles/y.Other\n";
        assert_eq!(zen_default_profile(ini, root).unwrap(), r"C:\Users\a\AppData\Roaming\zen\Profiles\y.Other");
        let ini2 = "[Profile0]\nIsRelative=0\nPath=D:\\zen\\p\n";
        assert_eq!(zen_default_profile(ini2, root).unwrap(), r"D:\zen\p");
        assert_eq!(zen_default_profile("[Profile0]\nPath=a\n[Profile1]\nPath=b\n", root), None);
    }

    #[test]
    fn versions() {
        assert!(version_at_least(Some("1.24.3b"), &ZEN_MINIMUM_SPACE_VERSION));
        assert!(version_at_least(Some("2.0"), &ZEN_MINIMUM_SPACE_VERSION));
        assert!(!version_at_least(Some("1.23.9b"), &ZEN_MINIMUM_SPACE_VERSION));
        assert!(!version_at_least(None, &ZEN_MINIMUM_SPACE_VERSION));
        assert_eq!(gecko_app_version("[App]\nVendor=Mozilla\nVersion=1.24.3b\n").as_deref(), Some("1.24.3b"));
    }
}
