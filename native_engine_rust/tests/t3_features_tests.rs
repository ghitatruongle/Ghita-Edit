//! T3 feature tests — engine-level demos for the 14 Video Features.
//! UI-facing items (graph editor, lanes, zoom/pan, clipboard, guides) are
//! T3b (Flutter) work; their engine seams are covered here where they exist.

use std::ffi::CString;

use ghita_engine::c_api::*;

fn ctx_new() -> *mut GhitaEngineContext {
    let p = unsafe { ghita_engine_create() };
    assert!(!p.is_null());
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    p
}

fn frame(w: usize, h: usize) -> Vec<u8> {
    vec![0u8; w * h * 4]
}

fn upsert(p: *mut GhitaEngineContext, id: i32, path: &str, start: i64, dur: i64, track: i32, kind: i32) {
    let path = CString::new(path).unwrap();
    let r = unsafe { ghita_engine_upsert_clip(p, id, path.as_ptr(), start, dur, 0, track, kind, 1.0, 1.0, 1.0) };
    assert_eq!(r, 1, "upsert clip {id}");
}

const MISSING: &str = "missing_t3.mp4";

// #4 — Blend modes -----------------------------------------------------------

#[test]
fn t3_blend_modes_change_composite() {
    let p = ctx_new();
    upsert(p, 1, MISSING, 0, 5000, 0, 0);
    upsert(p, 2, MISSING, 0, 5000, 0, 0);

    // Normal blend baseline.
    let mut normal = frame(64, 36);
    let path = CString::new(MISSING).unwrap();
    unsafe { ghita_engine_load_media(p, path.as_ptr()) };
    assert!(unsafe { ghita_engine_render_frame_at(p, normal.as_mut_ptr(), 64, 36, 1000) });

    // Multiply blend must differ from normal.
    assert_eq!(unsafe { ghita_engine_set_clip_blend_mode(p, 2, 1) }, 0); // Multiply
    assert_eq!(unsafe { ghita_engine_set_clip_blend_mode(p, 99, 1) }, -1);
    let mut multiply = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, multiply.as_mut_ptr(), 64, 36, 1000) });
    assert_ne!(normal, multiply, "blend mode must change pixels");

    // Add mode over a gray canvas brightens it — differs from multiply.
    unsafe { ghita_engine_set_canvas_background(p, 0, 0xFF808080, 0) };
    assert_eq!(unsafe { ghita_engine_set_clip_blend_mode(p, 2, 4) }, 0);
    let mut add = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, add.as_mut_ptr(), 64, 36, 1000) });
    assert_ne!(add, multiply, "add over gray must differ from multiply over black");
    unsafe { ghita_engine_destroy(p) };
}

// #5 — Masks ------------------------------------------------------------------

#[test]
fn t3_masks_cut_out_regions() {
    let p = ctx_new();
    upsert(p, 1, MISSING, 0, 5000, 0, 0);
    let path = CString::new(MISSING).unwrap();
    unsafe { ghita_engine_load_media(p, path.as_ptr()) };

    let mut full = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, full.as_mut_ptr(), 64, 36, 1000) });

    // Rect mask → corners transparent → black with default canvas.
    assert_eq!(unsafe { ghita_engine_set_clip_mask(p, 1, 1, 0.0, 0.0) }, 0); // Rect
    assert_eq!(unsafe { ghita_engine_set_clip_mask(p, 99, 1, 0.0, 0.0) }, -1);
    let mut masked = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, masked.as_mut_ptr(), 64, 36, 1000) });
    // Corner pixel: full has content, masked is black (masked out).
    let corner = (35 * 64 + 63) * 4;
    assert_ne!(full[corner], 0, "unmasked corner should have content");
    assert!(masked[corner] == 0 && masked[corner + 1] == 0 && masked[corner + 2] == 0);
    // Center pixels still render.
    let center = (18 * 64 + 32) * 4;
    assert_ne!(masked[center], 0);
    unsafe { ghita_engine_destroy(p) };
}

// #9 — Canvas background ------------------------------------------------------

