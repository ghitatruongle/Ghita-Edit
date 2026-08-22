//! ABI-level integration tests — mirror of native_engine_self_test.cpp key
//! coverage, exercised through the exact C API surface (same entry points
//! Dart uses via FFI). Verifies return-code conventions, JSON shapes,
//! timeline semantics and render behavior.

use std::ffi::CString;
use std::ptr;

use ghita_engine::c_api::*;

// Test helpers ---------------------------------------------------------------

struct Ctx(*mut GhitaEngineContext);

// The engine is internally synchronized (engine + render locks) and the C
// API is designed for multi-threaded callers (Dart UI isolate + probe
// isolate), so sharing the context across threads is the intended usage.
unsafe impl Send for Ctx {}
unsafe impl Sync for Ctx {}

impl Ctx {
    fn new() -> Self {
        let p = unsafe { ghita_engine_create() };
        assert!(!p.is_null(), "create must not return null");
        let c = Ctx(p);
        assert_eq!(unsafe { ghita_engine_init(p) }, 0, "init must return 0");
        c
    }
}

impl Drop for Ctx {
    fn drop(&mut self) {
        unsafe { ghita_engine_destroy(self.0) };
    }
}

fn cstr(s: &str) -> CString {
    CString::new(s).unwrap()
}

fn frame(w: usize, h: usize) -> Vec<u8> {
    vec![0u8; w * h * 4]
}

// Lifecycle / version --------------------------------------------------------

#[test]
fn lifecycle_create_init_version_destroy() {
    let p = unsafe { ghita_engine_create() };
    assert!(!p.is_null());
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    // null ctx guards
    assert_eq!(unsafe { ghita_engine_init(ptr::null_mut()) }, -1);
    assert_eq!(unsafe { ghita_engine_get_duration_ms(ptr::null_mut()) }, 0);
    assert_eq!(unsafe { ghita_engine_get_media_width(ptr::null_mut()) }, 0);
    assert!(!unsafe { ghita_engine_is_playing(ptr::null_mut()) });
    assert_eq!(unsafe { ghita_engine_get_snapping_fps(ptr::null_mut()) }, 30);
    assert_eq!(unsafe { ghita_engine_get_playback_rate(ptr::null_mut()) }, 1.0);
    unsafe { ghita_engine_destroy(p) };
    // double destroy must be safe
    unsafe { ghita_engine_destroy(ptr::null_mut()) };
}

#[test]
fn version_string_format() {
    let v = unsafe { ghita_engine_get_version() };
    assert!(!v.is_null());
    let s = unsafe { std::ffi::CStr::from_ptr(v) }.to_str().unwrap();
    assert!(s.starts_with("Ghita Core Engine v1.1.1"), "got: {s}");
}

#[test]
fn load_media_missing_file_returns_error_but_synthetic_content() {
    let c = Ctx::new();
    let path = cstr("nonexistent_media_xyz.mp4");
    // v0.8.0: missing file → -1 (honest reporting)
    assert_eq!(unsafe { ghita_engine_load_media(c.0, path.as_ptr()) }, -1);
    // ...but the decoder still falls back to synthetic (1920x1080 / 60s)
    assert_eq!(unsafe { ghita_engine_get_media_width(c.0) }, 1920);
    assert_eq!(unsafe { ghita_engine_get_media_height(c.0) }, 1080);
    assert_eq!(unsafe { ghita_engine_get_duration_ms(c.0) }, 60000);
}

// Rendering ------------------------------------------------------------------

#[test]
fn render_frame_rgba_opaque() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_load_media(c.0, path.as_ptr()) };
    let mut buf = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_rgba(c.0, buf.as_mut_ptr(), 64, 36) });
    for px in buf.chunks_exact(4) {
        assert_eq!(px[3], 255, "alpha must be opaque");
    }
}

#[test]
fn render_frame_at_does_not_advance_playhead() {
    let c = Ctx::new();
    unsafe { ghita_engine_seek(c.0, 1000) };
    assert_eq!(unsafe { ghita_engine_get_position_ms(c.0) }, 1000);
    let mut buf = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, buf.as_mut_ptr(), 64, 36, 5000) });
    // position untouched by render_frame_at
    assert_eq!(unsafe { ghita_engine_get_position_ms(c.0) }, 1000);
}

