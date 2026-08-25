# So sánh ghita_edit với 7 dự án tham khảo — 70 điểm

Ngày tạo: 2026-08-12
Tham khảo: refer_project/{OpenCut, audacity, gimp, krita, darktable, RawTherapee, digikam}
Trạng thái ghita_edit: v1.1.1+0 (Flutter UI + C++20 engine qua Dart FFI)

> Lưu ý: ghita_edit là prototype (vài tháng), các dự án kia phát triển 15–25 năm
> với hàng trăm contributor. Danh sách này là bản đồ khoảng trống để định hướng
> phát triển, không phải đánh giá tiêu cực.

## Phần 1 — 50 tính năng dự án tham khảo có, ghita_edit chưa có

### Video editing (OpenCut) — 14 điểm

1. Graph editor cho keyframe — chỉnh curve bằng bezier handles (ghita mới có nhập số + bezier API)
2. Copy/paste keyframes giữa các element
3. Keyframe lanes trên timeline — expand 1 clip ra lane riêng cho từng property animation
4. Blend modes — Multiply, Screen, Overlay... cho clip/text
5. Mask hình học — ellipse, star, heart, diamond, cinematic bars với feather/stroke + drag handles trên preview
6. Paste media từ clipboard — Ctrl+V dán ảnh/video/audio thẳng vào editor
7. Maintain-pitch khi đổi tốc độ — speed nhanh/chậm mà giọng không biến đổi
8. Font picker 1000+ fonts — Google Fonts + hệ thống
9. Canvas background tùy chọn — blur / solid / gradient + canvas size tự do
10. Bookmarks — đánh dấu thời điểm kèm note, màu label, duration
11. Auto-captions — auto-transcription + import transcript file để tạo subtitle
12. Preview zoom & pan
13. Guides — đường dẫn kéo thả + snap-to-guides, giữ Shift để tạm tắt snap
14. Effect như element độc lập trên timeline, không bị buộc vào clip

### Audio (Audacity) — 22 điểm

15. Spectrogram view — colormap perceptual (Roseus) + wavelet view, không chỉ waveform
16. Spectral editing — chỉnh sửa trực tiếp trên miền tần số
17. Time-stretch & pitch-shift độc lập — kéo dài clip không đổi pitch, đổi giọng không đổi tốc độ
18. Punch and Roll recording — ghi đè lại 1 đoạn nghe được bối cảnh
19. Timer Record — hẹn giờ thu
20. Overdubbing — thu chồng nghe lại được
21. Play-at-speed — phát ở tốc độ tùy chọn giữ nguyên pitch
22. Loop playback — Set Loop to Selection / Clear Looping Region bằng phím tắt
23. Label tracks — track ghi chú + xuất labels ra WebVTT/SRT subtitle
24. Realtime effect chain per track + master effects (VST3, LV2, LADSPA, Audio Units)
25. Compressor / Limiter realtime với gain-reduction history + presets
26. Noise Gate — attack/hold/delay đầy đủ
27. Noise Reduction hoàn chỉnh (kèm residue option) — ghita mới chỉ có toggle đơn giản
28. Bộ EQ/effect cơ bản — Bass & Treble, Distortion, Phaser, Reverb, Wahwah, Shelf Filter
29. Nyquist scripting + Macros — tự động hóa xử lý hàng loạt file trong app
30. Audio Setup — chọn thiết bị ghi/phát, đo latency
31. Tempo detection tự động — nhận diện BPM của loop khi import
32. Beats & Measures timeline + Time Signature toolbar — làm nhạc theo nhịp
33. Export multichannel — channel mapping 5.1/7.1, chọn sample rate
34. Import đa định dạng — OGG, FLAC, Opus, Wavpack, MP2, Raw headerless
35. Clip pitch/speed indicator + trim/stretch cursor hiển thị ngay trên clip
36. Export Selected Audio / Export to external program

### Photo / RAW (GIMP, Krita, darktable, RawTherapee, digiKam) — 14 điểm

