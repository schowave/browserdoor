//! App icons for the picker and the settings: the `.exe`'s icon as a PNG data URL, cached per path.

use std::collections::HashMap;
use std::sync::Mutex;

use base64::Engine;
use windows_sys::Win32::Graphics::Gdi::{
    BI_RGB, BITMAPINFO, BITMAPINFOHEADER, CreateCompatibleDC, DIB_RGB_COLORS, DeleteDC, DeleteObject, GetDIBits,
};
use windows_sys::Win32::UI::Shell::SHDefExtractIconW;
use windows_sys::Win32::UI::WindowsAndMessaging::{DestroyIcon, GetIconInfo, HICON, ICONINFO};

use crate::system::wide;

const SIZE: i32 = 48;

#[derive(Default)]
pub struct IconCache {
    icons: Mutex<HashMap<String, Option<String>>>,
}

impl IconCache {
    pub fn get(&self, exe: &str) -> Option<String> {
        let key = exe.to_lowercase();
        if let Some(hit) = self.icons.lock().ok()?.get(&key) {
            return hit.clone();
        }
        let icon = extract(exe);
        if let Ok(mut map) = self.icons.lock() {
            map.insert(key, icon.clone());
        }
        icon
    }
}

fn extract(exe: &str) -> Option<String> {
    let path = wide(exe);
    let mut large: HICON = std::ptr::null_mut();
    // SAFETY: GDI objects are released below; buffers are sized for SIZE × SIZE × 4.
    unsafe {
        let hr = SHDefExtractIconW(path.as_ptr(), 0, 0, &mut large, std::ptr::null_mut(), SIZE as u32);
        if hr != 0 || large.is_null() {
            return None;
        }
        let mut info: ICONINFO = std::mem::zeroed();
        let ok = GetIconInfo(large, &mut info);
        if ok == 0 {
            DestroyIcon(large);
            return None;
        }
        let dc = CreateCompatibleDC(std::ptr::null_mut());
        let mut header: BITMAPINFO = std::mem::zeroed();
        header.bmiHeader = BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: SIZE,
            biHeight: -SIZE,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB,
            ..std::mem::zeroed()
        };
        let mut bgra = vec![0u8; (SIZE * SIZE * 4) as usize];
        let lines = GetDIBits(dc, info.hbmColor, 0, SIZE as u32, bgra.as_mut_ptr().cast(), &mut header, DIB_RGB_COLORS);
        // Icons without an alpha channel: take transparency from the mask.
        if lines != 0 && bgra.chunks(4).all(|p| p[3] == 0) {
            let mut mask = vec![0u8; (SIZE * SIZE * 4) as usize];
            GetDIBits(dc, info.hbmMask, 0, SIZE as u32, mask.as_mut_ptr().cast(), &mut header, DIB_RGB_COLORS);
            for (p, m) in bgra.chunks_mut(4).zip(mask.chunks(4)) {
                p[3] = if m[0] == 0 { 255 } else { 0 };
            }
        }
        DeleteDC(dc);
        DeleteObject(info.hbmColor);
        DeleteObject(info.hbmMask);
        DestroyIcon(large);
        if lines == 0 {
            return None;
        }
        for p in bgra.chunks_mut(4) {
            p.swap(0, 2);
        }
        let mut png_bytes = vec![];
        {
            let mut encoder = png::Encoder::new(&mut png_bytes, SIZE as u32, SIZE as u32);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder.write_header().ok()?;
            writer.write_image_data(&bgra).ok()?;
        }
        Some(format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(png_bytes)))
    }
}