#[test]
fn t3_canvas_background_solid_gradient_blur() {
    let p = ctx_new();
    // 0xFF0000FF = opaque BLUE (A R G B). A clip at opacity 0 lets the
    // canvas background show through (alpha 0 → no blend).
    let path = CString::new(MISSING).unwrap();
    let r = unsafe { ghita_engine_upsert_clip(p, 1, path.as_ptr(), 0, 5000, 0, 0, 0, 1.0, 0.0, 1.0) };
    assert_eq!(r, 1);
    unsafe { ghita_engine_set_canvas_background(p, 0, 0xFF0000FF, 0) };
    let path = CString::new(MISSING).unwrap();
    unsafe { ghita_engine_load_media(p, path.as_ptr()) };
    let mut solid = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, solid.as_mut_ptr(), 64, 36, 100) });
    assert_eq!(solid[2], 0xFF); // blue
    assert_eq!(solid[0], 0);
    assert_eq!(solid[1], 0);

    // Gradient: top blue → bottom green.
    unsafe { ghita_engine_set_canvas_background(p, 1, 0xFF0000FF, 0xFF00FF00) };
    let mut grad = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, grad.as_mut_ptr(), 64, 36, 100) });
    assert_eq!(grad[2], 0xFF); // top = blue (B high)
    assert_eq!(grad[1], 0); // top has no green
    let bottom = (35 * 64) * 4;
    assert!(grad[bottom + 1] > 0, "green present at bottom");

    // Blur background: renders (no clip → black fallback).
    unsafe { ghita_engine_set_canvas_background(p, 2, 0, 0) };
    let mut blur = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, blur.as_mut_ptr(), 64, 36, 100) });
    unsafe { ghita_engine_destroy(p) };
}

// #10 — Bookmarks -------------------------------------------------------------

#[test]
fn t3_bookmarks_crud_and_json() {
    let p = ctx_new();
    let note = CString::new("intro").unwrap();
    let id1 = unsafe { ghita_engine_add_bookmark(p, 1200, 0xFFFF0000, note.as_ptr()) };
    assert!(id1 >= 1);
    let id2 = unsafe { ghita_engine_add_bookmark(p, 3400, 0xFF00FF00, note.as_ptr()) };
    assert!(id2 > id1);
    assert_eq!(unsafe { ghita_engine_get_bookmark_count(p) }, 2);

    let j = unsafe { ghita_engine_get_bookmarks_json(p) };
    let s = unsafe { std::ffi::CStr::from_ptr(j) }.to_str().unwrap().to_string();
    assert!(s.contains("\"timeMs\":1200"), "json: {s}");
    assert!(s.contains("\"timeMs\":3400"));

    assert_eq!(unsafe { ghita_engine_remove_bookmark(p, id1) }, 0);
    assert_eq!(unsafe { ghita_engine_remove_bookmark(p, id1) }, -1);
    assert_eq!(unsafe { ghita_engine_get_bookmark_count(p) }, 1);
    unsafe { ghita_engine_destroy(p) };
}

// #2 — Keyframe copy/paste ----------------------------------------------------

#[test]
fn t3_copy_keyframes_between_clips() {
    let p = ctx_new();
    upsert(p, 1, MISSING, 0, 5000, 0, 0);
    upsert(p, 2, MISSING, 0, 5000, 1, 0);
    assert_eq!(unsafe { ghita_engine_add_keyframe_ex(p, 1, 0, 0.0, 0, 0, 0.0, 0.0, 0.0, 0.0) }, 0);
    assert_eq!(unsafe { ghita_engine_add_keyframe_ex(p, 1, 5000, 1.0, 0, 0, 0.0, 0.0, 0.0, 0.0) }, 0);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(p, 2) }, 0);
    assert_eq!(unsafe { ghita_engine_copy_keyframes(p, 1, 2) }, 0);
    assert_eq!(unsafe { ghita_engine_copy_keyframes(p, 99, 2) }, -1);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(p, 2) }, 2);
    assert_eq!(unsafe { ghita_engine_get_clip_keyframe_count(p, 1) }, 2, "source unchanged");
    unsafe { ghita_engine_destroy(p) };
}

// #14 — Effect elements -------------------------------------------------------

#[test]
fn t3_effect_element_applies_filter() {
    let p = ctx_new();
    upsert(p, 1, MISSING, 0, 5000, 0, 0);
    // Effect clip (kind 5) on track 1 with grayscale filter.
    let path = CString::new("").unwrap();
    let r = unsafe { ghita_engine_upsert_clip(p, 2, path.as_ptr(), 0, 5000, 0, 1, 5, 1.0, 1.0, 1.0) };
    assert_eq!(r, 1, "effect kind upsert must succeed");
    assert_eq!(unsafe { ghita_engine_set_clip_filter(p, 2, 1, 1.0) }, 0);

    let path = CString::new(MISSING).unwrap();
    unsafe { ghita_engine_load_media(p, path.as_ptr()) };
    let mut fx = frame(64, 36);
    assert!(unsafe { ghita_engine_render_frame_at(p, fx.as_mut_ptr(), 64, 36, 1000) });
    // Every pixel must be gray (r==g==b after grayscale effect).
    for px in fx.chunks_exact(4) {
        assert_eq!(px[0], px[1], "r==g");
        assert_eq!(px[1], px[2], "g==b");
    }
    unsafe { ghita_engine_destroy(p) };
}

// #11 — Transcript import -----------------------------------------------------

