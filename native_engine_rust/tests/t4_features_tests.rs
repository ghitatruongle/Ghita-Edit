//! T4 integration tests — audio features through the C API + engine:
//! effect chain, spectrogram, spectral edit, tempo, beats, loop, clip pitch,
//! recording lifecycle (device-dependent) and label export (SRT/VTT).

#![cfg(feature = "ffmpeg")]

use std::ffi::CString;

use ghita_engine::c_api::*;

fn ctx_new() -> *mut GhitaEngineContext {
    let p = unsafe { ghita_engine_create() };
    assert!(!p.is_null());
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    p
}

const MEDIA: &str = "../test_sine.wav";

fn rms(buf: &[f32]) -> f32 {
    if buf.is_empty() {
        return 0.0;
    }
    (buf.iter().map(|v| v * v).sum::<f32>() / buf.len() as f32).sqrt()
}

/// The suite used to depend on an untracked ../test_sine.wav that only existed
/// on dev machines (fresh checkouts / CI had none, so every setup_sine test
/// failed). Generate it when missing: 2 s of near-full-scale 440 Hz stereo.
///
/// Tests run in parallel threads, so generation is serialized under a mutex:
/// every caller goes through this gate BEFORE opening the media, so no thread
/// can read a half-written file, and Windows refuses rename-over-open-file
/// (os error 5) — direct write under the lock is the only safe form.
fn ensure_sine_wav() {
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let _guard = LOCK.lock().unwrap();
    if std::path::Path::new(MEDIA).exists() {
        return;
    }
    const RATE: f32 = 44100.0;
    let frames = RATE as usize * 2;
    let mut samples = Vec::with_capacity(frames * 2);
    for i in 0..frames {
        let v = ((i as f32) * 440.0 * std::f32::consts::TAU / RATE).sin() * 0.9;
        samples.push(v);
        samples.push(v);
    }
    ghita_engine::audio_t4::write_wav_pcm16(MEDIA, &samples).expect("write test_sine.wav");
}

fn setup_sine(p: *mut GhitaEngineContext) {
    ensure_sine_wav();
    let path = CString::new(MEDIA).unwrap();
    unsafe { ghita_engine_load_media(p, path.as_ptr()) };
    let path = CString::new(MEDIA).unwrap();
    assert_eq!(unsafe { ghita_engine_upsert_clip(p, 1, path.as_ptr(), 0, 2000, 0, 0, 1, 1.0, 1.0, 1.0) }, 1);
}

// #24/#25 Effect chain ------------------------------------------------------

#[test]
fn t4_effect_chain_compressor_changes_mix() {
    let p = ctx_new();
    setup_sine(p);
    let mut base = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, base.as_mut_ptr(), 13230) });
    let base_peak = base.iter().fold(0.0f32, |m, v| m.max(v.abs()));

    // Heavy compressor on a loud sine (the WAV is near-full-scale).
    assert!(unsafe { ghita_engine_add_audio_effect(p, 0, -30.0, 10.0, 5.0, 100.0) } >= 0);
    let mut compressed = vec![0.0f32; 13230];
    // Warm the compressor envelope with one pass first.
    let mut warm = vec![0.0f32; 13230];
    let _ = unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, warm.as_mut_ptr(), 13230) };
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, compressed.as_mut_ptr(), 13230) });
    let comp_peak = rms(&compressed[..compressed.len()/2]);
    assert!(
        comp_peak < base_peak * 0.7,
        "compressor must reduce the bus: {base_peak} -> {comp_peak}"
    );
    assert!(unsafe { ghita_engine_get_gain_reduction_db(p) } > 1.0, "GR history");

    // Clear restores the mix.
    unsafe { ghita_engine_clear_audio_effects(p) };
    let mut clean = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, clean.as_mut_ptr(), 13230) });
    // Compare RMS to RMS — the old assert measured clean RMS against base
    // PEAK, which only holds for a near-square source wave.
    let clean_rms = rms(&clean[..clean.len() / 2]);
    let base_rms = rms(&base[..base.len() / 2]);
    assert!((clean_rms - base_rms).abs() < 0.05, "clear restores: {clean_rms} vs {base_rms}");
    unsafe { ghita_engine_destroy(p) };
}

// #15 Spectrogram -----------------------------------------------------------

