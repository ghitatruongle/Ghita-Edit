# Kế hoạch v1.5.5 — 5 mốc × 6 track

> Trạng thái: DỰ THẢO chờ duyệt. Tạo 2026-08-28, tái cấu trúc mốc × track
> 2026-08-30. Nền: v1.5.0 final (main = `a1e33e8`, Rust engine drop-in parity
> 44/44, rayon 5.27x, wgpu/FFmpeg/SQLite feature-gated).

## Định nghĩa — Mốc / Track / Phase

- **Mốc (milestone)** = một bản phát hành có version riêng (5 mốc: demo →
  beta1 → beta2 → beta3 → final). Mỗi mốc là 1 chu kỳ khép kín: code → gates
  → build + stage DLL → commit local → **hỏi duyệt** → tag/release.
- **Track (T1–T6)** = luồng công việc xuyên suốt, kế thừa convention
  T1–T6 của v1.5.0. Mỗi mốc kích hoạt **n track** (tùy trọng tâm giai đoạn);
  track không ghi trong mốc = cố ý đóng băng, không code mới.
- **Phase (P1, P2…)** = các bước tuần tự bên trong một track của một mốc
  (m phase/track). Ký hiệu `T{k}.P{m}` để điểm danh tiến độ, ví dụ
  `T3.P2` = phase 2 của track UI trong mốc đang chạy.

## Ma trận tổng quan — mốc × track

| Mốc | T1 Rust hóa | T2 Media/Export | T3 Beta UI | T4 Hiệu năng | T5 Chất lượng | T6 Release |
|---|---|---|---|---|---|---|
| **demo** | nhẹ: rayon + 1–2 Dart loop | – | B1–B3 | – | gates cơ bản | suffix + cycle |
| **beta1** | SIMD filter nóng | B4 GIF export | polish B1–B3 | cache + startup | benchmark số liệu | cycle |
| **beta2** | 100% symbol + audio | fix export bugs | fix B1–B4 | – | test debt | cycle |
| **beta3** | fix leak FFI/Rust | stress export | ổn định hóa B1–B4 | profiling full | regression matrix | docs draft |
| **final** | ❄️ freeze | ❄️ freeze | ❄️ freeze | tuning cuối (nếu RC bắt được) | RC verify máy sạch | CHANGELOG + tag |

Quy tắc freeze: ❄️ = chỉ sửa bug chặn release nếu phát hiện, không thêm gì.

## Định nghĩa 6 track

- **T1 — Rust hóa & Engine:** mọi việc chuyển/hoàn thiện code native sang Rust
  (feature gates, port Dart loop, SIMD, độ phủ symbol, audio/GDI).
- **T2 — Media & Export:** GIF export, ProRes UI path, stress export matrix.
- **T3 — Tính năng Beta (UI):** B1 GPU toggle, B2 ProRes preset, B3 graph
  pipeline, B4 (nằm ở T2 nhưng UI bật qua đây), badge "Beta" + on/off.
- **T4 — Hiệu năng & Tài nguyên:** cache LRU, cold-start, memory leak, profiling.
- **T5 — Chất lượng & Kiểm thử:** flutter analyze/test, cargo test,
  `engine_compare` parity, regression matrix, bug sweep.
- **T6 — Release & Tài liệu:** version suffix/bump, stage DLL, installer,
  CHANGELOG trung thực, tag/release (luôn hỏi duyệt trước).

---

## Mốc 1 — v1.5.5-demo (n = 4 track: T1, T3, T5, T6)

**Mục tiêu:** người dùng thử được beta thật, có badge + nút bật/tắt; không phá
tính năng ổn định.

**T1 — Rust hóa nhẹ**
- T1.P1: bật feature `parallel` (rayon) mặc định cho build release Windows.
- T1.P2: kiểm kê Dart-side pixel loop (`engine_service.dart`,
  `preview_player.dart`…) → port 1–2 loop nóng nhất sang FFI Rust.

**T3 — Beta features B1–B3**
- T3.P1: B1 GPU compositor toggle (wgpu runtime CPU/GPU switch, mặc định off;
  scope đúng 3 filter đã parity: Grayscale/Sepia/Invert, còn lại fallback CPU).
- T3.P2: B2 ProRes preset trong Export dialog (engine đã có yuv422p10le).
- T3.P3: B3 graph pipeline wire THẬT tới export path: node
  brightness/contrast/saturation, chain được, panel riêng — không dead code.

**T5 — Gates cơ bản**
- T5.P1: flutter analyze 0 lỗi, flutter test + cargo test xanh.
- T5.P2: `engine_compare` parity nếu T1 đụng engine.

**T6 — Release cycle**
- T6.P1: thêm `kVersionSuffix` vào `version.dart` (CI gate giữ numeric-only);
  bump 1.5.5 demo qua build_runner `--release` + mirror `Cargo.toml`.
- T6.P2: build Windows + `scripts/stage_windows_release.sh`, verify máy sạch
  (PATH tước msys64, Demo Mode chạy được).
- T6.P3: commit local → **hỏi duyệt** → tag + release.

Kích thước: **M** — rủi ro thấp nhất trong 5 mốc.

---

## Mốc 2 — v1.5.5-beta1 (n = 5 track: T1, T2, T3, T4, T6)

**Mục tiêu:** beta features hoàn thiện hơn + tăng tốc đo được bằng số.

**T1 — Tối ưu thuật toán**
- T1.P1: auto-vectorize/SIMD filter nóng (grayscale/sepia/invert/blur).
- T1.P2: tile size rayon adaptive theo kích thước ảnh.

