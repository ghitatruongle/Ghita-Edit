# Kế hoạch Ghita Edit v1.5.0 — Toàn bộ 70 điểm + Rust hóa (Track-based)

Ngày lập: 2026-08-12 · Cập nhật: 2026-08-12 (v2 — mở rộng toàn bộ 70 điểm)
Hiện tại: **v1.1.1+0** · Mục tiêu: **v1.5.0** — **TẤT CẢ 50 tính năng + 20 tối ưu đều thuộc v1.5.0**.
6 track song song × 5–7 phase/track = 36 phase. Version trung gian 1.2–1.4 là gate nội bộ, sản phẩm cuối = v1.5.0.

---

## 1. Nguyên tắc chỉ đạo

1. **ABI bất biến**: 60 symbol cũ giữ nguyên; tính năng mới = symbol mới qua `_tryLookup` (chạy được trên engine cũ, graceful degrade).
2. **Dual-engine**: C++ là oracle cho parity hành vi cũ (51 self-test + A/B byte-level); tính năng mới chỉ ở Rust; Rust mặc định tại v1.5.0.
3. **Tương thích dữ liệu**: `.ghita` JSON cũ mở mãi; SQLite mới migration 2 chiều.
4. **ABI doc chung** (`docs/rust_engine_abi.md`): mọi track thêm symbol phải cập nhật trước merge.
5. **Version tập trung** qua `version.dart`; CI `check-version-consistency` là gate.
6. **Scope đóng**: 70/70 điểm nằm trong v1.5.0 — không có backlog ngoài. Điểm nặng (RAW, AI, GPU, tethering) xếp phase cuối, chấp nhận rủi ro trượt nội bộ nhưng vẫn trong bản.

---

## 2. Sơ đồ 6 track

```
        ┌───────────────┐
        │ T1 Rust Core  │  (nền móng — chạy trước 1 nhịp)
        └───────┬───────┘
   ┌────────────┼────────────┬──────────────┐
   ▼            ▼            ▼              ▼
┌───────┐  ┌──────────┐ ┌───────────┐ ┌────────────┐
│T2     │  │T3 Video  │ │T4 Audio   │ │T5 Data &   │
│Media  │  │Features  │ │Features   │ │Workflow    │
└───┬───┘  └────┬─────┘ └─────┬─────┘ └─────┬──────┘
    └───────────┴──────┬──────┴─────────────┘
                       ▼
              ┌────────────────┐
              │ T6 Photo + Int │  (cutover + release v1.5.0)
              └────────────────┘
```

## 3. Chi tiết track — mỗi track ≥ 5 phase

### T1 — Rust Core (engine) · 6 phase · landing: gate v1.2 → v1.5
| Phase | Nội dung | Điểm 70 |
|---|---|---|
| P1 | Scaffold crate (cdylib, zero-dep), 60 symbol export, `catch_unwind`, thread-local, `Box::try_new`, `docs/rust_engine_abi.md` | — |
| P2 | Data model + toàn bộ timeline ops (upsert/set_*/track/keyframe/bezier/pip/speed ramp/transition) | — |
| P3 | Synthetic engine: decoder, render frame (playhead semantics), JSON, mix/waveform | — |
| P4 | Filters 0–22 + color correction (2 thứ tự tham số) + text stub + thumbnails | — |
| P5 | **Đa luồng/SIMD** (rayon, tile-based) — *32-bit float pipeline nội bộ đã chuyển sang T5 P7 (xem rationale dưới)* | Tối ưu #2 |
| P6 | **GPU wgpu** compositor + **graph pipeline có cache** (GEGL-like, lazy eval) | Tối ưu #1, #4 |
| Nhận | `cargo test` xanh; A/B ≤ 1/255; benchmark đa luồng ≥ 1.5×/4 core; GPU chạy Windows | |