#[test]
fn t4_spectrogram_from_timeline() {
    let p = ctx_new();
    setup_sine(p);
    let columns: i32 = 16;
    let bins: i32 = 64;
    let mut mags = vec![0.0f32; (columns * bins) as usize];
    assert!(unsafe { ghita_engine_get_spectrogram(p, mags.as_mut_ptr(), columns, bins, 0) });
    let max_v = mags.iter().cloned().fold(0.0f32, f32::max);
    assert!(max_v > 0.3, "sine timeline must show energy: {max_v}");
    // The WAV is a sine — check the peak bin is low (the file is 440 Hz).
    let mut best = 0usize;
    let mut best_v = 0.0f32;
    for b in 0..bins as usize {
        let v = mags[b];
        if v > best_v {
            best_v = v;
            best = b;
        }
    }
    assert!(best <= 12, "440 Hz peak should be a low bin, got {best}");
    unsafe { ghita_engine_destroy(p) };
}

// #16 Spectral editing --------------------------------------------------------

#[test]
fn t4_spectral_edit_changes_mix() {
    let p = ctx_new();
    setup_sine(p);
    let mut before = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, before.as_mut_ptr(), 13230) });
    assert!(unsafe { ghita_engine_add_spectral_edit(p, 0, 10_000, 200.0, 2000.0, -40.0) } >= 0);
    let mut after = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, after.as_mut_ptr(), 13230) });
    let before_peak = rms(&before[..before.len()/2]);
    let after_peak = rms(&after[..after.len()/2]);
    assert!(
        after_peak < before_peak * 0.7,
        "spectral cut must reduce a 440 Hz window: {before_peak} -> {after_peak}"
    );
    unsafe { ghita_engine_clear_spectral_edits(p) };
    let mut restored = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, restored.as_mut_ptr(), 13230) });
    let restored_peak = rms(&restored[..restored.len()/2]);
    assert!((restored_peak - before_peak).abs() < 0.05);
    unsafe { ghita_engine_destroy(p) };
}

// #5/opt RMS waveform --------------------------------------------------------

#[test]
fn t4_timeline_rms() {
    let p = ctx_new();
    setup_sine(p);
    let mut rms = vec![0.0f32; 16];
    assert!(unsafe { ghita_engine_get_timeline_rms(p, rms.as_mut_ptr(), 16, 0) });
    assert!(rms.iter().any(|v| *v > 0.05), "sine RMS: {rms:?}");
    unsafe { ghita_engine_destroy(p) };
}

// #31 Tempo -------------------------------------------------------------------

#[test]
fn t4_tempo_detection_runs() {
    let p = ctx_new();
    setup_sine(p);
    // A sine has no strong onsets — the detector may return 0; the call must
    // not crash and must return a sane value.
    let bpm10 = unsafe { ghita_engine_detect_tempo(p) };
    assert!(bpm10 >= 0 && bpm10 <= 2000, "bpm*10 in range: {bpm10}");
    unsafe { ghita_engine_destroy(p) };
}

// #32 Beats -------------------------------------------------------------------

#[test]
fn t4_beat_times_grid() {
    let p = ctx_new();
    setup_sine(p);
    unsafe { ghita_engine_set_time_signature(p, 4, 4) };
    let mut beats = vec![0i64; 8];
    let n = unsafe { ghita_engine_get_beat_times(p, beats.as_mut_ptr(), 8) };
    assert!(n > 0, "timeline 2 s @ 120 bpm = 4 beats, got {n}");
    assert_eq!(beats[0], 0);
    unsafe { ghita_engine_destroy(p) };
}

// #22 Loop region -------------------------------------------------------------

#[test]
fn t4_loop_region_wraps_playhead() {
    let e = ghita_engine::engine::GhitaEngine::new();
    assert!(e.initialize());
    e.set_loop_region(500, 1500, true);
    // Simulate the wrap computation used in render_frame_rgba.
    let (ls, le, enabled) = e.get_loop_region();
    assert!(enabled && ls == 500 && le == 1500);
    let mut pos = 1600i64;
    if enabled && le > ls && pos >= le {
        pos = ls + ((pos - ls) % (le - ls).max(1));
    }
    assert_eq!(pos, 600, "wrap: 1600 -> 600 in [500,1500)");
    e.set_loop_region(0, 0, false);
    assert!(!e.get_loop_region().2);
}

// #17 Clip pitch shift ---------------------------------------------------------

