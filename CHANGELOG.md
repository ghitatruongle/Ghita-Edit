# Changelog — Ghita Edit

## v1.5.5-demo (2026-09-02 — bản demo beta, CHƯA publish)

> **Phạm vi:** 3 tính năng beta (B1 GPU toggle, B2 ProRes preset, B3
> adjustment graph) + rust hóa nhẹ (T1.P1 rayon default, T1.P2 waveform
> resample). Mọi mục đều có badge "Beta" rõ ràng; GPU mặc định TẮT để giữ
> parity CPU. Chưa commit/push theo yêu cầu — số liệu gates ghi bên dưới là
> kết quả local.

### B1 — GPU compositor toggle (wgpu, runtime switch)
- `ghita_engine_set_gpu_enabled` / `ghita_engine_gpu_enabled` — dispatch GPU
  opt-in, mặc định OFF (CPU là parity default như v1.5.0).
- GPU chỉ xử lý 3 filter đã parity (Grayscale/Sepia/Invert) trên frame
  ≥512×256; filter khác + frame nhỏ + rayon-tile tự fallback CPU.
- UI: toolbar "Beta" → switch bật/tắt + telemetry (adapter, gpu_frames,
  CPU fallbacks) qua `ghita_engine_gpu_stats` (thêm trường `enabled`).

### B2 — ProRes preset (beta)
- Preset "ProRes HQ (Beta)" (MOV • ProRes 10-bit yuv422p10le • 200 Mbps •
  30fps) + tùy chọn ProRes trong custom mode MOV.
- Engine lookup encoder thật (`avcodec_find_encoder_by_name("prores")`) và
  fail loudly khi build thiếu encoder — không còn vụ "H.264 giả ProRes"
  của v1.1.0.

### B3 — Adjustment graph (beta)
- `ghita_engine_graph_add_node` / `ghita_engine_graph_remove_last` /
  `ghita_engine_graph_clear` — chain node Brightness/Contrast/Saturation.
- Node áp SAU color correction trên `render_timeline_frame` — preview và
  export đi CHUNG đường này (không dead code; graph là no-op khi chain
  rỗng → parity giữ nguyên).
- Cache invalidation: `timeline_state_hash` trộn cả chain (đổi node →
  frame pause hết hiệu lực, đúng như CC).
- UI: Beta panel — thêm/sửa/xóa node (LIFO) cho clip đang chọn; đổi giá trị
  → clear + re-add toàn chain (engine mirror).

### T1 — Rust hóa nhẹ
- `parallel` (rayon) giờ nằm trong feature list của MỌI release build
  (CI Dart-test DLL + Windows release DLL); docs/rust_engine_abi.md cập nhật.
- `ghita_engine_resample_waveform` — port `_upsampleWaveform` Dart (loop
  nóng chạy theo zoom level) sang Rust/dsp, byte-identical (4 test so với
  reference cùng thuật toán; DLL cũ không có symbol → fallback Dart).

### Infrastructure & gates (local, 2026-09-02)
- Version 1.5.5-demo: `kVersionSuffix` trong version.dart (CI chỉ đọc phần
  số); pubspec/Cargo.toml/CMake/banner C++ = 1.5.5 đồng bộ.
- **Parity fix (pre-existing từ T2):** Rust engine thiếu
  `av_log_set_level(AV_LOG_ERROR)` mà C++ có (fix "per-frame warning flood"
  v1.0.1) → mp3float spam stderr và release smoke test fail. Đã thêm vào
  `initialize()` (feature-gated ffmpeg). Xác minh pre-existing: build lại
  DLL từ code v1.5.0 gốc (stash) cũng spam y hệt.
- **Review/debug pass (2026-09-04) — 4 lỗi tìm & sửa:**
  1. `VERSION_STRING` Rust hardcode v1.5.0 sau bump (test ABI
     `version_string_format` bắt được) → src + test chuyển sang
     `concat!(env!("CARGO_PKG_VERSION"))`, không bao giờ drift nữa.
  2. BetaPanel desync khi đổi clip (chain của clip A bị push sang clip B) →
     thêm symbol `ghita_engine_graph_get_json` + mirror theo `_mirrorClipId`
     + controller listener + chặn clip text/sticker/audio (không đi qua
     render path của graph).
  3. NaN/inf truyền qua FFI graph node làm khung hình đen âm thầm →
     sanitize tại `add_graph_node`.
  4. Brightness node truncate trong khi contrast/saturation round → thống
     nhất round-half-up.
