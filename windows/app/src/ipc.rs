//! One resident instance per user (SPEC 8, Windows). A named mutex decides who is resident; every
//! later launch hands its links over a named pipe and exits. Before it writes, it lets the
//! resident instance take the foreground (`AllowSetForegroundWindow`): the user just clicked a
//! link, so the launched process may come forward, and passes that right on to the picker.

use std::ffi::c_void;
use std::thread;
use std::time::Duration;

use windows_sys::Win32::Foundation::{
    CloseHandle, ERROR_ALREADY_EXISTS, ERROR_PIPE_BUSY, ERROR_PIPE_CONNECTED, GENERIC_WRITE, GetLastError, HANDLE,
    INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_FLAG_FIRST_PIPE_INSTANCE, OPEN_EXISTING, PIPE_ACCESS_INBOUND, ReadFile,
    WriteFile,
};
use windows_sys::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, GetNamedPipeServerProcessId, PIPE_READMODE_BYTE,
    PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE, PIPE_UNLIMITED_INSTANCES, PIPE_WAIT, WaitNamedPipeW,
};
use windows_sys::Win32::System::Threading::CreateMutexW;
use windows_sys::Win32::UI::WindowsAndMessaging::AllowSetForegroundWindow;

use crate::app::Launch;
use crate::system::{identity, wide};

/// The mutex is per session (`Local\`); the pipe name carries the user's SID, so another user
/// can't predict it, and the first instance is created with FILE_FLAG_FIRST_PIPE_INSTANCE, so
/// nobody can hold the name before the resident instance does.
fn names() -> (Vec<u16>, Vec<u16>) {
    let user = user_sid().unwrap_or_else(|| {
        std::env::var("USERNAME")
            .unwrap_or_default()
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '_' })
            .collect()
    });
    let id = identity().replace(' ', "");
    (wide(&format!(r"Local\{id}-resident")), wide(&format!(r"\\.\pipe\{id}-{user}")))
}

/// The current user's SID as text (`S-1-5-21-…`).
fn user_sid() -> Option<String> {
    use windows_sys::Win32::Foundation::LocalFree;
    use windows_sys::Win32::Security::Authorization::ConvertSidToStringSidW;
    use windows_sys::Win32::Security::{GetTokenInformation, TOKEN_QUERY, TOKEN_USER, TokenUser};
    use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};
    // SAFETY: the token handle is closed; the buffer is sized by the first call; the string
    // ConvertSidToStringSidW allocates is freed with LocalFree.
    unsafe {
        let mut token: HANDLE = std::ptr::null_mut();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
            return None;
        }
        let mut len = 0u32;
        GetTokenInformation(token, TokenUser, std::ptr::null_mut(), 0, &mut len);
        let mut buf = vec![0u8; len as usize];
        let ok = GetTokenInformation(token, TokenUser, buf.as_mut_ptr().cast(), len, &mut len);
        CloseHandle(token);
        if ok == 0 {
            return None;
        }
        let user = &*(buf.as_ptr() as *const TOKEN_USER);
        let mut text: *mut u16 = std::ptr::null_mut();
        if ConvertSidToStringSidW(user.User.Sid, &mut text) == 0 {
            return None;
        }
        let mut n = 0;
        while *text.add(n) != 0 {
            n += 1;
        }
        let sid = String::from_utf16_lossy(std::slice::from_raw_parts(text, n));
        LocalFree(text.cast());
        Some(sid)
    }
}

/// The pipe server of the resident instance.
pub struct Server {
    pipe_name: Vec<u16>,
}

/// Becomes the resident instance, or hands `launch` to the one that runs and returns None.
pub fn claim(launch: &Launch) -> Option<Server> {
    let (mutex_name, pipe_name) = names();
    // SAFETY: plain Win32 call with a NUL-terminated name; the handle is kept for the process lifetime.
    let mutex = unsafe { CreateMutexW(std::ptr::null(), 0, mutex_name.as_ptr()) };
    let already = unsafe { GetLastError() } == ERROR_ALREADY_EXISTS;
    if !mutex.is_null() && !already {
        return Some(Server { pipe_name });
    }
    if let Err(e) = forward(launch) {
        crate::system::log(&format!("hand-over to the resident instance failed: {e}"));
    }
    None
}

