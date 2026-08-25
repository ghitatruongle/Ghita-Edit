# Ghita Edit — v1.5.0 (Rust engine mặc định · ổn định hóa + hiệu năng)

A cross-platform multimedia editor suite built with **Flutter** and a native engine connected via Dart FFI (Rust là engine shipping; C++ đóng băng làm A/B oracle).

## Platform Status

| Nền tảng | Trạng thái |
|---|---|
| Windows | ✅ Đầy đủ (engine Rust + FFmpeg) |
| Android | ⚠️ Demo Mode — chưa có `.so` engine, xem [docs/android_status.md](docs/android_status.md) |

## Features

### v0.8.0 — Real Timeline Engine, Audio, & Feature Completeness

- 🎬 **Timeline compositor thật** — Preview/export render đúng timeline: nhiều clip/track, trim/split/move phản ánh ngay, opacity, speed, per-clip filter, text/sticker, transitions FadeIn/FadeOut/Crossfade
- 🔊 **Âm thanh trong preview** — Engine mix PCM (clip × track × master volume, mute) phát qua waveOut khi Play
- 🎵 **Export có audio** — MP4 với H.264/H.265/VP9 + AAC 44.1kHz; encoder fallback chain luôn ra file chạy được
- 🎙 **Voiceover recorder thật** — Thu WAV → audio clip undoable (toolbar → Audio)
- 🎨 **21 filters đầy đủ** — Thêm VHS, Glitch, Chromatic Aberration, Vignette, Film Grain, Light Leak, Sharpen, Posterize, Duotone, Background Blur
- 🎚 **Color correction vào engine** — Exposure/Contrast/Saturation/Temperature/Tint/Vibrance/Highlights/Shadows hiển thị trên preview + export
- 🎛 **Track mute/visible/volume thật** — Ảnh hưởng render + mix
- 🛡 **Ổn định** — Fix concurrency decoder (m_renderMutex), deadlock audio thread, SIGFPE export (stream trước header + AAC priming), heap underflow text, JSON escape, loadMedia báo lỗi thật

### v0.5.5 — Editor Experience Update

- ✂️ **Trim Handles** — Resize clips from either edge with visual drag handles
- 🧲 **Snap-to-Grid** — Real snap engine (Off / 0.5s / 1s), snaps to grid, clip edges, playhead
- 🖱 **Multi-select** — Ctrl+Click toggle, Shift+Click range, long-press marquee selection
- 👁 **Track Visibility** — Show/hide tracks with eye icon in timeline header
- 🎛 **Per-Clip Inspector** — Editable properties, per-clip filter/volume/speed/opacity
- 🎬 **Keyframe UI** — Animation keyframe panel with interpolation types
- 📝 **Text Overlay** — Text presets (Title, Subtitle, Lower Third, Watermark)
- 📁 **Real Media Bin** — Shows imported clips with drag-drop to timeline
- 🎬 **Export Presets** — YouTube, TikTok, Twitter, Web VP9, ProRes, Custom
- ⏩ **Playback Speed** — 0.25x–4x speed control in preview player
- 💡 **Light Theme** — Full light/dark theme support
- 🔧 **C++ Engine Extensions** — Playback rate API, text rasterizer stub, keyframe interpolation

### v0.4.5 — FFmpeg Integration & Major Update

- 🎬 **Real FFmpeg Media Decoder** — Actual video/audio decoding via libavformat/libavcodec (graceful fallback to synthetic decoder when FFmpeg unavailable)
- 📹 **Real Video Export** — H.264, H.265, VP9 encoding with configurable bitrate and AAC audio
- 🎨 **10 Built-in Filters** — Grayscale, Sepia, Invert, Brightness, Blur, Edge Detect, Color Grading, Adjust (BCSH), Pixelate, Mosaic
- 🔄 **8 Transition Types** — FadeIn, FadeOut, Crossfade, Slide, Wipe, Zoom, Dissolve, Radial
- 🎯 **Keyframe Animation** — Linear interpolation for clip properties
- 💻 **macOS Support** — Native engine builds via Homebrew FFmpeg
- 📱 **iOS Framework** — Static framework build for iOS integration
- 🔧 **Extended Export Dialog** — Codec selection, bitrate slider, include-audio toggle, ETA tracking
- 🛡 **Thread Safety** — shared_mutex read/write locking, atomic memory ordering
- ✅ **Version Consistency CI** — Automated check across all 10 version sources

### Core (v0.4.0+)

