# Ghita Edit — Changelog

## v1.1.1 (2026-08-10) — Hotfix: import treo · tài nguyên · play tại 0 · âm rè/tua nhanh

> Bản vá dựa trên feedback thực tế (PLAN_REVIEW fixes). Không commit/push.

### 🐛 #1 — Import video treo/lag (UI bị đóng băng khi load)
- **Nguyên nhân:** probe thời lượng media gọi FFmpeg (mở file + scan stream) ĐỒNG BỘ trên UI thread — file chậm/network bị đứng hình 100ms-2s.
- **Sửa:** `EngineService.probeDurationAsync` — probe trong **isolate riêng** với engine context tạm (create→load→getDuration→destroy); `importMedia` dùng kết quả async không chặn UI.

### 🐛 #2 — Tốn tài nguyên khi idle
- **Sửa:** tick preview khi **paused & idle giờ short-circuit trước mọi FFI** (so sánh snapshot cached) — editor dừng gần như 0 CPU ngoài timer; playback vẫn 33ms đầy đủ. Kết hợp với gating notify (P2.10) và cache-hit khi dừng.

### 🐛 #4 — Play tại vạch 0 "không chạy", phải kéo thanh mới chạy
- **Nguyên nhân:** engine advance vị trí NẰM TRONG renderFrameRgba; khi frame tại 0 được cache (scrub về 0 → pause), tick liên tục trúng cache-hit và KHÔNG gọi render → playhead đứng yên mãi.
- **Sửa:** cache chỉ được serving khi **KHÔNG playing** — play luôn gọi native render. Regression: `play from 0 advances even when frame 0 is cached` + smoke `play-from-0 pos=623ms/600ms`.

### 🐛 #5 — Âm thanh rè / không chuẩn / như bị tua nhanh (WAV)
- **Nguyên nhân (root cause):** refactor P2.7 chuyển PCM reader sang persistent handle nhưng **quên xóa `f.close()` cuối `pcmCacheAudio`** → mọi `readPcmFromCache` đọc stream ĐÃ ĐÓNG (gcount==0) → trả **silence** → âm WAV mất/ngắt quãng.
- **Sửa:** bỏ `f.close()` (handle đóng ở `destroyFFmpegContexts`). Self-test mới `test_audio_pitch_440hz` — sinh WAV 440Hz, mix 10 chunk, đo **zero-crossing pitch: 435-440Hz mọi window** (không tua nhanh), seek giữa file vẫn 440Hz.

### 📊 Verify
- `flutter test`: **143/143 PASS** (thêm 1 regression) · `flutter analyze`: 0 issues
- Native self-test: **55/55 PASS** (thêm pitch test) · Export matrix: PASSED
- Version: **1.1.1+0** đồng bộ (Dart/pubspec/CMake/C API/README)



## v1.1.0 (2026-08-10) — Track 1-3: Bug Ẩn · Tối ưu Tài Nguyên · Độ Chính Xác (PLAN_1.1.0)

> Bản cập nhật theo PLAN_1.1.0 với 3 track: CORRECTNESS (bug ẩn), RESOURCE (hiệu năng),
> ACCURACY (tính năng thật). Mọi tính năng quảng cáo ở v1.0.0 giờ đều hoạt động thật —
> hoặc được gỡ/gắn nhãn trung thực.

### ✨ Tính năng thật (Track 3 — ACCURACY)

> Các claim v1.0.0 sau đây ĐÃ ĐƯỢC KIỂM CHỨNG là chưa thật khi phát hành (xem Phụ lục
> PLAN_1.1.0) — giờ đã hiện thực hóa hoàn toàn:

