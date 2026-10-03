# Changelog — Ghita Edit

## v1.5.5-beta2 (2026-10-01 — mốc 3, mốc GỘP beta2+beta3)

> **Trọng tâm mốc:** rust hóa hoàn chỉnh + ổn định hóa toàn bộ — chỉ sửa + đo,
> KHÔNG thêm tính năng. Mọi con số là kết quả đo, chi tiết tại
> `docs/perf_v1.5.5_beta2.md`.

### T5 — Flake parity đã LỘC NGUỒN (pre-existing từ trước demo)
- `engine_compare` real_timeline@* lệch ~1/9 run: **oracle C++ là outlier,
  engine Rust sạch** — chứng minh bằng 3 phép chứng thực khi failure còn sống
  (self-consistency trong context, fresh-context replay, direct decode):
  fresh C++ context khớp byte-identical với Rust, còn context C++ đầu tiên
  trong scenario ra khung lân cận một cách xác định. Hồ sơ đầy đủ:
  `docs/flake_investigation.md`.
- Harness tự khử nhiễu có kiểm soát: khi bằng chứng chỉ ra C++ outlier,
  thay oracle bằng fresh-C++ (parity 2 engine vẫn được kiểm ở trạng thái
  sạch) + in cảnh báo. **Không nới tolerance** — mọi trường hợp nghi Rust
  vẫn FAIL như cũ.

### T1 — C++ engine RỜI KHỎI build sản phẩm
- `windows/CMakeLists.txt`: `GHITA_BUILD_CPP_ENGINE=OFF` mặc định — flutter
  build không còn build/ghi đè DLL C++ lên DLL Rust (nguyên nhân của
  "LUÔN phải chạy stage_windows_release.sh" — script vẫn giữ để stage DLL
  Rust + FFmpeg). C++ chỉ còn là oracle parity build riêng
  (`scripts/build_cpp_engine.sh`).
- **Audit ABI 100%:** 116 symbol export / 110 Dart lookup — 110/110 resolve,
  0 thiếu; 6 symbol harness-only được ghi rõ. 2 test chặn mới: Rust quét
  source (đổi/xóa/thêm symbol nào không có trong doc là fail) + Dart quét
  mọi lookup FFI (đánh máy bị `_tryLookup` nuốt sẽ fail loé thay vì fallback
  câm). Audio audit: 0 waveOut trong Rust engine; 3 feature windows-sys đều
  có nơi dùng.
- **Memory audit:** stress 240 vòng create→decode→render→destroy + 100 vòng
  upsert/remove — working set 26.8 → 43.7 MB (**Δ16.8 MB**, trần 150 MB).

### T2 — Export: fix + stress (bug thật tìm ra bởi chính stress test)
- **ghita_cli export/batch export TRÊN TIMELINE RỖNG** — cả lệnh `export`
  lẫn `batch` đều start_export ngay sau init không hề dựng timeline → mọi
  file xuất ra 0 byte. Fix: `export` parse project JSON thật + upsert từng
  clip đúng mapping của app (text/sticker skip có cảnh báo); `batch` load
  media + upsert full-length; cả hai **fail-loud** (exit 1) thay vì báo
  thành công với file rỗng. Verified: 12-clip project → MP4 1.3 MB; batch
  4 format.
- GIF kích thước lớn thành test cố định (640×480 + 1920×1080, ffprobe
  verify codec/size/frame). ProRes 4444 round-trip: assert **profile 4444**
  (không phải XQ); lưu ý FFmpeg 8 decoder báo yuv444p12le cho family 4444
  (10-bit data trong container 12-bit) — không phải bug engine.
- **DLL cũ trên PATH che DLL repo:** bản cài đặt trong
  `AppData\Local\Programs\Ghita Edit` nằm trên PATH + candidate đầu của
  bindings là tên trần `ghita_engine.dll` → flutter test nạp phải DLL CŨ
  (thiếu sqlite/blend/bookmark). Fix thứ tự candidate: exe-dir trước, tên
  trần sau cùng; bỏ hẳn oracle C++ khỏi danh sách.
- Test sqlite cũ kỳ vọng **1 = success** trong khi engine trả **0** — test
  chưa từng chạy thật (luôn skip vì DLL cũ). Sửa + thêm test SQLite ×50
  vòng byte-identical; test *không* free pointer trả về (thread-local buffer
  của Rust — free bằng allocator Dart làm hỏng heap).

