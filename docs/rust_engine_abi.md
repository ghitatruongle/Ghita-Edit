# Ghita Engine Rust — ABI Contract (docs/rust_engine_abi.md)

Track 1 (Rust Core) deliverable · 2026-08-12
Crate: `native_engine_rust/` — drop-in replacement for `native_engine/` (C++20).

> **Rule for every track (T1–T6):** the symbol list & return-code conventions
> documented here are the single source of truth. Any track adding a symbol
> must update this file BEFORE merging.

## 1. Drop-in contract

- The Dart layer (`lib/src/ffi/native_bindings.dart`, `engine_service.dart`)
  is **unchanged** — it locates the library by file name and looks up the
  `ghita_engine_*` symbols:
  - Windows: `ghita_engine.dll` (MSVC) / `libghita_engine.dll` (MinGW/Rust)
  - Android: `libghita_engine.so` (packaged via jniLibs)
  - macOS/Linux: `libghita_engine.dylib` / `libghita_engine.so`
- The Rust crate builds a `cdylib` (+ `lib` for tests) with 65 exports,
  byte-identical names to the C++ DLL (verified with objdump, 65/65).
- `bool` is 1-byte (`_Bool` equivalent) — matches Dart FFI `Bool` and C.
- No struct crosses the FFI boundary: `GhitaEngineContext*` is opaque; all
  payloads are `char*` / `uint8_t*` / `float*` + scalars.

## 2. Return-code conventions (the two families)

Dart checks `== 0` for the legacy family and `!= 0` for the v0.8.0 family —
**they must never be mixed**.

| Family | Functions | Success / error |
|---|---|---|
| 0/-1 | init, load_media, remove_clip, set_clip_position, set_clip_filter, start_export(_ex), add_clip_keyframe, clear_clip_keyframes, set/get_clip_keyframe_interpolation (setter), add_keyframe_ex, set_keyframe_bezier, set_clip_pip, add_speed_ramp_point, clear_speed_curve | 0 / -1 |
| 1/0 | upsert_clip, set_track_state, set_clip_color_correction, set_clip_text, has_clip | 1 / 0 |
| other | add_clip → clip id (≥1); get_clip_keyframe_count → -1 missing clip; get_snapping_fps null→30; get_playback_rate null→1.0; get_clip_keyframe_interpolation null→0 | — |

## 3. Panic containment & allocation rules

1. **Every exported function is wrapped in `catch_unwind`** — a Rust panic
   must never cross the FFI boundary. On panic the documented sentinel
   (`-1`/`0`/`false`/`nullptr`) is returned (c_api.rs `c_guard!`).
2. `ghita_engine_create` must return **null on OOM** (Dart checks null → demo
   mode). `Box::try_new` is unstable, so the crate allocates via
   `std::alloc::alloc` (returns null, never aborts).
3. `bool` params from Dart are C `int` 0/1 — the wrappers convert with `!= 0`.

## 4. Thread-local return buffers

Dart reads these synchronously and copies immediately — the pointer is only
valid until the next call **on the same thread** (Dart also calls from a
second OS thread via `Isolate.run` — hence thread-local, not static):

| Function | Buffer | Contract |
|---|---|---|
| get_media_info / get_available_filters | shared per-thread `CString` (T_JSON) | NUL-terminated; `"{}"` / `"[]"` on null ctx |
| get_thumbnail | per-thread `Vec<u8>` (T_THUMB) | `nullptr` on failure |

⚠️ The C++-side thread-local `std::string` is NOT NUL-terminated-safe in Rust —
the Rust port uses `CString` (a plain Rust `String` is not NUL-terminated and
would over-read past the buffer).

## 5. Load-bearing ABI quirks (do not "fix")

| Quirk | Detail |
|---|---|
| Two color-correction arg orders | `set_clip_color_correction`: exposure, contrast, saturation, temperature, tint, vibrance, highlights, shadows. `apply_color_correction`: exposure, contrast, **highlights, shadows**, temperature, tint, vibrance, **saturation**. |
| Two interpolation numberings | `KeyframeInterpolation` enum (Linear=0, EaseIn=1, EaseOut=2, Hold=3 — sets clip.keyframeInterpolation) vs the per-keyframe `interpolation` field evaluated at render (0=linear, 1=step, 2=bezier). |
| render_frame_rgba advances the playhead | wall-clock elapsed × playback_rate, wrap to 0 at duration — the Dart tick loop depends on this. render_frame_at/at_ex must NOT mutate playback state. |
| Export two-phase publish | claim slot under the engine lock; join previous thread OUTSIDE it (deadlock avoidance). MP3 bypasses w/h/fps validation. |
| Export fallback renders the legacy decoder | the no-FFmpeg path writes raw RGBA via the local decoder (NOT the timeline compositor) — parity preserved. |