- Gates (sau review): `flutter analyze` 0 lỗi; `flutter test` **157 pass,
  1 skip**; `cargo test --features ffmpeg,parallel,sqlite` **134/134** (gồm
  5 test graph + 4 test resample); `--features ffmpeg,gpu,sqlite,parallel`
  **135/135**; `--features gpu` **105/105**; `engine_compare` A/B vs C++
  **PASS — full parity** (synthetic + real-media, max_diff=0);
  `run_engine_smoke_test.sh` **PASSED — log clean**.
- Bundle verify: `stage_windows_release.sh` (Rust DLL + FFmpeg closure 93
  DLL) + load `ghita_engine.dll` bằng `LoadLibraryEx(LOAD_WITH_ALTERED_SEARCH_PATH)`
  với PATH **tước msys64** → OK (Demo Mode không xảy ra trên máy sạch).
- **Review/debug pass 2 (2026-09-05) — xóa 2 hạn chế lớn + 1 bug mới:**
  1. **Bug:** GPU toggle KHÔNG invalidate paused-frame cache (timeline hash
     thiếu GPU state) → toggle GPU khi pause phục frame stale. Fix: hash
     fold `gpu_enabled` (feature-gated) + test ABI
     `gpu_toggle_invalidates_paused_frame_cache` chứng minh miss xảy ra.
  2. **Hạn chế removed — graph giờ UNDOABLE:** `setClipGraph` qua
     `ClipStateCommand` (coalesce theo gestureId — 1 lần kéo slider = 1
     entry undo).
  3. **Hạn chế removed — graph giờ PERSIST:** `graphNodes` trong Clip
     toJson/fromJson (optional, file cũ load bình thường); deferred
     fingerprint resync đẩy chain vào engine theo nhóm 'graph'.
  4. **BetaPanel kiến trúc mới:** model là nguồn sự thật duy nhất (hết lớp
     bug desync), switch GPU disable khi không khả dụng, seek-repaint khi
     toggle, gestureId cho slider drag.
- **Review round 3 (2026-09-05, chạy export matrix):**
  1. **Bug của CHÍNH script verify** (không phải engine): check kênh AAC
     hardcode thứ tự cột ffprobe `stream,<n>,<codec>,<type>` nhưng ffprobe bản
     này trả `stream,<codec>,<type>,<n>` → aac_51/71 fail OAN (file export
     đúng). Fix: pattern chấp nhận cả hai thứ tự.
  2. **B2 giờ mới được verify end-to-end:** matrix chưa từng có case ProRes
     → thêm `prores_mov` (ffprobe phải báo codec `prores` thật, không phải
     h264-trong-.mov kiểu v1.1.0). **PASS.**
- Gates (sau round 3): `flutter analyze` 0 lỗi; `flutter test` **161 pass,
  1 skip** (thêm 4 test persistence); `cargo test --features
  ffmpeg,gpu,sqlite,parallel` **136/136** (thêm gpu-hash test);
  `engine_compare` **PASS — full parity**; `run_engine_smoke_test.sh`
  **PASSED — log clean**; `verify_export_matrix.sh` **8 PASS / 1 SKIP (gif,
  đúng limitation pal8 lịch sử) / 0 FAIL**; installer rebuilt + verify máy sạch.
- **Installer naming:** `kVersionSuffix` giờ được `build_release.sh` + CI
  ISCC step đọc từ version.dart và truyền `/DPreReleaseSuffix=` vào
  `ghita_edit_setup.iss` → bản demo đóng gói thành
  **`GhitaEdit-1.5.5-demo-Setup.exe`** (AppVersion trong Control Panel cũng
  hiện `1.5.5-demo`); bản final suffix rỗng → tên giữ nguyên numeric pattern.
- Demo limitation còn lại (beta2): graph chưa có trong SQLite media-library
  search facets (chỉ nằm trong project JSON — đúng thiết kế).

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
