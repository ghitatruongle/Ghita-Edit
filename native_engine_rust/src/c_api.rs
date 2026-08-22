//! The C ABI surface — drop-in replacement for the C++ ghita_c_api.cpp.
//!
//! Contract rules preserved from the C++ side:
//! - every exported fn is panic-contained (`catch_unwind`) so a Rust panic
//!   can never cross the FFI boundary
//! - `create` returns null on OOM (Box::try_new) — Dart checks for null
//! - thread-local buffers for get_media_info / get_available_filters /
//!   get_thumbnail — callers copy synchronously before the next call
//! - return-code split: 0/-1 family vs 1/0 family (Dart checks ==0 vs !=0)
//! - `bool` is 1-byte, matching both C `_Bool` and Dart FFI `Bool`

use std::cell::RefCell;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::OnceLock;

use crate::engine::GhitaEngine;
use crate::model::{BlendMode, ColorCorrection, KeyframeInterpolation, MaskType, NativeClipKind,
                   TransitionType};

/// Opaque context — mirrors `struct GhitaEngineContext { GhitaEngine engine; }`.
#[repr(C)]
pub struct GhitaEngineContext {
    pub engine: GhitaEngine,
}

/// Process-lifetime version string — safe to return for FFI.
pub const VERSION_STRING: &str = "Ghita Core Engine v1.1.1 (Rust/Flutter)";

fn version_cstring() -> &'static std::ffi::CStr {
    static V: OnceLock<CString> = OnceLock::new();
    V.get_or_init(|| CString::new(VERSION_STRING).unwrap()).as_c_str()
}

// Thread-local buffers for JSON return values (FFI-safe, same contract as the
// C++ `static thread_local std::string t_jsonBuffer`). CString guarantees the
// NUL terminator C callers read (a plain String is not NUL-terminated).
thread_local! {
    static T_JSON: RefCell<CString> = RefCell::new(CString::default());
    static T_THUMB: RefCell<Vec<u8>> = RefCell::new(Vec::new());
}

/// Wraps an export body with panic containment; returns the sentinel on panic.
macro_rules! c_guard {
    ($body:expr, $sentinel:expr) => {
        match catch_unwind(AssertUnwindSafe(|| $body)) {
            Ok(v) => v,
            Err(_) => $sentinel,
        }
    };
}

unsafe fn engine_of<'a>(p: *mut GhitaEngineContext) -> Option<&'a GhitaEngine> {
    if p.is_null() {
        None
    } else {
        Some(&(*p).engine)
    }
}

/// Reads a C string parameter safely (null → empty sentinel handled by caller).
unsafe fn cstr_arg<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