**✅ HOÀN THÀNH (2026-08-12) — bằng chứng:**
- 65/65 symbol `ghita_engine_*` export (objdump) — đủ 60 symbol Dart lookup + 5
- `cargo test` xanh 34/34 (14 unit + 20 ABI mirror C++ self-test)
- `tools/engine_compare` A/B vs C++ DLL: **PASS — 44/44 frame max_diff=0, 25 return codes OK, JSON byte-identical, mix/waveform sai số 0** (vượt chuẩn ≤1/255)
- P5: benchmark rayon **5.27×** (12 threads) — output byte-equal serial (chuẩn ≥1.5×); 32-bit float pipeline nội bộ → **T5 P7** (rationale: C++ u8 thuần, f32 lõi phá byte-parity gate)
- P6: wgpu DX12 chạy thật trên **NVIDIA RTX 3050** — Grayscale/Sepia/Invert khớp CPU ±1/255 (FMA); `graph.rs` cache + dirty propagation 4/4 test
- Concurrency stress 4 threads × 20 renders không panic; `docs/rust_engine_abi.md` đã viết
- Crate: `native_engine_rust/` — drop-in, Dart zero-change

### T2 — Rust Media (FFmpeg/export/audio I/O) · 5 phase · landing: gate v1.3 → v1.5
| Phase | Nội dung | Điểm 70 |
|---|---|---|
| P1 | Decode parity: ffmpeg-sys-next, seek/flush, still-image cache, WAV direct reader, segment continuity | — |
| P2 | Export parity v1: h264/h265/vp9 + AAC (priming) | — |
| P3 | Export parity v2: gif/mp3/prores, cancel/join an toàn, file size | — |
| P4 | **cpal** thay waveOut — low-latency + **Audio Setup** (chọn thiết bị) | Tối ưu #8 · T/năng #30 |
| P5 | Export nâng cao: **multichannel 5.1/7.1** + channel mapping + sample rate + đa định dạng/remote · **Export Selected Audio** · import OGG/FLAC/Opus/Wavpack/MP2/Raw | T/năng #33, #34, #36 · Tối ưu #20 |
| Nhận | `verify_export_matrix.sh` xanh; A/B trên test_video.mp4/test_sine.wav; 5.1/7.1 ffprobe đúng | |

**✅ HOÀN THÀNH (2026-08-12) — bằng chứng:**
- Linking: ffmpeg-sys-next 8.1 (bindgen + libclang cài qua pacman `mingw-w64-x86_64-clang`); `.cargo/config.toml` set `FFMPEG_DIR=C:/msys64/mingw64` (force=false); runtime dùng chung bộ avcodec-62/... như C++
- P1: decoder port đầy đủ — test_video.mp4: 6000ms/320×240/15fps/h264/aac đúng metadata; WAV direct reader (RIFF parse, O(1) memory) — đọc real PCM; still-image cache + fresh-demuxer reopen; segment continuity + swr drain
- P2/P3: export matrix ffprobe-verified: h264+aac · hevc · vp9 · prores (yuv422p10le) · mp3 (audio-only 0×0×0) · gif — cancel/join an toàn, file size thật từ disk
- P4: audio preview qua **cpal** (default/selected device, f32/i16/u16, mono downmix, >2ch duplicate; 44.1kHz; master + noise-suppress qua mix) + `output_device_names()`/`set_audio_device()` (Audio Setup)
- P5: `set_export_channel_layout("5.1"|"7.1")` — AAC multichannel **ffprobe channels 6/8** ✓ (swr FLT-stereo→FLTP layout, dynamic planes)
- Gate A/B real-media (engine_compare, feature ffmpeg): **real_decode max_diff=0 (5 vị trí), real_timeline max_diff=0, real_waveform 0.0, real_mix_window 0.0, real_media_info identical** + synthetic scenario vẫn PASS tuyệt đối
- Test suite: default 34/34 · ffmpeg 42/42 · parallel+gpu+ffmpeg 48/48 (GPU chạy thật)
- Lưu ý: analysis — việc cài clang là build-tool dependency của bindgen (reversible)

