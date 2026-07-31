# Ghita Edit — Changelog

## v0.5.5 (2026-07-30) — Editor Experience Update
- 🎬 **Phase 1: Timeline UX Overhaul**
  - **Trim Handles** — Resize clips from either edge with visual drag handles; undoable via TrimClipCommand
  - **Snap-to-Grid** — Real snap engine with Off / 0.5s / 1s toggle; snaps to grid lines, clip edges, and playhead
  - **Multi-select Clips** — Ctrl+Click toggle, Shift+Click range select, long-press+drag marquee selection
  - **Bulk Operations** — Delete all, apply filter to all selected clips
  - **Track Visibility Toggle** — Eye icon in track header to show/hide tracks
- 🎨 **Phase 2: Professional Inspector & Features**
  - **Per-Clip Inspector** — Editable timecode fields, per-clip filter (not global), per-clip volume
  - **Clip Properties Panel** — Speed (0.25x–4x) and Opacity (0–100%) sliders per clip
  - **Keyframe Animation Panel** — Add/Remove keyframes, interpolation types (Linear/EaseIn/EaseOut/Hold)
  - **Text Overlay Tool** — MediaBin Text tab with presets (Title, Subtitle, Lower Third, Watermark); adds text clips to overlay track
  - **Audio Mixer Surface** — Per-clip volume control in inspector
- 🚀 **Phase 3: Workflow Improvements**
  - **Real Media Bin** — Shows actual imported clips with duration, type icon; syncs with project
  - **Drag-Drop to Timeline** — Long-press drag from MediaBin to timeline track (DragTarget)
  - **Export Presets** — 8 one-click presets: YouTube 1080p/4K, TikTok 9:16, Twitter 720p, Web VP9, Archive ProRes, Custom
  - **Aspect Ratio Display** — Shows W:H ratio in export dialog
  - **Playback Speed Control** — Speed dropdown in preview player (0.25x–4x)
  - **Extended Filter Chips** — Dynamic filter list from engine, per-clip filter application
- 💻 **Phase 4: C++ Engine & Quality of Life**
  - **Playback Rate API** — `ghita_engine_set_playback_rate` C API, `m_playbackRate` atomic field
  - **Text Overlay Renderer** — Basic text rasterizer stub in C++ engine
  - **Keyframe Interpolation** — `KeyframeInterpolation` enum (Linear, EaseIn, EaseOut, Hold) + C API
  - **Light Theme** — Full light theme palette with helper color functions
  - **Version Bump** — Centralized version updated to v0.5.5 across all 10+ files
- ✅ **Clip Model Extensions** — Added `speed` and `opacity` fields with JSON serialization

## v0.4.5+5 (2026-07-30) — FFmpeg Integration & Export, UI Overhaul, Cross-Platform
- 🎬 **Phase 0: Version bump** — Centralized version updated to v0.4.5+5 across all 10 files
- 🚀 **Phase 1: Real FFmpeg Integration** — Replaced synthetic decoder with actual FFmpeg decoding pipeline (`avformat`, `avcodec`, `swscale`, `swresample`)
  - Real video/audio file decoding via `RealFFmpegMediaDecoder`
  - True PCM audio waveform extraction from actual media files
  - New C API: `ghita_engine_get_media_info` returning JSON metadata (codec, bitrate, resolution)
  - Graceful fallback to synthetic decoder when FFmpeg unavailable
  - CMake FFmpeg detection with vcpkg/prebuilt fallback on Windows
- 📹 **Phase 2: Real Video Export** — Replaced raw RGBA export with FFmpeg encoding pipeline
  - H.264 (`libx264`), H.265 (`libx265`), VP9 codec support
  - AAC audio encoding via `libfdk_aac` / native FFmpeg AAC
  - New C APIs for codec selection, bitrate control, file size estimation
  - Cancellation-safe export with mid-stream cleanup
  - UI: codec dropdown, bitrate slider, include-audio toggle, ETA display
- 🎨 **Phase 3: Editor & UI Improvements**
  - Real audio waveform visualization with zoom-dependent detail
  - Snap-to-grid with toggle button, multi-select clips (Ctrl/Cmd+click, Shift-range)
  - Drag-drop clips between tracks, smooth scroll-zoom
  - 6 new filters: Blur (Gaussian), Edge Detect (Sobel), Color Grading (3×3 matrix), Adjust (BCSH), Pixelate/Mosaic
  - 5 new transitions: Slide, Wipe, Zoom, Dissolve, Radial
  - Dynamic filter list via `ghita_engine_get_available_filters()` API
  - Basic keyframe animation system (position, opacity, filter intensity, scale)
  - Frame caching & thread pool for rendering performance
- 💻 **Phase 4: Cross-Platform & Stability**
  - macOS CI build job + native engine compilation via Homebrew FFmpeg
  - macOS Flutter runner with `.dylib` FFI paths
  - iOS basic support: `.framework` build script, arm64 FFmpeg
  - Thread safety audit: shared_mutex review, atomic memory ordering fixes
  - AddressSanitizer-enabled CI builds for memory leak detection
  - Stress tests: concurrent 100+ thread read/write, frame buffer overflow, export lifecycle
  - Comprehensive Dart tests: export validation, multi-selection, snap-to-grid, keyframes
  - Documentation: README, CONTRIBUTING.md updated with FFmpeg/macOS build instructions

## v0.4.0+4
- 🔒 Fixed critical FFI error handling — missing native functions throw descriptive exceptions instead of crashing silently
- 🔒 Added dispose guard in EngineService and EditorController to prevent double-free memory issues
- 🔒 Added path validation in importMedia to prevent potential path traversal attacks
- 🔒 Fixed C++ Rule of Five — deleted copy operations, added move semantics to prevent undefined behavior
- 🛠 Centralized version management in `lib/src/core/version.dart` to eliminate version string drift
- 📝 Added strict lint rules via `analysis_options.yaml` with package:lints/recommended
- 🎨 Added `.editorconfig` for consistent code formatting across editors
- 🤖 Updated CI/CD pipeline with macOS builds, native self-test execution, and version consistency checks
- 📚 Added `CONTRIBUTING.md` with detailed contribution guidelines

## v0.3.7+3
- 🚀 **C++20 Engine MSVC Fixes**: Fixed C++20 move constructor issues for `std::atomic` and `std::shared_mutex` for zero-warning MSVC compilation.
- 🎨 **App Branding & Windows Packaging**: Converted brand `logo.png` to multi-resolution Windows `app_icon.ico` and integrated directly into Windows runner `Runner.rc`.
- 🛡 **Safeguarded Enterprise `.gitignore`**: Hardened `.gitignore` with explicit source extension protections (`!*.dart`, `!*.cpp`, `!*.h`, `!*.kt`, `!*.java`, etc.) and unignored Android Gradle Wrapper (`gradlew`).
- 🛠 **Centralized Versioning**: Synchronized version constants to `v0.3.7+3` across `pubspec.yaml`, `version.dart`, `README.md`, `CMakeLists.txt`, and C++ headers.

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