### T3 — Ổn định hóa + rút cờ
- ProRes HQ **rút cờ Beta** (matrix/CI verify mọi run từ v1.5.0); ProRes 4444
  giữ cờ (mới nhất, nhánh ghi alpha chưa test); panel Beta Tools giữ (GPU
  toggle còn phụ thuộc availability).
- Gates: flutter analyze 0 lỗi · flutter test **166/166** · cargo test
  (ffmpeg+sqlite+parallel) **155/155** · parity 6/6 run liên tiếp · smoke
  test PASSED · export matrix 10/10 PASS 0 skip.

### T4 — Profiling (docs/perf_v1.5.5_beta2.md)
- Export 1080p30 timeline 26 s: **25.3 s ≈ 1.0× realtime**. Native init
  0.00 ms; cache hit ~0.67; filter vector hóa 1.09–1.18×; rayon 2.4–3.0×.
- 6/6 target định lượng cho final đã đạt trước hạn.

## v1.5.5-beta1 (2026-09-27 — mốc 2, commit f3c04ce)

> **Trọng tâm mốc:** lấp khoản trống engine cuối cùng (GIF export thật),
> polish B1–B3, tối ưu **đo được bằng số**. Mọi con số dưới đây là kết quả
> đo trên máy, không phải ước lượng.

### T2 — B4 GIF export thật (đã bị cắt ở v1.0.0 vì "GIF animated thật" không bao giờ chạy)
- Module mới `gif_quant.rs`: median-cut trên histogram 5-bit/kênh + LUT
  nearest-color 15-bit + dithering Floyd–Steinberg (7 unit test).
- Engine: encoder `pix_fmt` đổi BGRA → **PAL8** (libavcodec GIF chỉ nhận PAL8 —
  đây là lý do `avcodec_open2` fail và mọi file GIF từng ra 0 byte); bỏ
  swscale, tự quantize RGBA→index; palette dựng từ 5 probe frame rải dọc
  timeline (không chỉ frame 0); muxer option `loop=0` (chạy vô hạn).
- **Bug thật tìm ra khi verify:** palette plane phải là **BGRA** — bản RGBA
  làm hoán đổi R↔B mọi màu (so bằng cách decode GIF lấy màu thanh màu nguồn:
  `f2 10 04` → sau fix `f2 10 03`, lệch đúng 1/255 do lượng tử hóa).
- Export matrix: `gif` **SKIP → PASS**. GIF thật: 160×120, 12 khung, 5.2 KB.

### T1 — Tối ưu thuật toán (đo trước/sau, byte-equal)
- Grayscale/sepia/invert viết dạng `chunks_exact_mut(4)` để auto-vectorize:
  **1.09× / 1.18× / 1.09×** (1920×1080, đo cùng process). Byte-equal được chứng
  minh bằng 3 test so với thân vòng lặp index gốc của v1.5.0 (Rust không có
  fast-math nên lane SIMD cho kết quả giống hệt) + `engine_compare` vẫn
  max_diff=0 với C++.
- **Tile rayon "adaptive" — đo rồi HOÀN NGUYÊN:** giả thuyết "4K với tile 32
  hàng thì 68 job, tăng band sẽ giảm overhead" **sai** — A/B 3840×2160:
  tile 32 → 2.79×/2.98×, tile 96 → 2.55×. Giữ tile 32, bổ sung test
  benchmark 4K để giữ việc này đo được thay vì giả định.
- Graph thêm node **Exposure (3)** và **Vibrance (4)** — chain rỗng vẫn no-op
  nên parity không đổi (test `graph_exposure_and_vibrance_nodes_render`).

### T3 — Polish B1–B3
- GPU toggle nhớ qua phiên (shared_preferences) + hotkey **Ctrl+Shift+B** mở
  panel Beta.
- Badge **"GPU ACTIVE +N"** dựa trên delta `gpu_frames` thật (bằng chứng GPU
  thực sự dispatch), không chỉ trạng thái bật/tắt.
- **ProRes 4444** (alpha, yuv444p12le) — engine chọn pix format theo codec
  string, `prores_ks` tự suy profile 4. ffprobe xác nhận `yuv444p12le`; 422 HQ
  vẫn `yuv422p10le`.
- Graph: **kéo handle để đổi thứ tự node** (thứ tự ảnh hưởng kết quả) +
  copy/paste chain giữa các clip (clipboard trong controller, sống qua các
  lần mở/đóng panel).

### T4 — Hiệu năng (đo, không giả định)
- Paused-scrub cache chuyển từ 48 entries → **budget 96 MB theo byte**:
  scrub 3 s ngược–xuôi (90 vị trí × 3 lượt) đo **36% → 67%** hit rate.
  Frame 4K tự giới hạn còn vài entries thay vì giữ hàng trăm MB.