// ---------------------------------------------------------------------------
// Core lifecycle / playback
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_create() -> *mut GhitaEngineContext {
    c_guard!(
        {
            // Null-on-OOM: `new (std::nothrow)` equivalent — Box::try_new is
            // still unstable, so allocate via the stable fallible allocator.
            let layout = std::alloc::Layout::new::<GhitaEngineContext>();
            let ptr = std::alloc::alloc(layout) as *mut GhitaEngineContext;
            if ptr.is_null() {
                std::ptr::null_mut()
            } else {
                ptr.write(GhitaEngineContext { engine: GhitaEngine::new() });
                ptr
            }
        },
        std::ptr::null_mut()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_destroy(ctx: *mut GhitaEngineContext) {
    c_guard!(
        {
            if !ctx.is_null() {
                drop(Box::from_raw(ctx));
            }
        },
        ()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_init(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) => {
                    if e.initialize() {
                        0
                    } else {
                        -1
                    }
                }
                None => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_load_media(ctx: *mut GhitaEngineContext, file_path: *const c_char) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(file_path)) {
                (Some(e), Some(p)) => {
                    if e.load_media(p) {
                        0
                    } else {
                        -1
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_duration_ms(ctx: *mut GhitaEngineContext) -> i64 {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_duration_ms(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_media_width(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_width(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_media_height(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_height(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_play(ctx: *mut GhitaEngineContext) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.play() }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_pause(ctx: *mut GhitaEngineContext) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.pause() }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_is_playing(ctx: *mut GhitaEngineContext) -> bool {
    c_guard!(match engine_of(ctx) { Some(e) => e.is_playing(), None => false }, false)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_seek(ctx: *mut GhitaEngineContext, position_ms: i64) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.seek(position_ms) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_position_ms(ctx: *mut GhitaEngineContext) -> i64 {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_position_ms(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_volume(ctx: *mut GhitaEngineContext, volume: f32) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_volume(volume) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_apply_filter(ctx: *mut GhitaEngineContext, filter_type: c_int, intensity: f32) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.apply_filter(filter_type, intensity) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_render_frame_rgba(
    ctx: *mut GhitaEngineContext,
    out_buffer: *mut u8,
    width: c_int,
    height: c_int,
) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_buffer.is_null() && width > 0 && height > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_buffer, (width as usize) * (height as usize) * 4);
                    e.render_frame_rgba(buf, width as usize, height as usize)
                }
                _ => false,
            }
        },
        false
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_render_frame_at(
    ctx: *mut GhitaEngineContext,
    out_buffer: *mut u8,
    width: c_int,
    height: c_int,
    position_ms: i64,
) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_buffer.is_null() && width > 0 && height > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_buffer, (width as usize) * (height as usize) * 4);
                    e.render_frame_at(buf, width as usize, height as usize, position_ms)
                }
                _ => false,
            }
        },
        false
    )
}

// ---------------------------------------------------------------------------
// Timeline / clip operations
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_clip(
    ctx: *mut GhitaEngineContext,
    file_path: *const c_char,
    start_ms: i64,
    duration_ms: i64,
    track_index: c_int,
) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(file_path)) {
                (Some(e), Some(p)) => e.add_clip(p, start_ms, duration_ms, track_index),
                _ => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_remove_clip(ctx: *mut GhitaEngineContext, clip_id: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.remove_clip(clip_id) {
                    0
                } else {
                    -1
                }
            }
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_clip_count(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_clip_count(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_position(ctx: *mut GhitaEngineContext, clip_id: c_int, start_ms: i64) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.set_clip_position(clip_id, start_ms) {
                    0
                } else {
                    -1
                }
            }
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_filter(ctx: *mut GhitaEngineContext, clip_id: c_int, filter_type: c_int, intensity: f32) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.set_clip_filter(clip_id, filter_type, intensity) {
                    0
                } else {
                    -1
                }
            }
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_transition(ctx: *mut GhitaEngineContext, clip_id: c_int, transition_type: c_int, duration_ms: c_int) -> bool {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.set_clip_transition(clip_id, TransitionType::from_i32(transition_type), duration_ms),
            None => false,
        },
        false
    )
}

// ---------------------------------------------------------------------------
// Export pipeline
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_start_export(
    ctx: *mut GhitaEngineContext,
    output_path: *const c_char,
    width: c_int,
    height: c_int,
    fps: c_int,
) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(output_path)) {
                (Some(e), Some(p)) => {
                    if e.start_export(p, width as usize, height as usize, fps) {
                        0
                    } else {
                        -1
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_export_progress(ctx: *mut GhitaEngineContext) -> f32 {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_export_progress(), None => 0.0 }, 0.0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_is_exporting(ctx: *mut GhitaEngineContext) -> bool {
    c_guard!(match engine_of(ctx) { Some(e) => e.is_exporting(), None => false }, false)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_cancel_export(ctx: *mut GhitaEngineContext) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.cancel_export() }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_version() -> *const c_char {
    c_guard!(version_cstring().as_ptr(), std::ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_audio_waveform(ctx: *mut GhitaEngineContext, out_samples: *mut f32, sample_count: c_int) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_samples.is_null() && sample_count > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_samples, sample_count as usize);
                    e.get_audio_waveform(buf, sample_count as usize)
                }
                _ => false,
            }
        },
        false
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_snapping_fps(ctx: *mut GhitaEngineContext, fps: c_int) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_frame_snapping_fps(fps) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_snapping_fps(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_frame_snapping_fps(), None => 30 }, 30)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_direct_buffer(ctx: *mut GhitaEngineContext, out_width: *mut c_int, out_height: *mut c_int) -> *mut u8 {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_width.is_null() && !out_height.is_null() => {
                    e.get_frame_direct_buffer_pointer(&mut *out_width, &mut *out_height)
                }
                _ => std::ptr::null_mut(),
            }
        },
        std::ptr::null_mut()
    )
}

