//! What Browserdoor registers under HKCU (SPEC 8, Windows): a browser under
//! `StartMenuInternet` with its capabilities, the `RegisteredApplications` entry, the ProgIDs for
//! links and HTML files, and the login item (a `Run` value). No admin rights needed. Windows 10
//! and later let only the user pick the default browser, in the Settings app.

use browserdoor_core::RegisteredApp;
use windows_sys::Win32::UI::Shell::{
    ASSOCF_IS_PROTOCOL, ASSOCSTR_PROGID, AssocQueryStringW, SHCNE_ASSOCCHANGED, SHCNF_IDLIST, SHChangeNotify,
    SHLoadIndirectString,
};
use winreg::RegKey;
use winreg::enums::{HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE, KEY_READ, KEY_WOW64_32KEY};

use crate::system::{identity, wide};

fn names() -> (String, String, String) {
    let id = identity();
    let compact = id.replace(' ', "");
    (id.to_string(), format!("{compact}URL"), format!("{compact}HTML"))
}

fn start_menu_key(app: &str) -> String {
    format!(r"Software\Clients\StartMenuInternet\{app}")
}

const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";

/// Writes the registration, pointing at `exe` (the stable path). Cheap and idempotent, so every
/// launch repairs it; Windows is told only when something changed.
pub fn register(exe: &str) {
    let (app, url_prog, html_prog) = names();
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let open = format!("\"{exe}\" \"%1\"");
    let icon = format!("\"{exe}\",0");
    let mut changed = false;
    let mut set = |path: &str, name: &str, value: &str| {
        let Ok((key, _)) = hkcu.create_subkey(path) else { return };
        if key.get_value::<String, _>(name).ok().as_deref() != Some(value) {
            changed |= key.set_value(name, &value).is_ok();
        }
    };
    for (prog, description) in [(&url_prog, format!("{app} URL")), (&html_prog, format!("{app} HTML Document"))] {
        let base = format!(r"Software\Classes\{prog}");
        set(&base, "", &description);
        set(&base, "FriendlyTypeName", &description);
        set(&format!(r"{base}\DefaultIcon"), "", &icon);
        set(&format!(r"{base}\shell\open\command"), "", &open);
        set(&format!(r"{base}\Application"), "ApplicationName", &app);
    }
    let smi = start_menu_key(&app);
    set(&smi, "", &app);
    set(&format!(r"{smi}\DefaultIcon"), "", &icon);
    set(&format!(r"{smi}\shell\open\command"), "", &format!("\"{exe}\""));
    let caps = format!(r"{smi}\Capabilities");
    set(&caps, "ApplicationName", &app);
    set(&caps, "ApplicationIcon", &icon);
    set(&caps, "ApplicationDescription", "Choose the Zen space, browser profile or browser for every link.");
    set(&format!(r"{caps}\StartMenu"), "StartMenuInternet", &app);
    for scheme in ["http", "https"] {
        set(&format!(r"{caps}\URLAssociations"), scheme, &url_prog);
    }
    for ext in [".htm", ".html", ".xhtml"] {
        set(&format!(r"{caps}\FileAssociations"), ext, &html_prog);
    }
    set(r"Software\RegisteredApplications", &app, &caps);
    // Keep an existing login item pointing at the stable path.
    if autostart_enabled() {
        let _ = set_autostart(exe, true);
    }
    if changed {
        // SAFETY: plain notification without item pointers.
        unsafe { SHChangeNotify(SHCNE_ASSOCCHANGED as i32, SHCNF_IDLIST, std::ptr::null(), std::ptr::null()) };
    }
}

