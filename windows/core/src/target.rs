//! Targets and how they open.

use crate::url_policy;

/// One entry the user can pick: a Zen space, a Chromium or Firefox profile, or a browser/app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    /// Stable ID, see [`crate::TargetId`].
    pub id: String,
    pub name: String,
    pub kind: TargetKind,
}

/// How one target opens, owned by its browser family.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TargetKind {
    /// A plain browser or app: `exe <url…>`.
    App { exe: String },
    /// `exe --profile-directory=<dir> <url…>`
    ChromiumProfile { exe: String, profile_directory: String },
    /// `exe -profile <dir> <url…>`: a second instance hands the URLs to a running one for the
    /// same profile and quits; otherwise Firefox starts with that profile.
    FirefoxProfile { exe: String, profile: String },
    /// `zen.exe [--profile <p>] --space <uuid> <url>`. `profile` only when the config overrides
    /// Zen's default profile. `color` and `icon` are the space's, for its picker icon.
    ZenSpace { exe: String, uuid: String, profile: Option<String>, icon: Option<String>, color: Option<Rgb> },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

/// One process to start, detached.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LaunchCommand {
    pub exe: String,
    pub args: Vec<String>,
}

impl TargetKind {
    pub fn exe(&self) -> &str {
        match self {
            TargetKind::App { exe }
            | TargetKind::ChromiumProfile { exe, .. }
            | TargetKind::FirefoxProfile { exe, .. }
            | TargetKind::ZenSpace { exe, .. } => exe,
        }
    }
}

impl Target {
    pub fn exe(&self) -> &str {
        self.kind.exe()
    }

    /// Commands that open `urls`; URLs `url_policy` rejects are dropped (they would become flags).
    /// `app_is_running` only matters for Zen: its `--space <space> [<url>]` takes one URL, so a
    /// running Zen gets one call per URL; a cold start takes them all in one call, so they open
    /// in the same window.
    pub fn launch_commands(&self, urls: &[String], app_is_running: bool) -> Vec<LaunchCommand> {
        let urls = url_policy::filter(urls);
        if urls.is_empty() {
            return vec![];
        }
        let cmd = |exe: &str, args: Vec<String>| LaunchCommand { exe: exe.to_string(), args };
        match &self.kind {
            TargetKind::App { exe } => vec![cmd(exe, urls)],
            TargetKind::ChromiumProfile { exe, profile_directory } => {
                vec![cmd(exe, [vec![format!("--profile-directory={profile_directory}")], urls].concat())]
            }
            TargetKind::FirefoxProfile { exe, profile } => {
                vec![cmd(exe, [vec!["-profile".to_string(), profile.clone()], urls].concat())]
            }
            TargetKind::ZenSpace { exe, uuid, profile, .. } => {
                let mut base = vec![];
                if let Some(p) = profile {
                    base.extend(["--profile".to_string(), p.clone()]);
                }
                base.extend(["--space".to_string(), uuid.clone()]);
                if app_is_running {
                    urls.into_iter().map(|u| cmd(exe, [base.clone(), vec![u]].concat())).collect()
                } else {
                    vec![cmd(exe, [base, urls].concat())]
                }
            }
        }
    }

    /// The app may stay in the background after a command to its running instance.
    pub fn activates_after_remote_command(&self) -> bool {
        matches!(self.kind, TargetKind::ZenSpace { .. })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn zen(profile: Option<&str>) -> Target {
        Target {
            id: "zen:{u}".into(),
            name: "Work".into(),
            kind: TargetKind::ZenSpace {
                exe: r"C:\Program Files\Zen Browser\zen.exe".into(),
                uuid: "{u}".into(),
                profile: profile.map(Into::into),
                icon: None,
                color: None,
            },
        }
    }

    #[test]
    fn zen_running_gets_one_call_per_url_cold_one_call() {
        let urls = vec!["https://a.com/".to_string(), "https://b.com/".to_string()];
        let running = zen(None).launch_commands(&urls, true);
        assert_eq!(running.len(), 2);
        assert_eq!(running[1].args, ["--space", "{u}", "https://b.com/"]);
        let cold = zen(Some(r"C:\p")).launch_commands(&urls, false);
        assert_eq!(cold.len(), 1);
        assert_eq!(cold[0].args, ["--profile", r"C:\p", "--space", "{u}", "https://a.com/", "https://b.com/"]);
    }

    #[test]
    fn rejected_urls_never_become_arguments() {
        let t = Target { id: "app:X".into(), name: "X".into(), kind: TargetKind::App { exe: "x.exe".into() } };
        assert!(t.launch_commands(&["--remote-debugging-port=1".into()], true).is_empty());
        let c = t.launch_commands(&["javascript:x".into(), "https://ok.com/".into()], true);
        assert_eq!(c[0].args, ["https://ok.com/"]);
    }

    #[test]
    fn profiles() {
        let c = Target {
            id: "chromium:Google Chrome:Profile 1".into(),
            name: "".into(),
            kind: TargetKind::ChromiumProfile { exe: "chrome.exe".into(), profile_directory: "Profile 1".into() },
        };
        assert_eq!(
            c.launch_commands(&["https://a.com/".into()], false)[0].args,
            ["--profile-directory=Profile 1", "https://a.com/"]
        );
        let f = Target {
            id: "firefox:F:Profiles/x".into(),
            name: "".into(),
            kind: TargetKind::FirefoxProfile { exe: "firefox.exe".into(), profile: r"C:\ff\Profiles\x".into() },
        };
        assert_eq!(
            f.launch_commands(&["https://a.com/".into()], false)[0].args,
            ["-profile", r"C:\ff\Profiles\x", "https://a.com/"]
        );
    }
}