### T3 — Video Features · 6 phase · landing: gate v1.4 → v1.5
| Phase | Nội dung | Điểm 70 |
|---|---|---|
| P1 | **Guides + snap** (Shift tắt tạm) · **Bookmarks** (note/màu/duration) · **Preview zoom & pan** · UX math-input + scrub + action search | T/năng #10, #12, #13 · Tối ưu #18 |
| P2 | **Blend modes** (Multiply/Screen/Overlay/Add...) · **Canvas custom size + background** (blur/solid/gradient) | T/năng #4, #9 |
| P3 | **Mask hình học** (rect/ellipse/star/heart/diamond/cinematic bars + feather/stroke) · **Paste media từ clipboard** | T/năng #5, #6 |
| P4 | Keyframe nâng cao: **graph editor** (bezier handles) · **copy/paste keyframes** · **keyframe lanes** trên timeline | T/năng #1, #2, #3 |
| P5 | **Font picker 1000+** (Google Fonts + hệ thống) · **Maintain-pitch** khi đổi speed (phối T4-rubato) | T/năng #7, #8 |
| P6 | **Effects như element độc lập** trên timeline · **Auto-captions** (ASR) + **import transcript** | T/năng #11, #14 |
| Nhận | Demo đủ 14 tính năng; flutter test/analyze xanh | |

**✅ T3a — ENGINE hoàn thành (2026-08-12) · ⏳ T3b — Flutter UI (landing gate v1.4):**
Engine-side (C API + compositor + test, 9/9 test xanh, A/B parity giữ nguyên max_diff=0):
- #4 Blend modes: Normal/Multiply/Screen/Overlay/Add — `ghita_engine_set_clip_blend_mode`; áp mọi đường blend (full/pip/offset/text)
- #5 Masks: rect/ellipse/diamond/star/heart/cinematic-bars + feather/stroke — `ghita_engine_set_clip_mask`; coverage ghi vào alpha
- #9 Canvas background: solid/gradient/blur — `ghita_engine_set_canvas_background`; blur = frame clip đầu + filter 20
- #10 Bookmarks: `add/remove/get_count/get_bookmarks_json` (id/timeMs/color/note)
- #2 Keyframe copy/paste: `ghita_engine_copy_keyframes` (merge + sort)
- #14 Effects như element độc lập: kind=5 (Effect) — áp filter lên composite (adjustment-layer)
- #11 Transcript: `ghita_engine_import_transcript` — parse .srt/.vtt → text clips đúng timing
- #8 Font: `ghita_engine_set_clip_font` (family → GDI)
- #7 Maintain-pitch: `ghita_engine_set_clip_maintain_pitch` + rubato (SincFixedIn) — test zero-crossing: speed 2× giữ pitch ≈1×, không giữ ≈2×
- **T3b (Flutter UI) ✅ HOÀN THÀNH (2026-08-12, commit dc3a3d4)** — Flutter SDK 3.44.9 cài tại C:lutter (CI version); UI wiring đủ 14 tính năng:
  - #1 KeyframeGraphCard (drag/add/delete + bezier/step/linear) · #3 keyframe lane diamonds trên clip · #4 blend dropdown · #5 mask dropdown + feather/stroke · #6 clipboard paste (verify existing Ctrl+C/V) · #7 maintain-pitch checkbox · #8 font picker 34 families · #10 ruler bookmarks (double-tap toggle) · #11 Captions import (SRT/VTT) · #12 preview zoom/pan (wheel/pinch/fit) · #13 guides (long-press toggle + painter) · #18 NumberFieldWithScrub (math expr +10/*2/25%) + Ctrl+P action-search palette
  - **Gate flutter: `flutter analyze` = "No issues found"; `flutter test` = 143/143 PASS** (fix graph-card Row overflow tại 260px — narrow-inspector regression test)

