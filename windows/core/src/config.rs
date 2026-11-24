//! The user's configuration, `%APPDATA%\Browserdoor\config.json`. Same keys as on macOS
//! (SPEC 5); target IDs carry Windows App IDs, so a file is only meaningful on its computer.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::target::Target;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TargetOverride {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hotkey: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ZenConfig {
    #[serde(rename = "profilePath", skip_serializing_if = "Option::is_none")]
    pub profile_path: Option<String>,
}

/// Every field is optional; unknown fields are ignored.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Config {
    #[serde(rename = "defaultTarget", skip_serializing_if = "Option::is_none")]
    pub default_target: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hidden: Option<Vec<String>>,
    /// Paths of `.exe` files to offer as targets too.
    #[serde(rename = "extraApps", skip_serializing_if = "Option::is_none")]
    pub extra_apps: Option<Vec<String>>,
    /// A BTreeMap so the file's keys stay sorted (stable diffs).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub targets: Option<BTreeMap<String, TargetOverride>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zen: Option<ZenConfig>,
}

#[derive(Debug)]
pub enum ConfigError {
    Io(std::io::Error),
    Json(serde_json::Error),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::Io(e) => write!(f, "{e}"),
            ConfigError::Json(e) => write!(f, "{e}"),
        }
    }
}

impl Config {
    /// Missing file → empty config. Malformed file → error, so the user gets told.
    pub fn load(path: &Path) -> Result<Config, ConfigError> {
        match std::fs::read(path) {
            Ok(data) => serde_json::from_slice(&data).map_err(ConfigError::Json),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
            Err(e) => Err(ConfigError::Io(e)),
        }
    }

    /// Pretty, key-sorted JSON (as on macOS), written atomically.
    pub fn save(&self, path: &Path) -> Result<(), ConfigError> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(ConfigError::Io)?;
        }
        let value = serde_json::to_value(self).map_err(ConfigError::Json)?;
        let mut text = serde_json::to_string_pretty(&sorted(value)).map_err(ConfigError::Json)?;
        text.push('\n');
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, text).map_err(ConfigError::Io)?;
        std::fs::rename(&tmp, path).map_err(ConfigError::Io)
    }

    /// A label that differs from the detected name, or None.
    pub fn custom_label(label: Option<&str>, detected: &str) -> Option<String> {
        label.filter(|l| !l.is_empty() && *l != detected).map(str::to_string)
    }

    /// A single-character hotkey, lowercased, or None.
    pub fn custom_hotkey(hotkey: Option<&str>) -> Option<char> {
        let h = hotkey?;
        let mut chars = h.chars();
        let c = chars.next()?;
        if chars.next().is_some() {
            return None;
        }
        c.to_lowercase().next()
    }

    /// `discovered` in config order: listed IDs first, the rest in discovery order.
    pub fn ordered(&self, discovered: &[Target]) -> Vec<Target> {
        let mut rank: HashMap<&str, usize> = HashMap::new();
        for (i, id) in self.order.iter().flatten().enumerate() {
            rank.entry(id.as_str()).or_insert(i);
        }
        let mut indexed: Vec<(usize, &Target)> = discovered.iter().enumerate().collect();
        indexed.sort_by(|(ia, a), (ib, b)| match (rank.get(a.id.as_str()), rank.get(b.id.as_str())) {
            (Some(ra), Some(rb)) => ra.cmp(rb),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => ia.cmp(ib),
        });
        indexed.into_iter().map(|(_, t)| t.clone()).collect()
    }
}

/// serde_json keeps struct field order; the file has sorted keys everywhere.
fn sorted(value: serde_json::Value) -> serde_json::Value {
    match value {
        serde_json::Value::Object(map) => {
            let sorted: BTreeMap<String, serde_json::Value> = map.into_iter().map(|(k, v)| (k, sorted(v))).collect();
            serde_json::Value::Object(sorted.into_iter().collect())
        }
        serde_json::Value::Array(items) => serde_json::Value::Array(items.into_iter().map(sorted).collect()),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_macos_shaped_file_and_ignores_unknown_fields() {
        let json = r#"{"defaultTarget":"zen:{a}","order":["zen:{a}"],"hidden":["app:X"],"extraApps":["C:\\x.exe"],
            "targets":{"zen:{a}":{"label":"David","hotkey":"d"}},"zen":{"profilePath":null},"future":1}"#;
        let c: Config = serde_json::from_str(json).unwrap();
        assert_eq!(c.default_target.as_deref(), Some("zen:{a}"));
        assert_eq!(c.targets.unwrap()["zen:{a}"].hotkey.as_deref(), Some("d"));
        assert_eq!(c.zen, Some(ZenConfig { profile_path: None }));
    }

    #[test]
    fn saves_sorted_and_loads_back() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("sub").join("config.json");
        assert_eq!(Config::load(&path).unwrap(), Config::default());
        let mut targets = BTreeMap::new();
        targets.insert("b".into(), TargetOverride { label: Some("B".into()), hotkey: None });
        targets.insert("a".into(), TargetOverride { label: None, hotkey: Some("x".into()) });
        let c = Config { default_target: Some("a".into()), targets: Some(targets), ..Default::default() };
        c.save(&path).unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.find("\"defaultTarget\"").unwrap() < text.find("\"targets\"").unwrap());
        assert!(text.find("\"a\"").unwrap() < text.find("\"b\"").unwrap());
        assert_eq!(Config::load(&path).unwrap(), c);
        std::fs::write(&path, "{ nope").unwrap();
        assert!(Config::load(&path).is_err());
    }

    #[test]
    fn hotkeys_and_labels() {
        assert_eq!(Config::custom_hotkey(Some("D")), Some('d'));
        assert_eq!(Config::custom_hotkey(Some("dd")), None);
        assert_eq!(Config::custom_hotkey(Some("")), None);
        assert_eq!(Config::custom_label(Some("Chrome"), "Chrome"), None);
        assert_eq!(Config::custom_label(Some(""), "Chrome"), None);
        assert_eq!(Config::custom_label(Some("Work"), "Chrome").as_deref(), Some("Work"));
    }
}