/// Sends `launch` to the resident instance. Retries for a few seconds while it starts up.
pub fn forward(launch: &Launch) -> Result<(), String> {
    let (_, pipe_name) = names();
    let payload = serde_json::to_vec(launch).map_err(|e| e.to_string())?;
    // Up to 30 s: at login the resident instance may still be starting WebView2.
    for _ in 0..300 {
        // SAFETY: NUL-terminated name; the handle is closed below.
        let h = unsafe {
            CreateFileW(
                pipe_name.as_ptr(),
                GENERIC_WRITE,
                0,
                std::ptr::null(),
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                std::ptr::null_mut(),
            )
        };
        if h == INVALID_HANDLE_VALUE {
            if unsafe { GetLastError() } == ERROR_PIPE_BUSY {
                unsafe { WaitNamedPipeW(pipe_name.as_ptr(), 500) };
            } else {
                thread::sleep(Duration::from_millis(100));
            }
            continue;
        }
        let mut pid = 0u32;
        // SAFETY: valid pipe handle; pid is a plain out parameter.
        if unsafe { GetNamedPipeServerProcessId(h, &mut pid) } != 0 {
            unsafe { AllowSetForegroundWindow(pid) };
        }
        let ok = write_all(h, &payload);
        unsafe { CloseHandle(h) };
        return if ok { Ok(()) } else { Err("write failed".into()) };
    }
    Err("no resident instance answered".into())
}

fn write_all(h: HANDLE, mut data: &[u8]) -> bool {
    while !data.is_empty() {
        let mut written = 0u32;
        // SAFETY: data is a valid buffer of the given length.
        let ok = unsafe { WriteFile(h, data.as_ptr(), data.len() as u32, &mut written, std::ptr::null_mut()) };
        if ok == 0 || written == 0 {
            return false;
        }
        data = &data[written as usize..];
    }
    true
}

impl Server {
    /// Serves the pipe on its own thread; `f` gets every launch that arrives.
    pub fn serve(self, f: impl Fn(Launch) + Send + 'static) {
        thread::spawn(move || {
            let mut first = true;
            loop {
                let flags = PIPE_ACCESS_INBOUND | if first { FILE_FLAG_FIRST_PIPE_INSTANCE } else { 0 };
                // SAFETY: NUL-terminated name; inbound only, local clients only.
                let h = unsafe {
                    CreateNamedPipeW(
                        self.pipe_name.as_ptr(),
                        flags,
                        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                        PIPE_UNLIMITED_INSTANCES,
                        0,
                        64 * 1024,
                        0,
                        std::ptr::null(),
                    )
                };
                first = false;
                if h == INVALID_HANDLE_VALUE {
                    crate::system::log("CreateNamedPipeW failed");
                    thread::sleep(Duration::from_secs(1));
                    continue;
                }
                let connected = unsafe { ConnectNamedPipe(h, std::ptr::null_mut()) } != 0
                    || unsafe { GetLastError() } == ERROR_PIPE_CONNECTED;
                let data = if connected { read_all(h) } else { vec![] };
                unsafe {
                    DisconnectNamedPipe(h);
                    CloseHandle(h);
                }
                if let Ok(launch) = serde_json::from_slice::<Launch>(&data) {
                    f(launch);
                }
            }
        });
    }
}

fn read_all(h: HANDLE) -> Vec<u8> {
    let mut out = vec![];
    let mut buf = [0u8; 8192];
    loop {
        let mut read = 0u32;
        // SAFETY: buf is valid for its length.
        let ok = unsafe {
            ReadFile(h, buf.as_mut_ptr() as *mut c_void as *mut u8, buf.len() as u32, &mut read, std::ptr::null_mut())
        };
        if read > 0 {
            out.extend_from_slice(&buf[..read as usize]);
        }
        if ok == 0 || read == 0 || out.len() > 1024 * 1024 {
            return out;
        }
    }
}
