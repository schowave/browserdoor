//! Adapters for the seams of `browserdoor-core` (`BrowserEnvironment`, `LaunchPort`) and small
//! Windows helpers.

use std::collections::HashSet;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;

use browserdoor_core::{BrowserEnvironment, ExeInfo, LaunchCommand, LaunchPort, RegisteredApp, paths};
use windows_sys::Win32::Foundation::{CloseHandle, HWND, INVALID_HANDLE_VALUE, LPARAM, POINT, RECT};
use windows_sys::Win32::Graphics::Gdi::{GetMonitorInfoW, MONITOR_DEFAULTTONEAREST, MONITORINFO, MonitorFromPoint};
use windows_sys::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows_sys::Win32::System::Console::{ATTACH_PARENT_PROCESS, AttachConsole, GetStdHandle, STD_OUTPUT_HANDLE};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::Threading::{
    CREATE_NEW_PROCESS_GROUP, DETACHED_PROCESS, OpenProcess, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
    QueryFullProcessImageNameW,
};
use windows_sys::Win32::UI::HiDpi::{GetDpiForMonitor, MDT_EFFECTIVE_DPI};
use windows_sys::Win32::UI::Shell::ShellExecuteW;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    ASFW_ANY, AllowSetForegroundWindow, EnumWindows, GW_OWNER, GetCursorPos, GetWindow, GetWindowThreadProcessId,
    IsIconic, IsWindowVisible, SW_RESTORE, SW_SHOWNORMAL, SetForegroundWindow, ShowWindow,
};

use crate::registry;

pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn from_wide(buf: &[u16]) -> String {
    let end = buf.iter().position(|c| *c == 0).unwrap_or(buf.len());
    String::from_utf16_lossy(&buf[..end])
}

/// Release builds (Scoop) are "Browserdoor"; debug builds run as "Browserdoor Dev" and share
/// neither the registration, the resident instance nor the settings with the installed app.
pub fn is_release_build() -> bool {
    !cfg!(debug_assertions)
}

pub fn identity() -> &'static str {
    if is_release_build() { "Browserdoor" } else { "Browserdoor Dev" }
}

pub fn version() -> &'static str {
    option_env!("BROWSERDOOR_VERSION").unwrap_or("0.0.0")
}

/// The path that survives updates (the **stable link**): Scoop's `current` folder instead of
/// the versioned one this process may run from.
pub fn stable_exe() -> String {
    let exe = std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default();
    stable_path(&exe)
}

pub fn stable_path(exe: &str) -> String {
    let lower = exe.to_lowercase();
    if let Some(i) = lower.find(r"\scoop\apps\browserdoor\") {
        let start = i + r"\scoop\apps\browserdoor\".len();
        if let Some(rel) = exe[start..].find('\\') {
            return format!("{}current{}", &exe[..start], &exe[start + rel..]);
        }
    }
    exe.to_string()
}

pub fn is_scoop_install() -> bool {
    stable_exe().to_lowercase().contains(r"\scoop\apps\browserdoor\current\")
}

pub fn app_data_dir() -> PathBuf {
    let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(base).join(identity())
}

pub fn log(message: &str) {
    use std::io::Write;
    let dir = app_data_dir();
    let _ = std::fs::create_dir_all(&dir);
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(dir.join("browserdoor.log")) {
        let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let _ = writeln!(f, "{secs} {message}");
    }
}

pub fn fatal(message: &str) {
    log(message);
    std::process::exit(1);
}

/// `--list-targets` prints to the terminal it was started from (the app has no console).
pub fn attach_console() {
    // Redirected output (a pipe, a file) is inherited and works as is; only an interactive
    // terminal needs attaching.
    // SAFETY: plain Win32 calls.
    unsafe {
        let out = GetStdHandle(STD_OUTPUT_HANDLE);
        if out.is_null() || out == INVALID_HANDLE_VALUE {
            AttachConsole(ATTACH_PARENT_PROCESS);
        }
    }
}

/// Opens a URL, a `ms-settings:` page or a file with the shell.
pub fn shell_open(target: &str) {
    let op = wide("open");
    let file = wide(target);
    // SAFETY: NUL-terminated strings.
    unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            op.as_ptr(),
            file.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            SW_SHOWNORMAL,
        )
    };
}