#[test]
fn render_frame_at_ex_raw_vs_processed() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_load_media(c.0, path.as_ptr()) };
    // global grayscale filter
    unsafe { ghita_engine_apply_filter(c.0, 1, 1.0) };
    let mut raw = frame(64, 36);
    let mut fx = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at_ex(c.0, fx.as_mut_ptr(), 64, 36, 100, 1) });
    assert!(unsafe { ghita_engine_render_frame_at_ex(c.0, raw.as_mut_ptr(), 64, 36, 100, 0) });
    // raw differs from filtered (grayscale changes pixels)
    assert_ne!(fx, raw);
}

// Timeline / clips -----------------------------------------------------------

#[test]
fn upsert_clip_return_codes() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    // invalid: clip_id <= 0
    assert_eq!(unsafe { ghita_engine_upsert_clip(c.0, 0, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) }, 0);
    // invalid: duration <= 0
    assert_eq!(unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 0, 0, 0, 0, 1.0, 1.0, 1.0) }, 0);
    // invalid kind
    assert_eq!(unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 99, 1.0, 1.0, 1.0) }, 0);
    // valid → 1 (the v0.8.0 1/0 family)
    assert_eq!(unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) }, 1);
    assert_eq!(unsafe { ghita_engine_get_clip_count(c.0) }, 1);
    assert_eq!(unsafe { ghita_engine_has_clip(c.0, 1) }, 1);
    assert_eq!(unsafe { ghita_engine_has_clip(c.0, 42) }, 0);
    // update existing (path change) → 1
    let path2 = cstr("other.mp4");
    assert_eq!(unsafe { ghita_engine_upsert_clip(c.0, 1, path2.as_ptr(), 1000, 5000, 0, 0, 0, 1.0, 1.0, 1.0) }, 1);
    assert_eq!(unsafe { ghita_engine_get_clip_count(c.0) }, 1);
}

#[test]
fn set_track_state_and_clip_text_codes() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    assert_eq!(unsafe { ghita_engine_set_track_state(c.0, 0, 0, 1, 1.0) }, 1);
    assert_eq!(unsafe { ghita_engine_set_track_state(c.0, -1, 0, 1, 1.0) }, 0);
    let text = cstr("Hello");
    assert_eq!(unsafe { ghita_engine_set_clip_text(c.0, 1, text.as_ptr(), 48.0, 0xFFFFFFFF) }, 1);
    assert_eq!(unsafe { ghita_engine_set_clip_text(c.0, 99, text.as_ptr(), 48.0, 0xFFFFFFFF) }, 0);
}

#[test]
fn legacy_clip_ops_0_neg1_family() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    let id = unsafe { ghita_engine_add_clip(c.0, path.as_ptr(), 0, 5000, 0) };
    assert!(id >= 1);
    assert_eq!(unsafe { ghita_engine_set_clip_position(c.0, id, 2000) }, 0);
    assert_eq!(unsafe { ghita_engine_set_clip_position(c.0, 999, 2000) }, -1);
    assert_eq!(unsafe { ghita_engine_set_clip_filter(c.0, id, 5, 0.5) }, 0);
    assert_eq!(unsafe { ghita_engine_set_clip_filter(c.0, 999, 5, 0.5) }, -1);
    assert_eq!(unsafe { ghita_engine_remove_clip(c.0, id) }, 0);
    assert_eq!(unsafe { ghita_engine_remove_clip(c.0, id) }, -1);
    assert_eq!(unsafe { ghita_engine_get_clip_count(c.0) }, 0);
}

// Keyframes ------------------------------------------------------------------