- **Cold-start: đo thì không cần sửa** — native `create`+`init` = **0.00 ms**
  (trung bình 5 lần). Lazy-init/defer panel sẽ không mua được gì đo được, nên
  KHÔNG thêm độ phức tạp vô ích.

### Bugs cũ (pre-existing) tìm ra khi làm mốc này
1. `verify_export_matrix.sh` **từ chối `--out`** — CI từ v1.5.0 truyền option
   đó, script exit 2 và job nuốt lỗi ⇒ **matrix chưa từng thực sự chạy trong
   CI**. Đã thêm option + smoke vẫn xanh.
2. Check kênh AAC trong script verify hardcode sai thứ tự cột ffprobe
   (`stream,<n>,<codec>,<type>`) trong khi bản này trả `stream,<codec>,<type>,<n>`
   ⇒ aac_51/71 fail oan dù file đúng. Đã chấp nhận cả hai thứ tự.

### Kết quả gates (local, 2026-10-27)
- `flutter analyze` 0 lỗi · `flutter test` **161 pass, 1 skip**.
- `cargo test`: **150** (ffmpeg,parallel,sqlite) · **152**
  (ffmpeg,gpu,sqlite,parallel) · **121** (gpu) — 0 fail.
- `run_engine_smoke_test.sh` **PASSED** (log clean) ·
  `verify_export_matrix.sh` **10 PASS / 0 SKIP / 0 FAIL** (thêm gif +
  prores4444).
- `engine_compare`: parity pass, **nhưng phát hiện flake có sẵn** — xem mục
  dưới.

### Vòng review/debug sau khi build (2026-10-28)
- **Bền vững GIF ở kích thước thật:** 640×480 / 20 fps → 116 khung, 5.8 s,
  36.5 KB, 681 ms; soi khung giữa bằng ffmpeg: đủ 8 thanh màu đúng thứ tự +
  vòng tròn + dải gradient (palette 256 màu giữ được cấu trúc màu).
- **Test mới (giữ để chống hồi quy):**
  `export_and_preview_render_concurrently_is_safe` (app render preview khi
  export chạy nền — kịch bản thật của người dùng) và
  `concurrent_render_stress_does_not_corrupt_later_frames` (4 luồng × 20
  render như harness: engine sau stress vẫn render **giống hệt** engine sạch).
- **Ba công cụ chẩn đoán thêm vào `tool/`:** `flake_repro.dart` (tái tạo
  đúng kịch bản media của harness, có cờ `--stress/--no-export/--no-mix`),
  `parity_flake_probe.dart` (solo vs xen kẽ), `gif_export_probe.dart`
  (GIF kích thước lớn + đo thời gian).
- `engine_compare` có bộ dò flake opt-in: `GHITA_PARITY_REPEAT=1` chạy media
  scenario 2 lần và in `run1/run2` để biết mismatch có tái lập không (mặc
  định 1 lần để không nhân đôi thời gian CI).

### ⚠️ Flake có sẵn trong `engine_compare` (không phải do mốc này)
- `real_timeline@*` đôi khi lệch `max_diff=255` (~50% pixel). Đo lại trên
  **bản đã commit (v1.5.5-demo)**: fail **1/6 lần** ⇒ tồn tại từ trước.
- Probe cô lập (`tool/parity_flake_probe.dart`): mỗi engine chạy riêng **tất
  định 12/12 run**; hai engine xen kẽ trong cùng process **0/20 lệch**. Vậy
  race chỉ nổi trong chuỗi kịch bản đầy đủ của harness (có export + mix).
- **Loại trừ có bằng chứng:** mỗi engine tất định (20 vòng Dart không khác
  biệt; test Rust chứng minh engine sau stress 4 luồng render y hệt engine
  sạch); kịch bản media tái tạo trong Dart: **0/20 lệch**; có thêm bước
  synthetic trước đó: 0/12; 4 harness chạy song song (tải cao): 4/4 PASS;
  export+preview đồng thời: test Rust PASS. Không có decoder cache static ở
  C++; thread audio chỉ start khi `play()` (harness không gọi).
- Kết luận: cần đúng bối cảnh process của harness và phụ thuộc thời gian —
  chưa localize được. Đưa vào hàng đợi mốc 3 (T5); **không nới tolerance
  để làm xanh giả**, và CI hiện vẫn có bước dò opt-in ở trên.

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