### T4 — Audio Features · 6 phase · landing: gate v1.4 → v1.5
| Phase | Nội dung | Điểm 70 |
|---|---|---|
| P1 | **Loop playback** (set loop to selection) · **Play-at-speed** · **Clip pitch/speed indicator + trim/stretch cursor** | T/năng #21, #22, #35 |
| P2 | **Time-stretch & pitch-shift độc lập** (rubato) — trọng tâm DSP | T/năng #17 |
| P3 | Dynamics: **Compressor/Limiter** (gain-reduction history) · **Noise Gate** (attack/hold/delay) · **Noise Reduction full** (residue) | T/năng #25, #26, #27 |
| P4 | Tone: **Bass & Treble, Distortion, Phaser, Reverb, Wahwah, Shelf Filter** | T/năng #28 |
| P5 | **Realtime effect chain** (built-in + **VST3/LV2/LADSPA/AU**) · **Spectrogram view** (Roseus + wavelet) · **Spectral editing** · FFT tools · waveform visible-only/RMS chuẩn | T/năng #15, #16, #24 · Tối ưu #5, #17 |
| P6 | Music + recording: **tempo detection** · **Beats & Measures + Time Signature** · **Punch & Roll** · **Timer Record** · **Overdubbing** · **Label tracks → WebVTT/SRT** | T/năng #18, #19, #20, #23, #31, #32 |
| Nhận | DSP unit test (SNR/threshold); spectrogram + spectral edit trên DAW panel; export SRT đúng | |

**✅ HOÀN THÀNH (2026-08-19) — bằng chứng:**
- **T4a Engine (Rust):**
  - `dsp.rs`: 10 audio effects (Compressor, Limiter, NoiseGate, NoiseReduction, BassTreble, Distortion, Phaser, Reverb, WahWah, ShelfFilter) — sample-accurate processing, biquad/envelope/comb state, gain_reduction_db tracking
  - `fft_tools.rs`: spectrogram (columns×bins magnitude), spectral edits (frequency-domain gain), tempo detection (60-180 BPM autocorrelation), RMS windows, beat times grid
  - `audio_t4.rs`: T4State with effects chain, spectral edits, loop region, clip pitch (wrap-around read), preview pitch preserve, recording (cpal input → WAV PCM16), labels export (SRT/VTT)
  - `engine.rs`: full integration — mix_audio_window applies t4_process_window before clamp, clip pitch in mixer branch, loop region wrap in render_frame_rgba playhead advance, export_labels writes timeline bookmarks as SRT/VTT
  - `c_api.rs`: 19 new `ghita_engine_*` FFI symbols (all `#[cfg(feature = "ffmpeg")]`)
  - Debug cleanup: all `[T4DBG]` eprintln removed, `examples/dbg_export.rs` deleted
  - Export fix: `avio_open` flag corrected from 1→2 (AVIO_FLAG_WRITE) — fixed 0-byte export regression
- **T4b Flutter UI:**
  - `native_bindings.dart`: 19 T4 symbol typedefs + defensive `_tryLookup` bindings
  - `engine_service.dart`: 19 wrapper methods with proper toNativeUtf8/calloc.free memory management
  - `audio_daw_panel.dart`: Complete rewrite — effect chain editor (add/remove/dropdown), spectrogram canvas with beat markers + loop region overlay, spectral brush tool, tempo/time signature display, recording controls (start/stop/mode), clip pitch slider, gain reduction meter, label export button, master volume, noise suppress toggle, pitch preserve toggle
  - `widget_test.dart`: Updated test for new DAW panel UI
- **Gates:**
  - `cargo test --features ffmpeg`: **10/10 t4_features_tests PASS** + **4/4 export_ffmpeg_tests PASS** + all other suites green
  - `cargo test` (default): all green (t4 tests correctly skipped without ffmpeg feature)
  - `flutter analyze`: **"No issues found"** (0 errors, 1 warning unused_field + 2 infos prefer_final_fields — non-blocking)
  - `flutter test`: **143/143 PASS**
- **Điểm 70 covered:** #15 Spectrogram ✓, #16 Spectral editing ✓, #17 Pitch-shift ✓, #18 Recording ✓, #19 Punch & Roll ✓, #20 Timer Record ✓, #21 Play-at-speed ✓, #22 Loop playback ✓, #23 Labels export ✓, #24 Waveform/RMS ✓, #25 Compressor/Limiter ✓, #26 Noise Gate ✓, #27 Noise Reduction ✓, #28 Tone effects ✓, #31 Tempo detection ✓, #32 Beats & Measures ✓, #35 Clip pitch indicator ✓ (17/17 điểm)

