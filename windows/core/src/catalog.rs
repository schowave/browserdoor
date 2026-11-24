//! Target catalog: config + discovery → the targets, their labels, hotkeys and order; saves edits.
//! The single source for the picker and the settings window.

use std::collections::HashSet;
use std::path::PathBuf;

use crate::config::{Config, ConfigError, TargetOverride, ZenConfig};
use crate::discovery::{BrowserEnvironment, Discovery};
use crate::target::Target;
use crate::target_id::TargetId;

/// One row of the settings window's target list: a discovered target plus its user settings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TargetSetting {
    pub target: Target,
    /// Custom name; None shows the detected name.
    pub label: Option<String>,
    /// Custom single-key shortcut, lowercase; None gets an automatic number key.
    pub hotkey: Option<char>,
    pub hidden: bool,
}

impl TargetSetting {
    pub fn id(&self) -> &str {
        &self.target.id
    }

    pub fn display_name(&self) -> &str {
        self.label.as_deref().unwrap_or(&self.target.name)
    }

    /// The last typed character, lowercased; empty → None.
    pub fn normalize_hotkey(input: &str) -> Option<char> {
        input.trim().chars().last().and_then(|c| c.to_lowercase().next())
    }
}

/// A target as shown in the picker, with config applied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PickerEntry {
    pub target: Target,
    pub label: String,
    pub hotkey: Option<char>,
}

impl PickerEntry {
    pub fn id(&self) -> &str {
        &self.target.id
    }
}

pub struct TargetCatalog<'a> {
    pub environment: &'a dyn BrowserEnvironment,
    pub config_path: PathBuf,
}

impl TargetCatalog<'_> {
    /// Missing config = defaults; unreadable config = defaults, flagged.
    pub fn load(&self) -> CatalogState {
        let (config, unreadable) = match Config::load(&self.config_path) {
            Ok(c) => (c, false),
            Err(_) => (Config::default(), true),
        };
        let targets = self.discover(&config);
        CatalogState::new(config, targets, unreadable)
    }

    /// Writes the edits. Re-discovers when an edit changes what can be discovered (extra apps,
    /// Zen profile); returns the state to continue editing with.
    pub fn save(&self, state: &CatalogState) -> Result<CatalogState, ConfigError> {
        let config = state.config();
        config.save(&self.config_path)?;
        let rediscover = config.extra_apps != state.base.extra_apps || config.zen != state.base.zen;
        let targets = if rediscover { self.discover(&config) } else { state.targets.clone() };
        Ok(CatalogState::new(config, targets, false))
    }

    fn discover(&self, config: &Config) -> Vec<Target> {
        Discovery {
            environment: self.environment,
            zen_profile_override: config.zen.as_ref().and_then(|z| z.profile_path.clone()).filter(|p| !p.is_empty()),
            extra_apps: config.extra_apps.clone().unwrap_or_default(),
        }
        .discover()
    }
}

/// A loaded catalog plus pending edits.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CatalogState {
    /// Every discovered target, hidden ones included.
    pub targets: Vec<Target>,
    /// Editable rows in picker order, hidden ones included.
    pub rows: Vec<TargetSetting>,
    pub default_target: Option<String>,
    /// Paths of `.exe` files the user added.
    pub extra_apps: Vec<String>,
    pub zen_profile_path: Option<String>,
    /// The config file exists but couldn't be parsed; defaults are in use, saving replaces it.
    pub config_is_unreadable: bool,
    base: Config,
}

const AUTO_HOTKEYS: &str = "1234567890";

impl CatalogState {
    pub fn new(base: Config, targets: Vec<Target>, config_is_unreadable: bool) -> CatalogState {
        let hidden: HashSet<&str> = base.hidden.iter().flatten().map(String::as_str).collect();
        let rows = base
            .ordered(&targets)
            .into_iter()
            .map(|target| {
                let o = base.targets.as_ref().and_then(|t| t.get(&target.id));
                TargetSetting {
                    label: Config::custom_label(o.and_then(|o| o.label.as_deref()), &target.name),
                    hotkey: Config::custom_hotkey(o.and_then(|o| o.hotkey.as_deref())),
                    hidden: hidden.contains(target.id.as_str()),
                    target,
                }
            })
            .collect();
        CatalogState {
            targets,
            rows,
            default_target: base.default_target.clone(),
            extra_apps: base.extra_apps.clone().unwrap_or_default(),
            zen_profile_path: base.zen.as_ref().and_then(|z| z.profile_path.clone()),
            config_is_unreadable,
            base,
        }
    }

    /// The config these edits amount to. Settings for targets not discovered right now are
    /// kept, after the edited ones.
    pub fn config(&self) -> Config {
        let mut c = self.base.clone();
        let ids: HashSet<&str> = self.rows.iter().map(|r| r.id()).collect();
        let mut order: Vec<String> = self.rows.iter().map(|r| r.id().to_string()).collect();
        order.extend(c.order.iter().flatten().filter(|id| !ids.contains(id.as_str())).cloned());
        c.order = Some(order);
        let mut hidden: Vec<String> = self.rows.iter().filter(|r| r.hidden).map(|r| r.id().to_string()).collect();
        hidden.extend(c.hidden.iter().flatten().filter(|id| !ids.contains(id.as_str())).cloned());
        c.hidden = Some(hidden);
        let mut overrides = c.targets.take().unwrap_or_default();
        overrides.retain(|k, _| !ids.contains(k.as_str()));
        for r in &self.rows {
            if r.label.is_some() || r.hotkey.is_some() {
                overrides.insert(
                    r.id().to_string(),
                    TargetOverride { label: r.label.clone(), hotkey: r.hotkey.map(String::from) },
                );
            }
        }
        c.targets = Some(overrides);
        c.default_target = self.default_target.clone();
        c.extra_apps = Some(self.extra_apps.clone());
        c.zen = self.zen_profile_path.clone().map(|p| ZenConfig { profile_path: Some(p) });
        c
    }