/// Removes everything `register` and the login item wrote (Scoop's uninstaller calls this).
pub fn unregister() {
    let (app, url_prog, html_prog) = names();
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    for path in
        [start_menu_key(&app), format!(r"Software\Classes\{url_prog}"), format!(r"Software\Classes\{html_prog}")]
    {
        let _ = hkcu.delete_subkey_all(path);
    }
    if let Ok(key) = hkcu.open_subkey_with_flags(r"Software\RegisteredApplications", winreg::enums::KEY_WRITE) {
        let _ = key.delete_value(&app);
    }
    if let Ok(key) = hkcu.open_subkey_with_flags(RUN_KEY, winreg::enums::KEY_WRITE) {
        let _ = key.delete_value(&app);
    }
    unsafe { SHChangeNotify(SHCNE_ASSOCCHANGED as i32, SHCNF_IDLIST, std::ptr::null(), std::ptr::null()) };
}

/// Whether the user chose Browserdoor for `https` links. Asks the shell for the effective
/// handler: Windows 11 keeps newer choices in `UserChoiceLatest\ProgId`, while `UserChoice` can
/// still name the previous browser, so reading one key is not enough.
pub fn is_default_browser() -> bool {
    let (_, url_prog, _) = names();
    match effective_https_prog_id() {
        Some(prog) => prog.eq_ignore_ascii_case(&url_prog),
        None => registry_https_prog_id().is_some_and(|p| p.eq_ignore_ascii_case(&url_prog)),
    }
}

/// The ProgID Windows opens `https` links with (`AssocQueryStringW`).
fn effective_https_prog_id() -> Option<String> {
    let scheme = wide("https");
    let mut buf = [0u16; 256];
    let mut len = buf.len() as u32;
    // SAFETY: NUL-terminated input; the output buffer holds `len` characters.
    let hr = unsafe {
        AssocQueryStringW(
            ASSOCF_IS_PROTOCOL,
            ASSOCSTR_PROGID,
            scheme.as_ptr(),
            std::ptr::null(),
            buf.as_mut_ptr(),
            &mut len,
        )
    };
    if hr != 0 {
        return None;
    }
    let end = buf.iter().position(|c| *c == 0).unwrap_or(0);
    let prog = String::from_utf16_lossy(&buf[..end]);
    (!prog.is_empty()).then_some(prog)
}

/// Fallback: the newest choice in the registry, `UserChoiceLatest` (value or `ProgId` subkey)
/// before `UserChoice`.
fn registry_https_prog_id() -> Option<String> {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let base = r"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https";
    [r"UserChoiceLatest\ProgId", "UserChoiceLatest", "UserChoice"].iter().find_map(|sub| {
        hkcu.open_subkey(format!(r"{base}\{sub}"))
            .and_then(|k| k.get_value::<String, _>("ProgId"))
            .ok()
            .filter(|p| !p.is_empty())
    })
}

/// The Settings page for Browserdoor's defaults (Windows 11), else the Default apps page.
pub fn open_default_apps_settings() {
    let (app, _, _) = names();
    crate::system::shell_open(&format!("ms-settings:defaultapps?registeredAppUser={}", app.replace(' ', "%20")));
}

pub fn autostart_enabled() -> bool {
    let (app, _, _) = names();
    RegKey::predef(HKEY_CURRENT_USER).open_subkey(RUN_KEY).and_then(|k| k.get_value::<String, _>(&app)).is_ok()
}

pub fn set_autostart(exe: &str, on: bool) -> Result<(), String> {
    let (app, _, _) = names();
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER).create_subkey(RUN_KEY).map_err(|e| e.to_string())?;
    if on {
        key.set_value(&app, &format!("\"{exe}\" --background")).map_err(|e| e.to_string())
    } else {
        match key.delete_value(&app) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}

