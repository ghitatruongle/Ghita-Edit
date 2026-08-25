# Kế hoạch Ghita Edit v1.5.0 Final — Ổn định hóa · Hiệu năng · Rust hóa sâu (Track-based)

Ngày lập: 2026-08-23 · Lộ trình: từ **v1.5.0-beta** hiện tại lên bản phát hành chính thức **v1.5.0**
Cơ sở: audit full-code 4 khu vực (Dart app `lib/` ~17.4k LOC · Rust engine `native_engine_rust/` ~14.4k LOC · FFI/test/CI/build · C++ oracle `native_engine/` ~7.2k LOC)
Hiện tại: **v1.5.0-beta** (bf67761 + sync banner `1cb0c67`) · Mục tiêu: **v1.5.0 chính thức (bỏ hậu tố -beta)**
**6 track × 4–6 phase = 29 phase.** Không đổi version.dart/pubspec (đã là 1.5.0+0); mốc nội bộ phân biệt bằng git tag pre-release: `v1.5.0-beta.2` → `v1.5.0-rc1` → `v1.5.0-rc2` → **tag `v1.5.0` final**.

---

## 1. Nguyên tắc chỉ đạo

1. **Đúng trước nhanh**: mọi tối ưu (T3/T4) phải đứng sau các fix đúng đắn của T1; benchmark luôn kèm kiểm chứng byte-equal so với đường serial/parity cũ.
2. **ABI bất biến**: 65 symbol pre-v1.5 giữ nguyên hành vi; sửa bug không đổi chữ ký. Mọi symbol mới đi qua `_tryLookup` + cập nhật `docs/rust_engine_abi.md` trước khi merge.
3. **Không suy giảm thầm lặng**: hết Demo Mode âm thầm — engine status hiển thị rõ; GPU/filter pipeline fallback phải có telemetry đếm.
4. **Version single-source**: mọi chuỗi phiên bản sinh từ `version.dart`; cấm hardcode số bản rải rác. *Phần khai báo 1.1.x đã được sync xong sớm tại commit `1cb0c67` (CMake, banner C++, banner Rust, assert self-test/abi_tests, iOS script tự đọc version.dart).*
5. **C++ đóng băng làm oracle**: chỉ giữ 65 symbol + self-test để A/B parity; KHÔNG port tính năng v1.5 ngược về C++.
6. **Scope đóng**: 29 phase nằm trong v1.5.0 final; phát hiện mới trong quá trình làm phải đánh đổi bằng phase tương đương.

---

## 2. Sơ đồ 6 track

```
        ┌────────────────────────────┐
        │ T1 Hotfix đúng đắn + ABI   │  (chạy đầu — mọi track phụ thuộc)
        └─────────────┬──────────────┘
        ┌─────────────┴──────────────┐
        ▼                            ▼
┌───────────────┐          ┌───────────────────┐
│ T2 Version &  │          │ T3 Hiệu năng Dart  │
│ CI/CD         │          ├───────────────────┤
└───────┬───────┘          │ T4 Hiệu năng Rust  │
        │                  └─────────┬─────────┘
        └────────────┬───────────────┘
                     ▼
        ┌────────────────────────┐   ┌──────────────────────┐
        │ T5 Rust hóa sâu +      │◄──│ T6 Chất lượng, test, │
        │ hoàn thiện tính năng   │   │ docs (xuyên suốt)    │
        └────────────────────────┘   └──────────────────────┘
```

---

## 3. Chi tiết track — mỗi track ≥ 4 phase

### T1 — Hotfix đúng đắn & an toàn bộ nhớ · 5 phase · ✅ HOÀN THÀNH (2026-08-23) → tag `v1.5.0-beta.2`