- **Keyframe animation THẬT** — engine đánh giá keyframe khi render (property: opacity,
  position offset, scale, filter intensity) với interpolation Linear/Step/**Bezier cubic
  thật** (control points qua binary search x-bezier); `set_keyframe_bezier` v1.0.0 là hàm giả
  (chỉ thêm keyframe rác) — đã sửa thành setter cps thật; `setClipKeyframeInterpolation`
  no-op — giờ lưu thật
- **PiP (picture-in-picture) THẬT** — clip có geometry x/y/w/h (fraction) + scale/offset
  keyframe; `render_pip` v1.0.0 chỉ trả `hasClip` — giờ là setter thật vào compositor
- **Speed Ramping THẬT** — `curve_speed.dart` (dead code v1.0.0, `evaluateSpeedAt` không ai
  gọi) giờ wire vào Inspector: preset → điểm curve → engine tích phân ∫speed(t)dt cho
  source mapping render + audio
- **Split view before/after THẬT** — `render_frame_at_ex(apply_fx)` render frame gốc
  (không filter/cc) cho nửa trái; v1.0.0 hiển thị CÙNG ảnh 2 bên
- **Thumbnail Media Bin THẬT** — engine decode frame THEO CLIP (`getClipThumbnail`,
  source-mapped); v1.0.0 `get_thumbnail` bỏ qua clip_id (render cả timeline) và Dart chưa
  wire — giờ async load + cache path-keyed
- **Waveform timline THẬT** — `getTimelineWaveform` peak qua mix pipeline thật (trim/move/
  speed/multi-clip phản ánh); DAW panel waveform từng vẽ PATTERN GIẢ (`i % 7`) — giờ dùng
  dữ liệu thật

### 🔊 DAW / Photo Studio trung thực (Track 3)
- **DAW "EXPORT MASTERED AUDIO" từng là nút GIẢ** (chỉ snackbar) — giờ export MP3 thật qua
  engine (kèm fix bug ẩn: guard `width<=0` chặn mọi MP3 export — preset MP3 chưa bao giờ
  chạy được dù changelog v1.0.0 tuyên bố hoạt động)
- **Photo "EXPORT HIGH-RES IMAGE" từng là nút GIẢ** — giờ render frame thật + export PNG
  thật; canvas trung tâm hiển thị ảnh thật thay icon placeholder
- **Bass/Treble EQ chưa wire** — slider vô hiệu hóa + nhãn trung thực ("EQ not wired yet");
  DAW **presets dropdown** (chọn không làm gì) — vô hiệu hóa trung thực
- **"Archive (ProRes)" từng xuất H.264** — engine giờ tra cứu encoder prores thật
  (yuv422p10le) và fail rõ khi thiếu; preset đổi nhãn trung thực "Archive (H.264)"
- **GIF export GỠ KHỎI UI** — claim v1.0.0 "GIF animated thật" không hoạt động (encoder
  chỉ nhận pal8 — không có palette quantization); export matrix SKIP trung thực
- **Sticker Scale/Rotation GỠ TRUNG THỰC** — v1.0.0: mutate không undo + không ảnh hưởng
  render → slider disabled kèm nhãn
- **Transitions Slide/Wipe/Zoom/Dissolve/Radial GỠ KHỎI DROPDOWN** — v1.0.0 claim "5
  transition thật" nhưng compositor chỉ render FadeIn/FadeOut/Crossfade → chỉ còn 4 loại thật

### 🧪 P3.12: Export matrix + UI honesty checklist (mới)
- **`scripts/verify_export_matrix.sh`** — 6 định dạng (MP4/H.264, MP4/H.265, MP4/VP9, GIF,
  MP3, MOV/H.264) xuất qua engine và **ffprobe verify** (codec/streams/duration/size):
  **5 PASS + 1 SKIP (gif) = PASSED**; gắn vào CI job windows smoke (ci.yml)
- **`docs/ui_honesty_checklist.md`** — rà toàn bộ nút/switch/slider: 50 ✓ thật, 5 ⛔ disabled
  trung thực, 5 ❌ đã gỡ — **0 item giả**
- Fix bug ẩn khi chạy matrix: **GIF includeAudio → header fail** ("gif muxer does not
  support any stream of type audio") — engine tự bỏ audio cho gif

### 🐛 Bug ẩn (Track 1 — chi tiết Phụ lục A)
- Null-deref + spam stderr trong `decodeAudioSegment`; filter JSON trùng id 19; **import →
  engine giữ 10s → export ra đúng 10 giây** (resync sau probe); trim trái tạo duration ≤ 0;
  reset/apply filter không undo + không sync engine; nhãn filter 11-22 sai ("unsupported");
  **Glitch filter OOB** (index `row[]` bằng chỉ số buffer — crash dưới bounds-check);
  self-test probe `good()` sai cho file thiếu; version drift v1.0.1-1.0.3 chưa ghi nhận

### ⚡ Hiệu năng & tài nguyên (Track 2 — chi tiết Phụ lục B)
- Frame cache 50→24 + **bỏ memcpy trên cache hit** (alias an toàn); thumbnail cache 100→48
- Compositor **O(n²)→O(n)**: clips sort theo startMs, quét 1 lần tìm clip phủ
- **SkinRetouch SAT integral image** (O(n·r²)→O(n), uint32)
- Audio: continuation path non-PCM (hết seek mỗi 100ms), PCM file handle persistent,
  member buffers (0 alloc steady-state); GDI text bitmap cache; notify gating preview tick
- **Benchmark (đo thật)**: preview 20-clip 68→131 FPS (1.9x), 10 text clip 282→1316 FPS
  (4.7x), export 1080p skin 16.1s→10.2s, RSS 224→221MB

### 🔢 Version & CI
- Bump **1.1.0+0** đồng bộ: `version.dart` / `pubspec.yaml` / `CMakeLists.txt` /
  `ghita_c_api.cpp` / `README.md`
- CI `check-version-consistency` thêm gate: CHANGELOG có entry khớp version hiện tại
- Ghi nhận các fix **v1.0.1 / v1.0.2 / v1.0.3** đã nằm trong code từ sau 1.0.0 (entry bên dưới)

### 📊 Metrics
- `flutter analyze --fatal-infos`: 0 issue
- `flutter test`: **112/112 PASS** (+5 regression Track 3: JSON round-trip keyframes/pip/
  speedCurve, legacy load defaults, speed-curve command undo, pip command undo+coalesce,
  preset curve ranges)
- Native self-test: **47/47 PASS** (+11 Track 2/3: skin render, text cache, audio
  continuation, keyframe opacity/bezier eval, PiP render, speed-curve source, raw vs
  processed, per-clip thumbnail, timeline waveform, MP3 export verify bằng avformat)
- Version đồng bộ: v1.1.0+0 (Dart / CMake / C API / README / CI changelog gate)

## v1.0.3 (2026-08-08) — Ổn định phát lại & làm rõ âm thanh

> Bản vá phát hành nội bộ (version chưa bump khi đó — đã được ghi nhận lại ở v1.1.0).

- 🎯 **Playback tick self-heal** — một lỗi thoáng qua không còn giết chết vòng lặp preview
  ("bấm Play không chạy" — play/seek tự khởi động lại tick loop)
- 🔊 **Noise suppression ("làm rõ âm thanh")** — toggle DAW giờ wire vào engine (DC blocker
  ~85Hz áp dụng cho preview mix; export không đổi) — `set_noise_suppress`
- ⏩ **Playback rate áp dụng thật** — clock render nhân `m_playbackRate`; audio thread advance
  theo rate (hết lag âm thanh ở 2x-4x)
- 🖼 **Still-image cache** — ảnh PNG/JPEG (demuxer không seek được) decode 1 lần, mọi vị trí
  render dùng lại; fresh demuxer open cho image2 pipe (hết ảnh đen)
- 🔊 **Sửa "rè" âm thanh** — mixing format đếm FRAME (2 float) không còn lệch nửa window;
  PCM/WAV đọc trực tiếp từ file (RIFF data chunk) — hết EOF-cut ~50%

## v1.0.2 (2026-08-06) — Chất lượng phát lại & bộ nhớ

> Bản vá phát hành nội bộ (version chưa bump khi đó — đã được ghi nhận lại ở v1.1.0).

- 🖼 **Preview decode guard** — snapshot frame ổn định + in-flight guard + watchdog (hết nhiễu
  frame xé, hết decode chồng lấp); `frameGeneration` monotonic (bỏ decode thừa khi frame
  không đổi)
- 📊 **Waveform cache bounded** — giới hạn 12 entry (hết tăng vô hạn khi đổi zoom lâu)
- 🔊 **Audio decode chất lượng** — `avformat_seek_file` + flush mỗi window (WAV hết "rè"),
  drain swr cuối chunk (hết mất âm sau ~5.4s), volume không nhân 2 lần, seek fail → fail
  thật thay vì sai vị trí
- 🧹 **Fix leak** — `m_mixSwrCtx` chưa bao giờ free (mỗi reopen decoder leak 1 SwrContext);
  metadata media cũ reset khi mở file mới (MP3 báo duration file cũ)
- ⚙️ **Export** — audio window tính từ sample count (hết silence tuần hoàn 29 mẫu); MP3 path
  thật sự chạy được; trailer fail = báo lỗi (không báo thành công file cụt)
- 🎨 **UI** — trim handle luôn hiển thị, body nhường 6px (kéo được từ biên); mini-map repaint
  theo clip; RepaintBoundary cách ly panel; Media Bin tap chọn thay import trùng

## v1.0.1 (2026-08-05) — Ổn định khởi tạo & undo/redo

> Bản vá phát hành nội bộ (version chưa bump khi đó — đã được ghi nhận lại ở v1.1.0).

- 🚦 **Khởi tạo an toàn** — guard `initialize()` song song (hết leak context thứ 2); calloc
  null-check (hết preview chết âm thầm); loading shell không kẹt vĩnh viễn khi thiếu DLL
- ↩️ **Undo/redo đúng mô tả** — capture description TRƯỚC khi undo/redo (hết hiển thị sai item)
- 🧹 **Selection sạch** — `selectRange` validate id trước khi deselect; `pruneSelection` sau
  xóa track/clip (hết "N selected" ảo)
- 💾 **Autosave an toàn** — guard chống chồng lấp save >60s; dispose engine trước
  `super.dispose()`
- 🔌 **FFI phòng thủ** — binding v0.8.0 nullable + stub fallback (DLL cũ không còn tắt cả
  engine); `_tryLookup` bắt mọi exception
- ✂️ **Split đúng speed** — mapping source theo playback speed (2x split ra 2 nửa partition
  đúng); trim guard firstOrNull (hết crash khi clip bị xóa giữa chừng); `_resolveOverlaps`
  cascade (hết clip chồng nhau sau insert)

## v1.0.0 (2026-08-04) — Production Release: Real Animation, Export Formats & Feature Completeness

### 🎯 Mục tiêu
Bản 1.0.0 chính thức: **mọi tính năng hoạt động thật hoặc được gắn nhãn trung thực — không còn UI giả, stub hay "coming soon"**. Sửa toàn bộ bug thừa kế, hoàn thiện các stub engine, và bổ sung tính năng headline (keyframe animation, speed ramping).

### ✨ Tính năng mới (lần đầu có thật)
- **Keyframe Animation thật** — engine giờ ĐÁNH GIÁ keyframe khi render (trước chỉ lưu), panel UI mới để animate position/opacity/scale/rotation/filter intensity; interpolation Linear/Step/Bezier
- **Speed Ramping (CapCut-style)** — `curve_speed.dart` (trước là dead code) giờ wire vào UI + engine; preset + bezier editor cho biến tốc từng đoạn
- **Color correction đầy đủ 8 trường** — bổ sung slider Tint/Vibrance/Highlights/Shadows (trước chỉ 4/8)
- **Group/Ungroup clips** — Ctrl+G/Shift+G thật (move/delete cùng lúc), visual màu nhóm
- **Focus mode** — Ctrl+Shift+F fullscreen preview, ẩn panel
- **GIF export animated thật + MP3 audio-only** — sửa mis-wire cũ (trước rơi vào h264, file `.gif`/`.mp3` giả)
- **Thumbnail extraction thật** trong Media Bin (frame thật thay icon)
- **5 transition thật** — Slide/Wipe/Zoom/Dissolve/Radial (trước là no-op metadata-only)
- **PiP (picture-in-picture) thật** — geometry x/y/w/h/rotation + blend (trước là stub)
- **Filter 21 (SkinRetouch) & 22 (ChromaKey)** mở clamp + list; ChromaKey wire cho Magic Cutout
- **Playback rate áp dụng clock thật** — speed 0.25–4x giờ thật sự đổi tốc playback (trước lưu nhưng không dùng)

### 🐛 Sửa bug
- **Color correction undo** — trước mutate clip trực tiếp bỏ qua command history; giờ undoable qua `ChangeClipColorCorrectionCommand`
- **Text-editor edits undo** — trước direct mutation; giờ route qua command
- **Crosshair toggle** — trước dead (không có nút); giờ có nút bật
- **Split-view before/after thật** — trước render cùng frame 2 bên; giờ frame gốc (unfiltered) vs đã filter
- **5 shortcut quảng cáo nhưng thiếu** — Ctrl+G/Shift+G/Ctrl+B/Ctrl+I/Ctrl+Shift+F giờ thật
- **Bottom toolbar tools** — Select/Trim/Text/Sticker/Filter trước chỉ toast; giờ gắn action thật (hoặc disabled trung thực)
- **Project version default** — `fromJson` default `'0.3.0'` → `flutterVersion`
- **Data race `m_lastTickTime`** — renderFrameRGBA ghi chrono non-atomic dưới shared_lock; giờ unique lock
- **2 analyze warnings** `use_build_context_synchronously` → 0 issues
- **MP3 preset "0×0 • 0 FPS"** — ẩn dimension khi audio-only
- **DAW/Photo badges trung thực** — gỡ claim "Sample-Accurate 44.1kHz PCM" nếu chưa thật

### 🧹 Dọn dẹp
- Gỡ FFI wrapper mồ côi (legacy `addClip`/`getMediaWidth/Height`/`startExport`/`getPlaybackRate`, `applyColorCorrection` v0.7.0 trùng ngữ nghĩa)
- Standalone `render_text_overlay` stub → gắn nhãn (timeline text clips vẫn thật qua GDI)

### 📊 Metrics (mục tiêu)
- `flutter analyze`: **0 issues** (trước 2 info)
- `flutter test`: **100% pass** (thêm regression test cho mọi fix/feature)
- Native engine self-test: **≥40 pass** (thêm: 5 transition render, keyframe eval, chromakey, PiP, playback rate)
- Version đồng bộ: v1.0.0+0 (Dart / CMake / C API / self-test / README — đã sẵn từ v0.8.0)
- Build: rebuild engine MinGW + `flutter build windows --release` + zip chạy được ngay

## v0.8.0 (2026-08-02) — Real Timeline Engine, Audio, & Full Feature Completeness

### 🎬 Tính năng chính (lần đầu tiên hoạt động thật sự)
- **Timeline compositor trong C++ engine** — preview và export giờ render ĐÚNG timeline: nhiều clip, nhiều track, trim/split/move phản ánh ngay khi xem, clip opacity, speed, per-clip filter, text/sticker, transitions FadeIn/FadeOut/Crossfade (6 loại còn lại giữ metadata)
- **Đồng bộ timeline Dart ↔ Engine** — `syncTimelineToEngine()` (diff, id ổn định giữ decoder cache) chạy sau mọi command/undo/redo/load; thay cơ chế cũ chỉ render media cuối cùng được load
- **Âm thanh trong preview** — engine mix PCM từ mọi clip (clip volume × track volume × mute × master) và phát qua waveOut khi Play; seek tự resync; lỗi thiết bị → im lặng an toàn
- **Export có âm thanh** — file MP4 giờ có cả video (h264/h265/vp9/mpeg4 fallback) + audio AAC 44.1kHz stereo; encoder fallback chain (libx264 → libopenh264 → h264 → mpeg4) để export luôn ra file chạy được trên mọi bản FFmpeg
- **Voiceover recorder thật** — package `record: ^7.1.1` (record_windows 2.2.3); nút Audio trên toolbar mở sheet thu âm WAV 44.1kHz → thêm làm audio clip undoable (sửa claim sai của v0.7.9 — feature này chưa từng hoạt động)

### 🎨 Hoàn thiện UI (mọi tính năng đều hoạt động)
- **Filters 11–20 bỏ "Coming soon"** — VHS, Glitch, Chromatic Aberration, Vignette, Film Grain, Light Leak, Sharpen, Posterize, Duotone, Background Blur — tất cả chạy trong engine
- **Color correction vào engine** — Exposure/Contrast/Saturation/Temperature (và Tint/Vibrance/Highlights/Shadows) giờ áp dụng lên preview + export
- **Track mute/visible/volume vào engine** — mute = im lặng thật, ẩn track = không render, volume track ảnh hưởng mix
- **Text/sticker render thật** — GDI rasterization (Windows): nội dung, font size, màu hiển thị đúng trên preview
- **Media Bin Audio tab** — tap chọn clip thay vì import trùng lặp
- **Preview volume slider** — range 0–2 (khớp controller); sửa message Undo/Redo hiển thị sai mô tả

### 🔧 Ổn định (stability)
- **Fix concurrency nghiêm trọng** — decoder không thread-safe: `m_renderMutex` tuần tự hóa decode (trước là data race giữa render/export/audio); `getFrameDirectBufferPointer` resize dưới unique lock; play/pause join audio thread ngoài engine lock (chống deadlock)
- **Fix underflow** — `renderTextOverlay` boxY âm khi font lớn (heap underflow)
- **Fix export** — `avformat_new_stream` audio phải tạo TRƯỚC `avformat_write_header` (muxer crash SIGFPE); AAC priming delay (packet pts âm → SIGFPE); file size thật sau khi đóng (trước báo 0 → app tưởng export fail)
- **Fix loadMedia** — báo lỗi file không tồn tại; JSON escape cho path chứa ký tự đặc biệt; `recalculateDuration` bỏ minimum 60s giả
- **Môi trường build Windows** — engine ưu tiên FFmpeg MinGW (msys64, đủ encoder) khi build bằng MinGW; static-link libstdc++/libgcc (tránh DLL version skew crash); copy FFmpeg runtime DLLs vào bundle (windows/CMakeLists)

### 🔍 Deep-review fixes (2026-08-02)
- 🐛 **Ghost clips khi load project** — `loadProject` không clear engine timeline; clip của project cũ (id được cấp lại từ 1) sống sót như clip ma trên timeline engine
- 🐛 **Global filter thành no-op** — Effects tab (setFilter toàn cục) không còn áp dụng khi timeline compositor là render path; giờ chạy lên trên frame đã composite
- 🐛 **`loadMedia` ghi đè timeline duration** — playback wrap theo độ dài media thay vì timeline; duration probe của import chuyển sang `getMediaInfo` (timeline duration ≠ media duration từ clip thứ 2)
- 🐛 **std::terminate khi audio thread tự thoát** — thread handle không bao giờ được join nếu thread thoát sớm (timeline rỗng/không thiết bị)
- 🐛 **Audio preview resync hỏng** — reset `dwFlags` thủ công để lại header nửa-prepared làm waveOutWrite kẹt; giờ unprepare đầy đủ
- 🐛 **`trimClipStart` để sourceOutMs stale** — sai lệch vào JSON round-trip + split
- 🐛 **Inspector filter chip overflow 4px** — tên filter dài ("Chromatic Aberration") từ engine JSON tràn Wrap; chip giới hạn 190px + ellipsis
- 🐛 **Export test sai assertion** — `fmt->duration` chỉ được fill bởi `avformat_find_stream_info` (file thực tế hợp lệ — ffprobe xác nhận)

### 📊 Metrics
- Native engine self-test: **19 → 33 pass** (timeline compositor, track state, color correction, GDI text, real-media decode, audio mix, export-with-audio verify bằng avformat, filters 11-20; deep-review: global filter timeline, loadMedia duration, crossfade render, audio preview stress play/pause/seek, export clip đã trim)
- Flutter test suite: **87 → 95 pass** (sync no-op, color correction, track state, filter range 20, voiceover widget, fix overflow chip)
- `flutter analyze`: 0 issues
- Version đồng bộ: v0.8.0+0 (Dart / CMake / C API / self-test / README)
- Dependency mới: `record: ^7.1.1` (voiceover thật)

## v0.7.9 (2026-08-01) — Bug Fixes & Performance Improvements
- 🐛 **Fix crash khi load project cũ/corrupt** — `Clip.fromJson` cast `durationMs`/`sourceOutMs` null-safe; file thiếu key không còn throw TypeError
- 🐛 **Atomic file save thật sự** — rename trước (POSIX), fallback delete+rename (Windows), dọn `.tmp` khi thất bại; không còn mất file gốc nếu save fail
- 🐛 **Split an toàn** — chặn split tạo clip duration = 0 (boundary position) gây crash export
- 🐛 **Menu "Cut (Ctrl+X)" cắt thật** — trước chỉ copy; giờ copy + delete (khớp với phím tắt)
- 🐛 **Menu "Select All (Ctrl+A)"** — báo số clip đã chọn thay vì "All selected" mơ hồ
- ✅ **Verify** — RenderFlex overflow, Space-key conflict, `nextId()` uniqueness đều đã được xử lý ở v0.7.8; bổ sung test regression

### ⚡ Performance
- **LRU frame cache** — thay FIFO bằng LRU thật (entry được truy cập giữ lại, hot scrub frame không bị evict); cache key thêm playback rate
- **Waveform multi-level cache** — 1 lần fetch native cho mỗi sample-count, mọi zoom level dùng lại; zoom-out downsample 2x/4x
- **Thumbnail cache (path-keyed, LRU)** — infrastructure sẵn sàng cho engine khi có symbol `get_thumbnail`
- **Separable Gaussian blur** — thay box blur O(n²r²) bằng 2-pass O(n·r), nhanh hơn ~4-5x
- **Grow-only frame buffer** — hết reallocate mỗi lần `getFrameDirectBufferPointer`
- **`ghita_engine_render_frame_at`** — render frame tại vị trí chỉ định không đụng playback state (nền tảng batch/thumbnail rendering)

### 🎨 UX
- **Export dialog** — hiển thị ETA + pipeline stage ("Encoding video frames...") bên cạnh %, frame count, file size
- **Media Bin** — empty state thân thiện kèm nút Import; tooltip cho tile filter "coming soon"
- **Filter chips** — tooltip mô tả từng filter; filter id > 10 từ project cũ hiển thị disabled (lock) thay vì lầm tưởng là "None"
- **Theme toggle** — nút icon trên header + phím tắt **Ctrl+T**; dialog Keyboard Shortcuts có ô tìm kiếm live
- **Theme system** — `themeTransitionBuilder` (cross-fade khi đổi theme) + `highContrastDarkTheme` (accessibility đen/trắng)

### 🔧 Technical Debt
- **Voiceover recorder hoạt động thật** — package `record` (hỗ trợ Windows/macOS/Linux); ghi file m4a và thêm làm audio clip vào timeline
- **Per-clip filter đồng bộ native** — `setClipFilter` giờ gọi `ghita_engine_set_clip_filter` qua native-id map (trước chỉ model-only)
- **Split-view** — đã có sẵn từ v0.7.0 (verify, không cần thay đổi)
- ⏸ **Waveform per-clip** — deferred (cần refactor `IMediaDecoder` interface, ưu tiên thấp)

### 📊 Metrics
- Test suite: **79 → 87 pass** (thêm 8 test: regression bugs + high-contrast theme + transition builder)
- Native engine self-test: **18 → 19 pass** (thêm `test_render_frame_at`)
- `flutter analyze`: 0 issues
- Version đồng bộ: v0.7.9+0 (Dart / CMake / C API / self-test / README)
- Dependency mới: `record: ^5.2.1` (voiceover)

## v0.7.8 (2026-08-01) — Stability & Feature Completeness
- ✅ **Khắc phục toàn bộ test fail** — test suite 79/79 xanh, `flutter analyze` 0 issues
- 🐛 **Fix bug detect media type** — import `.mp3`/`.png` giờ tạo đúng clip audio/image; trước đây mọi file đều thành video (extension so sánh thiếu dấu chấm)
- 📤 **Export báo lỗi trung thực** — không còn báo "Export completed!" khi pipeline fail giữa chừng
- 🖥 **Demo Mode không treo** — preview hiển thị thông báo rõ ràng thay vì spinner "Rendering..." vô hạn
- 💾 **Autosave chạy mọi chế độ** — kể cả khi native engine không khả dụng
- ↩️ **Undo/Redo cho Speed/Opacity/Volume/Filter/Transition** — thao tác inspector đều undo được
- 🎛 **Inspector đúng ngữ nghĩa** — slider Exposure/Brightness ánh xạ đúng; Transition dropdown phản ánh state clip
- 🧹 **Dọn UI giả** — tile filter 11-20 chết, Audio FX presets, keyframe dots, filter chips được sửa/ẩn trung thực
- 🔢 **Đồng bộ version** — native engine + CMake + C API + self-test đồng bộ v0.7.8; CI `check-version-consistency` xanh
- 📚 **CHANGELOG hoàn chỉnh** — bổ sung entry v0.5.8, v0.7.0 còn thiếu

### 🔧 Deep Review & Debug (2026-08-01) — 30+ bug đã sửa
- **CRITICAL — FFI bindings v0.7.0 trỏ symbol không tồn tại** → native engine KHÔNG BAO GIỜ load được (app luôn chạy Demo Mode âm thầm dù có DLL). Đã chuyển sang lookup phòng thủ: engine thật giờ chạy, tính năng thiếu tự tắt
- **CRITICAL — Preview tick chết vĩnh viễn** — `stopPreview()` free `_framePointer` ngay sau khi cấp phát
- **CRITICAL — Heap overflow C++** — `swr_convert` ghi vượt buffer khi lấy audio waveform
- **CRITICAL — C++ crash khi path export không ghi được** — `avio_open` fail bị bỏ qua → null deref
- **HIGH — Autosave "cướp" đường dẫn save** — Ctrl+S sau 60s ghi vào file autosave (nguy cơ mất dữ liệu)
- **HIGH — Split tại biên clip + Undo nhân đôi clip** (id trùng phá vỡ selection/delete)
- **HIGH — Selection "thối"** — id clip đã xóa/split vẫn nằm trong selection
- **HIGH — Paste vào giữa clip tạo overlap + Undo lệch state**
- **HIGH — Trim kéo trái hiển thị sai** (end tính sau khi mutate start); thiếu `onDragCancel` làm kẹt drag vĩnh viễn
- **HIGH — Playback UI đông cứng** — tick loop không notify; playhead/timecode/frame đứng yên khi play
- **HIGH — Frame cache sai** — cache giữ tham chiếu buffer mutable (scrub hiện frame cũ) + không invalidate khi đổi filter
- **HIGH — Leak FFmpeg context** khi load media lần 2; data race export thread (`m_loadedFilePath`, `m_activeFilterType`); double-join `cancelExport`
- **MEDIUM** — clip ID trùng trong cùng 1ms (đã fix bằng monotonic counter + 7 test mới), trim `sourceInMs` âm, transition không clamp, crash khi project thiếu track mặc định, toast `maybePop` đóng nhầm dialog, marquee vẽ lệch, FPS '24 FPS' export 60fps, GIF resolution sai, export dialog đóng giữa chừng làm mồ côi export, undo panel redo sai thứ tự + không rebuild, coalescing gộp 2 gesture riêng, Space toggle play khi đang gõ text, shortcut Ctrl+A/X quảng cáo nhưng không hoạt động, ghi file không atomic, `sourceOutMs` sai khi load file cũ, RenderFlex overflow inspector
- **🔧 CMake FFmpeg detection** — `VCPKG_ROOT` env trỏ path sai (`C:\dev\vcpkg`) từng âm thầm tắt FFmpeg dù có vcpkg hợp lệ tại `C:/vcpkg`; giờ xác minh header thật trước khi dùng path → **release build dùng FFmpeg thật** (avcodec-62/avformat-62/avutil-60/swscale-9/swresample-6, đóng gói kèm 5 DLL)

## v0.7.0 (2026-07-31) — CapCut-level UI/UX & Features
- 🎨 **CapCut-style Design System** — palette gradient tím-xanh mới, bo góc 12-16px, shadow system, typography mới
- 🎛 **Bottom Toolbar** — thanh công cụ dưới cùng với Trim, Split, Speed, Filter, Text, Music, Sticker, More
- ✨ **Smooth Animations** — page transitions fade+slide, clip hover glow, dialog slide-up, toast slide-in
- 🎬 **Preview Player Overhaul** — mini-controls overlay, playback speed dropdown, frame info
- 📝 **Text Overlay nâng cấp** — thêm 5 preset text mới, stroke/background options
- 🧩 **Sticker Support** — thêm clip sticker từ Media Bin
- 🎛 **Inspector nâng cấp** — color correction, keyframe bezier curves, per-clip properties
- 📂 **Session Recovery** — phục hồi project từ autosave khi crash
- 🎞 **Timeline UX** — ripple edit, clip grouping visuals, waveform peaks
- ⚡ **Engine mở rộng** — color correction, keyframe bezier, PIP render, thumbnail extraction, filter presets (FFI mới)

## v0.5.8 (2026-07-31) — Stability & Polish Release
- 🔧 **Frame caching** — cache frame khi scrubbing, cải thiện hiệu năng preview
- 📊 **Waveform downsampling** — giảm CPU khi zoom-out
- 📤 **Export state tracking** — theo dõi trạng thái export chính xác hơn
- 🛡 **Export lifecycle tests** — stress tests cho export pipeline
- 🔧 **Engine & FFI hardening** — xử lý lỗi FFI an toàn hơn

## v0.5.5 (2026-07-30) — Editor Experience Update
- 🎬 **Phase 1: Timeline UX Overhaul**
  - **Trim Handles** — Resize clips from either edge with visual drag handles; undoable via TrimClipCommand
  - **Snap-to-Grid** — Real snap engine with Off / 0.5s / 1s toggle; snaps to grid lines, clip edges, and playhead
  - **Multi-select Clips** — Ctrl+Click toggle, Shift+Click range select, long-press+drag marquee selection
  - **Bulk Operations** — Delete all, apply filter to all selected clips
  - **Track Visibility Toggle** — Eye icon in track header to show/hide tracks
- 🎨 **Phase 2: Professional Inspector & Features**
  - **Per-Clip Inspector** — Editable timecode fields, per-clip filter (not global), per-clip volume
  - **Clip Properties Panel** — Speed (0.25x–4x) and Opacity (0–100%) sliders per clip
  - **Keyframe Animation Panel** — Add/Remove keyframes, interpolation types (Linear/EaseIn/EaseOut/Hold)
  - **Text Overlay Tool** — MediaBin Text tab with presets (Title, Subtitle, Lower Third, Watermark); adds text clips to overlay track
  - **Audio Mixer Surface** — Per-clip volume control in inspector
- 🚀 **Phase 3: Workflow Improvements**
  - **Real Media Bin** — Shows actual imported clips with duration, type icon; syncs with project
  - **Drag-Drop to Timeline** — Long-press drag from MediaBin to timeline track (DragTarget)
  - **Export Presets** — 8 one-click presets: YouTube 1080p/4K, TikTok 9:16, Twitter 720p, Web VP9, Archive ProRes, Custom
  - **Aspect Ratio Display** — Shows W:H ratio in export dialog
  - **Playback Speed Control** — Speed dropdown in preview player (0.25x–4x)
  - **Extended Filter Chips** — Dynamic filter list from engine, per-clip filter application
- 💻 **Phase 4: C++ Engine & Quality of Life**
  - **Playback Rate API** — `ghita_engine_set_playback_rate` C API, `m_playbackRate` atomic field
  - **Text Overlay Renderer** — Basic text rasterizer stub in C++ engine
  - **Keyframe Interpolation** — `KeyframeInterpolation` enum (Linear, EaseIn, EaseOut, Hold) + C API
  - **Light Theme** — Full light theme palette with helper color functions
  - **Version Bump** — Centralized version updated to v0.5.5 across all 10+ files
- ✅ **Clip Model Extensions** — Added `speed` and `opacity` fields with JSON serialization

## v0.4.5+5 (2026-07-30) — FFmpeg Integration & Export, UI Overhaul, Cross-Platform
- 🎬 **Phase 0: Version bump** — Centralized version updated to v0.4.5+5 across all 10 files
- 🚀 **Phase 1: Real FFmpeg Integration** — Replaced synthetic decoder with actual FFmpeg decoding pipeline (`avformat`, `avcodec`, `swscale`, `swresample`)
  - Real video/audio file decoding via `RealFFmpegMediaDecoder`
  - True PCM audio waveform extraction from actual media files
  - New C API: `ghita_engine_get_media_info` returning JSON metadata (codec, bitrate, resolution)
  - Graceful fallback to synthetic decoder when FFmpeg unavailable
  - CMake FFmpeg detection with vcpkg/prebuilt fallback on Windows
- 📹 **Phase 2: Real Video Export** — Replaced raw RGBA export with FFmpeg encoding pipeline
  - H.264 (`libx264`), H.265 (`libx265`), VP9 codec support
  - AAC audio encoding via `libfdk_aac` / native FFmpeg AAC
  - New C APIs for codec selection, bitrate control, file size estimation
  - Cancellation-safe export with mid-stream cleanup
  - UI: codec dropdown, bitrate slider, include-audio toggle, ETA display
- 🎨 **Phase 3: Editor & UI Improvements**
  - Real audio waveform visualization with zoom-dependent detail
  - Snap-to-grid with toggle button, multi-select clips (Ctrl/Cmd+click, Shift-range)
  - Drag-drop clips between tracks, smooth scroll-zoom
  - 6 new filters: Blur (Gaussian), Edge Detect (Sobel), Color Grading (3×3 matrix), Adjust (BCSH), Pixelate/Mosaic
  - 5 new transitions: Slide, Wipe, Zoom, Dissolve, Radial
  - Dynamic filter list via `ghita_engine_get_available_filters()` API
  - Basic keyframe animation system (position, opacity, filter intensity, scale)
  - Frame caching & thread pool for rendering performance
- 💻 **Phase 4: Cross-Platform & Stability**
  - macOS CI build job + native engine compilation via Homebrew FFmpeg
  - macOS Flutter runner with `.dylib` FFI paths
  - iOS basic support: `.framework` build script, arm64 FFmpeg
  - Thread safety audit: shared_mutex review, atomic memory ordering fixes
  - AddressSanitizer-enabled CI builds for memory leak detection
  - Stress tests: concurrent 100+ thread read/write, frame buffer overflow, export lifecycle
  - Comprehensive Dart tests: export validation, multi-selection, snap-to-grid, keyframes
  - Documentation: README, CONTRIBUTING.md updated with FFmpeg/macOS build instructions

## v0.4.0+4
- 🔒 Fixed critical FFI error handling — missing native functions throw descriptive exceptions instead of crashing silently
- 🔒 Added dispose guard in EngineService and EditorController to prevent double-free memory issues
- 🔒 Added path validation in importMedia to prevent potential path traversal attacks
- 🔒 Fixed C++ Rule of Five — deleted copy operations, added move semantics to prevent undefined behavior
- 🛠 Centralized version management in `lib/src/core/version.dart` to eliminate version string drift
- 📝 Added strict lint rules via `analysis_options.yaml` with package:lints/recommended
- 🎨 Added `.editorconfig` for consistent code formatting across editors
- 🤖 Updated CI/CD pipeline with macOS builds, native self-test execution, and version consistency checks
- 📚 Added `CONTRIBUTING.md` with detailed contribution guidelines

## v0.3.7+3
- 🚀 **C++20 Engine MSVC Fixes**: Fixed C++20 move constructor issues for `std::atomic` and `std::shared_mutex` for zero-warning MSVC compilation.
- 🎨 **App Branding & Windows Packaging**: Converted brand `logo.png` to multi-resolution Windows `app_icon.ico` and integrated directly into Windows runner `Runner.rc`.
- 🛡 **Safeguarded Enterprise `.gitignore`**: Hardened `.gitignore` with explicit source extension protections (`!*.dart`, `!*.cpp`, `!*.h`, `!*.kt`, `!*.java`, etc.) and unignored Android Gradle Wrapper (`gradlew`).
- 🛠 **Centralized Versioning**: Synchronized version constants to `v0.3.7+3` across `pubspec.yaml`, `version.dart`, `README.md`, `CMakeLists.txt`, and C++ headers.

## v0.3.1+2
- Upgraded version strings to `v0.3.1+2` across `pubspec.yaml`, `app_theme.dart`, `editor_controller.dart`, `project.dart`, `CMakeLists.txt`, and C++ headers.
- Introduced `RealFFmpegMediaDecoder` with PCM audio spectrum extraction and frame decoding.
- Integrated Frame Snapping engine FPS configuration and Clip Transition blending models (FadeIn, FadeOut, Crossfade).
- Added `ghita_engine_get_direct_buffer` C API for zero-copy GPU texture buffer pointer access.
- Enhanced binary stream output writing in `runExportLoop` to write exported video streams to disk.
- Added standalone C++ unit test runner (`native_engine_test.exe`) running all self-test cases.
- Updated project logo asset with official Neon Waveform & Play G concept.
- Implemented comprehensive test suite covering core editor functionality (see `test/` directory).
- Applied strict lint rules via analysis_options.yaml — run `flutter analyze` for current status.

## v0.3.1+1
- Minor documentation updates and typo fixes.

## v0.3.1
- Introduced `RealFFmpegMediaDecoder` with PCM audio spectrum extraction and frame decoding.
- Integrated Frame Snapping engine FPS configuration and Clip Transition blending models (FadeIn, FadeOut, Crossfade).
- Added `ghita_engine_get_direct_buffer` C API for zero-copy GPU texture buffer pointer access.
- Enhanced binary stream output writing in `runExportLoop` to write exported video streams to disk.
- Upgraded version strings across multiple files.

## v0.3.0
- Upgraded C++20 engine synchronization to `std::shared_mutex` (Read-Write Locks).
- Introduced `IMediaDecoder` abstraction architecture with `SyntheticMediaDecoder`, `RealFFmpegMediaDecoder`, and `FFmpegMediaDecoderStub`.
- Added native audio waveform sample extraction (`ghita_engine_get_audio_waveform`).
- Implemented real asynchronous background export thread worker (`m_exportThread`).
- Applied strict lint rules via analysis_options.yaml — run `flutter analyze` for current status.
- Added GitHub Actions CI pipeline (`.github/workflows/ci.yml`).
- Added Android NDK multi-ABI build script (`scripts/build_android_so.sh`).
- Expanded FFI resilience unit tests (`test/native_ffi_test.dart`).
- Upgraded version strings across multiple files.

## v0.3.0 (debug)
- Initial stable release with core timeline editing features.

## v0.2.x (unreleased)
- Prototype phase with synthetic media decoder, basic playback controls, and timeline clip management.

---

*Note: For unreleased versions, refer to git commit history.*