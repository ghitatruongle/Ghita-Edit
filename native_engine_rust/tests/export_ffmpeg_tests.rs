//! T2 export matrix — real FFmpeg encodes verified by ffprobe, mirroring the
//! app's verify_export_matrix.sh gate (H.264/H.265/VP9/MOV-ProRes/MP3/GIF).

#![cfg(feature = "ffmpeg")]

use std::ffi::CString;
use std::process::Command;

use ghita_engine::c_api::*;

fn ctx_new() -> *mut GhitaEngineContext {
    let p = unsafe { ghita_engine_create() };
    assert!(!p.is_null());
    assert_eq!(unsafe { ghita_engine_init(p) }, 0);
    p
}

fn probe(out: &str, args: &[&str]) -> String {
    let out = Command::new("ffprobe")
        .args(["-v", "error"])
        .args(args)
        .arg(out)
        .output()
        .expect("ffprobe on PATH (MinGW distribution)");
    assert!(out.status.success(), "ffprobe failed: {}", String::from_utf8_lossy(&out.stderr));
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn wait_export(p: *mut GhitaEngineContext) {
    for _ in 0..3000 {
        if !unsafe { ghita_engine_is_exporting(p) } {
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    panic!("export did not finish");
}

fn setup_timeline(p: *mut GhitaEngineContext, path: &str) {
    let path = CString::new(path).unwrap();
    unsafe { ghita_engine_load_media(p, path.as_ptr()) };
    // Two video clips back-to-back (audio track too).
    let path = CString::new(path.to_str().unwrap()).unwrap();
    assert_eq!(unsafe { ghita_engine_upsert_clip(p, 1, path.as_ptr(), 0, 2000, 0, 0, 0, 1.0, 1.0, 1.0) }, 1);
    assert_eq!(unsafe { ghita_engine_upsert_clip(p, 2, path.as_ptr(), 2000, 2000, 0, 0, 0, 1.0, 1.0, 1.0) }, 1);
}

fn export(p: *mut GhitaEngineContext, out: &str, codec: &str, w: i32, h: i32, fps: i32) -> i32 {
    let out = CString::new(out).unwrap();
    let codec = CString::new(codec).unwrap();
    let ret = unsafe {
        ghita_engine_start_export_ex(p, out.as_ptr(), w, h, fps, codec.as_ptr(), 5_000_000, true)
    };
    if ret == 0 {
        wait_export(p);
    }
    ret
}

const MEDIA: &str = "../test_video.mp4";
const OUT_DIR: &str = "target/export_matrix";

#[test]
fn export_matrix_h264_h265_vp9() {
    if !std::path::Path::new(MEDIA).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    std::fs::create_dir_all(OUT_DIR).unwrap();
    let p = ctx_new();
    setup_timeline(p, MEDIA);
    assert!(unsafe { ghita_engine_has_ffmpeg(p) }, "ffmpeg build expected");

    // H.264 + AAC (audio included by default).
    let f = format!("{OUT_DIR}/h264.mp4");
    assert_eq!(export(p, &f, "h264", 64, 36, 10), 0);
    assert!(unsafe { ghita_engine_get_export_file_size(p) } > 0);
    assert!(unsafe { ghita_engine_get_export_progress(p) } >= 1.0);
    let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0"]);
    assert!(v.starts_with("h264"), "got: {v}");
    assert!(v.contains("64,36") || v.contains("64,36"), "size: {v}");
    let a = probe(&f, &["-select_streams", "a:0", "-show_entries", "stream=codec_name,channels", "-of", "csv=p=0"]);
    assert!(a.starts_with("aac"), "audio stream: {a}");

    // H.265 (HEVC).
    let f = format!("{OUT_DIR}/h265.mp4");
    assert_eq!(export(p, &f, "h265", 64, 36, 10), 0);
    let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0"]);
    assert!(v.starts_with("hevc"), "got: {v}");

    // VP9. Note: exported into an MP4 container (not WebM) so the AAC audio
    // track is legal — the WebM muxer only accepts Opus/Vorbis audio and would
    // reject the timeline's AAC mix (matches verify_export_matrix.sh mp4_vp9 gate).
    let f = format!("{OUT_DIR}/vp9.mp4");
    assert_eq!(export(p, &f, "vp9", 64, 36, 10), 0);
    let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0"]);
    assert!(v.starts_with("vp9"), "got: {v}");

    unsafe { ghita_engine_destroy(p) };
    println!("export matrix h264/h265/vp9: PASS (ffprobe-verified)");
}

#[test]
fn export_matrix_prores_mp3_gif() {
    if !std::path::Path::new(MEDIA).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    std::fs::create_dir_all(OUT_DIR).unwrap();
    let p = ctx_new();
    setup_timeline(p, MEDIA);

    // ProRes (4:2:2 10-bit) into .mov — the kProRes preset.
    let f = format!("{OUT_DIR}/prores.mov");
    assert_eq!(export(p, &f, "prores", 64, 36, 10), 0);
    let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name,pix_fmt", "-of", "csv=p=0"]);
    assert!(v.starts_with("prores"), "got: {v}");
    assert!(v.contains("yuv422p10le"), "prores must be 4:2:2 10-bit: {v}");

    // T5.P3 (beta2): ProRes 4444 round-trip — prores_ks must derive profile 4
    // (4444, 10-bit, alpha-capable) from yuv444p10le. Assert the PROFILE, not
    // the decoded pix_fmt: FFmpeg 8's prores decoder reports yuv444p12le for
    // the 4444 family (10-bit data carried in a 12-bit container).
    let f = format!("{OUT_DIR}/prores4444.mov");
    assert_eq!(export(p, &f, "prores4444", 64, 36, 10), 0);
    let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name,profile,pix_fmt", "-of", "csv=p=0"]);
    assert!(v.starts_with("prores"), "got: {v}");
    assert!(v.contains("4444") && !v.contains("XQ"), "prores4444 must be profile 4444 (not XQ): {v}");

    // MP3 (audio-only, 0×0×0 allowed by the ABI).
    let f = format!("{OUT_DIR}/audio.mp3");
    assert_eq!(export(p, &f, "mp3", 0, 0, 0), 0);
    let a = probe(&f, &["-show_entries", "stream=codec_name", "-of", "csv=p=0"]);
    assert!(a.starts_with("mp3"), "got: {a}");

    // GIF (image container, no audio). beta1 implemented PAL8 quantization
    // (median-cut palette + Floyd–Steinberg dithering) — export must produce
    // a real, ffprobe-verifiable file now.
    let f = format!("{OUT_DIR}/anim.gif");
    assert_eq!(export(p, &f, "gif", 64, 36, 10), 0);
    assert!(unsafe { ghita_engine_get_export_file_size(p) } > 0);
    let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0"]);
    assert!(v.starts_with("gif"), "got: {v}");

    unsafe { ghita_engine_destroy(p) };
    println!("export matrix prores/mp3/gif: PASS (ffprobe-verified)");
}

#[test]
fn export_multichannel_5_1_and_7_1() {
    if !std::path::Path::new(MEDIA).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    std::fs::create_dir_all(OUT_DIR).unwrap();
    let e = ghita_engine::engine::GhitaEngine::new();
    assert!(e.initialize());
    e.load_media(MEDIA);
    use ghita_engine::model::NativeClipKind;
    e.upsert_clip(1, MEDIA, 0, 2000, 0, 0, NativeClipKind::Video, 1.0, 1.0, 1.0);

    // 5.1
    e.set_export_channel_layout("5.1");
    let f = format!("{OUT_DIR}/51.mp4");
    assert!(e.start_export_ex(&f, 64, 36, 10, "h264", 5_000_000, true));
    while e.is_exporting() {
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    assert!(e.get_export_file_size() > 0);
    let a = probe(&f, &["-select_streams", "a:0", "-show_entries", "stream=channels", "-of", "csv=p=0"]);
    // ffprobe reports channels=6. The layout *name* is unavailable for AAC in
    // MP4 (reports "unknown" even for valid 5.1), so assert the channel count.
    assert!(a.starts_with("6"), "5.1 export must have 6 channels: {a}");

    // 7.1
    e.set_export_channel_layout("7.1");
    let f = format!("{OUT_DIR}/71.mp4");
    assert!(e.start_export_ex(&f, 64, 36, 10, "h264", 5_000_000, true));
    while e.is_exporting() {
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    assert!(e.get_export_file_size() > 0);
    let a = probe(&f, &["-select_streams", "a:0", "-show_entries", "stream=channels,channel_layout", "-of", "csv=p=0"]);
    assert!(a.starts_with("8"), "7.1 export must have 8 channels: {a}");

    // Back to stereo for the rest.
    e.set_export_channel_layout("stereo");
    println!("multichannel 5.1/7.1: PASS (ffprobe channels 6/8)");
}

#[test]
fn export_cancel_joins_cleanly() {
    if !std::path::Path::new(MEDIA).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    let p = ctx_new();
    setup_timeline(p, MEDIA);
    let f = format!("{OUT_DIR}/cancel.mp4");
    let out = CString::new(f).unwrap();
    let codec = CString::new("h264").unwrap();
    assert_eq!(unsafe { ghita_engine_start_export_ex(p, out.as_ptr(), 128, 72, 30, codec.as_ptr(), 5_000_000, true) }, 0);
    unsafe { ghita_engine_cancel_export(p) };
    assert!(!unsafe { ghita_engine_is_exporting(p) }, "cancel must join the thread");
    unsafe { ghita_engine_destroy(p) };
}

#[test]
fn gif_export_large_sizes_are_wellformed() {
    // T2.P2 (v1.5.5-beta2): the GIF pipeline (PAL8 median-cut palette +
    // Floyd–Steinberg dithering) was only pinned at 64×36; this pins it at
    // real editing sizes — the 640×480 probe from beta1 plus a 1080p pass.
    if !std::path::Path::new(MEDIA).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    std::fs::create_dir_all(OUT_DIR).unwrap();
    let p = ctx_new();
    setup_timeline(p, MEDIA);
    assert!(unsafe { ghita_engine_has_ffmpeg(p) }, "ffmpeg build expected");
    for (w, h, name) in [(640i32, 480i32, "gif_640"), (1920, 1080, "gif_1080")] {
        let f = format!("{OUT_DIR}/{name}.gif");
        assert_eq!(export(p, &f, "gif", w, h, 10), 0, "{name}: start_export");
        assert!(unsafe { ghita_engine_get_export_file_size(p) } > 0, "{name}: empty output");
        let v = probe(&f, &["-select_streams", "v:0", "-show_entries", "stream=codec_name,width,height", "-of", "csv=p=0"]);
        assert!(v.starts_with("gif"), "{name}: codec: {v}");
        assert!(v.contains(&format!("{w},{h}")), "{name}: dimensions: {v}");
        let n = probe(&f, &["-select_streams", "v:0", "-count_frames", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0"]);
        let frames: u32 = n.parse().unwrap_or(0);
        assert!(frames > 0, "{name}: no decodable frames");
        println!("{name}: {frames} frames, size {} bytes", unsafe { ghita_engine_get_export_file_size(p) });
    }
    unsafe { ghita_engine_destroy(p) };
    println!("gif large-size wellformed: PASS (ffprobe-verified)");
}