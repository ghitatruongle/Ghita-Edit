# Ghita Edit — v0.3.7

A cross-platform multimedia editor suite built with **Flutter** and a native **C++20 rendering engine** connected via Dart FFI.

## Features

- 🎬 Video preview player with multi-threaded C++20 rendering engine
- 🎛️ Real-time filters: Grayscale, Sepia, Invert, Brightness
- 📐 Multi-track timeline with playhead scrubbing, clip splitting & drag-and-drop
- 🎵 Native C++ Audio Waveform generation & volume control
- 🚀 Asynchronous background export thread worker pipeline
- 🔒 C++20 `std::shared_mutex` read-write lock synchronization
- 🤖 Android NDK multi-ABI cross-compilation & GitHub Actions CI/CD
- 🌙 Dark-themed UI inspired by DaVinci Resolve / Premiere Pro
- 🪟 Windows + Android + Linux support (Windows primary)

## Project Structure

```
├── lib/                  # Flutter UI + controller layer
│   ├── main.dart
│   └── src/
│       ├── controllers/  # EditorController & EngineService
│       ├── ffi/          # Dart ↔ C++ FFI bindings
│       └── ui/           # Theme, views, widgets
├── native_engine/        # C++20 shared library
│   ├── include/          # Public headers (ghita_engine.h, ghita_c_api.h)
│   └── src/              # IMediaDecoder + C API wrapper + Export thread
├── scripts/              # Automated build scripts (build_android_so.sh)
├── .github/workflows/    # CI/CD workflows (ci.yml)
├── android/              # Android build (Gradle + NDK-ready)
├── windows/              # Windows runner + native_engine integration
└── test/                 # Dart + FFI + Widget tests
```

## Prerequisites

| Tool | Purpose |
|------|---------|
| Flutter SDK ≥ 3.27.x | Dart/UI framework |
| Android SDK + NDK r25+ | Android builds (.so) |
| CMake ≥ 3.15 | Native engine build |
| MSVC 2022 (Windows) / GCC 11+ | C++20 compiler with std::shared_mutex |

## Build & Run

### Windows (recommended for development)
```bash
cd native_engine
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
cd ..
flutter run -d windows
```

The `windows/CMakeLists.txt` automatically sub-builds `native_engine` so the DLL is copied into the runner output.

### Android
Automated cross-compilation for all 4 ABIs (`arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`):
```bash
./scripts/build_android_so.sh
flutter run -d android
```

## Architecture Notes

- The native engine exposes a **stable C ABI** (`extern "C"`) through `ghita_c_api.h`.
- `IMediaDecoder` interface abstraction provides seamless fallback and FFmpeg decoder hookups.
- C++20 `std::shared_mutex` ensures non-blocking concurrent frame reads.
- Asynchronous background thread (`m_exportThread`) handles progress calculation and render loops without freezing the UI.

## Changelog

### v0.3.0
- Upgraded C++20 engine synchronization to `std::shared_mutex` (Read-Write Locks).
- Introduced `IMediaDecoder` abstraction architecture with `SyntheticMediaDecoder` and `FFmpegMediaDecoderStub`.
- Added native audio waveform sample extraction (`ghita_engine_get_audio_waveform`).
- Implemented real asynchronous background export thread worker (`m_exportThread`).
- Resolved all 207 Flutter linter warnings (0 errors, 0 warnings with `flutter analyze`).
- Added GitHub Actions CI pipeline (`.github/workflows/ci.yml`).
- Added Android NDK multi-ABI build script (`scripts/build_android_so.sh`).
- Expanded FFI resilience unit tests (`test/native_ffi_test.dart`).
- Upgraded version strings to `v0.3.0+1` across `pubspec.yaml`, `app_theme.dart`, and C++ headers.
