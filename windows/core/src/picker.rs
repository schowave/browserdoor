//! Picker session: one appearance of the picker, its links, entries and selection; turns input
//! into effects. The window only renders it and performs the effects.

use std::collections::HashMap;

use crate::badge::ProfileBadge;
use crate::catalog::{CatalogState, PickerEntry};
use crate::target::Target;

/// A key press as the web view reports it (`KeyboardEvent.key` and modifiers).
#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize)]
pub struct KeyPress {
    pub key: String,
    #[serde(default)]
    pub ctrl: bool,
    #[serde(default)]
    pub alt: bool,
    #[serde(default)]
    pub shift: bool,
    #[serde(default)]
    pub meta: bool,
}

/// What the user does in the picker.
#[derive(Debug, Clone, PartialEq, serde::Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum PickerInput {
    Key(KeyPress),
    Click {
        row: usize,
    },
    /// The mouse is over a row, at (x, y) in the window.
    Hover {
        row: usize,
        x: f64,
        y: f64,
    },
    CopyButton,
    /// The settings button of an empty picker.
    SettingsButton,
    /// The window lost keyboard focus (click outside).
    LostFocus,
}

/// What the picker's host has to do, in order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PickerEffect {
    Close,
    Open(Vec<String>, Target),
    Copy(String),
    /// Show the settings window on its Targets tab.
    OpenSettings,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum KeyAction {
    Cancel,
    Confirm,
    MoveUp,
    MoveDown,
    MoveFirst,
    MoveLast,
    Copy,
    Settings,
    Pick(usize),
    Ignore,
}

/// How far (px) the mouse has to move before hover selects.
pub const MOVE_THRESHOLD: f64 = 2.0;

#[derive(Debug, Clone, PartialEq)]
pub struct PickerSession {
    pub links: Vec<String>,
    pub entries: Vec<PickerEntry>,
    pub selection: usize,
    /// The links were copied during this session.
    pub copied: bool,
    pub config_is_unreadable: bool,
    /// The row `Enter` opens until the selection moves; it carries the ↩ mark.
    pub default_row: Option<usize>,
    pub badges: HashMap<String, ProfileBadge>,
    /// Where the mouse was first seen. Hover only selects once it has moved away from there, so
    /// a pointer that happens to rest on a row doesn't override the default.
    first_pointer: Option<(f64, f64)>,
    pointer_moved: bool,
}

impl PickerSession {
    pub fn new(
        links: Vec<String>,
        entries: Vec<PickerEntry>,
        default_index: Option<usize>,
        config_is_unreadable: bool,
    ) -> Self {
        let default_row = default_index.filter(|i| *i < entries.len());
        let badges = ProfileBadge::badges(&entries.iter().map(|e| (&e.target, e.label.as_str())).collect::<Vec<_>>());
        PickerSession {
            links,
            selection: default_row.unwrap_or(0),
            entries,
            copied: false,
            config_is_unreadable,
            default_row,
            badges,
            first_pointer: None,
            pointer_moved: false,
        }
    }

    pub fn from_catalog(links: Vec<String>, catalog: &CatalogState) -> Self {
        let entries = catalog.picker_entries();
        let default = catalog.default_index(&entries);
        PickerSession::new(links, entries, default, catalog.config_is_unreadable)
    }

    /// More links arrived while the picker is open; one choice opens them all.
    pub fn add(&mut self, more: Vec<String>) {
        for l in more {
            if !self.links.contains(&l) {
                self.links.push(l);
            }
        }
    }

