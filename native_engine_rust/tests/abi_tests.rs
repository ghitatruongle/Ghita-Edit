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
    // Derived from CARGO_PKG_VERSION — never hardcode a release number here.
    assert!(
        s.starts_with(concat!("Ghita Core Engine v", env!("CARGO_PKG_VERSION"))),
        "got: {s}"
    );
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

// v1.5.5-demo (B3): adjustment graph -----------------------------------------

fn graph_json_of(c: &Ctx, clip: i32) -> String {
    unsafe { std::ffi::CStr::from_ptr(ghita_engine_graph_get_json(c.0, clip)) }
        .to_str()
        .unwrap()
        .to_string()
}

#[test]
fn graph_empty_is_identity() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    let mut a = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, a.as_mut_ptr(), 64, 36, 1000) });
    // add then clear → must return to the identical frame (parity default)
    assert!(unsafe { ghita_engine_graph_add_node(c.0, 1, 0, 0.5, 0.0, 0.0) } >= 0);
    assert_eq!(unsafe { ghita_engine_graph_clear(c.0, 1) }, 1);
    let mut b = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, b.as_mut_ptr(), 64, 36, 1000) });
    assert_eq!(a, b, "cleared graph must render identically to no graph");
}

#[test]
fn graph_brightness_changes_frame() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    let mut base = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, base.as_mut_ptr(), 64, 36, 1000) });
    assert!(unsafe { ghita_engine_graph_add_node(c.0, 1, 0, 0.5, 0.0, 0.0) } >= 0);
    let mut bright = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, bright.as_mut_ptr(), 64, 36, 1000) });
    assert_ne!(base, bright, "brightness +0.5 must change pixels");
    for (i, (b, w)) in base.iter().zip(bright.iter()).enumerate() {
        if i % 4 == 3 {
            assert_eq!(w, b, "alpha must be untouched");
        } else {
            assert!(w >= b, "brightness must only lift channels");
        }
    }
}

#[test]
fn graph_node_order_matters() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    // contrast → saturation
    unsafe {
        ghita_engine_graph_add_node(c.0, 1, 1, 0.8, 0.0, 0.0);
        ghita_engine_graph_add_node(c.0, 1, 2, -1.0, 0.0, 0.0);
    }
    let mut ab = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, ab.as_mut_ptr(), 64, 36, 1000) });
    // saturation → contrast (reversed chain)
    unsafe {
        ghita_engine_graph_clear(c.0, 1);
        ghita_engine_graph_add_node(c.0, 1, 2, -1.0, 0.0, 0.0);
        ghita_engine_graph_add_node(c.0, 1, 1, 0.8, 0.0, 0.0);
    }
    let mut ba = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, ba.as_mut_ptr(), 64, 36, 1000) });
    assert_ne!(ab, ba, "node order must matter (contrast→sat ≠ sat→contrast)");
}

#[test]
fn graph_preserved_across_upsert() {
    // Review regression guard: upsert_clip updates in place — the graph
    // chain must survive a timeline re-sync.
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    assert!(unsafe { ghita_engine_graph_add_node(c.0, 1, 2, 0.7, 0.0, 0.0) } >= 0);
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 1000, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    let j = graph_json_of(&c, 1);
    assert!(j.contains("\"type\":2"), "graph lost across upsert: {j}");
}

#[test]
fn graph_json_roundtrip_lifo_and_unknown() {
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    assert_eq!(graph_json_of(&c, 1), "[]");
    assert_eq!(unsafe { ghita_engine_graph_add_node(c.0, 1, 0, 0.25, 0.0, 0.0) }, 0);
    assert_eq!(unsafe { ghita_engine_graph_add_node(c.0, 1, 1, -0.5, 0.0, 0.0) }, 1);
    let j = graph_json_of(&c, 1);
    assert!(j.contains("\"type\":0") && j.contains("\"type\":1"), "{j}");
    // LIFO remove
    assert_eq!(unsafe { ghita_engine_graph_remove_last(c.0, 1) }, 1);
    let j2 = graph_json_of(&c, 1);
    assert!(j2.contains("\"type\":0") && !j2.contains("\"type\":1"), "{j2}");
    // unknown clip
    assert_eq!(unsafe { ghita_engine_graph_add_node(c.0, 999, 0, 0.1, 0.0, 0.0) }, -1);
    assert_eq!(graph_json_of(&c, 999), "[]");
    assert_eq!(unsafe { ghita_engine_graph_clear(c.0, 999) }, 0);
}

