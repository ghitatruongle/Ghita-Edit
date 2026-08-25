//! T2-P4: cpal audio preview lifecycle + Audio Setup (device selection).

#![cfg(feature = "ffmpeg")]

use ghita_engine::engine::GhitaEngine;
use ghita_engine::model::NativeClipKind;

#[test]
fn device_enumeration_and_selection() {
    let e = GhitaEngine::new();
    let names = e.output_device_names();
    if names.is_empty() {
        // Headless CI runners expose no audio endpoints — nothing to assert.
        eprintln!("SKIP: no output devices on this machine");
        return;
    }
    // Selecting the first device must not panic.
    e.set_audio_device(Some(names[0].clone()));
    e.set_audio_device(None);
}

#[test]
fn preview_thread_lifecycle_with_clips() {
    let path = "../test_video.mp4";
    if !std::path::Path::new(path).exists() {
        eprintln!("SKIP: test_video.mp4 missing");
        return;
    }
    let e = GhitaEngine::new();
    assert!(e.initialize());
    e.load_media(path);
    e.upsert_clip(1, path, 0, 2000, 0, 0, NativeClipKind::Video, 1.0, 1.0, 1.0);

    // play() starts the preview thread; pause() joins it.
    e.play();
    std::thread::sleep(std::time::Duration::from_millis(150));
    assert!(e.is_playing());
    e.pause();
    assert!(!e.is_playing());

    // Empty timeline → the preview thread exits immediately without a device.
    let e2 = GhitaEngine::new();
    e2.initialize();
    e2.play();
    std::thread::sleep(std::time::Duration::from_millis(80));
    e2.pause();
}
