//! Profile badge: the lettered circle on the icon of a target whose app appears more than once.

use std::collections::HashMap;

use crate::paths;
use crate::target::{Rgb, Target, TargetKind};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct ProfileBadge {
    pub letter: String,
    pub color: Rgb,
}

/// Colors that carry white text and stand out on app icons, in light and dark mode (as on macOS).
const PALETTE: [Rgb; 8] = [
    Rgb { r: 0xD9, g: 0x3A, b: 0x3A },
    Rgb { r: 0xE0, g: 0x7A, b: 0x10 },
    Rgb { r: 0x2E, g: 0x9E, b: 0x4F },
    Rgb { r: 0x16, g: 0x8C, b: 0x8C },
    Rgb { r: 0x2F, g: 0x6F, b: 0xDB },
    Rgb { r: 0x6E, g: 0x4B, b: 0xD8 },
    Rgb { r: 0xC2, g: 0x3E, b: 0x9E },
    Rgb { r: 0x6B, g: 0x72, b: 0x80 },
];

impl ProfileBadge {
    /// Badges by target ID for the targets as listed, each with its display name. Zen spaces
    /// and apps listed once get none.
    pub fn badges(targets: &[(&Target, &str)]) -> HashMap<String, ProfileBadge> {
        let mut per_app: HashMap<String, Vec<(&Target, &str)>> = HashMap::new();
        for (t, label) in targets.iter().filter(|(t, _)| !matches!(t.kind, TargetKind::ZenSpace { .. })) {
            per_app.entry(paths::normalized(t.exe())).or_default().push((t, label));
        }
        let mut result = HashMap::new();
        for group in per_app.values().filter(|g| g.len() > 1) {
            for (t, label) in group {
                result.insert(t.id.clone(), ProfileBadge { letter: initial(label), color: color(&t.id) });
            }
        }
        result
    }
}

/// The first letter or digit of the profile's part of the name ("Firefox › Work" → "W").
pub fn initial(name: &str) -> String {
    let profile = name.rsplit(" › ").next().unwrap_or(name);
    profile.chars().find(|c| c.is_alphanumeric()).map(|c| c.to_uppercase().collect()).unwrap_or_else(|| "?".to_string())
}

/// The same color for a target ID on every launch (FNV-1a, as on macOS).
pub fn color(id: &str) -> Rgb {
    let mut hash: u64 = 0xCBF2_9CE4_8422_2325;
    for b in id.bytes() {
        hash = (hash ^ b as u64).wrapping_mul(0x0000_0100_0000_01B3);
    }
    PALETTE[(hash % PALETTE.len() as u64) as usize]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initials() {
        assert_eq!(initial("Firefox › work"), "W");
        assert_eq!(initial("Chrome › 2nd"), "2");
        assert_eq!(initial("Chrome › ✨"), "?");
    }

    #[test]
    fn only_apps_listed_more_than_once() {
        let a = Target {
            id: "chromium:C:Default".into(),
            name: "C › A".into(),
            kind: TargetKind::ChromiumProfile { exe: "C.exe".into(), profile_directory: "Default".into() },
        };
        let b = Target {
            id: "chromium:C:P1".into(),
            name: "C › B".into(),
            kind: TargetKind::ChromiumProfile { exe: "c.exe".into(), profile_directory: "P1".into() },
        };
        let e = Target { id: "app:E".into(), name: "E".into(), kind: TargetKind::App { exe: "e.exe".into() } };
        let badges = ProfileBadge::badges(&[(&a, "C › A"), (&b, "C › B"), (&e, "E")]);
        assert_eq!(badges.len(), 2);
        assert_eq!(badges["chromium:C:P1"].letter, "B");
        assert_eq!(color("x"), color("x"));
    }
}