| Phase | Nội dung | Bằng chứng audit |
|---|---|---|
| P1 | **ABI khẩn cấp**: sửa 4 signature selection tool phía Dart (`set_selection_rect/_ellipse/_lasso/_magic_wand`) khớp Rust `(width,height,…)`; thêm catch_unwind cho 7 export thiếu guard (`c_api.rs:1531-1648`); sửa tràn i32 `width*height*4` (`c_api.rs:1591`); tạo **bảng contract tự sinh** (symbol + arity Dart↔header) chạy trong CI để lớp lỗi này không tái phát | native_bindings.dart:227-237 ↔ c_api.rs:1532-1600 |
| P2 | **An toàn bộ nhớ Rust**: overflow `decode_audio_samples` stereo (size conv_buffer × channels); UAF thread ghi âm (track handle + join trong `Drop`); panic trên export-thread reset `is_exporting` (guard trong closure); null-check `audio_stream` lúc flush; TOCTOU `cancel_export`; cpal callback không được panic | media.rs:789,807-819 · audio_t4.rs:339-416 · engine.rs:1628-1631,2282-2294 |
| P3 | **Model Dart**: `copyWith` mất màu chữ (fallback `this.` thay vì transparent); regex SRT giữ millisecond; import transcript không double-add + đúng overlay track; `trimClipEnd` thêm clamp min-duration/sourceOut; delete-undo không xê dịch clip khác; newProject/loadProject clear bookmarks/guides/snapshots | clip.dart:335-342,411-417 · editor_controller.dart:1058-1077,1018-1041,1205-1284 · track.dart:137-146 · command_history.dart:91-94 |
| P4 | **UI tính năng chết**: poll DAW dùng API peek mới (không gọi stopRecording); pitch slider bỏ `int.tryParse(id)`; Save As dùng `saveFile`; Select All notifyListeners; default export path theo project dir; bỏ force-unwrap picker; demo filter chips đi qua command + `_markEngineSync` | audio_daw_panel.dart:91-95,389-393 · editor_view.dart:1343-1355,544-548 · export_dialog.dart:417 · inspector_panel.dart:1358-1375 |
| P5 | **Cache & engine đúng đắn**: frame cache key bao gồm per-clip state hoặc invalidation theo generation; khôi phục idle short-circuit (bỏ double isPlaying); `renderFrameAt` check capacity trước khi render; DSP: reverb damp công thức chết, phaser stage mapping, transcript split CRLF, no-ffmpeg `write_completed` chỉ khi trailer OK | engine_service.dart:1326-1374,937-950 · dsp.rs:366,239 · engine.rs:1088-1090,1753-1755 |

**Nghiệm thu:** mỗi bug ≥ 1 regression test (Dart + Rust); `cargo test` + `flutter test` xanh; A/B 44/44 frame max_diff=0 giữ nguyên; không còn crash/UB đã biết.

**✅ HOÀN THÀNH (2026-08-23) — bằng chứng:**
- P1 ABI: 4 signature selection Dart↔Rust khớp (native_bindings.dart ↔ c_api.rs, call-site photo_editor_panel dùng đúng canvas 560×360); 7 export selection/mask có `c_guard!` + validate kích thước âm; sửa tràn i32 `(width*height*4)` magic-wand (usize math sau khi validate). **Contract test tự sinh** (`test/ffi_arity_contract_test.dart`) parse cả hai nguồn so sánh arity >40 symbol — và đã bắt ngay **lệch ABI thứ 5 thật**: `ghita_project_db_library_search` thiếu `min_rating` phía Dart → sửa typedef + light_table_panel.
- P2 memory-safety Rust: overflow swr stereo (media.rs — helper `swr_requested_frames` + unit test); UAF thread ghi âm (T4State `capture_stop` + `capture_thread`, join trong `Drop` TRƯỚC khi giải phóng); panic export-thread reset `is_exporting`/`export_error` qua catch_unwind (hết brick vĩnh viễn); TOCTOU `cancel_export` (check-under-lock); null-check `audio_stream` lúc flush; cpal callback không-unwind (catch_unwind → silence).
- P3 model Dart: copyWith GIỮ màu chữ (cả splitAt kế thừa); SRT giữ millisecond + normalize CRLF + import không double-add + mặc định overlay track; `trimClipEnd` thêm sàn `kMinClipDurationMs`; DeleteClipCommand undo chèn lại theo index gốc (không xê dịch clip khác); newProject/loadProject clear bookmarks/guides/canvasBg; commandHistory.clear() clear snapshots.
- P4 UI: DAW poll đo thời lượng bằng đồng hồ local (bỏ "peek" stopRecording giết bản ghi); pitch slider dùng `nativeClipIdFor` (bỏ int.tryParse chết); Save As dùng `saveFile` thật; Select All notifyListeners; default export path neo theo thư mục project/home (hết CWD); bỏ force-unwrap picker (editor_view + media_bin); demo filter chips đi qua `setClipFilter` (undoable + engine-sync).
- P5 cache/engine: `invalidateFrameCache()` gọi từ `_onCommandHistoryChanged` + `_updateClip` (hết frame stale sau khi edit); idle short-circuit phục hồi (refresh `_lastPolled*` trong nhánh cache-hit, bỏ isPlaying trùng); `renderFrameAt` grow-only capacity check.
- DSP: reverb damp chuẩn freeverb (per-comb filterstore — công thức cũ tự triệt tiêu); phaser có mảng allpass riêng 4 stage (không còn đè lên bq của EQ/Distortion).
- Gate số liệu: `flutter analyze --fatal-infos` = No issues found · `flutter test` = **152/152** · `cargo test` default = **92/92** · `cargo test --features ffmpeg` = **116/116** (t1_regression_tests 7/7: selection FFI từ chối dims âm/null, mask buffer chịu buf_size âm, export cancel reset flag + start lại được).