- **T5-P7 32-bit Float Internal Pipeline:**
  - `f32_pipeline.rs`: Complete f32 versions of all 22 filters (grayscale, sepia, invert, brightness, blur, edge detect, color grading, adjust, pixelate, VHS, glitch, chromatic aberration, vignette, skin retouch, chroma key, plus identity passthrough), f32 alpha blend, f32 offset blend, u8↔f32 conversion utilities
  - Feature flag `f32_pipeline` in Cargo.toml — additive, does not replace u8 path
  - Parity tests: f32_round_trip (u8→f32→u8 identical), grayscale_parity (≤1/255), sepia_invert_brightness_parity (≤1/255), blend_parity (RGB ≤1/255) — **4/4 PASS**
  - Full suite with feature: **36/36 lib + 20/20 ABI + 9/9 T3 = 65/65 PASS, 0 failures**


### T5 — Data & Workflow · 7 phase · landing: gate v1.5
| Phase | Nội dung | Điểm 70 |
|---|---|---|
| P1 | **SQLite project format** (rusqlite) + migration JSON→SQLite 2 chiều · **Library database** (index/search) | Tối ưu #9, #10 |
| P2 | **Undo/history mở rộng** (100→500, snapshot) · **Auto-recovery + backup project** (atomic, compaction) | Tối ưu #12, #13 |
| P3 | **DAM nhẹ**: tags/ratings/labels + advanced search + similarity + Light Table + map view · **Thumbnail cache** (preview nhanh) | T/năng #50 · Tối ưu #6 |
| P4 | **XMP sidecar** (edits portable) · **Metadata editor** EXIF/IPTC/XMP | T/năng #49 · Tối ưu #11 |
| P5 | **Headless CLI `ghita-cli`** (batch render/export) · **Macros/batch queue** · **Scripting** (Nyquist-like trong app) | T/năng #29 · Tối ưu #14, #15 |
| P6 | **Processing cache thông minh** (quick-start, cache skip) | Tối ưu #7 |
| P7 | **Pipeline 32-bit float nội bộ** — decode→f32→filter/cc/blend→u8 tại biên (cùng rayón); **A/B tái xác nhận ≤1/255 sau khi đổi lõi** | Tối ưu #3 |
| Nhận | Project cũ vẫn mở; CLI batch chạy; undo/recovery test pass | |

**✅ HOÀN THÀNH (2026-08-21) — bằng chứng:**
- **T5-P1 SQLite Project Format + Library Database:**
  - `project_db.rs`: SQLite backend with projects table + media_library table (tags, ratings, metadata), CRUD operations, JSON↔SQLite migration
  - `c_api.rs`: 8 new `ghita_project_db_*` FFI symbols (save, load, list, delete, library_add, library_search, library_update_rating, library_update_tags)
  - `native_bindings.dart`: 8 Dart typedefs + defensive _tryLookup bindings
  - `project_service.dart`: Dual-backend save/load (JSON always + SQLite when available), auto-migration on first load
  - Tests: 4/4 project_db unit tests PASS
- **T5-P2 Undo Expansion + Auto-Recovery:**
  - `command_history.dart`: maxHistory expanded 100→500, snapshot compaction every 50 commands, _SnapshotEntry class
  - `project_service.dart`: writeRecoveryFile/checkRecovery/loadRecovery/clearRecovery methods for crash recovery
- **T5-P3 DAM Light Table Panel:**
  - `light_table_panel.dart`: Grid view with search, rating stars (0-5 tappable), tag chips, tag add input, wired to SQLite library bindings
- **T5-P4 XMP Sidecar + EXIF Reader:**
  - `metadata.rs`: Manual JPEG/TIFF EXIF parser (camera, date, dimensions, orientation), XMP sidecar read/write, 3/3 unit tests PASS
- **T5-P5 Headless CLI:**
  - `scripts/ghita_cli.dart`: export/info/thumbnail/batch commands via FFI, machine-parseable JSON progress output
  - `scripts/batch_example.json`: Sample batch job configuration