// ---------------------------------------------------------------------------
// v0.4.5 API
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_media_info(ctx: *mut GhitaEngineContext) -> *const c_char {
    c_guard!(
        {
            let json = match engine_of(ctx) {
                Some(e) => e.get_media_info_json(),
                None => "{}".to_string(),
            };
            T_JSON.with(|b| {
                let mut b = b.borrow_mut();
                *b = CString::new(json).unwrap_or_default();
                b.as_ptr()
            })
        },
        std::ptr::null()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_available_filters(ctx: *mut GhitaEngineContext) -> *const c_char {
    c_guard!(
        {
            let json = match engine_of(ctx) {
                Some(e) => e.get_available_filters_json(),
                None => "[]".to_string(),
            };
            T_JSON.with(|b| {
                let mut b = b.borrow_mut();
                *b = CString::new(json).unwrap_or_default();
                b.as_ptr()
            })
        },
        std::ptr::null()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_start_export_ex(
    ctx: *mut GhitaEngineContext,
    output_path: *const c_char,
    width: c_int,
    height: c_int,
    fps: c_int,
    codec: *const c_char,
    bitrate: i64,
    include_audio: bool,
) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(output_path), cstr_arg(codec)) {
                (Some(e), Some(p), Some(c)) => {
                    if e.start_export_ex(p, width as usize, height as usize, fps, c, bitrate, include_audio) {
                        0
                    } else {
                        -1
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_export_file_size(ctx: *mut GhitaEngineContext) -> i64 {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_export_file_size(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_clip_keyframe(ctx: *mut GhitaEngineContext, clip_id: c_int, time_ms: i64, value: f32) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.add_clip_keyframe(clip_id, time_ms, value) {
                    0
                } else {
                    -1
                }
            }
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_clear_clip_keyframes(ctx: *mut GhitaEngineContext, clip_id: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.clear_clip_keyframes(clip_id) {
                    0
                } else {
                    -1
                }
            }
            None => -1,
        },
        -1
    )
}

/// Compile-time FFmpeg availability, mirroring `#ifdef GHITA_HAS_FFMPEG`.
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_has_ffmpeg(_ctx: *mut GhitaEngineContext) -> bool {
    cfg!(feature = "ffmpeg")
}

// ---------------------------------------------------------------------------
// v0.5.5 API
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_playback_rate(ctx: *mut GhitaEngineContext, rate: f32) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_playback_rate(rate) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_playback_rate(ctx: *mut GhitaEngineContext) -> f32 {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_playback_rate(), None => 1.0 }, 1.0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_keyframe_interpolation(ctx: *mut GhitaEngineContext, clip_id: c_int, interpolation_type: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.set_clip_keyframe_interpolation(clip_id, KeyframeInterpolation::from_i32(interpolation_type)) {
                    0
                } else {
                    -1
                }
            }
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_clip_keyframe_interpolation(ctx: *mut GhitaEngineContext, clip_id: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.get_clip_keyframe_interpolation(clip_id) as c_int,
            None => 0,
        },
        0
    )
}

/// v0.5.5 text overlay stub — byte-identical to the C++ implementation
/// (solid rect + text bytes encoded in the top-left corner pixels).
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_render_text_overlay(
    ctx: *mut GhitaEngineContext,
    out_buffer: *mut u8,
    width: c_int,
    height: c_int,
    text: *const c_char,
    font_size: c_int,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) -> bool {
    c_guard!(
        {
            if engine_of(ctx).is_none() || out_buffer.is_null() || text.is_null() || width <= 0 || height <= 0 {
                return false;
            }
            let text_bytes = CStr::from_ptr(text).to_bytes();
            let text_len = text_bytes.len();
            let buf = std::slice::from_raw_parts_mut(out_buffer, (width as usize) * (height as usize) * 4);

            let box_w = width.min(40.max(text_len as c_int * font_size / 2));
            let box_h = height.min(font_size * 2);
            let box_x = 20;
            let box_y = (height - box_h - 20).max(0);

            for y in box_y..(box_y + box_h).min(height) {
                for x in box_x..(box_x + box_w).min(width) {
                    let idx = (y * width + x) as usize * 4;
                    buf[idx] = (r * 255.0) as u8;
                    buf[idx + 1] = (g * 255.0) as u8;
                    buf[idx + 2] = (b * 255.0) as u8;
                    buf[idx + 3] = (a * 255.0) as u8;
                }
            }

            // Encode text string in pixel data (for debugging / placeholder).
            for i in 0..text_len.min((box_w) as usize) {
                if box_x + i as c_int >= box_x + box_w || box_y >= height {
                    break;
                }
                let byte = text_bytes[i] as i8 as i32; // signed char semantics
                let idx = (box_y * width + box_x + i as c_int) as usize * 4;
                buf[idx] = (byte % 256) as u8;
                buf[idx + 1] = ((byte >> 8) % 256) as u8;
                buf[idx + 2] = font_size as u8;
                buf[idx + 3] = 200;
            }
            true
        },
        false
    )
}

// ---------------------------------------------------------------------------
// v0.8.0 API
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_upsert_clip(
    ctx: *mut GhitaEngineContext,
    clip_id: c_int,
    file_path: *const c_char,
    start_ms: i64,
    duration_ms: i64,
    source_in_ms: i64,
    track_index: c_int,
    kind: c_int,
    volume: f32,
    opacity: f32,
    speed: f32,
) -> c_int {
    c_guard!(
        {
            let k = match NativeClipKind::from_i32(kind) {
                Some(k) => k,
                None => return 0,
            };
            match (engine_of(ctx), cstr_arg(file_path)) {
                (Some(e), Some(p)) if clip_id > 0 => e.upsert_clip(
                    clip_id, p, start_ms, duration_ms, source_in_ms, track_index, k, volume, opacity, speed,
                ),
                _ => 0,
            }
        },
        0
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_clear_clips(ctx: *mut GhitaEngineContext) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.clear_clips() }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_track_state(ctx: *mut GhitaEngineContext, track_index: c_int, muted: c_int, visible: c_int, volume: f32) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) if track_index >= 0 => e.set_track_state(track_index, muted != 0, visible != 0, volume),
            _ => 0,
        },
        0
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_color_correction(
    ctx: *mut GhitaEngineContext,
    clip_id: c_int,
    exposure: f32,
    contrast: f32,
    saturation: f32,
    temperature: f32,
    tint: f32,
    vibrance: f32,
    highlights: f32,
    shadows: f32,
) -> c_int {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) => e.set_clip_color_correction(
                    clip_id,
                    ColorCorrection {
                        exposure,
                        contrast,
                        saturation,
                        temperature,
                        tint,
                        vibrance,
                        highlights,
                        shadows,
                    },
                ),
                None => 0,
            }
        },
        0
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_text(ctx: *mut GhitaEngineContext, clip_id: c_int, text: *const c_char, font_size: f32, color_argb: u32) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(text)) {
                (Some(e), Some(t)) => e.set_clip_text(clip_id, t, font_size, color_argb),
                _ => 0,
            }
        },
        0
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_has_clip(ctx: *mut GhitaEngineContext, clip_id: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => {
                if e.has_clip(clip_id) {
                    1
                } else {
                    0
                }
            }
            None => 0,
        },
        0
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_audio_preview_enabled(ctx: *mut GhitaEngineContext, enabled: c_int) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_audio_preview_enabled(enabled != 0) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_noise_suppress(ctx: *mut GhitaEngineContext, enabled: c_int) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_noise_suppress(enabled != 0) }, ())
}