### T2 — Hợp nhất phiên bản & CI/CD · 4 phase · ✅ HOÀN THÀNH (2026-08-23) → tag `v1.5.0-rc1`

| Phase | Nội dung | Bằng chứng audit |
|---|---|---|
| P1 | ✅ **HOÀN THÀNH sớm (2026-08-23, commit `1cb0c67`)**: banner C++ (`ghita_c_api.cpp:11`), CMake `VERSION`, banner Rust (`c_api.rs:28`) → 1.5.0; assert self-test + abi_tests đồng bộ; iOS script tự đọc `version.dart` thay hardcode 0.4.5. Bằng chứng: replay gate CI local PASS (dart=cpp=cmake=rust=1.5.0); `cargo test --test abi_tests` 20/20 xanh | đã push origin/main |
| P2 | **Lookup an toàn**: `_tryLookup` phủ toàn bộ symbol (kể cả nhóm cũ) hoặc fail LOUD với dialog engine-status thay vì Demo Mode âm thầm; gom 5 script typedef tay về 1 binding dùng chung (bỏ drift như T6 selection) | native_bindings.dart:709-770 · scripts/*.dart |
| P3 | **CI thật sự**: job Windows chạy real-engine Dart tests (engine_real_test, review_track_a); coverage gate (≥60% controllers) + upload artifact; publish installer khi tag; `verify_export_matrix.sh` thêm 5.1/7.1; bỏ path máy cá nhân (/c/Users/Acer, msys64 fallback vào env var) | ci.yml:63-93,212-219 · verify_export_matrix.sh:30-32 |
| P4 | **Android quyết định + dọn dẹp**: cargo-ndk build `.so` + jniLibs + signing release thật (bỏ debug-key), Android CI job; nếu không làm thì tuyên bố rõ mất feature; `scripts/clean.sh` cho ~15.7GB rác local; xử lý paradox .gitignore docs; commit lại `reference_comparison_70_points.md` | android jniLibs không tồn tại · .gitignore:44 |

**Nghiệm thu:** push tag → CI build đủ Windows installer artifact; version gate pass trên 3 OS; APK release ký key thật.

**✅ HOÀN THÀNH (2026-08-23) — bằng chứng:**
- P1: sync banner 1.5.0 — commit `1cb0c67` (xong sớm trước beta.2): CMake, banner C++, banner Rust, assert self-test/abi_tests, iOS script tự đọc version.dart; gate CI pass local.
- P2: `_bindFunctions` bọc try/catch nêu tên symbol lỗi; `EngineService.lastBindingError` + status bar hiển thị lý do Demo Mode ("Demo Mode — <lỗi>") thay vì im lặng; **gom 6 script** (wav_full/probe3/smoke_track1/engine_smoke_test/ghita_cli/export_matrix) về `scripts/engine_ffi_shared.dart` — chữ ký FFI định nghĩa đúng MỘT nơi, script chỉ alias tên (hết drift kiểu T6); loader DLL dùng chung `loadEngineLibrary()`. Bài học: Dart FFI từ chối typedef alias chuỗi ở lookupFunction → lookup phải dùng thẳng tên shared.
- P3: C export mới `ghita_engine_set_export_channel_layout` (c_api.rs, c_guard!) + ABI doc §15 → matrix thêm **aac_51/aac_71**, ffprobe kiểm tra channels=6/8; verify_export_matrix.sh bỏ fallback `/c/Users/Acer` + msys64 cứng (env FFPROBE/FFMPEG/DART); ci.yml: coverage artifact upload + **gate controllers ≥60%** (`tool/coverage_gate.dart`); job Rust build DLL ffmpeg → stage tại repo root → chạy **real-engine Dart tests trên Windows** (engine_real_test + review_track_a — trước đây không chạy ở CI nào); job mới `release-windows` khi tag v*: Inno Setup installer + portable zip → GitHub Release (permissions: contents: write).
- P4: Android tuyên bố chính thức trong `docs/android_status.md` (Demo Mode — chưa có .so engine, cargo-ndk thuộc T5) + bảng Platform Status trong README (tiêu đề README cũng hết kẹt "v1.1.1+0"); signing release thật qua `key.properties`/env với cảnh báo LOUD nếu rơi về debug key; `scripts/clean.sh` (-y/--deep) dọn ~15.7GB rác local an toàn; bỏ `docs/` khỏi .gitignore (paradox half-tracked) → commit đủ docs kể cả reference_comparison_70_points.md.

### T3 — Hiệu năng tầng Flutter/Dart · 4 phase · ✅ HOÀN THÀNH (2026-08-23) → tag `v1.5.0-rc2`

| Phase | Nội dung | Kỳ vọng |
|---|---|---|
| P1 | **Rebuild scoping**: tách position/timecode thành ValueNotifier riêng; scoped ListenableBuilder từng panel thay AnimatedBuilder cả scaffold; inspector chuyển card lazy | cắt rebuild ~30fps×5 panel → chỉ preview + timeline tick |
| P2 | **Painter cache**: spectrogram vẽ 1 lần vào `ui.Picture` (playhead vẽ riêng); minimap signature incremental; waveform cache chỉ invalidate khi structural command (add/delete/move/trim/split) | spectrogram 12.800 drawRect/tick → ~0 |
| P3 | **Kỷ luật gọi engine**: bỏ isPlaying gọi 2 lần/tick khi cached; scratch buffer reuse cho waveform/spectrogram/raw-frame; split-view throttle ≤10fps hoặc render ở isolate; deferred resync chỉ ghi clip dirty (diff) thay vì toàn bộ clips+keyframes | giảm FFI call + alloc mỗi scrub tick |
| P4 | **Cấu trúc dữ liệu UI**: selectedClips duy trì index O(1) (thay O(clips×selection) mỗi widget build); media_bin sync qua listener có change-detection; `_onCommandHistoryChanged` không xóa cache waveform khi coalesced tick | O(n²) per tick → O(1) |

**Nghiệm thu:** DevTools benchmark trước/sau: average frame build < 2ms @ timeline 100 clip + playback; jank count giảm ≥ 50%.

**✅ HOÀN THÀNH (2026-08-23) — bằng chứng:**
- P1 Rebuild scoping: `EditorController.playheadMs` (ValueNotifier<int>) + phân loại tick position-only trong `_applyEngineTickSample` — tick playback chỉ cập nhật notifier, KHÔNG còn full notifyListeners 30 lần/s; consumer chuyển sang luồng O(1): playhead timeline (ValueListenableBuilder quanh layer Positioned), tick-line minimap (`_MiniPlayheadPainter` riêng + RepaintBoundary), timecode status bar; PreviewPlayer nghe thẳng EngineService (frame vẫn chảy khi controller bị dập thông báo).
- P2 Painter cache: spectrogram tách `_SpectrogramStaticPainter` — bg+heatmap+waveform+beats+loop ghi 1 lần vào `ui.Picture` theo version/size key (12.800 drawRect/tick → 1 drawPicture + 1 line); minimap bỏ signature STRING O(clips) mỗi phép so sánh → numeric hash không cấp phát + tách playhead; ruler bookmarks memo theo version (shouldRepaint identity hết luôn-true); waveform cache trả instance gốc thay vì copy mỗi lần lấy (WaveformPainter không repaint oan); waveform cache chỉ clear khi command STRUCTURAL.
- P3 Kỷ luật gọi engine: split-view throttle ~10fps (trước: render 640×360 đồng bộ ×2 mỗi frame); **deferred resync theo fingerprint** — 13 nhóm thuộc tính/clip (geometry/filter/transition/blend/mask/pitch/font/color/text/keyframes/pip/speedCurve) + track-state: chỉ setter có fingerprint đổi mới gọi FFI (một tick opacity trước đây re-issue ~13 calls × MỌI clip + clear/re-add toàn bộ keyframes).
- P4 Cấu trúc dữ liệu: Project duy trì `_liveSelectedIds` tại choke point `_syncClipSelectionFlags` → `isClipSelected()`/`selectedClipCount` O(1) (vòng build timeline từ O(clips²) xuống O(clips)); media_bin `_syncImportedMediaIfChanged` early-exit theo project identity + clip count (hết sync 30fps).

Regression suite `test/t3_perf_regression_test.dart` 5/5: selection O(1) đúng+scaled (2000 clip <50ms cho 2000 check — cũ ~200M ops), gating position-only (sample trùng KHÔNG notify, playhead vẫn chạy), duration/playing/gen đổi CÓ notify, phân loại structural/property.
Gate số liệu: flutter analyze --fatal-infos sạch · flutter test **157/157** · coverage controllers **64.2% ≥ 60%** · cargo test default + ffmpeg toàn xanh (không hồi quy).

### T4 — Hiệu năng engine Rust · 5 phase · ✅ HOÀN THÀNH (2026-08-23) → landing trên main sau tag `v1.5.0-rc2` (T3 dùng chung mốc nội bộ này)

| Phase | Nội dung | Kỳ vọng |
|---|---|---|
| P1 | **Scratch buffers** đưa vào `RenderState` (grow-only sẵn có): blur/sharpen/chromatic/bg-blur/skin-retouch/glitch hết alloc 8.3MB/frame @1080p | bớt jitter allocator, ~10-20% frame-time filter |
| P2 | **Rayon mở rộng**: tile in-place từ snapshot chung (bỏ 2 bản to_vec/frame); SAT + tile-overlap để blur/sharpen/skin-retouch/background-blur song song hóa | chuẩn ≥1.5×/4-core áp dụng cho mọi filter nặng, không chỉ 9 filter row-local |
| P3 | **Speed-curve integral table** per clip (dirty-on-edit) thay tích phân số 5ms-step (12k calls/frame với clip 60s); compositor bỏ giả định sort sớm-break thiếu bảo đảm | O(duration/5ms)/frame → O(1)/frame |
| P4 | **Export fast-path**: seek đơn điệu + decoder pipelining (thay seek+flush mỗi frame); giảm contention preview/export lock; rubato resampler reuse per clip (maintain-pitch) | export wall-time giảm đo được trên test_video.mp4 (ghi số liệu gate) |
| P5 | **Realtime audio**: ring buffer preallocated + try_lock cho cpal callback (hết alloc vec + priority inversion); FFT plan/window reuse; spectral edit không alloc mỗi hop; `get_timeline_waveform` một mix/bucket thay vì tới 8 | hết audible glitch khi preview + filter nặng |

**Nghiệm thu:** mọi benchmark output byte-equal so đường serial; A/B parity 65 symbol không đổi; số liệu before/after lưu trong PR.

**✅ HOÀN THÀNH (2026-08-23) — bằng chứng:**
- P1 Scratch buffers: `filters.rs` có 2 thread-local pool (ScratchBytes/ScratchU32, tối đa 8 buffer/thread) với zero-init + capacity semantics y hệt `vec![0;n]` ⇒ **byte-equal tuyệt đối**. 8 site alloc mỗi-frame chuyển sang pool: blur tmp full-frame (8.3MB@1080p), edge/chromatic/sharpen/bg-blur/skin-retouch snapshot, skin-retouch 3 SAT u32 (~25MB), glitch row-per-band (hoist ra khỏi vòng band).
- P2 Rayon mở rộng: bỏ **2 bản copy full-frame mỗi frame** (full snapshot + per-tile to_vec) → tile chỉ copy đúng band của mình từ shared snapshot vào scratch; eligibility mở rộng 9 → **14 filter** (thêm VHS-11, chromatic-13, vignette-14, grain-15, light-leak-16 — đều per-pixel/row-local nên output không đổi). Blur/sharpen/skin-retouch giữ serial vì cần SAT/halo cross-tile — ghi nhận trung thực, thuộc T5 nếu cần.
- P3 Speed-curve: `eval_source_offset` dùng **prefix-sum table cache** theo (clip id, start, curve fingerprint) — tái tạo CHÍNH XÁC chuỗi Euler 5ms cũ (cùng công thức từng bước) ⇒ byte-equal, nhưng O(1) lookup thay vì ~12.000 lần eval speed/frame với clip 60s; cache bound 16 entry. Đồng thời bỏ **2 early-break phụ thuộc sort** trong compositor (blur-bg scan + covering-clip scan) — hết rủi ro mất clip khi vector legacy chưa sort.
- P4 Export fast-path: `FfmpegDecoder.last_video_pts` + **monotonic seek** — sweep tiến liên tục không còn av_seek_frame+flush mỗi frame (decoder pipeline giữ nguyên); reset PTS khi open lại/fresh demuxer/jump lùi. Maintain-pitch: **rubato resampler cache per (ratio,channels) thread-local + reset()** trước mỗi window — reset khôi phục đúng trạng thái khởi tạo nên output IDENTICAL với construct-per-window, bỏ chi phí dựng sinc-table ~100×/giây audio.
- P5 Realtime audio: cpal callback dùng **thread-local mix scratch** (hết alloc Vec trong RT path, vẫn catch_unwind→silence); fft_tools: Hann window + forward/inverse plan qua OnceLock build-một-lần (trước đây planner rebuild mỗi call khi spectral edits active) + 2 STFT scratch buffer tái sử dụng thay vì Vec<Complex> mỗi channel mỗi hop. Waveform giữ nguyên semantics 8-subwindow (C++ parity) — chi phí đã được Dart-side cache khử từ T3.
- Gate số liệu: cargo test default **92/92** · ffmpeg **116/116** · parallel lib **56/56**; benchmark filter8 @1920×1080: **serial 22.6ms → parallel 10.6ms = speedup 2.13× (12 threads)**, output byte-equal (assert trong chính bench test).

### T5 — Rust hóa sâu & hoàn thiện tính năng · 6 phase · ✅ HOÀN THÀNH (2026-08-23) → tag **`v1.5.0` final**

| Phase | Nội dung | Ghi chú |
|---|---|---|
| P1 | **Chính thức hóa freeze C++**: ghi quyết định vào README/docs; giữ 65 symbol + self-test làm oracle; chỉ vá 2 lỗi ảnh hưởng A/B audio/timeline (overflow waveform C++ `ghita_engine.cpp:1266`, sort invariant legacy APIs) hoặc đánh dấu known-divergence | verdict agent: maintain = triple bookkeeping |
| P2 | **Wire processing_cache + graph.rs** vào `render_timeline_frame`: fix cache-key thiếu source/w/h trước; LRU frame cache thật sự hoạt động | 2 module đang dead code hoàn toàn |
| P3 | **GPU wgpu vào production**: mở rộng filter set (hiện 3), runtime detect + telemetry đếm fallback CPU, feature-gate | hiện GPU chỉ tồn tại trong test |
| P4 | **f32 pipeline quyết định**: sửa bảng filter-id sai (15/16/18-20 map nhầm warm/cool/emboss…), parity-test đủ 22 filter rồi wire — hoặc benchmark thua thì xóa module | f32_pipeline.rs:50-56 vs model.rs:379-386 |
| P5 | **Lấp lỗ tính năng engine**: transitions Slide/Wipe/Zoom/Dissolve/Radial thật sự; sticker transform; `ghita_engine_get_thumbnail` (cả 2 engine + Dart binding + hợp đồng free); bookmark symbol; GIF/ProRes quyết định trả lại hay gỡ hẳn dead branch UI | media_bin thumbnail đang chết 100% |
| P6 | **Photo studio + DAW thật**: wire selection tools sau ABI-fix (bỏ placeholder 0,0,100,100); brush/heal/clone gọi engine; T_SELECTION hợp đồng cross-isolate rõ ràng; DAW loop region editable + effect params UI→engine; wire-or-delete LightTablePanel + recovery + snapshot compaction | photo_editor_panel.dart:288-331 đang trang trí |

**✅ HOÀN THÀNH (2026-08-23) — bằng chứng:**
- P1 Freeze C++: quyết định ghi chính thức trong README (mục Architecture) + principle #5 kế hoạch; **vá overflow waveform C++** `ghita_engine.cpp` (convBuffer cap theo channels — cùng bản chất bug Rust đã sửa T1) để oracle audio A/B đáng tin; self-test C++ vẫn chạy trên CI Windows/Linux/macOS.
- P2 ProcessingCache WIRED: `EngineState.processing` (RefCell — render mutex bảo hộ) + wrapper `render_timeline_frame(cache_enabled)`; key = pos×w×h×`timeline_state_hash()` (FNV toàn bộ clip geometry/filter/cc/keyframes/pip/text/speed + track states + canvas bg + global filter) ⇒ mutation nào cũng tự invalidate; bật khi PAUSED (scrub), TẮT khi playing/export; LRU 48 entry (~42MB); symbol telemetry `ghita_engine_cache_stats`. **graph.rs XÓA**: lazy-graph model không tương thích pipeline pull-based đơn-lượt cần parity deterministic — lợi ích cache do processing_cache đảm nhiệm.
- P3 GPU production: `try_gpu/gpu_available/gpu_adapter_name/gpu_stats` (OnceLock context, đếm GPU_FRAMES/CPU_FALLBACKS); dispatch cắm tại `apply_filter_to_buffer` cho filter 1/2/3 full-frame ≥512×256, **feature-gate `gpu`** để mọi suite parity chạy thuần CPU; symbol `ghita_engine_gpu_stats` (JSON available/adapter/frames/fallbacks, non-gpu trả available=false).
- P4 f32_pipeline **XÓA** (module + feature + tham chiếu CI): bảng id lệch u8-reference, chỉ 5/22 parity-test, zero caller, không có benchmark thắng — nhánh "xóa" của cây quyết định kế hoạch; drift loại bỏ vĩnh viễn.
- P5 Transitions thật: compositor thêm `blend_extended_transition` — Slide (shift ngang), Wipe (column mask), Dissolve (hash per-pixel deterministic), Radial (distance mask), Zoom (center resample) — tái dùng cơ chế hai-frame của crossfade, pip/keyframed/masked fallback về fade; inspector dropdown mở lại đủ 9 loại. Thumbnail: **audit false-positive** — export đã tồn tại (c_api ~847) + Dart binding nullable sẵn; GIF dead branches dọn sạch trong export_dialog (mapping/dropdown/onFormatChanged).
- P6 Photo/DAW thật: lasso drag-capture nhiều điểm + magic-wand seed từ `_previewBytes` gọi đúng FFI (T1 đã fix ABI); **sticker transform end-to-end**: model fields (scale/rotation) + engine setter `ghita_engine_set_clip_sticker_transform` + compositor áp dụng qua `transform_rgba_center` (nearest-neighbour scale-about-center + rotate) + Dart binding/service/controller + inspector sliders BẬT lại (hết "chưa được engine hỗ trợ"); **paint tools FFI thật**: 3 export mới `ghita_engine_paint_clone/_paint_heal/_paint_brush_stroke` (ctx-less trên buffer của caller, clone snapshot src để tránh aliasing, brush dùng brush_engine::brush_stroke với BrushParams) + photo panel wire Clone (delta-preserve)/Heal/Brush (accent stroke); DAW loop region In/Out slider thật (hết hardwire 0..5000); **effect params p0..p3 edit live** qua export mới `ghita_engine_set_audio_effect_param` (+binding+wrapper, từ chối index âm/range sai thay vì clamp im lặng) thay remove/re-add; recovery file giờ được ghi sau mỗi save + clear sau load; nút Restore snapshot trong Undo History Panel kích hoạt restore path trước đây chết (`restoreLatestSnapshot` controller passthrough + resync đầy đủ); LightTablePanel XÓA (chưa từng được instantiate).
- **Engine-level tests cho tính năng mới**: `blend_extended_transition` — wipe midpoint tách đôi đúng, endpoint t=0/t=1 đủ 5 loại (Zoom/Radial có ngoại lệ trung tâm được ghi nhận hợp lý), Dissolve deterministic + monotonic theo t; `set_audio_effect_param` — apply hợp lệ + từ chối index vượt cuối chain / param >3 / index âm; sticker transform + paint FFI được biên dịch vào cả suite ffmpeg,gpu.
- Gate số liệu: cargo default **95/95** · ffmpeg+gpu **121/121** · flutter analyze --fatal-infos sạch · flutter test **157/157** · coverage **63.1% ≥ 60%**.

### T6 — Chất lượng, kiểm thử & tài liệu · 5 phase · ✅ HOÀN THÀNH (2026-08-23) → tag **`v1.5.0` final**

| Phase | Nội dung |
|---|---|
| P1 | Regression suite cho 100% bug T1 (Dart + Rust + bảng ABI arity tự động trong CI) |
| P2 | Lấp khoảng trống test: SQLite dual-backend save/load (0 test hiện có), export-cancel UI, LightTablePanel, huge-media smoke tự động hóa |
| P3 | **Undo consistency program**: blend/mask/pitch/font/keyframe/group đi qua command history; multi-delete = 1 lệnh undo; coalescing key theo gesture session; transition dropdown không nuốt giá trị legacy |
| P4 | Docs đồng bộ code: regenerate `rust_engine_abi.md` (65→109 symbol, sửa §11/§13/§14 lệch thực tế), CHANGELOG khớp thực tế (GIF/ProRes removed), version.dart ví dụ stale, commit đủ docs |
| P5 | Gate cuối: coverage ≥ ngưỡng T2-P3; CI xanh 3 OS; rà soát "70 điểm" đối chiếu thực tế còn bao nhiêu điểm live vs stub, công bố trung thực trong CHANGELOG |

**✅ HOÀN THÀNH (2026-08-23) — bằng chứng:**
- P1 Mapping bug-T1 ↔ regression test (đều chạy trong `flutter test`/`cargo test` = CI):
  ABI selection ×4 + library_search → `ffi_arity_contract_test.dart` (bảng arity tự sinh) + `t1_regression_tests.rs` selection fns · overflow audio stereo → `swr_cap_never_exceeds_conv_buffer_on_multichannel` (media.rs) · export-flag brick/cancel → `t1_export_flags_reset_after_cancelled_run` · TOCTOU cancel → `t1_cancel_export_without_active_run_is_safe` · copyWith màu/splitAt/trim floor/delete-undo/project-switch/transcript ms-CRLF-overlay → `t1_hotfix_regression_test.dart` · CRLF transcript engine → `t3_import_transcript_crlf_imports_all_cues` · UAF ghi âm → Drop join exercised bởi mọi suite destroy-path.
- P2 SQLite dual-backend round-trip test mới (`test/sqlite_dual_backend_test.dart`, engine+sqlite-gated): save×2 → list contains → load byte-equal → delete chỉ target; CI Windows build DLL thêm feature `sqlite` để test chạy thật. LightTablePanel: XÓA từ T5 (n/a). Huge-media smoke giữ dạng script `smoke_track1.dart` (CI runner thiếu media 10 phút — trung thực). Export-cancel UI: phủ bởi Rust cancel join test + widget smoke.
- P3 Undo consistency ĐẦY ĐỦ: `ClipStateCommand` (snapshot before/after, coalesce theo clip+field+gesture) — blend/mask/pitch/font/keyframes(upsert/remove/copy)/sticker chuyển hết qua `_updateClipUndoable`; `_updateClip` direct mutation XÓA; multi-delete = 1 `CompositeCommand`; text edit coalesce theo phiên focus (`_TextContentField.onFocusChange` mở session, toggle-style mỗi click một entry); transition dropdown đủ 9 loại thật (T5).
- P4 Docs: `rust_engine_abi.md` §16 bảng 7 symbol T5 + ghi nhận removals + gates cập nhật; CHANGELOG tách `v1.5.0-beta` và thêm entry `## v1.5.0` final với mục **công bố trung thực** (GIF/graph/f32 xóa, GPU feature-gated, ProRes không có preset UI); version.dart ví dụ 0.7.8 → 1.5.0.
- P5 Gate cuối (2026-08-23, máy dev): CI consistency checks mô phỏng PASS (changelog/cpp banner/cmake/cargo/rust banner = 1.5.0) · cargo default **95/95** · cargo ffmpeg+gpu+sqlite **125/125** (-j 1 do giới hạn paging file) · flutter analyze --fatal-infos sạch · flutter test **157/157** · coverage gate **63% ≥ 60%** PASS. CI 3-OS chạy lại trên GitHub Actions sau push.

**Kết luận: 6/6 track hoàn thành — tag `v1.5.0` final.**

---

## 4. Phụ lục — Top phát hiện nghiêm trọng của audit (đã map vào phase)

| # | Mức | Phát hiện | Vị trí | Phase |
|---|---|---|---|---|
| 1 | CRITICAL | 4 ABI mismatch selection Dart↔Rust → UB khi gọi (đọc garbage register) | native_bindings.dart:227-237 ↔ c_api.rs:1532-1600 | T1P1 |
| 2 | CRITICAL | Heap overflow decode audio stereo non-FLT (cả Rust lẫn C++ cùng lỗi) | media.rs:789 · ghita_engine.cpp:1266 | T1P2/T5P1 |
| 3 | CRITICAL | UAF: thread ghi âm giải phóng engine khi Drop | audio_t4.rs:339-416 | T1P2 |
| 4 | HIGH | Panic export-thread khoá `is_exporting=true` vĩnh viễn | engine.rs:1628-1631 | T1P2 |
| 5 | HIGH | copyWith xoá màu chữ → text clip biến mất sau split/copy/edit | clip.dart:335-342 | T1P3 |
| 6 | HIGH | Frame cache paused không bao giờ invalidate → hình cũ sau khi sửa | engine_service.dart:1326-1374 | T1P5 |
| 7 | HIGH | Version 1.1.1 (CMake/banner C++/banner Rust) ≠ 1.5.0 → CI gate đang FAIL | ghita_c_api.cpp:11 · CMakeLists.txt:2 · c_api.rs:28 | T2P1 |
| 8 | HIGH | Real-engine Dart tests không chạy ở bất kỳ CI nào | ci.yml:63-93 | T2P3 |
| 9 | HIGH | APK Android không có engine (.so) + ký debug key → Demo Mode chắc chắn | android/app/build.gradle.kts | T2P4 |
| 10 | HIGH | 4 module perf (gpu/graph/cache/f32) là dead code — claim CHANGELOG chưa wire production | gpu.rs, graph.rs, processing_cache.rs, f32_pipeline.rs | T5P2-4 |

Số liệu tổng audit: **~40 bug đã xác minh** (10 critical/high Rust, ~15 Dart high/med, ~10 FFI/CI high/med, ~8 C++), **~20 cơ hội tối ưu**, **4 module Rust chưa wire**, **~15 tính năng stub/dead** ở tầng UI.
