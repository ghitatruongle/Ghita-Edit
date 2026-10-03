# Flake investigation — engine_compare `real_timeline@*` (T5.P1, v1.5.5-beta2)

## Triệu chứng

`engine_compare` thi thoảng FAIL: các cặp frame `real_timeline@{0,300,900,1800}`
lệch đồng loạt trong một run (`max_diff` ≈ 200–255, ~25 % pixel), trong khi
`real_decode@*` và toàn bộ synthetic scenario vẫn OK. Tần suất quan sát:
khoảng 1/6–1/9 lần chạy process, có từ trước phiên bản demo (đã tái hiện trên
binary đã commit).

## Kết luận (2026-10-01, có bằng chứng đo được)

**Oracle C++ lệch — Rust engine sạch.** Sản phẩm chỉ render bằng Rust nên
không bị ảnh hưởng; đây là lỗi phía oracle parity (C++), chỉ chạm tới harness.

Bằng chứng (run dính flake, bộ dò `GHITA_PARITY_REPEAT=1` + instrumentation
mới trong `tools/engine_compare`):

1. **Self-consistency trong context:** render lại đúng vị trí trên CÙNG
   context của cả hai engine đều ra byte-identical (`[0,0]`) — cả hai
   "kiên định" với render đầu tiên của mình; không race trong context.
2. **Fresh-context replay:** tạo context C++ MỚI, replay đúng chuỗi ops của
   scenario (decode probes → wav → waveform → upsert) rồi render cùng vị trí
   → **khớp byte-identical với Rust**, không khớp render đầu tiên của C++.
3. **Direct decode (load-only)** trên cả hai engine → khớp nhau, khớp Rust.
4. Dump PNG: frame C++ outlier không phải đen/rác — là color bars hợp lệ chỉ
   khác vùng đáy ⇒ khung lân cận / trạng thái decode lệch, không phải hỏng
   buffer.

⇒ Context C++ đầu tiên trong scenario mang trạng thái nội bộ (per-context,
ổn định trong context) làm nó render khung lệch một cách xác định; mọi
"ý kiến" độc lập khác (C++ mới, Rust, decode thuần) đều thống nhất.

Phạm vi nguyên nhân: trạng thái nằm trong instance C++, KHÔNG phải static
toàn cục (grep toàn bộ `native_engine/src`: chỉ `thread_local` buffer JSON/
thumbnail và bảng `static const`); cơ chế nội bộ chính xác bên trong C++ chưa
bịt được và **không còn giá trị sản phẩm** vì C++ chỉ còn là oracle parity
(xem T1.P3: C++ đã rời build sản phẩm từ beta2).

## Bộ dò + harden harness (đã vào code)

- `GHITA_PARITY_REPEAT=1` chạy scenario ×2 (có từ beta1).
- beta2: so sánh A/B **ngay trong lúc render** (không chờ buffer cuối) +
  `diagnose_ab_mismatch` tự động chạy 3 phép chứng thực trên, dump toàn bộ
  biến thể vào `flake_dump/*.rgba`.
- **Recovery có kiểm soát:** chỉ khi bằng chứng chỉ ra C++ outlier (C++
  self-consistent, Rust self-consistent, fresh-C++ khớp Rust) harness thay
  oracle của cặp đó bằng frame fresh-C++ và in
  `NOTE: N C++ oracle state flake(s) recovered`. Parity hai engine vẫn được
  kiểm trên trạng thái sạch. **Không nới tolerance;** mọi trường hợp nghi
  Rust (self-inconsistent, outlier, REAL DIVERGENCE, INCONCLUSIVE) vẫn FAIL
  như cũ.

## Số liệu

- 2026-10-01: 28 lần chạy process trên máy dev (8 + 20, dừng sớm khi bùng);
  flake bùng ở run 9 và (trong run đó) cả hai scenario đều dính — mỗi
  scenario với context C++ riêng ⇒ sự kiện tính theo process, không phải
  context đơn.
- Các run không dính: 100 % PASS, 0 recovery giả.
