# Ghita Edit — Changelog

## v0.4.0 (in development)
- 🔒 Fixed critical FFI error handling — missing native functions throw descriptive exceptions instead of crashing silently
- 🔒 Added dispose guard in EngineService and EditorController to prevent double-free memory issues
- 🔒 Added path validation in importMedia to prevent potential path traversal attacks
- 🔒 Fixed C++ Rule of Five — deleted copy operations, added move semantics to prevent undefined behavior
- 🛠 Centralized version management in `lib/src/core/version.dart` to eliminate version string drift
- 📝 Added strict lint rules via `analysis_options.yaml` with package:lints/recommended
- 🎨 Added `.editorconfig` for consistent code formatting across editors
- 🤖 Updated CI/CD pipeline with macOS builds, native self-test execution, and version consistency checks
- 📚 Added `CONTRIBUTING.md` with detailed contribution guidelines

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