// ---------------------------------------------------------------------------
// v1.0.0 API
// ---------------------------------------------------------------------------

/// NOTE: arg order differs from set_clip_color_correction on purpose —
/// highlights/shadows come 3rd/4th here, saturation last (C++ ABI quirk).
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_apply_color_correction(
    ctx: *mut GhitaEngineContext,
    clip_id: c_int,
    exposure: f32,
    contrast: f32,
    highlights: f32,
    shadows: f32,
    temperature: f32,
    tint: f32,
    vibrance: f32,
    saturation: f32,
) {
    c_guard!(
        {
            if let Some(e) = engine_of(ctx) {
                e.set_clip_color_correction(
                    clip_id,
                    ColorCorrection {
                        exposure,
                        contrast,
                        saturation,
                        temperature,
                        tint,
                        vibrance,
                        highlights,
                        shadows,
                    },
                );
            }
        },
        ()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_keyframe_bezier(ctx: *mut GhitaEngineContext, clip_id: c_int, keyframe_index: c_int, cp1x: f32, cp1y: f32, cp2x: f32, cp2y: f32) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.set_keyframe_bezier_ex(clip_id, keyframe_index, cp1x, cp1y, cp2x, cp2y),
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_render_pip(ctx: *mut GhitaEngineContext, overlay_clip_id: c_int, x: f32, y: f32, width: f32, height: f32, rotation: f32) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) => {
                    e.set_clip_pip(
                        overlay_clip_id,
                        crate::model::PipGeometry { x, y, w: width, h: height, rotation },
                    ) == 0
                }
                None => false,
            }
        },
        false
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_thumbnail(ctx: *mut GhitaEngineContext, clip_id: c_int, time_ms: i64, width: c_int, height: c_int) -> *mut u8 {
    c_guard!(
        {
            let e = match engine_of(ctx) {
                Some(e) => e,
                None => return std::ptr::null_mut(),
            };
            if width <= 0 || height <= 0 {
                return std::ptr::null_mut();
            }
            let n = (width as usize) * (height as usize) * 4;
            T_THUMB.with(|b| {
                let mut b = b.borrow_mut();
                b.resize(n, 0);
                if e.get_clip_thumbnail(&mut b[..], width as usize, height as usize, clip_id, time_ms) {
                    b.as_mut_ptr()
                } else {
                    std::ptr::null_mut()
                }
            })
        },
        std::ptr::null_mut()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_filter_preset(ctx: *mut GhitaEngineContext, clip_id: c_int, filter_type: c_int, intensity: f32) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_clip_filter(clip_id, filter_type, intensity); }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_audio_waveform_peaks(ctx: *mut GhitaEngineContext, out_samples: *mut f32, sample_count: c_int) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_samples.is_null() && sample_count > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_samples, sample_count as usize);
                    e.get_audio_waveform(buf, sample_count as usize)
                }
                _ => false,
            }
        },
        false
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_mix_audio_window(ctx: *mut GhitaEngineContext, start_ms: i64, end_ms: i64, out_samples: *mut f32, sample_count: c_int) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_samples.is_null() && sample_count > 0 && end_ms > start_ms => {
                    let buf = std::slice::from_raw_parts_mut(out_samples, sample_count as usize);
                    e.mix_audio_window(start_ms, end_ms, buf, sample_count as usize, false)
                }
                _ => false,
            }
        },
        false
    )
}

