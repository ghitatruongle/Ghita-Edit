//! GDI text rasterization for text/sticker clips (Windows only) — port of
//! C++ renderTextGdi including the LRU bitmap cache (cap 16, keyed by
//! text/font size/color/frame size). On non-Windows platforms it returns
//! false exactly like the C++ `#else` branch.

use std::collections::VecDeque;

/// v1.1.0 (PLAN 2.8/C6): cached rasterized text frames.
pub struct TextGlyphCacheEntry {
    pub key: String,
    pub width: i32,
    pub height: i32,
    pub rgba: Vec<u8>,
}

const MAX_TEXT_CACHE_ENTRIES: usize = 16;

/// Rasterizes [text] into [out] (RGBA, transparent background). Returns false
/// on non-Windows or when the payload is invalid.
#[cfg(windows)]
pub fn render_text_gdi(
    cache: &mut VecDeque<TextGlyphCacheEntry>,
    out: &mut [u8],
    width: usize,
    height: usize,
    text: &str,
    font_size: f32,
    color_argb: u32,
) -> bool {
    use windows_sys::Win32::Foundation::RECT;
    use windows_sys::Win32::Globalization::{MultiByteToWideChar, CP_UTF8};
    use windows_sys::Win32::Graphics::Gdi::{
        CreateCompatibleDC, CreateDIBSection, CreateFontW, DeleteDC, DeleteObject, DrawTextW,
        GdiFlush, SelectObject, SetBkMode, SetTextColor, BITMAPINFO, BITMAPINFOHEADER, BI_RGB,
        CLEARTYPE_QUALITY, DIB_RGB_COLORS, DT_CENTER, DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER,
        FW_NORMAL, RGBQUAD, TRANSPARENT,
    };

    if text.is_empty() || width == 0 || height == 0 || out.len() < width * height * 4 {
        return false;
    }

    // Serve repeated payloads from the bitmap cache (LRU).
    let cache_key = format!("{width}x{height}|{font_size}|{color_argb}|{text}");
    if let Some(pos) = cache.iter().position(|e| e.key == cache_key) {
        let entry = cache.remove(pos).unwrap();
        let n = entry.rgba.len();
        out[..n].copy_from_slice(&entry.rgba);
        cache.push_front(entry);
        return true;
    }

    let bmi = BITMAPINFO {
        bmiHeader: BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: width as i32,
            biHeight: -(height as i32), // top-down
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB,
            biSizeImage: 0,
            biXPelsPerMeter: 0,
            biYPelsPerMeter: 0,
            biClrUsed: 0,
            biClrImportant: 0,
        },
        bmiColors: [RGBQUAD { rgbBlue: 0, rgbGreen: 0, rgbRed: 0, rgbReserved: 0 }],
    };

    let dc = unsafe { CreateCompatibleDC(std::ptr::null_mut()) };
    if dc.is_null() {
        return false;
    }
    let mut bits: *mut std::ffi::c_void = std::ptr::null_mut();
    let dib = unsafe {
        CreateDIBSection(
            dc,
            &bmi,
            DIB_RGB_COLORS,
            &mut bits,
            std::ptr::null_mut(),
            0,
        )
    };
    if dib.is_null() {
        unsafe { DeleteDC(dc) };
        return false;
    }
    let old_bmp = unsafe { SelectObject(dc, dib as _) };

    let font_h = (font_size * 96.0 / 72.0).max(6.0) as i32;
    let font = unsafe {
        CreateFontW(
            -font_h,
            0,
            0,
            0,
            FW_NORMAL as i32, // cweight is i32 in windows-sys while FW_NORMAL is u32
            0,                // italic
            0,                // underline
            0,                // strikeout
            1,                // DEFAULT_CHARSET (u32)
            0,                // OUT_DEFAULT_PRECIS
            0,                // CLIP_DEFAULT_PRECIS
            CLEARTYPE_QUALITY as u32,
            0, // DEFAULT_PITCH | FF_DONTCARE
            windows_sys::core::w!("Segoe UI"),
        )
    };
    let old_font = unsafe { SelectObject(dc, font as _) };

    unsafe { SetBkMode(dc, TRANSPARENT as i32) };
    let cr = (color_argb >> 16) & 0xFF;
    let cg = (color_argb >> 8) & 0xFF;
    let cb = color_argb & 0xFF;
    let colorref = cr | (cg << 8) | (cb << 16);
    unsafe { SetTextColor(dc, colorref) };

    // UTF-8 → UTF-16 (emoji stickers need wide chars).
    let wlen = unsafe {
        MultiByteToWideChar(
            CP_UTF8,
            0,
            text.as_ptr(),
            text.len() as i32,
            std::ptr::null_mut(),
            0,
        )
    };
    let mut wtext = vec![0u16; (wlen.max(0) + 1) as usize];
    if wlen > 0 {
        unsafe {
            MultiByteToWideChar(
                CP_UTF8,
                0,
                text.as_ptr(),
                text.len() as i32,
                wtext.as_mut_ptr(),
                wlen,
            );
        }
    }
    let mut rc = RECT {
        left: 0,
        top: 0,
        right: width as i32,
        bottom: height as i32,
    };
    unsafe {
        DrawTextW(
            dc,
            wtext.as_ptr(),
            -1,
            &mut rc,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX,
        );
        GdiFlush();
    }

    // Copy DIB → output; any non-zero pixel is drawn content → alpha 255.
    let src = bits as *const u8;
    for i in 0..width * height {
        let si = i * 4;
        // DIB 32bpp memory order is BGRA.
        let sr = unsafe { *src.add(si + 2) };
        let sg = unsafe { *src.add(si + 1) };
        let sb = unsafe { *src.add(si) };
        out[si] = sr;
        out[si + 1] = sg;
        out[si + 2] = sb;
        out[si + 3] = if (sr | sg | sb) != 0 { 255 } else { 0 };
    }

    unsafe {
        SelectObject(dc, old_font);
        SelectObject(dc, old_bmp);
        DeleteObject(font as _);
        DeleteObject(dib as _);
        DeleteDC(dc);
    }

    // Cache the rasterized frame (LRU, bounded).
    if cache.len() >= MAX_TEXT_CACHE_ENTRIES {
        cache.pop_back();
    }
    cache.push_front(TextGlyphCacheEntry {
        key: cache_key,
        width: width as i32,
        height: height as i32,
        rgba: out[..width * height * 4].to_vec(),
    });
    true
}

#[cfg(not(windows))]
pub fn render_text_gdi(
    _cache: &mut VecDeque<TextGlyphCacheEntry>,
    _out: &mut [u8],
    _width: usize,
    _height: usize,
    _text: &str,
    _font_size: f32,
    _color_argb: u32,
) -> bool {
    false
}