#[test]
fn graph_exposure_and_vibrance_nodes_render() {
    // v1.5.5-beta1 (T1.P3): the two node types added in beta1 must reach the
    // render path (not silently ignored by the engine's node match).
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0) };
    let mut base = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, base.as_mut_ptr(), 64, 36, 1000) });

    // Exposure +1 stop: every channel must be >= base.
    assert!(unsafe { ghita_engine_graph_add_node(c.0, 1, 3, 1.0, 0.0, 0.0) } >= 0);
    let mut exposed = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, exposed.as_mut_ptr(), 64, 36, 1000) });
    assert_ne!(base, exposed, "exposure node must change the frame");
    for (i, (b, e)) in base.iter().zip(exposed.iter()).enumerate() {
        if i % 4 == 3 {
            assert_eq!(e, b, "alpha untouched");
        } else {
            assert!(*e >= *b, "exposure +1 stop must only lift channels");
        }
    }
    assert!(unsafe { ghita_engine_graph_clear(c.0, 1) } != 0);

    // Vibrance must also reach the render path.
    assert!(unsafe { ghita_engine_graph_add_node(c.0, 1, 4, 0.8, 0.0, 0.0) } >= 0);
    let mut vibed = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(c.0, vibed.as_mut_ptr(), 64, 36, 1000) });
    assert_ne!(base, vibed, "vibrance node must change the frame");
}

#[test]
fn paused_scrub_cache_hit_rate_is_measured() {
    // v1.5.5-beta1 (T4.P1): measure the paused-scrub cache hit rate instead
    // of assuming it. A user dragging the playhead sweeps positions, then
    // comes back — that is the access pattern the paused cache exists for.
    let p = unsafe { ghita_engine_create() };
    assert!(!p.is_null());
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    let path = cstr("missing.mp4");
    assert_eq!(
        unsafe { ghita_engine_upsert_clip(p, 1, path.as_ptr(), 0, 20000, 0, 0, 0, 1.0, 1.0, 1.0) },
        1
    );
    unsafe { ghita_engine_seek(p, 0) };

    let w = 640i32;
    let h = 360i32;
    let mut buf = vec![0u8; (w * h * 4) as usize];
    // 3 seconds of timeline at 30 fps = 90 distinct positions, swept
    // forward, backward, forward again — a realistic back-and-forth scrub.
    let step_ms = 1000 / 30;
    let mut render = |pos: i64| unsafe {
        ghita_engine_render_frame_at(p, buf.as_mut_ptr(), w, h, pos)
    };
    for pos in (0..90).map(|i| i * step_ms) {
        render(pos);
    }
    for pos in (0..90).rev().map(|i| i * step_ms) {
        render(pos);
    }
    for pos in (0..90).map(|i| i * step_ms) {
        render(pos);
    }

    let stats = unsafe { std::ffi::CStr::from_ptr(ghita_engine_cache_stats(p)) }
        .to_str()
        .unwrap()
        .to_string();
    let num = |key: &str| -> u64 {
        let i = stats.find(&format!("\"{key}\":")).expect(key) + key.len() + 3;
        let rest = &stats[i..];
        let end = rest.find([',', '}']).unwrap();
        rest[..end].parse().unwrap()
    };
    let (hits, misses) = (num("hits"), num("misses"));
    let rate = hits as f64 / (hits + misses).max(1) as f64;
    println!("scrub cache: {hits} hits / {misses} misses = {:.0}%", rate * 100.0);
    unsafe { ghita_engine_destroy(p) };
    // A 3s back-and-forth scrub MUST land real hits — if this drops, the
    // paused cache stopped serving its purpose.
    assert!(rate >= 0.4, "paused-scrub hit rate collapsed: {rate:.2}");
}

