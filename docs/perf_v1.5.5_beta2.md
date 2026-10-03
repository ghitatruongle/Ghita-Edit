# Profiling — v1.5.5-beta2 (T4.P1, đo 2026-10-01 trên máy dev Windows)

Mọi số liệu dưới đây là số ĐO được (không phải ước lượng), trừ nơi ghi rõ
"target". Nguồn: cargo test (`--nocapture`), engine_compare, export matrix
local, CLI export 1080p.

## Engine

| Chỉ số | Giá trị đo | Nguồn |
|---|---|---|
| Native init (engine initialize) | 0.00 ms | abi test `native_engine_init_cost_is_measured` (beta1) |
| Working set sau 240 vòng create→decode→render→destroy + 100 vòng upsert/remove | 26.8 → 43.7 MB (Δ **16.8 MB**) | abi test `engine_lifecycle_stress_memory_is_bounded` (beta2) |
| Paused-scrub cache hit rate (90 vị trí quét xuôi/ngược/xuôi) | ≥ 0.40 assert, đo **~0.67** | abi test `paused_scrub_cache_hit_rate_is_measured` |
| Cache byte budget (trần thiết kế) | 96 MB (`CACHE_BYTE_BUDGET`) | processing_cache.rs |
| Filter nóng vector hóa (4K, so scalar) | 1.09 / 1.18 / 1.09× | filters.rs benchmark (beta1) |
| Rayon tile song song (4K) | 2.4–3.0× | parallel_filter_benchmark_4k (beta1; tile 32 giữ nguyên sau A/B) |

## Export (CLI headless, DLL Rust)

| Case | Kết quả đo |
|---|---|
| 1080p30 H.264, timeline 26 s (780 frame, 13 clip) | **25.3 s** (≈31 fps ≈ **1.0× realtime**), 8.57 MB |
| Matrix 10 case (320×180, media 1.2 s) | 10/10 PASS; mỗi case 61–874 ms |
| GIF 640×480 + 1920×1080 (quantize + dither) | PASS trong 1.84 s (test `gif_export_large_sizes_are_wellformed`) |
| Undo 500 thao tác + undo đầy đủ | PASS (test Dart, <1 s) |
| SQLite save→load ×50, payload tăng đến ~5 KB | PASS, byte-identical từng vòng |

## Target định lượng chốt cho v1.5.5 final

- Native init ≤ 50 ms — hiện 0.00 ms ✅
- RAM tăng sau stress vòng đời ≤ 150 MB — hiện 16.8 MB ✅
- Paused-scrub hit rate ≥ 0.40 — hiện ~0.67 ✅
- Export 1080p ≥ 0.5× realtime — hiện ~1.0× ✅
- Parity A/B với oracle C++: max_diff ≤ 1 — 10/10 matrix + recovery oracle-flake ✅
- RAM scrub trần cache 96 MB (đúng thiết kế, không vượt) ✅

## Ghi chú tuning

- Cache eviction theo BYTE (96 MB) thay vì theo số entry — beta1; không có
  số liệu nào ở beta2 đòi đổi thêm.
- Tile rayon 32 đã được A/B (96 → 2.55× vs 32 → 2.79–2.98×) — giữ 32.
- Không phát hiện điểm cần tuning mới ở beta2; mọi target đã đạt trước hạn.
