//! What the windows get to render (mirrors windows/ui/src/lib/api.ts).

use browserdoor_core::badge::{self, ProfileBadge};
use browserdoor_core::link_display::LinkDisplay;
use browserdoor_core::target::Rgb;
use browserdoor_core::{CatalogState, PickerSession, Target, TargetKind, paths};
use serde::Serialize;

use crate::app::AppState;
use crate::{prefs, registry, system, updates};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BadgeView {
    letter: String,
    color: Rgb,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IconView {
    image: Option<String>,
    emoji: Option<String>,
    initial: Option<String>,
    color: Option<Rgb>,
    badge: Option<BadgeView>,
}

fn icon(state: &AppState, target: &Target, label: &str, badge: Option<&ProfileBadge>) -> IconView {
    let badge = badge.map(|b| BadgeView { letter: b.letter.clone(), color: b.color });
    match &target.kind {
        TargetKind::ZenSpace { icon, color, .. } => IconView {
            image: None,
            emoji: icon.clone(),
            initial: Some(badge::initial(label)),
            color: *color,
            badge: None,
        },
        other => IconView { image: state.icons.get(other.exe()), emoji: None, initial: None, color: None, badge },
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkView {
    primary: String,
    secondary: String,
    line: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PickerEntryView {
    id: String,
    label: String,
    hotkey: Option<String>,
    icon: IconView,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PickerView {
    links: Vec<LinkView>,
    entries: Vec<PickerEntryView>,
    selection: usize,
    default_row: Option<usize>,
    copied: bool,
    config_unreadable: bool,
    accent: String,
}

fn home() -> String {
    std::env::var("USERPROFILE").unwrap_or_default()
}

pub fn picker(state: &AppState, session: &PickerSession) -> PickerView {
    let home = home();
    PickerView {
        links: session
            .links
            .iter()
            .map(|l| {
                let d = LinkDisplay::new(l, &home);
                LinkView { line: format!("{}{}", d.primary, d.secondary), primary: d.primary, secondary: d.secondary }
            })
            .collect(),
        entries: session
            .entries
            .iter()
            .map(|e| PickerEntryView {
                id: e.target.id.clone(),
                label: e.label.clone(),
                hotkey: e.hotkey.map(String::from),
                icon: icon(state, &e.target, &e.label, session.badges.get(&e.target.id)),
            })
            .collect(),
        selection: session.selection,
        default_row: session.default_row,
        copied: session.copied,
        config_unreadable: session.config_is_unreadable,
        accent: registry::accent_color(),
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TargetRowView {
    id: String,
    name: String,
    label: Option<String>,
    display_name: String,
    hotkey: Option<String>,
    effective_key: Option<String>,
    hidden: bool,
    is_default: bool,
    extra_app: Option<String>,
    icon: IconView,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtraAppView {
    exe: String,
    name: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsView {
    version: String,
    is_default_browser: bool,
    autostart: bool,
    autostart_error: Option<String>,
    show_in_tray: bool,
    check_automatically: bool,
    update: updates::Status,
    rows: Vec<TargetRowView>,
    unlisted_extra_apps: Vec<ExtraAppView>,
    zen_profile_path: Option<String>,
    config_path: String,
    config_unreadable: bool,
    accent: String,
}

pub fn settings(state: &AppState, catalog: &CatalogState, autostart_error: Option<String>) -> SettingsView {
    let keys = catalog.effective_keys();
    let entries = catalog.picker_entries();
    let badges = ProfileBadge::badges(&entries.iter().map(|e| (&e.target, e.label.as_str())).collect::<Vec<_>>());
    let prefs = state.prefs.lock().map(|p| p.clone()).unwrap_or_default();
    SettingsView {
        version: system::version().to_string(),
        is_default_browser: registry::is_default_browser(),
        autostart: registry::autostart_enabled(),
        autostart_error,
        show_in_tray: prefs.show_in_tray,
        check_automatically: prefs.update.check_automatically,
        update: state.update.lock().map(|u| u.clone()).unwrap_or(updates::Status::Idle),
        rows: catalog
            .rows
            .iter()
            .map(|r| TargetRowView {
                id: r.target.id.clone(),
                name: r.target.name.clone(),
                label: r.label.clone(),
                display_name: r.display_name().to_string(),
                hotkey: r.hotkey.map(String::from),
                effective_key: keys.iter().find(|(id, _)| *id == r.target.id).map(|(_, k)| k.to_string()),
                hidden: r.hidden,
                is_default: catalog.default_target.as_deref() == Some(r.target.id.as_str()),
                extra_app: catalog.extra_app_for_target(&r.target.id),
                icon: icon(state, &r.target, r.display_name(), badges.get(&r.target.id)),
            })
            .collect(),
        unlisted_extra_apps: catalog
            .unlisted_extra_apps()
            .into_iter()
            .map(|exe| ExtraAppView { name: paths::file_name(&exe).to_string(), exe })
            .collect(),
        zen_profile_path: catalog.zen_profile_path.clone(),
        config_path: prefs::config_path().display().to_string(),
        config_unreadable: catalog.config_is_unreadable,
        accent: registry::accent_color(),
    }
}