#[test]
fn native_engine_init_cost_is_measured() {
    // v1.5.5-beta1 (T4.P2): measure native startup so any cold-start claim
    // is backed by a number. 5 fresh contexts (create+init+destroy).
    let mut create_total = 0.0f64;
    let mut init_total = 0.0f64;
    for _ in 0..5 {
        let t0 = std::time::Instant::now();
        let p = unsafe { ghita_engine_create() };
        create_total += t0.elapsed().as_secs_f64();
        let t1 = std::time::Instant::now();
        assert_eq!(unsafe { ghita_engine_init(p) }, 0);
        init_total += t1.elapsed().as_secs_f64();
        unsafe { ghita_engine_destroy(p) };
    }
    println!(
        "cold-start native: create {:.2} ms, init {:.2} ms (avg of 5)",
        create_total * 100.0,
        init_total * 100.0
    );
    // Sanity ceiling: native init must stay well under a frame budget so
    // startup regressions are loud.
    assert!(init_total / 5.0 < 0.25, "native init regressed past 250 ms");
}

#[test]
fn export_and_preview_render_concurrently_is_safe() {
    // v1.5.5-beta1 (debug): the app DOES render preview frames while an
    // export runs on its own thread (users export while the timeline keeps
    // playing). Both paths call render_timeline_frame against the SAME
    // engine state, so this must not panic or corrupt either side.
    // This is also the shape the engine_compare flake needs: concurrent
    // renders + a live export in one process.
    let c = Ctx::new();
    let path = cstr("missing.mp4");
    assert_eq!(
        unsafe { ghita_engine_upsert_clip(c.0, 1, path.as_ptr(), 0, 10000, 0, 0, 0, 1.0, 1.0, 1.0) },
        1
    );
    let out = cstr("concurrency_probe.mp4");
    let codec = cstr("h264");
    assert_eq!(
        unsafe { ghita_engine_start_export_ex(c.0, out.as_ptr(), 64, 36, 10, codec.as_ptr(), 500000, false) },
        0
    );
    assert!(unsafe { ghita_engine_is_exporting(c.0) });

    // Preview renders while the export thread is busy.
    let mut buf = vec![0u8; 64 * 36 * 4];
    let mut renders = 0u32;
    for i in 0..200 {
        if unsafe { ghita_engine_render_frame_at(c.0, buf.as_mut_ptr(), 64, 36, (i * 37) % 5000) } {
            renders += 1;
        }
    }
    assert!(renders > 0, "preview renders must keep working during export");

    // Export must finish (cancel_export joins the thread; a panic inside it
    // would surface as export_error).
    for _ in 0..3000 {
        if !unsafe { ghita_engine_is_exporting(c.0) } {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    assert!(
        !unsafe { ghita_engine_is_exporting(c.0) },
        "export never finished while preview was rendering"
    );
    let _ = std::fs::remove_file("concurrency_probe.mp4");
}

#[test]
fn concurrent_render_stress_does_not_corrupt_later_frames() {
    // v1.5.5-beta1 (debug): the engine_compare harness runs a 4-thread ×
    // 20-render stress BEFORE the real-media scenario, and the media frames
    // then mismatch the C++ engine intermittently. This pins the cause: if a
    // stressed engine still renders byte-identically to a pristine one, the
    // stress is NOT the corruptor and the flake lives elsewhere.
    let mk = || {
        let c = Ctx::new();
        let p = cstr("missing.mp4");
        unsafe {
            ghita_engine_upsert_clip(c.0, 1, p.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 1.0, 1.0);
        }
        c
    };

    let render = |c: &Ctx, pos: i64| -> Vec<u8> {
        let mut b = frame(64, 36);
        assert!(unsafe { ghita_engine_render_frame_at(c.0, b.as_mut_ptr(), 64, 36, pos) });
        b
    };

    // Control: never stressed.
    let control = mk();
    let control_frames: Vec<Vec<u8>> = [0, 300, 900, 1800].iter().map(|p| render(&control, *p)).collect();

    // Stressed: 4 threads × 20 concurrent renders, exactly the harness shape.
    let stressed = mk();
    {
        let raw = unsafe { std::sync::Arc::new(stressed.0 as usize) };
        let mut handles = Vec::new();
        for t in 0..4 {
            let raw = std::sync::Arc::clone(&raw);
            handles.push(std::thread::spawn(move || {
                let addr = *raw as usize;
                let ctx = addr as *mut GhitaEngineContext;
                let mut local = vec![0u8; 64 * 36 * 4];
                for k in 0..20 {
                    let pos = ((t * 7 + k) * 11) % 4000;
                    unsafe {
                        ghita_engine_render_frame_at(ctx, local.as_mut_ptr(), 64, 36, pos);
                    }
                }
            }));
        }
        for h in handles {
            h.join().expect("stress thread must not panic");
        }
    }

    for (i, pos) in [0, 300, 900, 1800].iter().enumerate() {
        let after = render(&stressed, *pos);
        assert_eq!(
            after,
            control_frames[i],
            "frame@{pos} differs after concurrent-render stress (t={i})"
        );
    }
}

#[test]
fn abi_surface_audit_all_116_symbols_present() {
    // T1.P1 (v1.5.5-beta2): every symbol the Flutter side looks up, plus the
    // parity-harness-only exports, must exist in the C API source. A rename
    // or accidental removal of any one breaks the drop-in ABI. Source-level
    // scan keeps this in sync without loading any DLL.
    let src = include_str!("../src/c_api.rs");
    let mut exported: Vec<String> = Vec::new();
    for line in src.lines() {
        let t = line.trim_start();
        if let Some(rest) = t.strip_prefix("pub unsafe extern \"C\" fn ") {
            if let Some(name) = rest.split(['(', '<']).next() {
                let name = name.trim();
                if name.starts_with("ghita_engine_") {
                    exported.push(name.to_string());
                }
            }
        }
    }
    exported.sort();
    exported.dedup();
    // The 110 symbols lib/src/ffi/native_bindings.dart actually looks up
    // (audit 2026-09-28: 110/110 resolve — zero missing exports).
    const PRODUCT: &[&str] = &[
        "ghita_engine_add_audio_effect",
        "ghita_engine_add_bookmark",
        "ghita_engine_add_clip",
        "ghita_engine_add_clip_keyframe",
        "ghita_engine_add_keyframe_ex",
        "ghita_engine_add_spectral_edit",
        "ghita_engine_add_speed_ramp_point",
        "ghita_engine_apply_color_correction",
        "ghita_engine_apply_filter",
        "ghita_engine_cache_stats",
        "ghita_engine_cancel_export",
        "ghita_engine_clear_audio_effects",
        "ghita_engine_clear_clip_keyframes",
        "ghita_engine_clear_clips",
        "ghita_engine_clear_selection",
        "ghita_engine_clear_spectral_edits",
        "ghita_engine_clear_speed_curve",
        "ghita_engine_copy_keyframes",
        "ghita_engine_create",
        "ghita_engine_destroy",
        "ghita_engine_detect_tempo",
        "ghita_engine_export_labels",
        "ghita_engine_get_audio_waveform",
        "ghita_engine_get_audio_waveform_peaks",
        "ghita_engine_get_available_filters",
        "ghita_engine_get_beat_times",
        "ghita_engine_get_bookmark_count",
        "ghita_engine_get_bookmarks_json",
        "ghita_engine_get_clip_count",
        "ghita_engine_get_clip_keyframe_count",
        "ghita_engine_get_clip_keyframe_interpolation",
        "ghita_engine_get_duration_ms",
        "ghita_engine_get_export_file_size",
        "ghita_engine_get_export_progress",
        "ghita_engine_get_gain_reduction_db",
        "ghita_engine_get_mask_buffer",
        "ghita_engine_get_media_height",
        "ghita_engine_get_media_info",
        "ghita_engine_get_media_width",
        "ghita_engine_get_playback_rate",
        "ghita_engine_get_position_ms",
        "ghita_engine_get_spectrogram",
        "ghita_engine_get_thumbnail",
        "ghita_engine_get_timeline_rms",
        "ghita_engine_get_timeline_waveform",
        "ghita_engine_get_version",
        "ghita_engine_gpu_enabled",
        "ghita_engine_gpu_stats",
        "ghita_engine_graph_add_node",
        "ghita_engine_graph_clear",
        "ghita_engine_graph_get_json",
        "ghita_engine_graph_remove_last",
        "ghita_engine_has_clip",
        "ghita_engine_has_ffmpeg",
        "ghita_engine_import_transcript",
        "ghita_engine_init",
        "ghita_engine_is_exporting",
        "ghita_engine_is_playing",
        "ghita_engine_is_recording",
        "ghita_engine_load_media",
        "ghita_engine_modify_mask",
        "ghita_engine_paint_brush_stroke",
        "ghita_engine_paint_clone",
        "ghita_engine_paint_heal",
        "ghita_engine_pause",
        "ghita_engine_play",
        "ghita_engine_remove_audio_effect",
        "ghita_engine_remove_bookmark",
        "ghita_engine_remove_clip",
        "ghita_engine_render_frame_at",
        "ghita_engine_render_frame_at_ex",
        "ghita_engine_render_frame_rgba",
        "ghita_engine_render_pip",
        "ghita_engine_render_text_overlay",
        "ghita_engine_resample_waveform",
        "ghita_engine_seek",
        "ghita_engine_set_audio_effect_param",
        "ghita_engine_set_canvas_background",
        "ghita_engine_set_clip_blend_mode",
        "ghita_engine_set_clip_color_correction",
        "ghita_engine_set_clip_filter",
        "ghita_engine_set_clip_font",
        "ghita_engine_set_clip_keyframe_interpolation",
        "ghita_engine_set_clip_maintain_pitch",
        "ghita_engine_set_clip_mask",
        "ghita_engine_set_clip_pip",
        "ghita_engine_set_clip_pitch",
        "ghita_engine_set_clip_position",
        "ghita_engine_set_clip_sticker_transform",
        "ghita_engine_set_clip_text",
        "ghita_engine_set_clip_transition",
        "ghita_engine_set_filter_preset",
        "ghita_engine_set_gpu_enabled",
        "ghita_engine_set_keyframe_bezier",
        "ghita_engine_set_loop_region",
        "ghita_engine_set_noise_suppress",
        "ghita_engine_set_playback_rate",
        "ghita_engine_set_preview_pitch_preserve",
        "ghita_engine_set_selection_ellipse",
        "ghita_engine_set_selection_lasso",
        "ghita_engine_set_selection_magic_wand",
        "ghita_engine_set_selection_rect",
        "ghita_engine_set_time_signature",
        "ghita_engine_set_track_state",
        "ghita_engine_set_volume",
        "ghita_engine_start_export",
        "ghita_engine_start_export_ex",
        "ghita_engine_start_recording",
        "ghita_engine_stop_recording",
        "ghita_engine_upsert_clip",
    ];
    // Exported for the A/B harness / parity completeness, unused by Flutter.
    const HARNESS_ONLY: &[&str] = &[
        "ghita_engine_get_direct_buffer",
        "ghita_engine_get_snapping_fps",
        "ghita_engine_mix_audio_window",
        "ghita_engine_set_audio_preview_enabled",
        "ghita_engine_set_export_channel_layout",
        "ghita_engine_set_snapping_fps",
    ];
    for sym in PRODUCT.iter().chain(HARNESS_ONLY.iter()) {
        assert!(
            exported.iter().any(|e| e == sym),
            "missing ABI symbol: {sym}"
        );
    }
    assert_eq!(
        exported.len(),
        PRODUCT.len() + HARNESS_ONLY.len(),
        "ABI surface changed — update docs/rust_engine_abi.md and this audit list"
    );
}

#[cfg(windows)]
fn working_set_mb() -> f64 {
    use windows_sys::Win32::System::ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS};
    use windows_sys::Win32::System::Threading::GetCurrentProcess;
    unsafe {
        let mut pmc: PROCESS_MEMORY_COUNTERS = std::mem::zeroed();
        pmc.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
        assert_ne!(GetProcessMemoryInfo(GetCurrentProcess(), &mut pmc, pmc.cb), 0);
        pmc.WorkingSetSize as f64 / 1024.0 / 1024.0
    }
}

#[test]
fn engine_lifecycle_stress_memory_is_bounded() {
    // T1.P4 (v1.5.5-beta2): long-run leak probe. 240 full create→init→
    // upsert→render→destroy cycles on real media plus 100 upsert/remove
    // churn cycles on one context; the working set must stay bounded —
    // decode buffers, caches and GDI handles must all die with the context
    // or with remove_clip on the happy path.
    const MEDIA: &str = "../test_video.mp4";
    if !std::path::Path::new(MEDIA).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    let path = cstr(MEDIA);
    let (w, h) = (320i32, 180i32);
    let mut buf = vec![0u8; (w * h * 4) as usize];
    let cycle = |i: usize, buf: &mut [u8]| unsafe {
        let p = ghita_engine_create();
        assert!(!p.is_null());
        assert_eq!(ghita_engine_init(p), 0);
        assert_eq!(
            ghita_engine_upsert_clip(p, 1, path.as_ptr(), 0, 20000, 0, 0, 0, 1.0, 1.0, 1.0),
            1
        );
        ghita_engine_seek(p, 0);
        assert!(ghita_engine_render_frame_at(p, buf.as_mut_ptr(), w, h, (i as i64 * 173) % 18000));
        assert!(ghita_engine_render_frame_at(p, buf.as_mut_ptr(), w, h, (i as i64 * 431) % 18000));
        assert!(ghita_engine_render_frame_at(p, buf.as_mut_ptr(), w, h, 0));
        ghita_engine_destroy(p);
    };
    for i in 0..40 {
        cycle(i, &mut buf); // warm-up: allocator reaches steady state
    }
    let before = working_set_mb();
    for i in 40..240 {
        cycle(i, &mut buf);
    }
    // Single-context churn: upsert/remove 100× — the app edit-loop pattern.
    let p = unsafe { ghita_engine_create() };
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    for i in 0..100 {
        assert_eq!(
            unsafe {
                ghita_engine_upsert_clip(p, 1 + (i % 3) as i32, path.as_ptr(), 0, 20000, 0, 0, 0, 1.0, 1.0, 1.0)
            },
            1
        );
        assert!(unsafe {
            ghita_engine_render_frame_at(p, buf.as_mut_ptr(), w, h, (i as i64 * 97) % 18000)
        });
        assert_eq!(unsafe { ghita_engine_remove_clip(p, 1 + (i % 3) as i32) }, 0);
    }
    unsafe { ghita_engine_destroy(p) };
    let after = working_set_mb();
    let growth = after - before;
    println!("memory stress: working set {before:.1} → {after:.1} MB (Δ{growth:.1} MB)");
    assert!(
        growth < 150.0,
        "working set grew {growth:.1} MB over 200 ctx cycles + 100 churn cycles — leak"
    );
}
