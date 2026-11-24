//! The picker window (SPEC 4, Windows): created hidden at startup so it appears without a
//! WebView2 cold start, shown at the mouse for every link, hidden again after a choice.

use browserdoor_core::picker::PickerInput;
use browserdoor_core::{LinkOpener, PickerEffect, PickerSession, TargetCatalog, placement};
use tauri::{
    AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};
use tauri_plugin_clipboard_manager::ClipboardExt;

use crate::app::AppState;
use crate::views::{self, PickerView};
use crate::{prefs, settings, system};

pub const LABEL: &str = "picker";
const WIDTH: f64 = 380.0;

#[derive(Default)]
pub struct PickerState {
    pub session: Option<PickerSession>,
    /// The mouse position the picker opened at, and the monitor's work area and scale.
    anchor: Option<((i32, i32), placement::Rect, f64)>,
}

pub fn create_window(app: &AppHandle) -> tauri::Result<()> {
    let window = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::App("picker.html".into()))
        .title("Browserdoor")
        .inner_size(WIDTH, 300.0)
        .decorations(false)
        .resizable(false)
        .maximizable(false)
        .minimizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        .shadow(true)
        .transparent(true)
        .effects(tauri::window::EffectsBuilder::new().effect(tauri::window::Effect::Acrylic).build())
        .build()?;
    let handle = app.clone();
    window.on_window_event(move |event| {
        if let WindowEvent::Focused(false) = event {
            let is_open = handle.state::<AppState>().picker.lock().map(|p| p.session.is_some()).unwrap_or(false);
            if is_open {
                let _ = input(&handle, PickerInput::LostFocus);
            }
        }
    });
    Ok(())
}

/// Links arrived: a new picker at the mouse, or more links for the open one.
pub fn present(app: &AppHandle, links: Vec<String>) {
    let state = app.state::<AppState>();
    let Some(window) = app.get_webview_window(LABEL) else { return };
    let view = {
        let Ok(mut picker) = state.picker.lock() else { return };
        if let Some(session) = picker.session.as_mut() {
            session.add(links);
            let view = views::picker(&state, session);
            drop(picker);
            let _ = window.emit_to(LABEL, "picker-state", &view);
            let _ = window.set_focus();
            return;
        }
        // Discovery runs every time the picker opens, so new Zen spaces and profiles show up.
        let env = system::WinEnv::new();
        let catalog = TargetCatalog { environment: &env, config_path: prefs::config_path() }.load();
        let session = PickerSession::from_catalog(links, &catalog);
        let view = views::picker(&state, &session);
        let anchor = system::mouse_and_work_area();
        picker.anchor = Some(anchor);
        let height = estimated_height(&session);
        place(&window, anchor, height);
        picker.session = Some(session);
        view
    };
    let _ = window.emit_to(LABEL, "picker-state", &view);
    let _ = window.show();
    let _ = window.set_focus();
    if !window.is_focused().unwrap_or(false) {
        // Windows refused the foreground: blink in the taskbar instead of opening without focus.
        let _ = window.request_user_attention(Some(tauri::UserAttentionType::Critical));
    }
}

/// Logical height of the picker for its rows; the page reports its real height afterwards.
fn estimated_height(session: &PickerSession) -> f64 {
    let rows = if session.entries.is_empty() { 2.4 } else { session.entries.len() as f64 };
    let notice = if session.config_is_unreadable { 34.0 } else { 0.0 };
    8.0 + 40.0 + notice + 6.0 + rows * 40.0 + 44.0
}

fn place(window: &tauri::WebviewWindow, anchor: ((i32, i32), placement::Rect, f64), logical_height: f64) {
    let (mouse, work, scale) = anchor;
    let max = (work.height as f64 / scale) - 16.0;
    let size = ((WIDTH * scale).round() as i32, (logical_height.min(max) * scale).round() as i32);
    let (x, y) = placement::origin(mouse, size, work, scale);
    let _ = window.set_size(PhysicalSize::new(size.0 as u32, size.1 as u32));
    let _ = window.set_position(PhysicalPosition::new(x, y));
}

fn input(app: &AppHandle, input: PickerInput) -> Option<PickerView> {
    let state = app.state::<AppState>();
    let effects = {
        let mut picker = state.picker.lock().ok()?;
        let session = picker.session.as_mut()?;
        session.handle(input)?
    };
    let mut closed = false;
    for effect in effects {
        match effect {
            PickerEffect::Close => {
                closed = true;
                if let Ok(mut picker) = state.picker.lock() {
                    picker.session = None;
                }
                if let Some(w) = app.get_webview_window(LABEL) {
                    let _ = w.hide();
                }
            }
            PickerEffect::Open(links, target) => {
                LinkOpener { port: &system::WinLaunch }.open(&links, &target);
            }
            PickerEffect::Copy(text) => {
                let _ = app.clipboard().write_text(text);
            }
            PickerEffect::OpenSettings => settings::show(app, Some("targets")),
        }
    }
    if closed {
        return None;
    }
    let picker = state.picker.lock().ok()?;
    picker.session.as_ref().map(|s| views::picker(&state, s))
}

#[tauri::command]
pub fn picker_state(app: AppHandle) -> Option<PickerView> {
    let state = app.state::<AppState>();
    let picker = state.picker.lock().ok()?;
    picker.session.as_ref().map(|s| views::picker(&state, s))
}

#[tauri::command]
pub fn picker_input(app: AppHandle, input: PickerInput) -> Option<PickerView> {
    self::input(&app, input)
}

/// The page's real height (logical pixels): resize, keeping the window at the mouse.
#[tauri::command]
pub fn picker_resize(app: AppHandle, height: f64) {
    let state = app.state::<AppState>();
    let Some(anchor) = state.picker.lock().ok().and_then(|p| p.anchor) else { return };
    if let Some(window) = app.get_webview_window(LABEL) {
        place(&window, anchor, height);
    }
}