## 6. Enums (exact values)

- TransitionType: None=0 FadeIn=1 FadeOut=2 Crossfade=3 Slide=4 Wipe=5 Zoom=6 Dissolve=7 Radial=8 (compositor renders 1–3; 4–8 registered only)
- NativeClipKind: Video=0 Audio=1 Image=2 Text=3 Sticker=4
- Keyframe property: 0=opacity 1=offsetX 2=scale 3=rotation(stored) 4=filter intensity
- Filter ids: 0 None … 22 Chroma Key — `filters_json()` is the single source
  of truth (id list 0..22 unique, asserted by tests)

## 7. Threading model (mirrors C++)

| Rust | C++ equivalent | Guards |
|---|---|---|
| `RwLock<EngineState>` | `shared_mutex m_engineMutex` | clips, tracks, legacy decoder, export path snapshot |
| `Mutex<RenderState>` | `m_renderMutex` | decoder LRU cache (cap 8), scratch buffers |
| `Mutex<Instant>` | `m_tickTimeMutex` | playhead clock |
| `ExportState.join_mutex` | `m_exportJoinMutex` | export thread join serialization |
| `AudioThreadState` | `m_audioThreadMutex` | audio preview thread (T1 parity stub; cpal in T2) |
| atomics | atomics | playhead, duration, volume, rate, filters, export state |

Lock order: engine → render → (direct buffer). Never join a thread while
holding the engine lock.

## 8. Verification (Track 1 evidence)

| Gate | Result |
|---|---|
| `cargo test` (default) | 34/34 pass (14 unit + 20 ABI) |
| `cargo test --features parallel` | +1 benchmark: **5.27× speedup** (12 threads), output byte-equal to serial |
| `cargo test --features gpu` | +4 graph cache tests; GPU parity on **NVIDIA RTX 3050** within ±1/255 (FMA rounding) |
| `cargo build` (cdylib) | 65/65 `ghita_engine_*` exports (objdump) |
| `tools/engine_compare` (A/B vs C++ DLL) | **PASS — 44/44 frames max_diff=0, 25 return codes OK, JSON byte-identical, mix/waveform 0.0** |
| Concurrency stress | 4 threads × 20 renders, no panic |

Run the A/B harness:

```bash
cargo build --release -p ghita_engine          # native_engine_rust
cd native_engine_rust/tools/engine_compare && cargo run --release
```

## 9. Feature flags & pipeline note

- `default` — core (no deps). Drop-in synthetic engine.
- `ffmpeg` — T2 (DONE 2026-08-12): real FFmpeg decode/encode via
  ffmpeg-sys-next 8.1 + cpal audio preview. Build env: `.cargo/config.toml`
  sets `FFMPEG_DIR=C:/msys64/mingw64` (force=false); bindgen needs
  `LIBCLANG_PATH` → `C:/msys64/mingw64/bin` (clang installed via
  `pacman -S mingw-w64-x86_64-clang`). Runtime DLLs = the same
  avcodec-62/avformat-62/... set beside the C++ engine.
- `parallel` — T1-P5: rayon tile-based filters (fall back to serial for
  non-row-local filters).
- `gpu` — T1-P6: wgpu DX12 compute filter (Grayscale/Sepia/Invert; CPU
  fallback) + GEGL-like lazy graph (`graph.rs`).

T2 pipes under `ffmpeg`:
- `media.rs` `FfmpegDecoder` — open/find_streams, decode-video (seek+flush,
  likelyStill + still cache, fresh-demuxer reopen), `decode_audio_segment`
  (mixSwr 44.1k stereo, contiguous fast-path, sample-skip, resampler drain),
  WAV/PCM direct-file reader (RIFF parse, persistent handle, O(1) memory),
  whole-file waveform decode.