#[test]
fn t3_import_transcript_creates_text_clips() {
    let srt = "1\n00:00:00,500 --> 00:00:02,000\nHello world\n\n2\n00:00:02,000 --> 00:00:04,000\nSecond line\n";
    let path = std::env::temp_dir().join("t3_transcript.srt");
    std::fs::write(&path, srt).unwrap();
    let p = ctx_new();
    let cpath = CString::new(path.to_str().unwrap()).unwrap();
    let n = unsafe { ghita_engine_import_transcript(p, cpath.as_ptr(), 3) };
    assert_eq!(n, 2, "two cues expected");
    assert_eq!(unsafe { ghita_engine_get_clip_count(p) }, 2);
    // Duration covers the transcript.
    assert_eq!(unsafe { ghita_engine_get_duration_ms(p) }, 4000);
    unsafe { ghita_engine_destroy(p) };
    let _ = std::fs::remove_file(&path);
}

// v1.5.0-T1 regression — CRLF-saved .srt must import EVERY cue: the old block
// split on a bare "\n\n" never matched "\r\n\r\n", so only the first cue
// became a clip.
#[test]
fn t3_import_transcript_crlf_imports_all_cues() {
    let srt = "1\r\n00:00:00,500 --> 00:00:02,000\r\nHello world\r\n\r\n2\r\n00:00:02,000 --> 00:00:04,000\r\nSecond line\r\n";
    let path = std::env::temp_dir().join("t3_transcript_crlf.srt");
    std::fs::write(&path, srt).unwrap();
    let p = ctx_new();
    let cpath = CString::new(path.to_str().unwrap()).unwrap();
    let n = unsafe { ghita_engine_import_transcript(p, cpath.as_ptr(), 3) };
    assert_eq!(n, 2, "CRLF file must yield two cues");
    assert_eq!(unsafe { ghita_engine_get_clip_count(p) }, 2);
    assert_eq!(unsafe { ghita_engine_get_duration_ms(p) }, 4000);
    unsafe { ghita_engine_destroy(p) };
    let _ = std::fs::remove_file(&path);
}

// #8 — Font family ------------------------------------------------------------

#[test]
fn t3_font_family_settable() {
    let p = ctx_new();
    upsert(p, 1, MISSING, 0, 5000, 0, 3);
    let font = CString::new("Arial").unwrap();
    assert_eq!(unsafe { ghita_engine_set_clip_font(p, 1, font.as_ptr()) }, 0);
    assert_eq!(unsafe { ghita_engine_set_clip_font(p, 99, font.as_ptr()) }, -1);
    unsafe { ghita_engine_destroy(p) };
}

// #7 — Maintain pitch ---------------------------------------------------------

#[test]
fn t3_maintain_pitch_keeps_zero_crossings() {
    let wav = "../../test_sine.wav";
    if !std::path::Path::new(wav).exists() {
        eprintln!("SKIP: test_sine.wav missing");
        return;
    }
    let e = ghita_engine::engine::GhitaEngine::new();
    assert!(e.initialize());
    e.load_media(wav);
    use ghita_engine::model::NativeClipKind;
    e.upsert_clip(1, wav, 0, 2000, 0, 0, NativeClipKind::Audio, 1.0, 1.0, 1.0);

    fn crossings(buf: &[f32]) -> usize {
        let mut n = 0usize;
        for i in 1..buf.len() / 2 {
            let l0 = buf[i * 2];
            let l1 = buf[i * 2 + 2];
            if (l0 < 0.0 && l1 >= 0.0) || (l0 >= 0.0 && l1 < 0.0) {
                n += 1;
            }
        }
        n
    }

    // Speed 1.0 baseline.
    let mut base = vec![0f32; 4410];
    assert!(e.mix_audio_window(0, 100, &mut base, 4410, true));
    let base_c = crossings(&base);
    assert!(base_c > 0);

    // Speed 2.0 without maintain-pitch → ~2× crossings (chipmunk).
    e.upsert_clip(1, wav, 0, 2000, 0, 0, NativeClipKind::Audio, 1.0, 1.0, 2.0);
    let mut fast = vec![0f32; 4410];
    assert!(e.mix_audio_window(0, 100, &mut fast, 4410, true));
    let fast_c = crossings(&fast);
    assert!(fast_c > base_c * 3 / 2, "speed 2× must roughly double crossings: {fast_c} vs {base_c}");

    // Speed 2.0 WITH maintain-pitch → crossings ≈ baseline (pitch preserved).
    e.set_clip_maintain_pitch(1, true);
    let mut pitched = vec![0f32; 4410];
    assert!(e.mix_audio_window(0, 100, &mut pitched, 4410, true));
    let pitched_c = crossings(&pitched);
    assert!(
        pitched_c < fast_c * 8 / 10,
        "maintain-pitch must NOT double the pitch: {pitched_c} vs {fast_c}"
    );
    assert!(
        pitched_c >= base_c * 6 / 10,
        "maintain-pitch must stay near the original pitch: {pitched_c} vs {base_c}"
    );
}