**T2 — B4 GIF export thật**
- T2.P1: palette quantization (median-cut hoặc neuquant) + dithering
  Floyd–Steinberg trong Rust, triệt tiêu limitation pal8 cũ.

**T3 — Polish B1–B3**
- T3.P1: UX/hotkey/lưu preset/edge cases theo feedback demo.

**T4 — Hiệu năng ứng dụng**
- T4.P1: `processing_cache` LRU — đo hit-rate, chỉnh capacity + dirty propagation.
- T4.P2: giảm cold-start (lazy init engine, defer panel phụ).
- T4.P3: audit zero-copy FFI buffer (tránh copy Uint8List qua lại).

**T6 — Release cycle** (P1 bump → P2 build/stage → P3 commit/hỏi duyệt)
- Kèm benchmark trước/sau bằng `tools/engine_compare`, ghi số liệu vào
  CHANGELOG (kiểu ghi 5.27x của T1 v1.5.0).

Kích thước: **M–L**.

---

## Mốc 3 — v1.5.5-beta2 (n = 5 track: T1, T2, T3, T5, T6)

**Mục tiêu:** sửa lỗi + rust hóa HOÀN CHỈNH các mục cần thiết.

**T1 — Rust hóa hoàn chỉnh**
- T1.P1: bảng đối chiếu C++ ↔ Rust đạt 100% symbol Flutter thực gọi
  (cập nhật `docs/rust_engine_abi.md`).
- T1.P2: audio path toàn cpal/Rust, bỏ hẳn waveOut cũ; port nốt
  GDI/fallback còn thiếu; C++ engine chỉ còn là parity baseline trong repo.

**T2 — Fix export**
- T2.P1: sửa bug export phát hiện từ demo/beta1 (GIF, ProRes, matrix).

**T3 — Fix B1–B4**
- T3.P1: bug sweep theo telemetry/log/crash; P0 (crash, hỏng dữ liệu) trước.

**T5 — Test debt**
- T5.P1: dọn flaky test, thêm test cho từng beta feature (round-trip GIF,
  ProRes, graph pipeline, SQLite round-trip giữ xanh).

**T6 — Release cycle** (như mốc 1).

Kích thước: **M**.

---

## Mốc 4 — v1.5.5-beta3 (n = 6 track: tất cả)

**Mục tiêu: "mọi tính năng đều có và dùng được, không lỗi không bug, mượt mà
sạch sẽ". Chỉ sửa + đo, KHÔNG thêm tính năng.**

**T1 — Sạch bug phần Rust**
- T1.P1: audit memory leak FFI (bitmap handle GDI, wgpu buffer, decode buffer).

**T2 — Stress export**
- T2.P1: batch export qua `scripts/ghita_cli.dart`, project lớn, undo 500 bước.

**T3 — Ổn định hóa beta**
- T3.P1: rút cờ "Beta" cho feature đủ ổn định (giữ cờ với cái còn rủi ro).

**T4 — Profiling Windows toàn bộ**
- T4.P1: CPU/GPU/RAM theo từng tính năng; tuning cache eviction; đặt target
  định lượng (startup ≤ Xs, RAM idle ≤ Y MB) ghi vào doc.

**T5 — Regression matrix**
- T5.P1: checklist manual toàn T1–T6 cũ + B1–B4; `engine_compare` parity
  full-suite; SQLite save/load round-trip.
- T5.P2: tiêu chí chốt: 0 crash phiên dài, 0 bug P0/P1.

**T6 — Docs draft**
- T6.P1: nháp CHANGELOG + cập nhật README nếu luồng dùng thay đổi.

Kích thước: **M**.

---

## Mốc 5 — v1.5.5 chính thức (n = 3 track: T4, T5, T6; T1–T3 freeze ❄️)

**T4** — tuning cuối chỉ nếu RC bắt được vấn đề.
**T5** — RC verify: CI xanh toàn bộ (Windows + Rust job), installer + DLL
bundle (~98 DLL closure) verified máy sạch, Demo Mode chạy không env dev.
**T6** — CHANGELOG trung thực chốt (bài học v1.5.0: chỉ ghi cái thật sự chạy
và đã test); tag `v1.5.5` + GitHub Release **chỉ sau khi duyệt** (tag v*
kích hoạt CI release bundle đã fix).

Kích thước: **S**.

---

## Checklist lặp lại MỖI mốc (áp cho mọi track)

1. Bump version: `version.dart` (+ suffix) → build_runner `--release` sinh
   pubspec → mirror `Cargo.toml`. Không sửa pubspec tay.
2. Gates: `flutter analyze` (0 lỗi) → `flutter test` → `cargo test` →
   `engine_compare` parity (nếu đụng engine).
3. `flutter build windows` **LUÔN chạy tiếp** `scripts/stage_windows_release.sh`
   (build ghi đè DLL Rust + FFmpeg); verify bằng PATH tước msys64.
4. Build ffmpeg cần PATH + LIBCLANG_PATH msys64; ICE thì `-j 2`.
5. Commit local. **Hỏi user trước khi push / tag / tạo Release.**
6. File `.rs`/`.dart` mới tạo bằng Write: kiểm tra cuối file trước khi
   compile (lỗi XML contamination đã gặp).

## Rủi ro chính

- GPU wgpu parity mới xác nhận với 3 filter — B1 toggle giới hạn đúng scope đó.
- GIF quantization: chất lượng palette + tốc độ phải A/B với tool chuẩn
  trước khi rời beta.
- Port Dart loop → FFI: zero-copy hoặc copy 1 lần, tránh chậm ngược.
- CI consistency gate: suffix version không được rò vào banner C++/CMake.