    /// What the picker shows: the visible rows, labelled, with hotkeys. A custom key stays only
    /// on the first row that has it; rows without one get the free number keys in order.
    pub fn picker_entries(&self) -> Vec<PickerEntry> {
        let mut used = HashSet::new();
        let mut entries: Vec<PickerEntry> = self
            .rows
            .iter()
            .filter(|r| !r.hidden)
            .map(|r| PickerEntry {
                target: r.target.clone(),
                label: r.display_name().to_string(),
                hotkey: r.hotkey.filter(|k| used.insert(*k)),
            })
            .collect();
        let mut free = AUTO_HOTKEYS.chars().filter(|k| !used.contains(k));
        for e in entries.iter_mut().filter(|e| e.hotkey.is_none()) {
            match free.next() {
                Some(k) => e.hotkey = Some(k),
                None => break,
            }
        }
        entries
    }

    /// The entry `Enter` opens: the default target if it is visible, else the first.
    pub fn default_index(&self, entries: &[PickerEntry]) -> Option<usize> {
        if entries.is_empty() {
            return None;
        }
        Some(self.default_target.as_ref().and_then(|id| entries.iter().position(|e| e.id() == id)).unwrap_or(0))
    }

    /// The key each visible target gets in the picker (custom or automatic), by target ID.
    pub fn effective_keys(&self) -> Vec<(String, char)> {
        self.picker_entries().into_iter().filter_map(|e| e.hotkey.map(|k| (e.target.id, k))).collect()
    }

    // Edits, as the settings window makes them.

    /// An empty name or the detected one removes the custom name.
    pub fn rename(&mut self, id: &str, name: &str) {
        self.edit(id, |r| {
            r.label = if name.is_empty() || name == r.target.name { None } else { Some(name.to_string()) }
        });
    }

    /// Sets a target's key from what was typed (the last character); empty removes it. A key
    /// belongs to one target: another that had it loses it. Returns the display name of the
    /// target the picker showed the key on before, if another.
    pub fn set_hotkey(&mut self, id: &str, typed: &str) -> Option<String> {
        let key = TargetSetting::normalize_hotkey(typed);
        let previous = key.and_then(|k| {
            let holder = self.effective_keys().into_iter().find(|(tid, v)| tid != id && *v == k)?;
            self.rows.iter().find(|r| r.id() == holder.0).map(|r| r.display_name().to_string())
        });
        if let Some(k) = key {
            for r in self.rows.iter_mut().filter(|r| r.target.id != id && r.hotkey == Some(k)) {
                r.hotkey = None;
            }
        }
        self.edit(id, |r| r.hotkey = key);
        previous
    }

    pub fn set_hidden(&mut self, id: &str, hidden: bool) {
        self.edit(id, |r| r.hidden = hidden);
    }

    /// Makes a target the one `Enter` opens, or, if it already is, removes the default.
    pub fn toggle_default(&mut self, id: &str) {
        self.default_target = if self.default_target.as_deref() == Some(id) { None } else { Some(id.to_string()) };
    }

    pub fn add_extra_apps(&mut self, exes: &[String]) {
        for exe in exes {
            if !self.extra_apps.iter().any(|e| e.eq_ignore_ascii_case(exe)) {
                self.extra_apps.push(exe.clone());
            }
        }
    }

    pub fn remove_extra_app(&mut self, exe: &str) {
        self.extra_apps.retain(|e| e != exe);
    }

    /// Added apps no target stands for (uninstalled, or a registered browser listed by its
    /// profiles), so the settings can still remove them.
    pub fn unlisted_extra_apps(&self) -> Vec<String> {
        let listed: HashSet<&str> = self.rows.iter().map(|r| r.id()).collect();
        self.extra_apps
            .iter()
            .filter(|e| !listed.contains(TargetId::App { app_id: (*e).clone() }.to_string().as_str()))
            .cloned()
            .collect()
    }

    /// The `.exe` behind a target the user added as an extra app.
    pub fn extra_app_for_target(&self, id: &str) -> Option<String> {
        match TargetId::parse(id)? {
            TargetId::App { app_id } if self.extra_apps.contains(&app_id) => Some(app_id),
            _ => None,
        }
    }

    /// Moves one row to `to` (its index after the move).
    pub fn move_row(&mut self, from: usize, to: usize) {
        if from >= self.rows.len() {
            return;
        }
        let row = self.rows.remove(from);
        let to = to.min(self.rows.len());
        self.rows.insert(to, row);
    }

    /// None or empty goes back to Zen's default profile.
    pub fn set_zen_profile(&mut self, path: Option<&str>) {
        self.zen_profile_path = path.filter(|p| !p.is_empty()).map(str::to_string);
    }

    fn edit(&mut self, id: &str, change: impl FnOnce(&mut TargetSetting)) {
        if let Some(r) = self.rows.iter_mut().find(|r| r.target.id == id) {
            change(r);
        }
    }
}