/// Browsers under `StartMenuInternet`: HKCU first, then HKLM (64- and 32-bit views).
pub fn browsers() -> Vec<RegisteredApp> {
    let mut out = vec![];
    let roots = [
        (RegKey::predef(HKEY_CURRENT_USER), KEY_READ),
        (RegKey::predef(HKEY_LOCAL_MACHINE), KEY_READ),
        (RegKey::predef(HKEY_LOCAL_MACHINE), KEY_READ | KEY_WOW64_32KEY),
    ];
    for (root, flags) in roots {
        let Ok(smi) = root.open_subkey_with_flags(r"Software\Clients\StartMenuInternet", flags) else { continue };
        for app_id in smi.enum_keys().filter_map(Result::ok) {
            let Ok(key) = smi.open_subkey_with_flags(&app_id, flags) else { continue };
            let command: String = key
                .open_subkey_with_flags(r"shell\open\command", flags)
                .and_then(|k| k.get_value(""))
                .unwrap_or_default();
            let exe = first_token(&command);
            if exe.is_empty() {
                continue;
            }
            let caps_name: Option<String> = key
                .open_subkey_with_flags("Capabilities", flags)
                .and_then(|k| k.get_value("ApplicationName"))
                .ok()
                .map(|s: String| resolve_indirect(&s));
            let default_name: Option<String> = key.get_value("").ok();
            let name = default_name
                .filter(|s| !s.is_empty() && !s.starts_with('@'))
                .or(caps_name.filter(|s| !s.is_empty()))
                .unwrap_or_else(|| app_id.clone());
            out.push(RegisteredApp { app_id, name, exe });
        }
    }
    out
}

/// The program of a command line: `"C:\a b\x.exe" --arg` → `C:\a b\x.exe`.
fn first_token(command: &str) -> String {
    let c = command.trim();
    let token = if let Some(rest) = c.strip_prefix('"') {
        rest.split('"').next().unwrap_or("")
    } else {
        match c.to_lowercase().find(".exe") {
            Some(i) => &c[..i + 4],
            None => c.split(' ').next().unwrap_or(""),
        }
    };
    let expanded = expand_env(token);
    expanded.trim().to_string()
}

fn expand_env(s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find('%') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        match after.find('%') {
            Some(end) => {
                let name = &after[..end];
                out.push_str(&std::env::var(name).unwrap_or_else(|_| format!("%{name}%")));
                rest = &after[end + 1..];
            }
            None => {
                out.push_str(&rest[start..]);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

/// `@C:\x\app.dll,-123` → the resource string; anything else as is.
fn resolve_indirect(s: &str) -> String {
    if !s.starts_with('@') {
        return s.to_string();
    }
    let source = wide(s);
    let mut buf = [0u16; 512];
    // SAFETY: NUL-terminated input, buffer of the given length.
    let hr = unsafe { SHLoadIndirectString(source.as_ptr(), buf.as_mut_ptr(), buf.len() as u32, std::ptr::null_mut()) };
    if hr == 0 {
        let end = buf.iter().position(|c| *c == 0).unwrap_or(0);
        String::from_utf16_lossy(&buf[..end])
    } else {
        String::new()
    }
}

/// `#RRGGBB` of the Windows accent color.
pub fn accent_color() -> String {
    RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey(r"Software\Microsoft\Windows\DWM")
        .and_then(|k| k.get_value::<u32, _>("AccentColor"))
        .map(|abgr| format!("#{:02x}{:02x}{:02x}", abgr & 0xFF, (abgr >> 8) & 0xFF, (abgr >> 16) & 0xFF))
        .unwrap_or_else(|_| "#005fb8".to_string())
}

/// Whether the taskbar is light (its icons need a dark glyph).
pub fn taskbar_is_light() -> bool {
    RegKey::predef(HKEY_CURRENT_USER)
        .open_subkey(r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        .and_then(|k| k.get_value::<u32, _>("SystemUsesLightTheme"))
        .is_ok_and(|v| v == 1)
}

#[cfg(test)]
mod tests {
    #[test]
    fn first_token() {
        assert_eq!(
            super::first_token(r#""C:\Program Files\Zen Browser\zen.exe" -osint -url "%1""#),
            r"C:\Program Files\Zen Browser\zen.exe"
        );
        assert_eq!(super::first_token(r"C:\x\y.exe --flag"), r"C:\x\y.exe");
    }
}
