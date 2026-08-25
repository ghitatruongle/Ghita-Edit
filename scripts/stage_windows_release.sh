# Stage the Windows Release bundle with the REAL native engine.
#
# `flutter build windows --release` alone produces a REGRESSED bundle:
#   1. CMake still builds the legacy C++ engine (native_engine/) and installs
#      its ghita_engine.dll over the Rust one.
#   2. FFmpeg runtime DLLs come from vcpkg — an older set whose avformat
#      lacks the PNG demuxer, so image imports fall back to synthetic.
# This script re-stages the correct files after every flutter build.
#
# Usage: bash scripts/stage_windows_release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="$ROOT/build/windows/x64/runner/Release"
RUST_DLL="$ROOT/native_engine_rust/target/release/ghita_engine.dll"
# CI override: setup-msys2 installs into a runner temp dir, not /c/msys64 —
# export MSYS_MINGW_BIN=<root>/mingw64/bin there.
MSYS_BIN="${MSYS_MINGW_BIN:-/c/msys64/mingw64/bin}"

for f in "$RUST_DLL" \
  "$MSYS_BIN/avcodec-62.dll" "$MSYS_BIN/avformat-62.dll" "$MSYS_BIN/avutil-60.dll" \
  "$MSYS_BIN/avdevice-62.dll" "$MSYS_BIN/avfilter-11.dll" \
  "$MSYS_BIN/swresample-6.dll" "$MSYS_BIN/swscale-9.dll"; do
  [ -f "$f" ] || { echo "ERROR: missing $f — build the Rust DLL or fix msys64 path"; exit 1; }
done

cp -f "$RUST_DLL" "$REL/ghita_engine.dll"
for d in avcodec-62 avformat-62 avutil-60 avdevice-62 avfilter-11 swresample-6 swscale-9; do
  cp -f "$MSYS_BIN/$d.dll" "$REL/$d.dll"
done

# The msys64 FFmpeg DLLs statically import ~60 third-party DLLs — without the
# full closure the engine DLL fails to load on any machine without msys64 in
# PATH (Demo Mode). Computes + copies the closure, dropping avdevice/avfilter
# (not imported by the Rust engine).
bash "$ROOT/scripts/bundle_ffmpeg_closure.sh"

# The legacy C++ engine backup must not ship in the installer/portable zip
# (.iss bundles every *.dll in Release).
rm -f "$REL/ghita_engine_cpp_backup.dll"

echo "Staged. Engine DLL hash:"
md5sum "$REL/ghita_engine.dll"