// ---------------------------------------------------------------------------
// v1.1.0 API (PLAN 3: Accuracy)
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_keyframe_ex(
    ctx: *mut GhitaEngineContext,
    clip_id: c_int,
    time_ms: i64,
    value: f32,
    property: c_int,
    interpolation: c_int,
    cp1x: f32,
    cp1y: f32,
    cp2x: f32,
    cp2y: f32,
) -> c_int {
    c_guard!(
        {
            if property < 0 || property > 4 || interpolation < 0 || interpolation > 2 {
                return -1;
            }
            match engine_of(ctx) {
                Some(e) => e.add_clip_keyframe_ex(clip_id, time_ms, value, property, interpolation, cp1x, cp1y, cp2x, cp2y),
                None => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_clip_keyframe_count(ctx: *mut GhitaEngineContext, clip_id: c_int) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_clip_keyframe_count(clip_id), None => -1 }, -1)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_pip(ctx: *mut GhitaEngineContext, clip_id: c_int, x: f32, y: f32, w: f32, h: f32, rotation: f32) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.set_clip_pip(
                clip_id,
                crate::model::PipGeometry { x, y, w, h, rotation },
            ),
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_speed_ramp_point(ctx: *mut GhitaEngineContext, clip_id: c_int, t: f32, speed: f32) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.add_speed_ramp_point(clip_id, t, speed), None => -1 }, -1)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_clear_speed_curve(ctx: *mut GhitaEngineContext, clip_id: c_int) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.set_clip_speed_curve(clip_id, Vec::new()), None => -1 }, -1)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_render_frame_at_ex(
    ctx: *mut GhitaEngineContext,
    out_buffer: *mut u8,
    width: c_int,
    height: c_int,
    position_ms: i64,
    apply_fx: c_int,
) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_buffer.is_null() && width > 0 && height > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_buffer, (width as usize) * (height as usize) * 4);
                    e.render_frame_at_ex(buf, width as usize, height as usize, position_ms, apply_fx != 0)
                }
                _ => false,
            }
        },
        false
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_timeline_waveform(ctx: *mut GhitaEngineContext, out_samples: *mut f32, sample_count: c_int, track_index: c_int) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_samples.is_null() && sample_count > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_samples, sample_count as usize);
                    e.get_timeline_waveform(buf, sample_count as usize, track_index)
                }
                _ => false,
            }
        },
        false
    )
}

// Keep c_void referenced (opaque handle type used by docs).
#[allow(dead_code)]
fn _unused(_: *mut c_void) {}

// ---------------------------------------------------------------------------
// v1.5.0 T3: blend modes / masks / canvas / bookmarks / keyframe copy / transcript
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_blend_mode(ctx: *mut GhitaEngineContext, clip_id: c_int, mode: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.set_clip_blend_mode(clip_id, BlendMode::from_i32(mode)),
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_mask(ctx: *mut GhitaEngineContext, clip_id: c_int, mask_type: c_int, feather: f32, stroke: f32) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.set_clip_mask(clip_id, MaskType::from_i32(mask_type), feather, stroke),
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_maintain_pitch(ctx: *mut GhitaEngineContext, clip_id: c_int, enabled: c_int) -> c_int {
    c_guard!(
        match engine_of(ctx) {
            Some(e) => e.set_clip_maintain_pitch(clip_id, enabled != 0),
            None => -1,
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_font(ctx: *mut GhitaEngineContext, clip_id: c_int, family: *const c_char) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(family)) {
                (Some(e), Some(f)) => e.set_clip_font(clip_id, f),
                _ => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_canvas_background(ctx: *mut GhitaEngineContext, kind: c_int, color: u32, color2: u32) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_canvas_background(kind, color, color2) }, ())
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_bookmark(ctx: *mut GhitaEngineContext, time_ms: i64, color: u32, note: *const c_char) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(note)) {
                (Some(e), Some(n)) => e.add_bookmark(time_ms, color, n),
                _ => -1,
            }
        },
        -1
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_remove_bookmark(ctx: *mut GhitaEngineContext, id: c_int) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.remove_bookmark(id), None => -1 }, -1)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_bookmark_count(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.get_bookmark_count(), None => 0 }, 0)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_bookmarks_json(ctx: *mut GhitaEngineContext) -> *const c_char {
    c_guard!(
        {
            let json = match engine_of(ctx) {
                Some(e) => e.get_bookmarks_json(),
                None => "[]".to_string(),
            };
            T_JSON.with(|b| {
                let mut b = b.borrow_mut();
                *b = CString::new(json).unwrap_or_default();
                b.as_ptr()
            })
        },
        std::ptr::null()
    )
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_copy_keyframes(ctx: *mut GhitaEngineContext, src_clip: c_int, dst_clip: c_int) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.copy_keyframes(src_clip, dst_clip), None => -1 }, -1)
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_import_transcript(ctx: *mut GhitaEngineContext, path: *const c_char, track_index: c_int) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(path)) {
                (Some(e), Some(p)) => e.import_transcript(p, track_index),
                _ => 0,
            }
        },
        0
    )
}

