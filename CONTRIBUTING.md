# Contributing to Ghita Edit

Welcome! We're excited to have you contribute to Ghita Edit, a cross-platform multimedia editor with a native C++ rendering engine.

## Development Setup

### Prerequisites

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| Flutter SDK | 3.27.x | Dart/UI framework |
| Android NDK | r25+ | Android native builds |
| CMake | 3.15+ | Native engine build |
| MSVC 2022 / GCC 11+ / Clang 15+ | - | C++20 compiler |
| **FFmpeg** (optional) | 4.4+ | Real media decode/encode (v0.4.5) |
| pkg-config | - | FFmpeg detection (Linux/macOS) |
| Git | - | Version control |

> **Note:** FFmpeg is optional. Without it, the engine uses a built-in synthetic decoder (Demo Mode).

### Installing FFmpeg

**Windows (via vcpkg):**
```powershell
git clone https://github.com/Microsoft/vcpkg.git
.\vcpkg\bootstrap-vcpkg.bat
.\vcpkg\vcpkg install ffmpeg:x64-windows
```

**macOS (via Homebrew):**
```bash
brew install ffmpeg pkg-config
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install -y libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev
```

### Building the Project

```bash
# Clone the repository
git clone https://github.com/your-org/ghita_edit.git
cd ghita_edit

# Get dependencies
flutter pub get

# Build native engine (Windows)
cd native_engine
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
cd ..

# Run on Windows
flutter run -d windows

# Or on Android (requires .so build first)
./scripts/build_android_so.sh
flutter run -d android

# Build on macOS
brew install ffmpeg pkg-config
./scripts/build_macos.sh
```

### Build Options

The native engine CMake supports these options:
- `-DBUILD_TESTING=ON` (default) — build self-test runner
- FFmpeg is auto-detected via pkg-config (Linux/macOS) or find_path/find_library (Windows)
- When FFmpeg is not found, `GHITA_NO_FFMPEG` is defined and synthetic decoder is used

## Coding Standards

### Dart Code

- Use `dart format` (`dart fix --apply`) before submitting changes
- All public methods must have documentation comments using `///` notation
- Follow [Effective Dart](https://dart.dev/effective-dart) guidelines
- New code should be null-safe and use modern Dart 3+ features (records, patterns, etc.)

### C++ Code

- Compile with C++20 standard (`-std=c++20`)
- Use `shared_mutex` for read-heavy concurrent access patterns
- All class destructors should properly clean up resources
- Header files must use include guards (`#ifndef ... #define ... #endif`)
- No raw `new`/`delete` — prefer smart pointers (`unique_ptr`, `shared_ptr`)
- All `extern "C"` functions must have proper error return codes (int for success/failure)
- FFmpeg code must be wrapped in `#ifdef GHITA_HAS_FFMPEG` guards

## Testing

Run all tests before submitting:

```bash
# Run all Dart unit tests
flutter test

# Run native engine self-tests
cd native_engine/build
./native_engine_test
cd ..
```

**Requirement:** All existing tests must pass before pull requests are accepted.

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`feature/add-new-filter`, `fix/memory-leak`, etc.)
3. Commit changes with clear, descriptive messages
4. Push to your fork
5. Open a Pull Request against `main` branch

PR Checklist:
- [ ] All tests pass
- [ ] No lint warnings (`flutter analyze` produces 0 warnings)
- [ ] Code is formatted (`dart format --set`)
- [ ] New features include corresponding tests
- [ ] Documentation updated if necessary
- [ ] Version strings remain consistent across files

## Version Policy

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version when API-breaking changes occur
- **MINOR** version when new backward-compatible features are added
- **PATCH** version for backward-compatible bug fixes

Version strings are centrally managed in `lib/src/core/version.dart`. All version references
in `pubspec.yaml`, `CMakeLists.txt`, C API strings, and test assertions must match this source.

## v0.4.5 New Features

- **Real FFmpeg Decoder**: Actual video/audio decoding via libavformat/libavcodec
- **Export Encoding**: H.264/H.265/VP9 encoding with configurable bitrate
- **10 Built-in Filters**: Grayscale, Sepia, Invert, Brightness, Blur, Edge Detect, Color Grading, Adjust, Pixelate, Mosaic
- **8 Transition Types**: None, FadeIn, FadeOut, Crossfade, Slide, Wipe, Zoom, Dissolve, Radial
- **Keyframe Animation**: Linear interpolation for clip properties
- **macOS Support**: Native engine builds via Homebrew FFmpeg
- **iOS Support**: Static framework build (without FFmpeg)