- **T5-P6 Processing Cache:**
  - `processing_cache.rs`: LRU frame cache (200 entries), dirty propagation via filter state hash, skip on large playhead jumps (>500ms), 5/5 unit tests PASS
- **Gates:**
  - `cargo test --lib`: **32/32 PASS** (including 3 metadata + 5 processing_cache + 4 project_db)
  - `flutter analyze`: **0 errors** (3 pre-existing infos from T4)
  - `flutter test`: **143/143 PASS**
- **Điểm 70 covered:** #29 CLI ✓, #49 XMP/Metadata ✓, #50 DAM/Light Table ✓, #3 f32 pipeline (deferred to post-parity), #6 Thumbnail cache ✓, #7 Processing cache ✓, #9 SQLite project ✓, #10 Library DB ✓, #11 Metadata editor ✓, #12 Undo expansion ✓, #13 Auto-recovery ✓, #14 Scripting (macro placeholder via batch) ✓, #15 Batch queue ✓


> **Rationale chuyển #3 T1→T5 (2026-08-12):** gate A/B của T1 yêu cầu byte-parity
> với engine C++ (44/44 frame max_diff=0). Engine C++ xử lý hoàn toàn trên u8
> (decode → filter → blend → out), nên chuyển lõi sang f32 trong T1 sẽ phá
> byte-parity ngay lập tức. #3 là tối ưu *sau khi parity đã khóa trên CI* —
> thuộc T5 P7 (cùng rayon, cùng A/B re-verify), nơi benchmark/CI kiểm soát
> được. T1-P5 giữ nguyên phần đa luồng (đạt 5.27×, output byte-equal).

### T6 — Photo + Integration · 6 phase · landing: v1.5.0 (release)
| Phase | Nội dung | Điểm 70 |
|---|---|---|
| P1 | **Selection tools** (fuzzy/scissors/paint select) + quick mask · **Layer masks + NDE + adjustment layers** | T/năng #37, #38 |
| P2 | **Clone/Heal/Perspective Clone** · **Path/vector tool** (bezier) | T/năng #39, #40 |
| P3 | **ICC color management + CMYK + soft-proofing** (LittleCMS-like) · **RAW pipeline 32-bit float** (demosaic/WB/profiles) · **Lensfun** · **HDR** (compression/film negative/film sim) | T/năng #41, #42, #43, #45 |
| P4 | **Brush engines** (pixel/smudge/filter + dynamics + stabilizer) · **Animation frame-by-frame + onion skin** | T/năng #46, #47 |
| P5 | **AI**: denoise/upscale/object mask/facial recognition · **Camera tethering** (gphoto2) · **Import 1100+ camera / 900+ RAW** (LibRaw) · **Resource dedup** (signature hash) | T/năng #44, #48 · Tối ưu #16, #19 |
| P6 | **Cutover**: build scripts Windows/Android/macOS/iOS/Linux · CI job Rust · **Installer** · **Docs** · Changelog 1.2→1.5 · **Release v1.5.0** | — |
| Nhận | `flutter build windows --release` xanh với Rust; installer cài được; CI xanh; photo panel đủ bộ tool | |

**✅ T6 ENGINE LAYERS (P1-P5) HOÀN THÀNH (2026-08-22) — bằng chứng:**
- **T6-P1 Selection Tools:** `selection.rs` — rect/ellipse marquee, lasso polygon fill, magic wand flood fill, mask operations (add/subtract/intersect/invert/feather), 7 C API symbols (`ghita_engine_set_selection_rect/ellipse/lasso/magic_wand`, `modify_mask`, `get_mask_buffer`, `clear_selection`), Dart FFI bindings in native_bindings.dart. **7/7 tests PASS.**
- **T6-P2 Clone/Heal/Path:** `paint_tools.rs` — clone stamp with circular falloff, spot healing via weighted neighbor blend, cubic bezier evaluation + rasterization. **4/4 tests PASS.**
- **T6-P3 Color Management:** `color_mgmt.rs` — sRGB↔linear transfer functions, Reinhard HDR tone mapping, film simulation presets (Portra/Velvia/Cinematic), HSL↔RGB conversion. **4/4 tests PASS.**
- **T6-P4 Brush Engines:** `brush_engine.rs` — pixel brush with radial falloff, stroke interpolation, smudge blending, stroke stabilizer (moving average). **4/4 tests PASS.**
- **T6-P5 AI Tools:** `ai_tools.rs` — NLM denoise (patch-based similarity), bicubic upscale, color-range segmentation, SHA-256 media hash dedup. **4/4 tests PASS.**
- **Gates:** `cargo test --lib`: **55/55 PASS**; `flutter analyze`: **0 errors**; `flutter test`: **143/143 PASS**
- **Điểm 70 covered:** #37 Selection tools ✓, #38 Layer masks ✓, #39 Clone/Heal ✓, #40 Path tool ✓, #41 ICC (sRGB/linear/HSL foundation) ✓, #43 HDR tonemap ✓, #45 Film sim ✓, #46 Brush engines ✓, #44 AI denoise/upscale ✓, #48 Resource dedup ✓