    /// Effects to perform; None if the input isn't the picker's.
    pub fn handle(&mut self, input: PickerInput) -> Option<Vec<PickerEffect>> {
        match input {
            PickerInput::Key(press) => {
                let hotkeys: Vec<Option<char>> = self.entries.iter().map(|e| e.hotkey).collect();
                match key_action(&press, &hotkeys) {
                    KeyAction::Ignore => return None,
                    KeyAction::Cancel => return Some(vec![PickerEffect::Close]),
                    KeyAction::Confirm => return Some(self.pick(self.selection)),
                    KeyAction::MoveUp => self.move_selection(-1),
                    KeyAction::MoveDown => self.move_selection(1),
                    KeyAction::MoveFirst => self.select(0),
                    KeyAction::MoveLast => self.select(self.entries.len().saturating_sub(1)),
                    KeyAction::Copy => return Some(self.copy()),
                    KeyAction::Settings => return Some(vec![PickerEffect::Close, PickerEffect::OpenSettings]),
                    KeyAction::Pick(row) => return Some(self.pick(row)),
                }
                Some(vec![])
            }
            PickerInput::Click { row } => Some(self.pick(row)),
            PickerInput::Hover { row, x, y } => {
                if !self.pointer_moved {
                    match self.first_pointer {
                        None => {
                            self.first_pointer = Some((x, y));
                            return Some(vec![]);
                        }
                        Some((fx, fy)) if (x - fx).hypot(y - fy) < MOVE_THRESHOLD => return Some(vec![]),
                        Some(_) => self.pointer_moved = true,
                    }
                }
                self.select(row);
                Some(vec![])
            }
            PickerInput::CopyButton => Some(self.copy()),
            PickerInput::SettingsButton => Some(vec![PickerEffect::Close, PickerEffect::OpenSettings]),
            PickerInput::LostFocus => Some(vec![PickerEffect::Close]),
        }
    }

    fn select(&mut self, row: usize) {
        if row < self.entries.len() {
            self.selection = row;
        }
    }

    fn move_selection(&mut self, delta: isize) {
        let n = self.entries.len() as isize;
        if n > 0 {
            self.selection = ((self.selection as isize + delta).rem_euclid(n)) as usize;
        }
    }

    fn pick(&self, row: usize) -> Vec<PickerEffect> {
        match self.entries.get(row) {
            Some(e) => vec![PickerEffect::Close, PickerEffect::Open(self.links.clone(), e.target.clone())],
            None => vec![],
        }
    }

    fn copy(&mut self) -> Vec<PickerEffect> {
        self.copied = true;
        vec![PickerEffect::Copy(self.links.join("\n"))]
    }
}

