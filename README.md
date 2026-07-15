# Ghita Edit

High-performance video/audio editor — **C++20 + Qt6 (QML) + FFmpeg**.

> Status: **M4 — full editor.** Playback with frame throttle + A/V sync, a
> multi-track timeline with cut/trim/snap and undo/redo, real-time video color
> grading and audio DSP (gain / normalize / fade), and export to MP4 (H.264 video
> + AAC audio) with effects baked in. The pipeline decodes video to RGBA and audio
> to float PCM via FFmpeg, uploads frames as an OpenGL texture through a custom
> `QQuickItem` (`PreviewSurface`), and plays audio via PortAudio.

## Design goals
- Maximum performance, close-to-hardware control.
- Native on **Windows** (primary) and **Linux / WSL**.
- Hardware acceleration: NVDEC (NVIDIA), QuickSync (Intel), AMF (AMD), VA-API (Linux).
- Audio is the master clock for A/V sync (low jitter).

## Architecture
```
Qt6 QML GUI  ──signals──▶  MediaEngine (C++)
                              ├─ Decoder  (FFmpeg, hw accel select)
                              ├─ FramePool (lock-free ring buffer)
                              ├─ DecodeWorker (QThread, frame throttle)
                              ├─ AudioEngine (PortAudio, low-latency)
                              ├─ AudioClock (master A/V sync)
                              ├─ VideoFX (YUV color grade, M3)
                              ├─ AudioDSP (float DSP: gain/normalize/fade, M2)
                              └─ Exporter (libx264/AAC MP4, M4)
```

## Prerequisites
- **C++20** compiler (MSVC 19.3+ on Windows, GCC 11+/Clang 14+ on Linux)
- **CMake ≥ 3.24**
- **Qt 6** (Quick + QuickControls2 + OpenGL)
- **FFmpeg** (`libavformat/libavcodec/libavutil/libswscale/libswresample`)
- **PortAudio**

## Build — Windows (VS2026 + vcpkg + aqtinstall)

### 1. Install dependencies
```powershell
# Qt 6.7.3 via aqtinstall
pip install aqtinstall
aqt install-qt windows desktop 6.7.3 win64_msvc2019_64 --outputdir C:\Qt

# FFmpeg + PortAudio via vcpkg (binary cache — ~1s)
cd C:\vcpkg
vcpkg install ffmpeg:x64-windows portaudio:x64-windows
```

### 2. Configure & build
```powershell
# Open VS2026 x64 Developer Command Prompt, then:
cmake -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_PREFIX_PATH="C:/Qt/6.7.3/msvc2019_64;C:/vcpkg/installed/x64-windows" ^
  -DCMAKE_MODULE_PATH="C:/vcpkg/installed/x64-windows/share/ffmpeg" ^
  -DCMAKE_TOOLCHAIN_FILE="C:/vcpkg/scripts/buildsystems/vcpkg.cmake"

cmake --build build-win --config Release
```

### 3. Deploy Qt DLLs (automatic)
The CMake build runs `windeployqt --qmldir qml` as a post-build step, so the
`build-win` folder is self-contained. If you move the `.exe`, re-run manually:
```powershell
windeployqt --qmldir qml build-win\GhitaEdit.exe
```

## Build — Linux / WSL
1. Install system packages:
   ```bash
   sudo apt install qt6-base-dev qt6-declarative-dev libqt6opengl6-dev \
     libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
     libswresample-dev portaudio19-dev ninja-build pkg-config
   ```
2. Configure & build:
   ```bash
   cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
   ninja -C build
   ```
3. Running under WSL: GUI needs a display. Use WSLg or an X server (VcXsrv).
   Headless test: `QT_QPA_PLATFORM=offscreen ./build/GhitaEdit`

## Run
```
./build/GhitaEdit        # or build-win\GhitaEdit.exe on Windows
```
A window opens with a toolbar, preview surface, timeline, and status bar.
Use **Open** to load a media file (MP4, MKV, MOV, AVI).

## Roadmap
| Milestone | Scope | Status |
|-----------|-------|-------|
| M0 | Basic playback: FFmpeg decode → OpenGL preview, PortAudio output | ✅ done |
| M0.5 | Frame throttle + AudioClock + duration/position display | ✅ done |
| M1 | Timeline: multi-track cut/trim/snap, undo/redo | ✅ done |
| M2 | Audio DSP: gain, normalize, fade-in/out | ✅ done |
| M3 | Video FX: brightness / contrast / saturation color grade | ✅ done |
| M4 | Export: MP4 (libx264 video + AAC audio) with effects baked in | ✅ done |
| M5 | Plugin system (C API + Python binding) | |

### What works today
- **Open** any MP4/MKV/MOV/AVI — its video lands on track V1 and audio on A1.
- **Play / Pause / Stop**, scrub the ruler, spacebar toggles playback.
- **Edit**: drag clips, trim handles, split at playhead (`S`), delete (`Del`),
  full undo/redo (`Ctrl+Z` / `Ctrl+Y`), snap-to edges.
- **Effects panel** (right side): brightness, contrast, saturation, audio gain
  (dB), normalize, fade-in/out. Reset button restores defaults.
- **Export**: pick an output `.mp4`, watch the progress bar; the file is encoded
  with your effects applied (software libx264/AAC; HW encode is a later opt).

### Known limitations (next steps)
- Export re-encodes with software libx264/AAC (NVENC/AMF/QuickSync not wired yet).
- Video FX is a YUV brightness/contrast/saturation grade (no crop/transitions yet).
- Audio DSP has gain/normalize/fade (no EQ or time-stretch yet).
- Timeline currently lays clips per-track; overlapping multi-clip composition is
  sequential per track.

## License
GPL-3.0-or-later.