- `engine.rs` `run_export_ffmpeg` — encoder fallback chain (libx265/hevc,
  libvpx-vp9/vp9, GIF, prores_ks/prores, libx264/libopenh264/h264/mpeg4)
  with the FFmpeg ≥ 7 `avcodec_get_supported_config` YUV420 probe; AAC/MP3
  with priming-delay PTS; multichannel audio via
  `set_export_channel_layout("5.1"|"7.1")` (FLT-stereo → FLTP layout);
  trailer + on-disk file size.
- cpal preview — default or `set_audio_device(name)` device, 44.1 kHz,
  f32/i16/u16 conversion, mono downmix; lifecycle identical to the C++
  waveOut thread (started outside the engine lock, joined on pause/destroy).

## 10. T3 symbols (v1.5.0 video features — additive, `_tryLookup`-safe)

| Symbol | Semantics |
|---|---|
| ghita_engine_set_clip_blend_mode(ctx, clip, mode) | 0/-1; mode: 0 Normal, 1 Multiply, 2 Screen, 3 Overlay, 4 Add |
| ghita_engine_set_clip_mask(ctx, clip, mask, feather, stroke) | 0/-1; mask: 0 None, 1 Rect, 2 Ellipse, 3 Diamond, 4 Star, 5 Heart, 6 CinematicBars |
| ghita_engine_set_clip_maintain_pitch(ctx, clip, enabled) | 0/-1; rubato SincFixedIn stretch in the mix path |
| ghita_engine_set_clip_font(ctx, clip, family) | 0/-1; GDI font family |
| ghita_engine_set_canvas_background(ctx, kind, color, color2) | 0 solid, 1 vertical gradient, 2 blur-of-first-clip |
| ghita_engine_add_bookmark / remove_bookmark / get_bookmark_count / get_bookmarks_json | id ≥ 1; JSON [{id,timeMs,color,note}] via thread-local |
| ghita_engine_copy_keyframes(ctx, src, dst) | 0/-1; merge + (time, property) sort |
| ghita_engine_import_transcript(ctx, path, track) | .srt/.vtt → text clips; returns count |

Notes: `upsert_clip` kind now accepts 5 = Effect (adjustment-layer semantics —
the effect's filter applies to the accumulated composite). Defaults preserve
the pre-T3 bytes exactly (verified: A/B parity max_diff=0 after the changes).

Dart side (T3b, commit dc3a3d4): all 11 symbols bound via `_tryLookup` in
native_bindings.dart, mirrored in engine_service.dart with graceful-fallback
wrappers, synced per-clip in `syncTimelineToEngine`. Gates: flutter analyze
"No issues found", flutter test 143/143 (Flutter 3.44.9 stable).

**Pipeline note (re-scope 2026-08-12):** the engine processes RGBA in u8
end-to-end, byte-porting the C++ engine — this is what makes the A/B gate
(44/44 frames max_diff=0) hold. Optimization point #3 (32-bit float internal
pipeline) is **moved to T5 P7** in plan_v1.5.0.md: switching the core to f32
would break byte-parity immediately, so it lands with the post-parity
performance work (T5, alongside rayon & A/B re-verification), not T1.

## 11. T4 symbols (v1.5.0 audio features — additive, `_tryLookup`-safe, `#[cfg(feature = "ffmpeg")]`)

All T4 symbols are gated behind the `ffmpeg` feature flag. On non-ffmpeg builds
they are absent from the DLL and Dart's `_tryLookup` returns null (graceful
degrade). Return family: 0/-1 for setters, count/bool for getters.