// ---------------------------------------------------------------------------
// v1.5.0 T4 (Audio Features) — feature "ffmpeg" only
// ---------------------------------------------------------------------------

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_audio_effect(ctx: *mut GhitaEngineContext, effect_type: c_int, p0: f32, p1: f32, p2: f32, p3: f32) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.add_audio_effect(effect_type, [p0, p1, p2, p3]), None => -1 }, -1)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_remove_audio_effect(ctx: *mut GhitaEngineContext, index: c_int) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.remove_audio_effect(index), None => -1 }, -1)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_clear_audio_effects(ctx: *mut GhitaEngineContext) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.clear_audio_effects() }, ())
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_gain_reduction_db(ctx: *mut GhitaEngineContext) -> f32 {
    c_guard!(match engine_of(ctx) { Some(e) => e.gain_reduction_db(), None => 0.0 }, 0.0)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_spectrogram(ctx: *mut GhitaEngineContext, out_mags: *mut f32, columns: c_int, bins: c_int, track_index: c_int) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_mags.is_null() && columns > 0 && bins > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_mags, columns as usize * bins as usize);
                    e.get_spectrogram(buf, columns as usize, bins as usize, track_index)
                }
                _ => false,
            }
        },
        false
    )
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_add_spectral_edit(ctx: *mut GhitaEngineContext, start_ms: i64, end_ms: i64, lo_hz: f32, hi_hz: f32, gain_db: f32) -> c_int {
    c_guard!(
        {
            let e = match engine_of(ctx) { Some(e) => e, None => return -1 };
            let mut edits = e.t4.spectral_edits.lock().unwrap();
            edits.push(crate::fft_tools::SpectralEdit { start_ms, end_ms, lo_hz, hi_hz, gain_db });
            (edits.len() - 1) as c_int
        },
        -1
    )
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_clear_spectral_edits(ctx: *mut GhitaEngineContext) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.t4.spectral_edits.lock().unwrap().clear() }, ())
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_timeline_rms(ctx: *mut GhitaEngineContext, out: *mut f32, count: c_int, track_index: c_int) -> bool {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out.is_null() && count > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out, count as usize);
                    e.get_timeline_rms(buf, count as usize, track_index)
                }
                _ => false,
            }
        },
        false
    )
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_detect_tempo(ctx: *mut GhitaEngineContext) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.detect_tempo(), None => 0 }, 0)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_time_signature(ctx: *mut GhitaEngineContext, num: c_int, den: c_int) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_time_signature(num, den) }, ())
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_beat_times(ctx: *mut GhitaEngineContext, out_ms: *mut i64, max_count: c_int) -> c_int {
    c_guard!(
        {
            match engine_of(ctx) {
                Some(e) if !out_ms.is_null() && max_count > 0 => {
                    let buf = std::slice::from_raw_parts_mut(out_ms, max_count as usize);
                    e.get_beat_times(buf) as c_int
                }
                _ => 0,
            }
        },
        0
    )
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_loop_region(ctx: *mut GhitaEngineContext, start_ms: i64, end_ms: i64, enabled: c_int) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_loop_region(start_ms, end_ms, enabled != 0) }, ())
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_clip_pitch(ctx: *mut GhitaEngineContext, clip_id: c_int, semitones: f32) -> c_int {
    c_guard!(match engine_of(ctx) { Some(e) => e.set_clip_pitch(clip_id, semitones), None => -1 }, -1)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_preview_pitch_preserve(ctx: *mut GhitaEngineContext, enabled: c_int) {
    c_guard!(if let Some(e) = engine_of(ctx) { e.set_preview_pitch_preserve(enabled != 0) }, ())
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_start_recording(ctx: *mut GhitaEngineContext, out_path: *const c_char, mode: c_int, pre_roll_ms: i64, delay_ms: i64, duration_ms: i64) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(out_path)) {
                (Some(e), Some(p)) => e.start_recording(p, mode, pre_roll_ms, delay_ms, duration_ms),
                _ => -1,
            }
        },
        -1
    )
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_stop_recording(ctx: *mut GhitaEngineContext) -> i64 {
    c_guard!(match engine_of(ctx) { Some(e) => e.stop_recording(), None => 0 }, 0)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_is_recording(ctx: *mut GhitaEngineContext) -> bool {
    c_guard!(match engine_of(ctx) { Some(e) => e.is_recording(), None => false }, false)
}

#[cfg(feature = "ffmpeg")]
#[no_mangle]
pub unsafe extern "C" fn ghita_engine_export_labels(ctx: *mut GhitaEngineContext, path: *const c_char, format: c_int) -> c_int {
    c_guard!(
        {
            match (engine_of(ctx), cstr_arg(path)) {
                (Some(e), Some(p)) => e.export_labels(p, format),
                _ => 0,
            }
        },
        0
    )
}

// ---------------------------------------------------------------------------
// T5-P1: SQLite project database (standalone — no engine context needed)
// ---------------------------------------------------------------------------

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_save(
    db_path: *const c_char,
    name: *const c_char,
    json_data: *const c_char,
) -> c_int {
    c_guard!(
        {
            match (cstr_arg(db_path), cstr_arg(name), cstr_arg(json_data)) {
                (Some(dp), Some(n), Some(j)) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.save_project(n, j) {
                            Ok(_) => 0,
                            Err(_) => -1,
                        },
                        Err(_) => -1,
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_load(
    db_path: *const c_char,
    name: *const c_char,
) -> *const c_char {
    c_guard!(
        {
            match (cstr_arg(db_path), cstr_arg(name)) {
                (Some(dp), Some(n)) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.load_project(n) {
                            Ok(Some(json)) => {
                                T_JSON.with(|buf| {
                                    *buf.borrow_mut() = CString::new(json).unwrap_or_default();
                                    buf.borrow().as_ptr()
                                })
                            }
                            _ => std::ptr::null(),
                        },
                        Err(_) => std::ptr::null(),
                    }
                }
                _ => std::ptr::null(),
            }
        },
        std::ptr::null()
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_list(
    db_path: *const c_char,
) -> *const c_char {
    c_guard!(
        {
            match cstr_arg(db_path) {
                Some(dp) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.list_projects() {
                            Ok(projects) => {
                                let json: Vec<String> = projects
                                    .iter()
                                    .map(|p| format!(
                                        r#"{{"id":{},"name":"{}","version":"{}","created_at":"{}","modified_at":"{}"}}"#,
                                        p.id, p.name, p.version, p.created_at, p.modified_at
                                    ))
                                    .collect();
                                let arr = format!("[{}]", json.join(","));
                                T_JSON.with(|buf| {
                                    *buf.borrow_mut() = CString::new(arr).unwrap_or_default();
                                    buf.borrow().as_ptr()
                                })
                            }
                            Err(_) => std::ptr::null(),
                        },
                        Err(_) => std::ptr::null(),
                    }
                }
                None => std::ptr::null(),
            }
        },
        std::ptr::null()
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_delete(
    db_path: *const c_char,
    name: *const c_char,
) -> c_int {
    c_guard!(
        {
            match (cstr_arg(db_path), cstr_arg(name)) {
                (Some(dp), Some(n)) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.delete_project(n) {
                            Ok(true) => 0,
                            _ => -1,
                        },
                        Err(_) => -1,
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_library_add(
    db_path: *const c_char,
    media_path: *const c_char,
    hash: *const c_char,
    metadata_json: *const c_char,
) -> c_int {
    c_guard!(
        {
            match (cstr_arg(db_path), cstr_arg(media_path), cstr_arg(hash), cstr_arg(metadata_json)) {
                (Some(dp), Some(mp), Some(h), Some(mj)) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.add_media(mp, h, mj) {
                            Ok(_) => 0,
                            Err(_) => -1,
                        },
                        Err(_) => -1,
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_library_search(
    db_path: *const c_char,
    query: *const c_char,
    min_rating: c_int,
) -> *const c_char {
    c_guard!(
        {
            match (cstr_arg(db_path), cstr_arg(query)) {
                (Some(dp), Some(q)) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.search_media(q, min_rating) {
                            Ok(entries) => {
                                let json: Vec<String> = entries
                                    .iter()
                                    .map(|e| format!(
                                        r#"{{"id":{},"path":"{}","hash":"{}","tags":"{}","rating":{},"last_seen":"{}"}}"#,
                                        e.id, e.path, e.hash, e.tags, e.rating, e.last_seen
                                    ))
                                    .collect();
                                let arr = format!("[{}]", json.join(","));
                                T_JSON.with(|buf| {
                                    *buf.borrow_mut() = CString::new(arr).unwrap_or_default();
                                    buf.borrow().as_ptr()
                                })
                            }
                            Err(_) => std::ptr::null(),
                        },
                        Err(_) => std::ptr::null(),
                    }
                }
                _ => std::ptr::null(),
            }
        },
        std::ptr::null()
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_library_update_rating(
    db_path: *const c_char,
    id: i64,
    rating: c_int,
) -> c_int {
    c_guard!(
        {
            match cstr_arg(db_path) {
                Some(dp) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.update_rating(id, rating) {
                            Ok(true) => 0,
                            _ => -1,
                        },
                        Err(_) => -1,
                    }
                }
                None => -1,
            }
        },
        -1
    )
}

#[cfg(feature = "sqlite")]
#[no_mangle]
pub unsafe extern "C" fn ghita_project_db_library_update_tags(
    db_path: *const c_char,
    id: i64,
    tags: *const c_char,
) -> c_int {
    c_guard!(
        {
            match (cstr_arg(db_path), cstr_arg(tags)) {
                (Some(dp), Some(t)) => {
                    match crate::project_db::ProjectDb::open(dp) {
                        Ok(db) => match db.update_tags(id, t) {
                            Ok(true) => 0,
                            _ => -1,
                        },
                        Err(_) => -1,
                    }
                }
                _ => -1,
            }
        },
        -1
    )
}

// ---------------------------------------------------------------------------
// T6-P1: Pixel-level selection tools (standalone, thread-local mask)
// ---------------------------------------------------------------------------

thread_local! {
    static T_SELECTION: std::cell::RefCell<Option<crate::selection::SelectionMask>> =
        std::cell::RefCell::new(None);
}

fn mask_op_from_int(op: i32) -> crate::selection::MaskOp {
    match op {
        1 => crate::selection::MaskOp::Add,
        2 => crate::selection::MaskOp::Subtract,
        3 => crate::selection::MaskOp::Intersect,
        _ => crate::selection::MaskOp::Replace,
    }
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_selection_rect(
    width: i32, height: i32, x: i32, y: i32, w: i32, h: i32, op: i32,
) -> c_int {
    let mask_op = mask_op_from_int(op);
    T_SELECTION.with(|s| {
        let mut guard = s.borrow_mut();
        if guard.is_none() || guard.as_ref().map_or(true, |m| m.width != width as u32 || m.height != height as u32) {
            *guard = Some(crate::selection::SelectionMask::new(width as u32, height as u32));
        }
        if let Some(ref mut mask) = *guard {
            crate::selection::select_rect(mask, x, y, w, h, mask_op);
        }
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_selection_ellipse(
    width: i32, height: i32, cx: i32, cy: i32, rx: i32, ry: i32, op: i32,
) -> c_int {
    let mask_op = mask_op_from_int(op);
    T_SELECTION.with(|s| {
        let mut guard = s.borrow_mut();
        if guard.is_none() || guard.as_ref().map_or(true, |m| m.width != width as u32 || m.height != height as u32) {
            *guard = Some(crate::selection::SelectionMask::new(width as u32, height as u32));
        }
        if let Some(ref mut mask) = *guard {
            crate::selection::select_ellipse(mask, cx, cy, rx, ry, mask_op);
        }
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_selection_lasso(
    width: i32, height: i32, points_x: *const i32, points_y: *const i32, count: i32, op: i32,
) -> c_int {
    if points_x.is_null() || points_y.is_null() || count <= 0 { return -1; }
    let pts: Vec<(i32, i32)> = (0..count as usize)
        .map(|i| (*points_x.add(i), *points_y.add(i)))
        .collect();
    let mask_op = mask_op_from_int(op);
    T_SELECTION.with(|s| {
        let mut guard = s.borrow_mut();
        if guard.is_none() || guard.as_ref().map_or(true, |m| m.width != width as u32 || m.height != height as u32) {
            *guard = Some(crate::selection::SelectionMask::new(width as u32, height as u32));
        }
        if let Some(ref mut mask) = *guard {
            crate::selection::select_lasso(mask, &pts, mask_op);
        }
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_set_selection_magic_wand(
    width: i32, height: i32, seed_x: i32, seed_y: i32, tolerance: f32, image_data: *const u8, op: i32,
) -> c_int {
    if image_data.is_null() { return -1; }
    let img_slice = std::slice::from_raw_parts(image_data, (width * height * 4) as usize);
    // Copy image data so we don't hold a reference across the borrow.
    let img_copy: Vec<u8> = img_slice.to_vec();
    let mask_op = mask_op_from_int(op);
    T_SELECTION.with(|s| {
        let mut guard = s.borrow_mut();
        if guard.is_none() || guard.as_ref().map_or(true, |m| m.width != width as u32 || m.height != height as u32) {
            *guard = Some(crate::selection::SelectionMask::new(width as u32, height as u32));
        }
        if let Some(ref mut mask) = *guard {
            crate::selection::select_magic_wand(mask, &img_copy, seed_x, seed_y, tolerance as f64, mask_op);
        }
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_modify_mask(operation: i32) -> c_int {
    T_SELECTION.with(|s| {
        let mut guard = s.borrow_mut();
        if let Some(ref mut mask) = *guard {
            match operation {
                0 => mask.invert(),
                1 => mask.feather(2),
                _ => {}
            }
        }
    });
    0
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_get_mask_buffer(
    out_buf: *mut u8, buf_size: i32,
) -> i32 {
    T_SELECTION.with(|s| {
        let guard = s.borrow();
        if let Some(ref mask) = *guard {
            let len = mask.data.len().min(buf_size as usize);
            if !out_buf.is_null() && len > 0 {
                std::ptr::copy_nonoverlapping(mask.data.as_ptr(), out_buf, len);
            }
            mask.data.len() as i32
        } else {
            0
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn ghita_engine_clear_selection() {
    T_SELECTION.with(|s| {
        let mut guard = s.borrow_mut();
        if let Some(ref mut mask) = *guard {
            mask.clear();
        }
    });
}
