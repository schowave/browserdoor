//! Browserdoor for Windows. The domain is `browserdoor-core`; this crate is the Windows shell
//! around it: the resident instance, its windows and tray icon, and the adapters for the seams
//! (registry, file system, processes). See SPEC.md, sections marked "Windows".
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(windows)]
mod app;
#[cfg(windows)]
mod i18n;
#[cfg(windows)]
mod icons;
#[cfg(windows)]
mod ipc;
#[cfg(windows)]
mod picker;
#[cfg(windows)]
mod prefs;
#[cfg(windows)]
mod registry;
#[cfg(windows)]
mod settings;
#[cfg(windows)]
mod system;
#[cfg(windows)]
mod tray;
#[cfg(windows)]
mod updates;
#[cfg(windows)]
mod views;

fn main() {
    #[cfg(windows)]
    app::main();
    #[cfg(not(windows))]
    {
        eprintln!("Browserdoor for Windows runs on Windows; the macOS app lives in Sources/.");
        std::process::exit(1);
    }
}