| Symbol | Semantics |
|---|---|
| ghita_engine_add_audio_effect(ctx, type, p0, p1, p2, p3) | 0/-1; type: 0 Compressor, 1 Limiter, 2 NoiseGate, 3 NoiseReduction, 4 BassTreble, 5 Distortion, 6 Phaser, 7 Reverb, 8 WahWah, 9 ShelfFilter |
| ghita_engine_remove_audio_effect(ctx, index) | 0/-1; remove by chain index |
| ghita_engine_clear_audio_effects(ctx) | void; clear entire chain |
| ghita_engine_get_gain_reduction_db(ctx) | f32; last compressor/limiter gain reduction |
| ghita_engine_get_spectrogram(ctx, out_mags, columns, bins, track) | bool; fills columns×bins magnitude buffer |
| ghita_engine_add_spectral_edit(ctx, start_ms, end_ms, lo_hz, hi_hz, gain_db) | 0/-1; frequency-domain gain edit |
| ghita_engine_clear_spectral_edits(ctx) | void |
| ghita_engine_get_timeline_rms(ctx, out, count, track) | bool; RMS per bucket |
| ghita_engine_detect_tempo(ctx) | BPM (int); 0 if undetected |
| ghita_engine_set_time_signature(ctx, num, den) | void; e.g. 4/4 |
| ghita_engine_get_beat_times(ctx, out_ms, max_count) | count; beat grid in ms |
| ghita_engine_set_loop_region(ctx, start_ms, end_ms, enabled) | void; playback loop |
| ghita_engine_set_clip_pitch(ctx, clip_id, semitones) | 0/-1; wrap-around pitch shift |
| ghita_engine_set_preview_pitch_preserve(ctx, enabled) | void; maintain-pitch during scrub |
| ghita_engine_start_recording(ctx, path, mode, pre_roll_ms, delay_ms, duration_ms) | 0/-1; cpal input → WAV |
| ghita_engine_stop_recording(ctx) | recorded duration ms |
| ghita_engine_is_recording(ctx) | bool |
| ghita_engine_export_labels(ctx, path, format) | 0/-1; format: 0 SRT, 1 VTT |

Dart side (T4b): all 19 symbols bound via `_tryLookup` in native_bindings.dart,
mirrored in engine_service.dart with graceful-fallback wrappers. DAW panel UI
(audio_daw_panel.dart) wires effect chain editor, spectrogram canvas with beat
markers, spectral brush, tempo/time signature display, recording controls, loop
region overlay, clip pitch slider, gain reduction meter, label export. Gates:
flutter analyze "No issues found" (0 errors), flutter test 143/143 PASS
(Flutter 3.44.9 stable).

## 12. T5 symbols (v1.5.0 data & workflow — standalone, sqlite feature)

All T5 project database symbols are standalone (no engine context parameter) and
gated behind the sqlite feature flag. Return family: 0/-1 for setters, JSON
string pointer for getters.

| Symbol | Semantics |
|---|---|
| ghita_project_db_save(db_path, name, json_data) | 0/-1; save project JSON to SQLite |
| ghita_project_db_load(db_path, name) | Pointer Utf8; load project JSON from SQLite |
| ghita_project_db_list(db_path) | Pointer Utf8; list all projects as JSON array |
| ghita_project_db_delete(db_path, name) | 0/-1; delete project from SQLite |
| ghita_project_db_library_add(db_path, path, hash, metadata_json) | 0/-1; add media entry |
| ghita_project_db_library_search(db_path, query) | Pointer Utf8; search media library |
| ghita_project_db_library_update_rating(db_path, id, rating) | 0/-1; update media rating (0-5) |
| ghita_project_db_library_update_tags(db_path, id, tags) | 0/-1; update media tags (comma-separated) |

Additional T5 modules (no FFI symbols, internal Rust only):
- metadata.rs: EXIF reader (JPEG/TIFF), XMP sidecar read/write
- processing_cache.rs: LRU frame cache with dirty propagation

Dart side (T5-P1): all 8 symbols bound via _tryLookup in native_bindings.dart.
ProjectService dual-backend: always writes JSON for backward compat, plus SQLite
when available. Auto-migrates JSON to SQLite on first load. Gates: cargo test --lib
32/32 PASS, flutter analyze 0 errors, flutter test 143/143 PASS.


## 13. T5-P7: 32-bit float internal pipeline (feature-gated, additive)

The f32_pipeline module provides f32 versions of all pixel processing functions.
Feature flag: f32_pipeline (additive, does not replace u8 path).

