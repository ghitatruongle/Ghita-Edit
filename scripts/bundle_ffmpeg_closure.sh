# Bundle the FULL transitive DLL closure of the FFmpeg runtime into the
# Windows Release folder.
#
# Why: the msys64 FFmpeg DLLs statically import ~60 third-party DLLs (libx264,
# libgnutls, zlib1, libwinpthread-1, ...). Windows refuses to load
# ghita_engine.dll unless EVERY static import in the chain resolves, so an
# installer that ships only the 7 av*/sw* DLLs works on the dev machine
# (msys64 in PATH) and dead-ends into Demo Mode on a clean machine.
#
# The closure is computed with objdump per DLL, BFS until fixpoint, copying
# every non-system import from msys64/mingw64/bin. avdevice-62/avfilter-11 are
# dropped first: the Rust engine does not import them (objdump-verified) and
# they drag huge trees (libwhisper/ggml/libplacebo/libopenal) nothing uses.
#
# Usage: bash scripts/bundle_ffmpeg_closure.sh
set -euo pipefail

REL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/windows/x64/runner/Release"
# CI override: setup-msys2 installs into a runner temp dir, not /c/msys64.
MSYS_BIN="${MSYS_MINGW_BIN:-/c/msys64/mingw64/bin}"

[ -f "$MSYS_BIN/avcodec-62.dll" ] || { echo "ERROR: msys64 FFmpeg not found at $MSYS_BIN"; exit 1; }

# DLLs that always resolve from the OS: anything present in System32 ships
# with every Windows install, so never copy it into the bundle.
is_system_dll() {
  [ -f "/c/Windows/System32/$1" ] && return 0
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    api-ms-win-*) return 0 ;;
    *) return 1 ;;
  esac
}

# Roots: exactly what ghita_engine.dll imports (objdump-verified 2026-08-24).
ROOTS="avcodec-62.dll avformat-62.dll avutil-60.dll swresample-6.dll swscale-9.dll"

# avdevice/avfilter are NOT imported by the Rust engine — drop them so their
# dependency trees (whisper, ggml, placebo, openal, ...) never ship.
rm -f "$REL/avdevice-62.dll" "$REL/avfilter-11.dll"

declare -A seen
queue=()
for r in $ROOTS; do
  cp -f "$MSYS_BIN/$r" "$REL/$r"
  seen["$r"]=1
  queue+=("$r")
done

copied=0
while [ ${#queue[@]} -gt 0 ]; do
  next=()
  for dll in "${queue[@]}"; do
    while IFS= read -r dep; do
      dep_lc="$(echo "$dep" | tr '[:upper:]' '[:lower:]')"
      is_system_dll "$dep_lc" && continue
      [ -n "${seen[$dep_lc]:-}" ] && continue
      seen["$dep_lc"]=1
      if [ ! -f "$MSYS_BIN/$dep" ]; then
        echo "ERROR: $dll imports $dep which is not in $MSYS_BIN" >&2
        exit 1
      fi
      cp -f "$MSYS_BIN/$dep" "$REL/$dep"
      next+=("$dep_lc")
      copied=$((copied + 1))
    done < <("$MSYS_BIN/objdump" -p "$MSYS_BIN/$dll" 2>/dev/null | sed -n 's/.*DLL Name: //p')
  done
  queue=("${next[@]}")
done

echo "Bundled $copied dependency DLLs (+5 roots). Total files in Release:"
ls "$REL"/*.dll | wc -l
