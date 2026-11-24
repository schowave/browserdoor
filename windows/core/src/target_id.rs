//! The stable ID of a target, as stored in the config: the one place that formats and parses it.

use std::fmt;

/// On Windows the app part is the **App ID**: the `StartMenuInternet` key of a registered
/// browser, or the path of the `.exe` for an app the user added.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TargetId {
    /// `zen:{uuid}`
    Zen { uuid: String },
    /// `chromium:<appId>:<profileDir>`
    Chromium { app_id: String, profile_directory: String },
    /// `firefox:<appId>:<profilePath>`
    Firefox { app_id: String, profile_path: String },
    /// `app:<appId>` (the app ID may be a path and contain `:`)
    App { app_id: String },
}

impl fmt::Display for TargetId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TargetId::Zen { uuid } => write!(f, "zen:{uuid}"),
            TargetId::Chromium { app_id, profile_directory } => write!(f, "chromium:{app_id}:{profile_directory}"),
            TargetId::Firefox { app_id, profile_path } => write!(f, "firefox:{app_id}:{profile_path}"),
            TargetId::App { app_id } => write!(f, "app:{app_id}"),
        }
    }
}

impl TargetId {
    /// None for anything that isn't one of the four forms. The last field may contain `:`.
    pub fn parse(s: &str) -> Option<TargetId> {
        let (kind, rest) = s.split_once(':')?;
        match kind {
            "zen" if !rest.is_empty() => Some(TargetId::Zen { uuid: rest.to_string() }),
            "app" if !rest.is_empty() => Some(TargetId::App { app_id: rest.to_string() }),
            "chromium" | "firefox" => {
                let (app, last) = rest.split_once(':')?;
                if app.is_empty() || last.is_empty() {
                    return None;
                }
                Some(if kind == "chromium" {
                    TargetId::Chromium { app_id: app.into(), profile_directory: last.into() }
                } else {
                    TargetId::Firefox { app_id: app.into(), profile_path: last.into() }
                })
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::TargetId;

    #[test]
    fn round_trips() {
        for s in [
            "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}",
            "chromium:Google Chrome:Profile 2",
            "firefox:Firefox-308046B0AF4A39CB:Profiles/x1y2.default-release",
            r"firefox:Firefox-308046B0AF4A39CB:C:\Users\a\ff",
            "app:Microsoft Edge",
            r"app:C:\Tools\Foo\foo.exe",
        ] {
            assert_eq!(TargetId::parse(s).unwrap().to_string(), s);
        }
        assert_eq!(TargetId::parse(r"app:C:\x.exe"), Some(TargetId::App { app_id: r"C:\x.exe".into() }));
    }

    #[test]
    fn rejects_malformed() {
        for s in ["", "zen:", "app:", "chromium:x", "chromium::d", "firefox:a:", "other:x", "nocolon"] {
            assert_eq!(TargetId::parse(s), None, "{s}");
        }
    }
}