#[test]
fn keyframe_api_contract() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };

    // legacy add (0/-1 family)
    assert_eq!(unsafe { ghita_engine_add_clip_keyframe(c.0, 1, 0, 0.0) }, 0);
    assert_eq!(unsafe { ghita_engine_add_clip_keyframe(c.0, 1, 5000, 1.0) }, 0);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(c.0, 1) }, 2);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(c.0, 99) }, -1);

    // extended (property/interpolation/bezier)
    assert_eq!(unsafe { ghita_engine_add_keyframe_ex(c.0, 1, 1000, 0.5, 2, 2, 0.4, 0.2, 0.6, 0.8) }, 0);
    assert_eq!(unsafe { ghita_engine_add_keyframe_ex(c.0, 1, 2000, 0.5, 2, 0, 0.0, 0.0, 0.0, 0.0) }, 0);
    // invalid property / interpolation → -1
    assert_eq!(unsafe { ghita_engine_add_keyframe_ex(c.0, 1, 3000, 0.5, 5, 0, 0.0, 0.0, 0.0, 0.0) }, -1);
    assert_eq!(unsafe { ghita_engine_add_keyframe_ex(c.0, 1, 3000, 0.5, 0, 3, 0.0, 0.0, 0.0, 0.0) }, -1);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(c.0, 1) }, 4);

    // bezier setter (real — v1.1.0)
    assert_eq!(unsafe { ghita_engine_set_keyframe_bezier(c.0, 1, 0, 0.1, 0.2, 0.3, 0.4) }, 0);
    assert_eq!(unsafe { ghita_engine_set_keyframe_bezier(c.0, 1, 99, 0.1, 0.2, 0.3, 0.4) }, -1);

    // interpolation enum
    assert_eq!(unsafe { ghita_engine_set_clip_keyframe_interpolation(c.0, 1, 1) }, 0);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_interpolation(c.0, 1) }, 1);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_interpolation(c.0, 99) }, 0);

    // pip + speed ramp
    assert_eq!(unsafe { ghita_engine_set_clip_pip(c.0, 1, 0.0, 0.0, 0.5, 0.5, 0.0) }, 0);
    assert_eq!(unsafe { ghita_engine_set_clip_pip(c.0, 99, 0.0, 0.0, 0.5, 0.5, 0.0) }, -1);
    assert_eq!(unsafe { ghita_engine_add_speed_ramp_point(c.0, 1, 0.0, 1.0) }, 0);
    assert_eq!(unsafe { ghita_engine_add_speed_ramp_point(c.0, 1, 1.0, 3.0) }, 0);
    assert_eq!(unsafe { ghita_engine_clear_speed_curve(c.0, 1) }, 0);
    assert_eq!(unsafe { ghita_engine_add_speed_ramp_point(c.0, 99, 0.0, 1.0) }, -1);

    assert_eq!(unsafe { ghita_engine_clear_clip_keyframes(c.0, 1) }, 0);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(c.0, 1) }, 0);
}

// JSON -----------------------------------------------------------------------

#[test]
fn media_info_json_shape() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_load_media(c.0, path.as_ptr()) };
    let p = unsafe { ghita_engine_get_media_info(c.0) };
    let s = unsafe { std::ffi::CStr::from_ptr(p) }.to_str().unwrap();
    let v: serde_json::Value = serde_json::from_str(s).expect("valid JSON");
    assert_eq!(v["width"], 1920);
    assert_eq!(v["height"], 1080);
    assert_eq!(v["durationMs"], 60000);
    assert_eq!(v["hasVideo"], true);
    assert_eq!(v["videoCodec"], "synthetic (fallback)");
    // null ctx → "{}"
    let p = unsafe { ghita_engine_get_media_info(ptr::null_mut()) };
    assert_eq!(unsafe { std::ffi::CStr::from_ptr(p) }.to_str().unwrap(), "{}");
}

#[test]
fn filters_json_unique_ids() {
    let c = Ctx::new();
    let p = unsafe { ghita_engine_get_available_filters(c.0) };
    let s = unsafe { std::ffi::CStr::from_ptr(p) }.to_str().unwrap();
    let v: serde_json::Value = serde_json::from_str(s).expect("valid JSON");
    let arr = v.as_array().expect("array");
    // v1.1.0 (PLAN 1.1/B2): ids are exactly 0..N-1 with no duplicates
    let ids: Vec<i64> = arr.iter().map(|f| f["id"].as_i64().unwrap()).collect();
    for (i, id) in ids.iter().enumerate() {
        assert_eq!(*id, i as i64, "filter ids must be 0..N-1");
    }
    assert_eq!(arr.len(), 23);
    assert_eq!(arr[22]["name"], "Chroma Key");
}

// Audio ----------------------------------------------------------------------

#[test]
fn mix_audio_window_silent_without_ffmpeg() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 1, 1.0, 1.0, 1.0) };
    let mut out = vec![0.5f32; 882];
    // no-FFmpeg: no decodable audio stream → false, buffer zeroed
    assert!(!unsafe { ghita_engine_mix_audio_window(c.0, 0, 100, out.as_mut_ptr(), 882) });
    for v in &out {
        assert_eq!(*v, 0.0);
    }
    // null guards
    assert!(!unsafe { ghita_engine_mix_audio_window(ptr::null_mut(), 0, 100, out.as_mut_ptr(), 882) });
}

#[test]
fn waveform_synthetic_rectified() {
    let c = Ctx::new();
    let mut out = vec![0f32; 200];
    assert!(unsafe { ghita_engine_get_audio_waveform(c.0, out.as_mut_ptr(), 200) });
    for v in &out {
        assert!(*v >= 0.0 && *v <= 1.0);
    }
    // peaks alias
    let mut out2 = vec![0f32; 200];
    assert!(unsafe { ghita_engine_get_audio_waveform_peaks(c.0, out2.as_mut_ptr(), 200) });
    assert_eq!(out, out2);
}