#[test]
fn t4_clip_pitch_shift_changes_frequency() {
    let p = ctx_new();
    setup_sine(p);
    fn crossings(buf: &[f32]) -> usize {
        let mut n = 0;
        for i in 1..buf.len() / 2 - 1 {
            let a = buf[i * 2];
            let b = buf[i * 2 + 2];
            if (a < 0.0 && b >= 0.0) || (a >= 0.0 && b < 0.0) {
                n += 1;
            }
        }
        n
    }
    let mut base = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, base.as_mut_ptr(), 13230) });
    let base_c = crossings(&base);
    assert!(base_c > 3, "sine has crossings: {base_c}");

    assert_eq!(unsafe { ghita_engine_set_clip_pitch(p, 1, 12.0) }, 0); // +1 octave
    assert_eq!(unsafe { ghita_engine_set_clip_pitch(p, 99, 12.0) }, -1);
    let mut shifted = vec![0.0f32; 13230];
    assert!(unsafe { ghita_engine_mix_audio_window(p, 1000, 1300, shifted.as_mut_ptr(), 13230) });
    let shifted_c = crossings(&shifted);
    assert!(
        shifted_c > base_c * 3 / 2,
        "+12 semitones must raise pitch: {base_c} -> {shifted_c}"
    );
    unsafe { ghita_engine_destroy(p) };
}

// #18–#20 Recording lifecycle ---------------------------------------------------

#[test]
fn t4_recording_lifecycle() {
    let e = ghita_engine::engine::GhitaEngine::new();
    assert!(e.initialize());
    assert!(!e.is_recording());
    // Timed recording: 300 ms. Device-dependent — skip gracefully when no
    // input device exists (CI containers).
    let out = std::env::temp_dir().join("t4_rec_test.wav");
    let r = e.start_recording(out.to_str().unwrap(), 2, 0, 50, 300);
    if r != 0 {
        eprintln!("SKIP: no input device");
        return;
    }
    assert!(e.is_recording());
    std::thread::sleep(std::time::Duration::from_millis(450));
    let ms = e.stop_recording();
    assert!(!e.is_recording());
    eprintln!("recorded {ms} ms");
    if ms > 0 {
        let meta = std::fs::metadata(&out).unwrap();
        assert!(meta.len() > 44, "WAV written: {} bytes", meta.len());
        // WAV header check: 'RIFF' + PCM16 stereo.
        let mut hdr = [0u8; 44];
        use std::io::Read;
        std::fs::File::open(&out).unwrap().read_exact(&mut hdr).unwrap();
        assert_eq!(&hdr[0..4], b"RIFF");
        assert_eq!(&hdr[8..12], b"WAVE");
        let _ = std::fs::remove_file(&out);
    }
}

// #23 Labels export -------------------------------------------------------------

#[test]
fn t4_export_labels_srt_and_vtt() {
    let p = ctx_new();
    let n1 = CString::new("intro").unwrap();
    let n2 = CString::new("outro").unwrap();
    unsafe { ghita_engine_add_bookmark(p, 1500, 0xFFFF0000, n1.as_ptr()) };
    unsafe { ghita_engine_add_bookmark(p, 4000, 0xFF00FF00, n2.as_ptr()) };

    let srt = std::env::temp_dir().join("t4_labels.srt");
    let srt_c = CString::new(srt.to_str().unwrap()).unwrap();
    assert_eq!(unsafe { ghita_engine_export_labels(p, srt_c.as_ptr(), 0) }, 2);
    let srt_data = std::fs::read_to_string(&srt).unwrap();
    assert!(srt_data.contains("00:00:01,500 --> 00:00:04,000"), "srt: {srt_data}");
    assert!(srt_data.contains("intro"));

    let vtt = std::env::temp_dir().join("t4_labels.vtt");
    let vtt_c = CString::new(vtt.to_str().unwrap()).unwrap();
    assert_eq!(unsafe { ghita_engine_export_labels(p, vtt_c.as_ptr(), 1) }, 2);
    let vtt_data = std::fs::read_to_string(&vtt).unwrap();
    assert!(vtt_data.starts_with("WEBVTT"), "vtt: {vtt_data}");
    assert!(vtt_data.contains("00:00:01.500 --> 00:00:04.000"));
    let _ = std::fs::remove_file(&srt);
    let _ = std::fs::remove_file(&vtt);
    unsafe { ghita_engine_destroy(p) };
}