Functions: u8_to_f32, f32_to_u8, apply_filter_f32 (all 22 filters), blend_rgba_f32,
blend_rgba_offset_f32. All operate on 0.0-1.0 range; conversion to u8 at output
boundary only via (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8.

Parity verification: 4/4 tests PASS (f32_round_trip, grayscale_parity,
sepia_invert_brightness_parity, blend_parity) — all within plus/minus 1/255 of u8 reference.
Full suite with feature: 65/65 PASS (36 lib + 20 ABI + 9 T3).


## 14. T6 symbols (v1.5.0 photo features — selection tools)

Selection tools operate on a thread-local pixel mask buffer (standalone, no engine context).

| Symbol | Semantics |
|---|---|
| ghita_engine_set_selection_rect(x, y, w, h, op) | 0/-1; rasterize rect into mask |
| ghita_engine_set_selection_ellipse(cx, cy, rx, ry, op) | 0/-1; rasterize ellipse into mask |
| ghita_engine_set_selection_lasso(points, count, op) | 0/-1; fill polygon into mask |
| ghita_engine_set_selection_magic_wand(image, w, h, sx, sy, tol, op) | 0/-1; flood fill from seed |
| ghita_engine_modify_mask(op) | 0/-1; invert current mask |
| ghita_engine_get_mask_buffer(out, max_size) | bytes written; copy mask to caller buffer |
| ghita_engine_clear_selection() | void; clear mask to zero |

Additional T6 modules (no FFI symbols, internal Rust only):
- paint_tools.rs: clone stamp, spot healing, bezier path rasterization
- color_mgmt.rs: sRGB/linear, Reinhard HDR, film simulation, HSL
- brush_engine.rs: pixel/smudge brush, stroke stabilizer
- ai_tools.rs: NLM denoise, bicubic upscale, color segmentation, hash dedup

Gates: cargo test --lib 55/55 PASS, flutter analyze 0 errors, flutter test 143/143 PASS.

## 15. T2 additions (v1.5.0 final — CI/CD track)

| Symbol | Semantics |
|---|---|
| ghita_engine_set_export_channel_layout(ctx, layout) | 0/-1; layout = "stereo" \| "5.1" \| "7.1" — selects the export AAC channel mapping (added in T2-P3 so shell drivers (export_matrix → ffprobe) can reach the multichannel path, which previously had NO C export). |

T1 corrections reflected here (parity fixes, no signature changes):
- §14 signatures above are the ACTUAL Rust exports `(width,height,…)`-style;
  the Dart bindings (native_bindings.dart) were re-aligned in T1-P1 and are
  now enforced by test/ffi_arity_contract_test.dart (symbol+arity table,
  Dart ↔ c_api.rs).
- ghita_project_db_library_search takes (db_path, query, min_rating).

Gates after T1/T2: flutter analyze --fatal-infos clean · flutter test 152/152 ·
cargo test default 92/92 · cargo test --features ffmpeg 116/116.

## 16. T5 additions (v1.5.0 final — Rust hóa sâu)

| Symbol | Semantics |
|---|---|
| ghita_engine_cache_stats(ctx) | JSON {hits,misses,entries,rate} — paused-scrub ProcessingCache telemetry |
| ghita_engine_gpu_stats() | JSON {available,adapter,gpu_frames,cpu_fallbacks} — available=false khi không build feature `gpu` |
| ghita_engine_set_clip_sticker_transform(ctx, clip_id, scale, rotation_deg) | 0/-1; chỉ áp dụng clip kind Sticker; scale clamp 0.05..8 |
| ghita_engine_set_audio_effect_param(ctx, index, param, value) | 0/-1; live-edit p0..p3 của effect chain (ffmpeg feature); từ chối index âm/vượt cuối chain thay vì clamp |
| ghita_engine_paint_clone(buf, w, h, src_x, src_y, dst_x, dst_y, radius, opacity) | 0/-1; ctx-less clone stamp trên buffer caller (src snapshot nội bộ chống aliasing) |
| ghita_engine_paint_heal(buf, w, h, cx, cy, radius) | 0/-1; spot heal ctx-less |
| ghita_engine_paint_brush_stroke(buf, w, h, px[], py[], count, size, hardness, opacity, color_rgba) | 0/-1; soft brush stroke dọc polyline; color little-endian RGBA |

Removed in T5 (không còn tồn tại): module `f32_pipeline` + feature
`f32_pipeline`; module `graph`. ProcessingCache giờ được wire vào render
paused-path (không còn dead code).

Gates after T6: cargo test default 95/95 · cargo test --features ffmpeg,gpu
121/121 · flutter analyze --fatal-infos clean · flutter test 157/157 ·
coverage ≥60% gate PASS.
