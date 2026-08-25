# Trạng thái nền tảng Android (v1.5.0-rc1)

> Cập nhật: 2026-08-23 · Track T2-P4 của `docs/plan_v1.5.0_final.md`

## Tuyên bố chính thức (không giấu)

**APK Android hiện chạy ở Demo Mode** — build Android KHÔNG kèm engine gốc
(`ghita_engine` `.so`), vì:

1. `android/app/src/main/jniLibs/` không tồn tại trong repo; CI không có bước
   build engine cho Android.
2. `scripts/build_android_so.sh` chỉ build **engine C++ đóng băng ở bộ 65
   symbol pre-v1.5** — toàn bộ tính năng v1.5 (blend/mask, audio effects,
   SQLite DAM, selection tools) chỉ tồn tại trong engine Rust, vốn chưa có
   cấu hình `cargo-ndk` cho target Android.

Hệ quả: import media, playback, export thật **không hoạt động trên Android**
cho tới khi Track T5 bổ sung pipeline `cargo-ndk` (hoặc quyết định bỏ hẳn
nền tảng này). UI vẫn khởi động được để demo giao diện.

## Ký release

Từ v1.5.0-T2, `android/app/build.gradle.kts` đọc keystore từ
`android/key.properties` (hoặc biến môi trường `KEYSTORE_PATH`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`):

```properties
keystorePath=C:/keys/ghita.jks
keystorePassword=***
keyAlias=ghita
keyPassword=***
```

Không cung cấp keystore → build release rơi về **debug key và in cảnh báo
LOUD** trên Gradle output — một APK ký debug không còn thể lọt qua im lặng.

## Việc còn mở (thuộc T5)

- [ ] `cargo-ndk`: build `libghita_engine.so` (arm64-v8a tối thiểu) với
      feature `ffmpeg` (FFmpeg Android toolchain) → đặt vào `jniLibs`.
- [ ] CI job build APK + smoke khởi động.
- [ ] Quyết định cuối: nếu chi phí FFmpeg-on-Android quá lớn, chốt phương án
      "Android = viewer/Demo Mode" và ghi rõ trong CHANGELOG thay vì giả vờ
      hỗ trợ.