pub fn reveal_in_explorer(path: &str) {
    let _ = std::process::Command::new("explorer.exe").raw_arg(format!("/select,\"{path}\"")).spawn();
}

// -----------------------------------------------------------------------------------------------
// BrowserEnvironment

pub struct WinEnv;

impl WinEnv {
    pub fn new() -> WinEnv {
        WinEnv
    }
}

impl BrowserEnvironment for WinEnv {
    fn local_app_data(&self) -> String {
        std::env::var("LOCALAPPDATA").unwrap_or_default()
    }
    fn roaming_app_data(&self) -> String {
        std::env::var("APPDATA").unwrap_or_default()
    }
    fn own_app_id(&self) -> String {
        identity().to_string()
    }
    fn registered_browsers(&self) -> Vec<RegisteredApp> {
        registry::browsers()
    }
    fn contents(&self, path: &str) -> Option<Vec<u8>> {
        std::fs::read(path).ok()
    }
    fn exe_info(&self, exe: &str) -> Option<ExeInfo> {
        if !std::path::Path::new(exe).is_file() {
            return None;
        }
        let name = file_description(exe).unwrap_or_else(|| {
            let file = paths::file_name(exe);
            file.strip_suffix(".exe").or_else(|| file.strip_suffix(".EXE")).unwrap_or(file).to_string()
        });
        Some(ExeInfo { name })
    }
}

/// `FileDescription` (else `ProductName`) from the `.exe`'s version resource.
pub fn file_description(exe: &str) -> Option<String> {
    let path = wide(exe);
    // SAFETY: buffers are sized by GetFileVersionInfoSizeW; VerQueryValueW returns pointers into it.
    unsafe {
        let size = GetFileVersionInfoSizeW(path.as_ptr(), std::ptr::null_mut());
        if size == 0 {
            return None;
        }
        let mut data = vec![0u8; size as usize];
        if GetFileVersionInfoW(path.as_ptr(), 0, size, data.as_mut_ptr().cast()) == 0 {
            return None;
        }
        let mut ptr: *mut std::ffi::c_void = std::ptr::null_mut();
        let mut len = 0u32;
        let query = wide(r"\VarFileInfo\Translation");
        let mut langs: Vec<(u16, u16)> = vec![];
        if VerQueryValueW(data.as_ptr().cast(), query.as_ptr(), &mut ptr, &mut len) != 0 && len >= 4 {
            let pairs = std::slice::from_raw_parts(ptr as *const u16, (len / 2) as usize);
            langs.extend(pairs.chunks(2).filter(|c| c.len() == 2).map(|c| (c[0], c[1])));
        }
        langs.push((0x0409, 0x04B0));
        for key in ["FileDescription", "ProductName"] {
            for (lang, cp) in &langs {
                let q = wide(&format!(r"\StringFileInfo\{lang:04x}{cp:04x}\{key}"));
                if VerQueryValueW(data.as_ptr().cast(), q.as_ptr(), &mut ptr, &mut len) != 0 && len > 1 {
                    let s = from_wide(std::slice::from_raw_parts(ptr as *const u16, len as usize));
                    let s = s.trim().to_string();
                    if !s.is_empty() {
                        return Some(s);
                    }
                }
            }
        }
        None
    }
}

// -----------------------------------------------------------------------------------------------
// LaunchPort

pub struct WinLaunch;

impl LaunchPort for WinLaunch {
    fn is_running(&self, exe: &str) -> bool {
        is_running(exe)
    }

    fn run(&self, command: &LaunchCommand) {
        // Browserdoor holds the foreground (the picker had it): let the browser take it.
        unsafe { AllowSetForegroundWindow(ASFW_ANY) };
        let result = std::process::Command::new(&command.exe)
            .args(&command.args)
            .creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP)
            .spawn();
        if let Err(e) = result {
            log(&format!("could not start {}: {e}", command.exe));
        }
    }

    fn activate(&self, exe: &str) {
        activate(exe);
    }
}