37. Layer masks + Non-destructive layer effects (GEGL) + adjustment layers
38. Bộ selection tools — fuzzy select, scissors, paint select, quick mask
39. Clone / Heal / Perspective Clone — sửa điểm, xóa vật thể
40. Path / vector tool — vẽ bezier vector
41. CMYK + soft-proofing + ICC color management (LittleCMS, Colord)
42. RAW pipeline 32-bit float — demosaic, white balance per camera, camera profiles
43. Lens correction tự động qua Lensfun (auto-detect ống kính)
44. AI features — AI denoise, AI upscale, object masks, facial recognition
45. HDR workflow — HDR compression, film negative developing, film simulation, HDR painting (rec2020-PQ)
46. Brush engines chuyên sâu (Krita) — dynamics, stabilizer, wrap-around mode
47. Animation frame-by-frame + onion skin (Krita)
48. Camera tethering (libgphoto2)
49. Metadata editor — EXIF/IPTC/XMP (digiKam, GIMP)
50. DAM thực thụ — albums/tags/ratings, advanced search theo metadata, map view, Light Table (digiKam)

## Phần 2 — 20 điểm các dự án tham khảo tối ưu hơn

### Hiệu năng engine — 8 điểm

1. GPU acceleration — darktable (OpenCL), Krita (OpenGL canvas), OpenCut (GPU compositing); ghita render CPU thuần
2. Đa luồng + SIMD — RawTherapee dùng OpenMP + code hand-optimized x86_64
3. Pipeline 32-bit float (RawTherapee) — độ chính xác cao khi xử lý màu vs buffer 8-bit RGBA
4. Đồ thị xử lý có cache & lazy eval (GIMP GEGL — tile cache, chạy song song) vs áp filter tuần tự từng clip
5. Render đúng nhu cầu (OpenCut) — chỉ render phần waveform đang nhìn thấy, scale RMS chuẩn
6. Preview nhanh cho RAW (darktable) — embedded JPEG thumbnail cho ảnh chưa edit, không cần decode full
7. Cache thông minh (RawTherapee) — processing cache + quick-start bỏ qua cache load
8. Âm thanh low-latency — Audacity qua PortAudio có đo/compensate latency; ghita dùng waveOut (legacy)

### Lưu trữ & độ bền dữ liệu — 5 điểm

9. Project format bền vững — Audacity .aup3 (SQLite single-file, atomic, chống corruption) vs ghi toàn bộ JSON
10. Library database — digiKam/darktable dùng SQLite/MySQL với index & search nhanh vs load JSON toàn bộ
11. Edits portable — darktable lưu XMP sidecar chuẩn vs định dạng độc quyền .ghita
12. History không giới hạn, non-destructive hoàn toàn (darktable; Audacity effect stacks undoable) vs undo 100 bước
13. Auto-recovery + Backup Project + DB compaction (Audacity) vs autosave 60 giây

### Workflow & tự động hóa — 7 điểm

14. Headless CLI batch — darktable-cli, rawtherapee-cli, gimp-console --batch
15. Macros / Batch Queue — Audacity Macros, digiKam Batch Queue Manager
16. Import quy mô lớn — digiKam 1100+ máy ảnh (gphoto2), 900+ định dạng RAW (LibRaw)
17. Phân tích FFT thực — Audacity spectrogram/spectral editing/tempo detection
18. UX tăng tốc thao tác — OpenCut math expression + scrub; GIMP Action Search (Ctrl+F); guides + Shift tắt snap
19. Quản lý tài nguyên có hash & dedup (Krita) — md5 signature, snapshot cho worker threads
20. Export linh hoạt — channel mapping 5.1/7.1, chọn sample rate, đa định dạng (AVIF/HEIF/JPEG-XL/EXR), export remote

## Ghi chú kỹ thuật (đã có sẵn, không liệt kê nhầm)

- Ripple edit mode (v0.7.0) ✓
- Ruler, snap-to-grid/clip edge ✓
- Font picker cơ bản, text shadow/stroke ✓
- Chroma key (filter 22) ✓
- Noise suppress toggle ✓
- Speed ramp (curve_speed.dart) ✓
- Pan/mixer cơ bản trong DAW panel ✓
- Search trong media bin ✓
