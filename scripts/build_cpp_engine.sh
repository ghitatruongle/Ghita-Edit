# Build the legacy C++ engine DLL — the parity oracle for
# native_engine_rust/tools/engine_compare.
#
# Since v1.5.5-beta2 (T1.P3) the C++ engine is out of the product build; the
# app ships the Rust ghita_engine.dll only. This standalone MinGW build is
# the supported way to refresh the oracle the A/B harness loads from
# native_engine/build/libghita_engine.dll.
#
# Usage: bash scripts/build_cpp_engine.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/c/msys64/mingw64/bin:$PATH"

# Locate CMake: PATH first, then the Visual Studio bundle / standalone
# install / Android SDK copy. (mingw64 does not ship cmake.)
CMAKE_BIN="$(command -v cmake || true)"
if [ -z "$CMAKE_BIN" ]; then
  for c in \
    "/c/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" \
    "/c/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe" \
    "/c/Program Files/CMake/bin/cmake.exe" \
    "$LOCALAPPDATA/Android/Sdk/cmake/3.22.1/bin/cmake.exe"; do
    if [ -f "$c" ]; then CMAKE_BIN="$c"; break; fi
  done
fi
if [ -z "$CMAKE_BIN" ]; then
  echo "ERROR: cmake not found — install CMake or the VS C++ workload" >&2
  exit 1
fi

# Build in a DEDICATED mingw64 dir with EXPLICIT mingw64 compilers. The old
# native_engine/build cache pins the ucrt64 g++, whose gcc 16.1 headers break
# on <chrono>/<ctime> (timespec_get) — reviewed beta2. The mingw64 toolchain
# compiles the same source fine; its FFmpeg links against the same
# av*-62.dll family already sitting next to the harness oracle.
"$CMAKE_BIN" -B "$ROOT/native_engine/build-mingw64" -S "$ROOT/native_engine" \
  -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=C:/msys64/mingw64/bin/gcc.exe \
  -DCMAKE_CXX_COMPILER=C:/msys64/mingw64/bin/g++.exe
"$CMAKE_BIN" --build "$ROOT/native_engine/build-mingw64" --target ghita_engine -j 2

# Swap the harness oracle (backup the previous one first).
cp -f "$ROOT/native_engine/build/libghita_engine.dll" "$ROOT/native_engine/build/libghita_engine.dll.bak"
cp -f "$ROOT/native_engine/build-mingw64/libghita_engine.dll" "$ROOT/native_engine/build/libghita_engine.dll"

echo "C++ oracle DLL refreshed (previous build kept as .bak):"
ls -la "$ROOT/native_engine/build/libghita_engine.dll" "$ROOT/native_engine/build-mingw64/libghita_engine.dll"
echo "Verify: cd native_engine_rust/tools/engine_compare && cargo run --release"