#[test]
fn timeline_waveform_empty_without_audio() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 1, 1.0, 1.0, 1.0) };
    let mut out = vec![0f32; 64];
    assert!(!unsafe { ghita_engine_get_timeline_waveform(c.0, out.as_mut_ptr(), 64, 0) });
}

// Playback rate / volume -----------------------------------------------------

#[test]
fn playback_rate_clamped() {
    let c = Ctx::new();
    unsafe { ghita_engine_set_playback_rate(c.0, 8.0) };
    assert_eq!(unsafe { ghita_engine_get_playback_rate(c.0) }, 4.0);
    unsafe { ghita_engine_set_playback_rate(c.0, 0.1) };
    assert_eq!(unsafe { ghita_engine_get_playback_rate(c.0) }, 0.25);
}

// Export ---------------------------------------------------------------------

#[test]
fn export_lifecycle_start_cancel() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_load_media(c.0, path.as_ptr()) };
    let out = cstr("test_out_rust.raw");
    assert_eq!(unsafe { ghita_engine_start_export(c.0, out.as_ptr(), 64, 36, 10) }, 0);
    assert!(unsafe { ghita_engine_is_exporting(c.0) });
    unsafe { ghita_engine_cancel_export(c.0) };
    assert!(!unsafe { ghita_engine_is_exporting(c.0) });
    // invalid dims → -1
    assert_eq!(unsafe { ghita_engine_start_export(c.0, out.as_ptr(), 0, 0, 0) }, -1);
    let _ = std::fs::remove_file("test_out_rust.raw");
}

// Text overlay stub ----------------------------------------------------------

#[test]
fn render_text_overlay_stub_box() {
    let c = Ctx::new();
    let mut buf = frame(160, 90);
    let text = cstr("AB");
    assert!(unsafe {
        ghita_engine_render_text_overlay(c.0, buf.as_mut_ptr(), 160, 90, text.as_ptr(), 20, 1.0, 0.0, 0.0, 1.0)
    });
    // box at bottom-left: boxY = max(0, 90 - 40 - 20) = 30, boxX = 20.
    // The C++ stub fills the rect first, then OVERWRITES the top-left row
    // with the text bytes (A = 0x41, font_size in B, alpha 200).
    let idx = (30 * 160 + 20) * 4;
    assert_eq!(buf[idx], b'A');
    assert_eq!(buf[idx + 1], 0);
    assert_eq!(buf[idx + 2], 20); // font_size
    assert_eq!(buf[idx + 3], 200);
    // A pixel inside the box but below the first row keeps the fill color.
    let idx2 = (35 * 160 + 30) * 4;
    assert_eq!(buf[idx2], 255);
    assert_eq!(buf[idx2 + 1], 0);
    assert_eq!(buf[idx2 + 2], 0);
    assert_eq!(buf[idx2 + 3], 255);
}

// Thumbnail ------------------------------------------------------------------

#[test]
fn thumbnail_returns_frame_for_clip() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    let t = unsafe { ghita_engine_get_thumbnail(c.0, 1, 1000, 64, 36) };
    assert!(!t.is_null());
    // thread-local buffer valid until the next call — copy now
    let bytes = unsafe { std::slice::from_raw_parts(t, 64 * 36 * 4) }.to_vec();
    assert_eq!(bytes[3], 255);
    // missing clip → null
    assert!(unsafe { ghita_engine_get_thumbnail(c.0, 99, 1000, 64, 36) }.is_null());
}

// Concurrency stress ---------------------------------------------------------

#[test]
fn concurrent_render_stress_no_panic() {
    use std::sync::Arc;
    let c = Arc::new(Ctx::new());
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    unsafe { ghita_engine_upsert_clip(c.0, 2, path.as_ptr(), 0, 5000, 0, 1, 0, 1.0, 0.8, 1.0) };
    let mut handles = Vec::new();
    for t in 0..4 {
        let c = c.clone();
        handles.push(std::thread::spawn(move || {
            for i in 0..20 {
                let mut buf = frame(64, 36);
                let pos = 100 * (t * 20 + i);
                let ok = unsafe { ghita_engine_render_frame_at(c.0, buf.as_mut_ptr(), 64, 36, pos as i64) };
                assert!(ok);
                assert_eq!(buf[3], 255);
            }
        }));
    }
    for h in handles {
        h.join().unwrap();
    }
    assert_eq!(unsafe { ghita_engine_get_clip_count(c.0) }, 2);
}