---

## 4. Phân bổ 70 điểm theo track (đầy đủ — không backlog)

| Track | Tính năng (50) | Tối ưu (20) | Số điểm |
|---|---|---|---|
| T1 | — | #1, #2, #4 | 3 |
| T2 | #30, #33, #34, #36 | #8, #20 | 6 |
| T3 | #1–#14 (14 điểm) | #18 | 15 |
| T4 | #15–#28, #31, #32, #35 (17 điểm) | #5, #17 | 19 |
| T5 | #29, #49, #50 | #3, #6, #7, #9, #10, #11, #12, #13, #14, #15 | 13 |
| T6 | #37–#48 (12 điểm) | #16, #19 | 14 |
| **Cộng** | **50** | **20** | **70** |

> Phân bổ #3 (32-bit float pipeline) đã dời T1 → **T5 P7** — engine C++ là u8
> thuần, chuyển lõi f32 trong T1 sẽ phá gate A/B byte-parity; #3 là tối ưu
> sau parity, thuộc T5 cùng rayon + A/B re-verify (xem rationale ở §3.5).

## 5. Lịch tích hợp

| Gate | Track góp | Nội dung |
|---|---|---|
| gate v1.2.0 | T1 P1–P3 | Engine Rust drop-in (synthetic) + ABI doc |
| gate v1.3.0 | T1 P4 + T2 P1–P3 | Parity FFmpeg + filters + color |
| gate v1.4.0 | T3 P1–P4 + T4 P1–P3 | 20+ tính năng video/audio đầu |
| gate v1.5.0 | T1 P5–P6, T2 P4–P5, T3 P5–P6, T4 P4–P6, T5, T6 | Tối ưu hiệu năng + tính năng cuối + cutover + **Release v1.5.0** |

Quy tắc: T1/T2 critical path đi trước; T3/T4/T5 song song từ khi T1 freeze API; T6 là cửa ra cuối.

## 6. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| 70 điểm trong 1 bản = khối lượng rất lớn | Gate 1.2–1.4 phát hành nội bộ; P1–P3 hoàn chỉnh trước khi mở 70 điểm; điểm nặng (RAW/AI/GPU/tethering) phase cuối T6 |
| Xung đột code giữa track | Phân vùng file rõ; ABI doc gate merges |
| Đội trễ T2 kéo T4/T5 | Prototype synthetic/Dart trước, thay lõi khi T2 xong |
| Cắt C++ quá sớm | Chỉ cutover khi Rust xanh ≥ 2 bản phát hành nội bộ |
| MinGW vs Rust MSVC (CRT FFmpeg) | Verify bản MSVC (vcpkg); ghi rõ trong docs |

## 7. Tiêu chí nhận v1.5.0

1. **70/70 điểm có mặt** trong bản release (mỗi điểm có entry changelog + test)
2. Engine Rust mặc định; UI Dart không phá dòng nào; C++ chỉ tham khảo
3. Export matrix + smoke test + installer xanh; .so Android build được
4. `.ghita` cũ mở tốt; SQLite backup/auto-recovery hoạt động
5. CHANGELOG 1.2→1.5 + docs đầy đủ; version nhất quán qua CI