- ⚡ **C++20 Engine** with shared_mutex synchronization
- 🎞 **Multi-track Timeline** with drag-to-move, zoom, snap-to-grid
- 🖼 **Real-time Filters** applied via native pixel shaders
- 🔊 **Audio Waveform** extraction and visualization
- ⌨️ **Keyboard Shortcuts** — JKL shuttle, Ctrl+Z/Y/S/C/V, Space, S, Delete, Home/End
- ↩️ **Undo/Redo** with 100-step CommandHistory
- 💾 **Auto-save** every 60 seconds, project save/load (.ghita JSON)
- 🎛 **Export Pipeline** — async background export with progress polling
- 🖥 **Dark UI Theme** with professional color scheme

## Quick Start

### Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | 3.27.x | Dart/UI framework |
| CMake | 3.15+ | Native engine build |
| C++20 compiler | MSVC 2022 / GCC 11+ / Clang 15+ | |
| FFmpeg | 4.4+ (optional) | Real media decode/encode |

### Build & Run

```bash
flutter pub get

# Build native engine (Windows)
cmake -B native_engine/build -S native_engine -DCMAKE_BUILD_TYPE=Release
cmake --build native_engine/build --config Release

# Run
flutter run -d windows

# Or Android (build .so first)
./scripts/build_android_so.sh
flutter run -d android

# Or macOS (requires Homebrew FFmpeg)
brew install ffmpeg pkg-config
./scripts/build_macos.sh
```

### Windows FFmpeg notes (v0.8.0)

- **MinGW builds prefer a MinGW-built FFmpeg** (`C:/msys64/mingw64`). MSVC-built FFmpeg (vcpkg) lacks the libx264/libx265/libvpx encoders — export still works via the fallback chain (mpeg4 last resort), but full-quality H.264/H.265/VP9 requires the MinGW FFmpeg.
- The engine DLL **statically links libstdc++/libgcc** (no version-skewed runtime DLLs from PATH).
- `flutter run -d windows` copies the FFmpeg runtime DLLs next to the exe automatically (see `windows/CMakeLists.txt`).
- **Runtime PATH order matters when running the engine tests manually**: put the FFmpeg bin dir first, e.g. `PATH="C:\Program Files\CodeBlocks\MinGW\bin;C:\msys64\mingw64\bin;%PATH%"`.

## Architecture

> **v1.5.0-T5 (P1) — Engine freeze decision:** the C++20 engine
> (`native_engine/`, 65 pre-v1.5 symbols) is **FROZEN as an A/B parity
> oracle**: it still builds on CI and runs its self-test, but receives NO new
> features. All v1.5+ functionality lives in the Rust engine
> (`native_engine_rust/`, 110 exports), which is the shipping default.
> Known divergences are documented in `docs/rust_engine_abi.md`.

```
┌─────────────────────────────────────┐
│         Flutter UI (Dart)            │
│  EditorView → Timeline / Inspector   │
│         ↓ FFI (dart:ffi)             │
├─────────────────────────────────────┤
│    GhitaNativeBindings (C API)       │
│         ↕ extern "C"                 │
├─────────────────────────────────────┤
│     GhitaEngine (C++20)              │
│  ┌───────────┐  ┌────────────────┐   │
│  │IMediaDecoder│  │ Export Pipeline│  │
│  │• Synthetic  │  │• Raw RGBA     │   │
│  │• FFmpeg ██  │  │• H.264 ██     │   │
│  │• Stub       │  │• H.265 ██     │   │
│  └───────────┘  └────────────────┘   │
│  shared_mutex • atomics • threads    │
└─────────────────────────────────────┘
       Windows │ Android │ macOS
```

██ = New in v0.4.5

## Project Structure

```
lib/
  main.dart                     # Entry point
  src/
    core/version.dart           # Centralized version constants
    controllers/
      editor_controller.dart    # Central state manager
      engine_service.dart       # FFI engine lifecycle
      command_history.dart      # Undo/Redo system
      project_service.dart      # Save/Load .ghita projects
    ffi/
      native_bindings.dart      # Dart FFI function bindings
    models/
      project.dart              # Project model
      track.dart                # Track model
      clip.dart                 # Clip model
    ui/
      theme/app_theme.dart      # Dark theme
      views/editor_view.dart    # Main editor layout
      widgets/                  # Inspector, Timeline, Preview, Media Bin, Export

native_engine/
  CMakeLists.txt                # FFmpeg-aware build
  include/ghita_engine.h        # C++ engine + decoder API
  include/ghita_c_api.h         # C API (25+ functions)
  src/ghita_engine.cpp          # Engine, decoders, filters, export
  src/ghita_c_api.cpp           # C API implementation
  test/native_engine_self_test.cpp  # 18+ self-tests
```

## Tests

```bash
flutter test                    # Dart unit tests
./native_engine/build/native_engine_test  # C++ self-tests
```

## Versioning

Version is centralized in `lib/src/core/version.dart` and auto-verified by CI.
Current: **v1.1.1+0** (build 0)

## License

This project is for educational and development purposes.
FFmpeg is optionally linked under LGPL/GPL — see FFmpeg licensing for details.
