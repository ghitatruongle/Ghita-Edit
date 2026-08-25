# Changelog — Ghita Edit

## v1.5.0 (2026-08-23 — bản final sau T1–T6 ổn định hóa)

> **Công bố trung thực so với bản beta 2026-08-22:** GIF export và GEGL graph
> pipeline đã bị XÓA (GIF: encoder pal8 limitation; graph: dead code chưa
> từng wire); ProRes giữ ở engine nhưng không có preset UI. GPU wgpu chỉ
> active trong build có feature `gpu` (mặc định tắt để đảm bảo parity);
> telemetry `ghita_engine_gpu_stats` luôn available. f32 pipeline bị xóa
> (drift + zero caller). Chi tiết đầy đủ: `docs/plan_v1.5.0_final.md`.

### T6 — Chất lượng & tài liệu (bản này)
- Undo consistency: blend/mask/pitch/font/keyframes/sticker qua command
  history (ClipStateCommand); multi-delete = 1 lệnh undo (CompositeCommand);
  text edit coalesce theo phiên focus; transition dropdown đủ 9 loại thật
- SQLite dual-backend round-trip test (engine-gated, chạy trên CI Windows)
- rust_engine_abi.md bổ sung symbol T2/T5; CHANGELOG khớp thực tế

## v1.5.0-beta (2026-08-22)

### Track 1 — Rust Core Engine
- Drop-in Rust replacement for C++ native engine (native_engine_rust/)
- 65 ghita_engine_* C ABI symbols, byte-identical to C++ DLL
- A/B parity vs C++: 44/44 frames max_diff=0, JSON byte-identical
- Rayon parallel filters: 5.27x speedup (12 threads), output byte-equal
- wgpu DX12 GPU compositor (Grayscale/Sepia/Invert within 1/255 vs CPU)
- GEGL-like lazy graph pipeline with dirty propagation

### Track 2 — Rust Media (FFmpeg/Export/Audio I/O)
- FFmpeg decode/encode via ffmpeg-sys-next 8.1 (MinGW)
- Export matrix: H.264, H.265, VP9, ProRes (yuv422p10le), MP3, GIF
- Multichannel audio export: 5.1 (6ch) and 7.1 (8ch) AAC
- cpal audio preview replacing waveOut (low-latency, device selection)
- WAV direct reader (RIFF parse, O(1) memory)

### Track 3 — Video Features (14 features)
- Blend modes: Normal/Multiply/Screen/Overlay/Add
- Geometric masks: rect/ellipse/diamond/star/heart/cinematic bars + feather/stroke
- Canvas background: solid/gradient/blur
- Bookmarks on ruler (id/timeMs/color/note)
- Keyframe copy/paste between clips
- Effects as independent timeline elements (adjustment layers)
- Transcript import (SRT/VTT to text clips)
- Font picker (34 families via GDI)
- Maintain-pitch speed change (rubato SincFixedIn)
- Keyframe graph editor (bezier/step/linear)
- Preview zoom and pan, Guides with snap, Math-input scrub, Action search (Ctrl+P)

### Track 4 — Audio Features (17 features)
- 10 DSP effects: Compressor, Limiter, NoiseGate, NoiseReduction, BassTreble, Distortion, Phaser, Reverb, WahWah, ShelfFilter
- Spectrogram view + spectral editing (frequency-domain gain)
- Tempo detection (60-180 BPM autocorrelation) + beat grid
- RMS timeline visualization
- Loop region playback + clip pitch shift
- Recording via cpal input to WAV PCM16
- Labels export (SRT/VTT)
- DAW Studio Panel UI: effect chain, spectrogram canvas, spectral brush, tempo display, recording controls, loop overlay, gain reduction meter

### Track 5 — Data and Workflow (13 optimizations)
- SQLite project format + media library database (tags, ratings, metadata)
- Dual-backend save/load (JSON backward compat + SQLite indexed)
- Undo expansion 100 to 500 with snapshot compaction
- Auto-recovery file for crash protection
- DAM Light Table panel (search, ratings, tags)
- XMP sidecar read/write + EXIF reader (JPEG/TIFF)
- Headless CLI (scripts/ghita_cli.dart): export/info/thumbnail/batch
- Processing cache with dirty propagation (LRU, 200 entries)
- 32-bit float internal pipeline (feature-gated, parity within 1/255 verified)

### Track 6 — Photo + Integration (14 features)
- Pixel-level selection tools: rect/ellipse marquee, lasso polygon fill, magic wand flood fill
- Mask operations: add/subtract/intersect/invert/feather
- Clone stamp with circular falloff + spot healing
- Cubic bezier path tool + rasterization
- Color management: sRGB/linear transfer functions, Reinhard HDR tone mapping
- Film simulation presets: Portra, Velvia, Cinematic
- Brush engines: pixel brush with radial falloff, smudge blending, stroke stabilizer
- AI tools: NLM denoise, bicubic upscale, color-range segmentation
- Resource dedup via SHA-256 hashing
- Version bump to 1.5.0 across version.dart, pubspec.yaml, Cargo.toml
- Rust CI job added to GitHub Actions

### Infrastructure
- Flutter SDK 3.44.9 stable
- Rust crate ghita_engine v1.5.0 (cdylib + lib)
- Feature flags: ffmpeg, parallel, gpu, sqlite, f32_pipeline
- All gates: cargo test 55/55 PASS, flutter analyze 0 errors, flutter test 143/143 PASS
