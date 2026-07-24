# Ghita Edit — v0.1.0+2 (Alpha)

A cross-platform multimedia editor prototype built with **Flutter** and a native **C++20 rendering engine** connected via Dart FFI.

## Features

- 🎬 Video preview player with synthetic frame rendering
- 🎛️ Real-time filters: Grayscale, Sepia, Invert, Brightness
- 📐 Multi-track timeline with playhead scrubbing & zoom
- 🖥️ Inspector panel for media properties & audio mixer
- 🚀 C++20 native engine exposed through FFI bindings
- 🌙 Dark-themed UI inspired by DaVinci Resolve / Premiere Pro
- 🪟 Windows + Android support (Windows primary)

## Project Structure

```
├── lib/                  # Flutter UI + controller layer
│   ├── main.dart
│   └── src/
│       ├── controllers/  # EditorController (orchestrator)
│       ├── ffi/          # Dart ↔ C++ FFI bindings
│       └── ui/           # Theme, views, widgets
├── native_engine/        # C++20 shared library
│   ├── include/          # Public headers (.h)
│   └── src/              # Engine core + C API wrapper
├── android/              # Android build (Gradle + NDK-ready)
├── windows/              # Windows runner + native_engine integration
└── test/                 # Dart + C++ tests
```

## Prerequisites

| Tool | Purpose |
|------|---------|
| Flutter SDK ≥ 3.12.x | Dart/UI framework |
| Android SDK + NDK r25+ | Android builds (.so) |
| CMake ≥ 3.15 | Native engine build |
| MSVC 2022 (Windows) or GCC/Clang | C++20 compiler |

## Build & Run

### Windows (recommended for development)
```bash
cd native_engine
cmake -B build -S . -DCMAKE_BUILD_TYPE=Debug
cmake --build build --config Debug
cd ..
flutter run -d windows
```

The `windows/CMakeLists.txt` automatically sub-builds `native_engine` so the DLL is copied into the runner output.

### Android
The C++ library must be cross-compiled for each ABI (arm64-v8a, x86_64). Use CMake/NDK to produce `libghita_engine.so` per architecture.

## Architecture Notes

- The native engine exposes a **stable C ABI** (`extern "C"`) through `ghita_c_api.h`.
- Dart bindings live in `lib/src/ffi/native_bindings.dart` using `dart:ffi`.
- `EditorController` drives the preview tick loop (~30 fps) and syncs state to the UI.
- Synthetic frames are generated pixel-by-pixel; this is suitable for Alpha verification only — real video decoding requires FFmpeg/Skia/Vulkan.

## Known Limitations (Alpha)

- No real file I/O for media decoding — only synthetic gradients.
- Export is simulated, not actual encoding.
- Audio playback is not implemented — volume slider is a visual control.
- File picker now uses `file_picker` for loading clip paths.

## Changelog

### v0.1.0+2 (Alpha)
- Fixed thread-safety bugs in native engine (consolidated mutex usage, removed `mutable` const_cast)
- Added Brightness filter implementation
- Refactored Dart controller with async init + EngineService separation
- Improved native library resolution across platforms
- Expanded FFI + widget tests
- Added self-contained C++ engine test runner
- Polished export dialog timer logic
- Rewrote README with build instructions and architecture docs