/// Process IDs whose image is `exe`. A process whose path can't be read but whose file name
/// matches counts too: a running Zen must not be taken for closed.
fn processes_of(exe: &str) -> HashSet<u32> {
    let want = paths::normalized(exe);
    let want_name = paths::file_name(&want).to_string();
    let mut found = HashSet::new();
    // SAFETY: snapshot handle is closed below; entries are plain structs.
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snap == INVALID_HANDLE_VALUE {
            return found;
        }
        let mut entry: PROCESSENTRY32W = std::mem::zeroed();
        entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
        let mut ok = Process32FirstW(snap, &mut entry);
        while ok != 0 {
            let name = from_wide(&entry.szExeFile).to_lowercase();
            if name == want_name {
                match image_path(entry.th32ProcessID) {
                    Some(path) if paths::normalized(&path) != want => {}
                    _ => {
                        found.insert(entry.th32ProcessID);
                    }
                }
            }
            ok = Process32NextW(snap, &mut entry);
        }
        CloseHandle(snap);
    }
    found
}

fn image_path(pid: u32) -> Option<String> {
    // SAFETY: handle closed below; buffer sized by `len`.
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h.is_null() {
            return None;
        }
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, buf.as_mut_ptr(), &mut len);
        CloseHandle(h);
        (ok != 0).then(|| String::from_utf16_lossy(&buf[..len as usize]))
    }
}

pub fn is_running(exe: &str) -> bool {
    !processes_of(exe).is_empty()
}

/// Brings the first visible top-level window of `exe` to the front.
pub fn activate(exe: &str) {
    struct Search {
        pids: HashSet<u32>,
        found: HWND,
    }
    unsafe extern "system" fn each(hwnd: HWND, lparam: LPARAM) -> i32 {
        // SAFETY: lparam is the &mut Search passed to EnumWindows below.
        let search = unsafe { &mut *(lparam as *mut Search) };
        let mut pid = 0u32;
        unsafe { GetWindowThreadProcessId(hwnd, &mut pid) };
        let owned = !unsafe { GetWindow(hwnd, GW_OWNER) }.is_null();
        if search.pids.contains(&pid) && unsafe { IsWindowVisible(hwnd) } != 0 && !owned {
            search.found = hwnd;
            return 0;
        }
        1
    }
    let mut search = Search { pids: processes_of(exe), found: std::ptr::null_mut() };
    if search.pids.is_empty() {
        return;
    }
    // SAFETY: the callback only runs during EnumWindows, while `search` lives.
    unsafe {
        EnumWindows(Some(each), &mut search as *mut Search as LPARAM);
        if !search.found.is_null() {
            if IsIconic(search.found) != 0 {
                ShowWindow(search.found, SW_RESTORE);
            }
            SetForegroundWindow(search.found);
        }
    }
}

// -----------------------------------------------------------------------------------------------
// Screen

/// The mouse position, the work area of its monitor (physical pixels) and the monitor's scale.
pub fn mouse_and_work_area() -> ((i32, i32), browserdoor_core::placement::Rect, f64) {
    // SAFETY: plain out-parameter calls.
    unsafe {
        let mut p = POINT { x: 0, y: 0 };
        GetCursorPos(&mut p);
        let monitor = MonitorFromPoint(p, MONITOR_DEFAULTTONEAREST);
        let mut info: MONITORINFO = std::mem::zeroed();
        info.cbSize = std::mem::size_of::<MONITORINFO>() as u32;
        let RECT { left, top, right, bottom } = if GetMonitorInfoW(monitor, &mut info) != 0 {
            info.rcWork
        } else {
            RECT { left: 0, top: 0, right: 1920, bottom: 1080 }
        };
        let (mut dx, mut dy) = (96u32, 96u32);
        let scale =
            if GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mut dx, &mut dy) == 0 { dx as f64 / 96.0 } else { 1.0 };
        (
            (p.x, p.y),
            browserdoor_core::placement::Rect { x: left, y: top, width: right - left, height: bottom - top },
            scale,
        )
    }
}
