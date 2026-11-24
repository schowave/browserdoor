//! Update policy for the Scoop build: when to check, what to announce (SPEC 7, Windows).
//!
//! The newest version comes from the Scoop manifest in the bucket: what `scoop update` would
//! install, without GitHub's API rate limit.

use std::cmp::Ordering;

/// A dotted numeric version like `0.1.1` (a leading `v` or `windows-v` is ignored).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppVersion(pub Vec<u64>);

impl AppVersion {
    pub fn parse(s: &str) -> Option<AppVersion> {
        let s = s.trim();
        let s = s.strip_prefix("windows-").unwrap_or(s);
        let s = s.strip_prefix(['v', 'V']).unwrap_or(s);
        let core = s.split(['-', '+']).next()?;
        let parts: Option<Vec<u64>> = core.split('.').map(|p| p.parse().ok()).collect();
        parts.filter(|p| !p.is_empty()).map(AppVersion)
    }

    pub fn is_dev(&self) -> bool {
        self.0.iter().all(|p| *p == 0)
    }
}

impl std::fmt::Display for AppVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let parts: Vec<String> = self.0.iter().map(u64::to_string).collect();
        f.write_str(&parts.join("."))
    }
}

impl PartialOrd for AppVersion {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for AppVersion {
    fn cmp(&self, other: &Self) -> Ordering {
        let n = self.0.len().max(other.0.len());
        for i in 0..n {
            let (a, b) = (self.0.get(i).copied().unwrap_or(0), other.0.get(i).copied().unwrap_or(0));
            if a != b {
                return a.cmp(&b);
            }
        }
        Ordering::Equal
    }
}

/// Where the Scoop build learns about new versions.
pub const MANIFEST_URL: &str = "https://raw.githubusercontent.com/schowave/scoop-bucket/main/browserdoor.json";
pub const REPOSITORY: &str = "https://github.com/schowave/browserdoor";

pub fn release_page(version: &AppVersion) -> String {
    format!("{REPOSITORY}/releases/tag/windows-v{version}")
}

/// The `version` of a Scoop manifest.
pub fn manifest_version(json: &[u8]) -> Option<AppVersion> {
    let v: serde_json::Value = serde_json::from_slice(json).ok()?;
    AppVersion::parse(v.get("version")?.as_str()?)
}

/// What the update check remembers between launches.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct UpdatePreferences {
    #[serde(rename = "checkAutomatically", default = "yes")]
    pub check_automatically: bool,
    /// Unix seconds.
    #[serde(rename = "lastCheck", default)]
    pub last_check: Option<u64>,
    /// A version the user answered with "Later"; automatic checks don't announce it again.
    #[serde(rename = "skippedVersion", default)]
    pub skipped_version: Option<String>,
}

fn yes() -> bool {
    true
}

impl Default for UpdatePreferences {
    fn default() -> Self {
        UpdatePreferences { check_automatically: true, last_check: None, skipped_version: None }
    }
}

pub const INTERVAL_SECONDS: u64 = 24 * 60 * 60;

impl UpdatePreferences {
    pub fn is_due(&self, now: u64) -> bool {
        self.check_automatically && self.last_check.is_none_or(|last| now.saturating_sub(last) >= INTERVAL_SECONDS)
    }
}

/// Whether `latest` is newer than `current`. A dev build (`0.0.0`) never updates.
pub fn is_update(latest: &AppVersion, current: &str) -> bool {
    match AppVersion::parse(current) {
        Some(c) if !c.is_dev() => c < *latest,
        _ => false,
    }
}

/// After an automatic check: announce only a newer version the user hasn't put off.
pub fn should_announce(latest: &AppVersion, current: &str, prefs: &UpdatePreferences) -> bool {
    is_update(latest, current) && prefs.skipped_version.as_deref() != Some(latest.to_string().as_str())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions() {
        assert!(AppVersion::parse("windows-v0.2.0").unwrap() > AppVersion::parse("0.1.9").unwrap());
        assert_eq!(AppVersion::parse("v1.2"), AppVersion::parse("1.2.0").map(|_| AppVersion(vec![1, 2])));
        assert_eq!(AppVersion::parse("1.2.0").unwrap().cmp(&AppVersion::parse("1.2").unwrap()), Ordering::Equal);
        assert_eq!(AppVersion::parse("x"), None);
        assert_eq!(AppVersion::parse("1.2.3-beta").unwrap().to_string(), "1.2.3");
    }

    #[test]
    fn manifest() {
        assert_eq!(manifest_version(br#"{"version":"0.3.1","url":"x"}"#), AppVersion::parse("0.3.1"));
        assert_eq!(manifest_version(b"{}"), None);
    }

    #[test]
    fn policy() {
        let v = AppVersion::parse("0.2.0").unwrap();
        assert!(is_update(&v, "0.1.0"));
        assert!(!is_update(&v, "0.2.0"));
        assert!(!is_update(&v, "0.0.0"));
        let mut prefs = UpdatePreferences::default();
        assert!(prefs.is_due(1000));
        prefs.last_check = Some(1000);
        assert!(!prefs.is_due(1000 + INTERVAL_SECONDS - 1));
        assert!(prefs.is_due(1000 + INTERVAL_SECONDS));
        prefs.skipped_version = Some("0.2.0".into());
        assert!(!should_announce(&v, "0.1.0", &prefs));
        prefs.check_automatically = false;
        assert!(!prefs.is_due(u64::MAX));
    }
}