/// Maps a key press to what it should do (SPEC 4, Windows: Ctrl instead of ⌘).
fn key_action(press: &KeyPress, hotkeys: &[Option<char>]) -> KeyAction {
    match press.key.as_str() {
        "Escape" => return KeyAction::Cancel,
        "Enter" => return KeyAction::Confirm,
        "ArrowUp" => return KeyAction::MoveUp,
        "ArrowDown" => return KeyAction::MoveDown,
        "Home" => return KeyAction::MoveFirst,
        "End" => return KeyAction::MoveLast,
        "Tab" => {
            return match (press.ctrl || press.alt || press.meta, press.shift) {
                (false, false) => KeyAction::MoveDown,
                (false, true) => KeyAction::MoveUp,
                _ => KeyAction::Ignore,
            };
        }
        _ => {}
    }
    let mut chars = press.key.chars();
    let (Some(c), None) = (chars.next(), chars.next()) else { return KeyAction::Ignore };
    let key = c.to_lowercase().next().unwrap_or(c);
    let ctrl_only = press.ctrl && !press.alt && !press.meta;
    if ctrl_only && key == 'c' {
        return KeyAction::Copy;
    }
    if ctrl_only && key == ',' {
        return KeyAction::Settings;
    }
    // Ctrl+Alt is AltGr on many layouts (`@` on German keyboards): a typed character, not a shortcut.
    let alt_gr = press.ctrl && press.alt;
    if (press.ctrl || press.alt || press.meta) && !alt_gr {
        return KeyAction::Ignore;
    }
    match hotkeys.iter().position(|h| *h == Some(key)) {
        Some(i) => KeyAction::Pick(i),
        None => KeyAction::Ignore,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::target::TargetKind;

    fn entry(id: &str, key: char) -> PickerEntry {
        PickerEntry {
            target: Target { id: id.into(), name: id.into(), kind: TargetKind::App { exe: format!("{id}.exe") } },
            label: id.into(),
            hotkey: Some(key),
        }
    }

    fn key(k: &str) -> PickerInput {
        PickerInput::Key(KeyPress { key: k.into(), ctrl: false, alt: false, shift: false, meta: false })
    }

    fn session() -> PickerSession {
        PickerSession::new(
            vec!["https://a.com/".into()],
            vec![entry("a", '1'), entry("b", '2'), entry("c", 'w')],
            Some(1),
            false,
        )
    }

    #[test]
    fn default_row_is_preselected_and_enter_opens_it() {
        let mut s = session();
        assert_eq!(s.selection, 1);
        let fx = s.handle(key("Enter")).unwrap();
        assert!(matches!(&fx[1], PickerEffect::Open(_, t) if t.id == "b"));
    }

    #[test]
    fn navigation_wraps_and_hotkeys_pick() {
        let mut s = session();
        s.handle(key("ArrowDown"));
        s.handle(key("ArrowDown"));
        assert_eq!(s.selection, 0);
        s.handle(key("ArrowUp"));
        assert_eq!(s.selection, 2);
        s.handle(key("Home"));
        assert_eq!(s.selection, 0);
        s.handle(PickerInput::Key(KeyPress { key: "Tab".into(), shift: true, ctrl: false, alt: false, meta: false }));
        assert_eq!(s.selection, 2);
        let fx = s.handle(key("W")).unwrap();
        assert!(matches!(&fx[1], PickerEffect::Open(_, t) if t.id == "c"));
        assert_eq!(s.handle(key("x")), None);
        assert_eq!(s.handle(key("Escape")), Some(vec![PickerEffect::Close]));
    }

    #[test]
    fn ctrl_shortcuts_and_alt_gr() {
        let mut s = session();
        let ctrl =
            |k: &str| PickerInput::Key(KeyPress { key: k.into(), ctrl: true, alt: false, shift: false, meta: false });
        assert_eq!(s.handle(ctrl("c")), Some(vec![PickerEffect::Copy("https://a.com/".into())]));
        assert!(s.copied);
        assert_eq!(s.handle(ctrl(",")), Some(vec![PickerEffect::Close, PickerEffect::OpenSettings]));
        assert_eq!(s.handle(ctrl("1")), None);
        let alt_gr = PickerInput::Key(KeyPress { key: "w".into(), ctrl: true, alt: true, shift: false, meta: false });
        assert!(matches!(&s.handle(alt_gr).unwrap()[1], PickerEffect::Open(_, t) if t.id == "c"));
    }

    #[test]
    fn hover_needs_the_mouse_to_move_first() {
        let mut s = session();
        s.handle(PickerInput::Hover { row: 0, x: 10.0, y: 10.0 });
        assert_eq!(s.selection, 1);
        s.handle(PickerInput::Hover { row: 0, x: 11.0, y: 10.5 });
        assert_eq!(s.selection, 1);
        s.handle(PickerInput::Hover { row: 0, x: 13.0, y: 10.0 });
        assert_eq!(s.selection, 0);
        s.handle(PickerInput::Hover { row: 2, x: 13.0, y: 10.0 });
        assert_eq!(s.selection, 2);
    }

    #[test]
    fn links_collect() {
        let mut s = session();
        s.add(vec!["https://a.com/".into(), "https://b.com/".into()]);
        assert_eq!(s.links, ["https://a.com/", "https://b.com/"]);
    }

    #[test]
    fn empty_picker() {
        let mut s = PickerSession::new(vec!["https://a.com/".into()], vec![], Some(0), false);
        assert_eq!(s.default_row, None);
        assert_eq!(s.handle(key("Enter")), Some(vec![]));
        assert_eq!(s.handle(PickerInput::SettingsButton), Some(vec![PickerEffect::Close, PickerEffect::OpenSettings]));
    }
}
