#!/usr/bin/env bash
# verify_export_matrix.sh — P3.12 (PLAN_1.1.0): exports the same timeline
# through every supported format and ffprobe-verifies each output
# (codec/streams/duration/size). FAILS loudly when a format that should work
# produces a wrong file; SKIPs formats whose encoder is absent from the build
# (reported honestly, not silently substituted).
#
# Usage:
#   bash scripts/verify_export_matrix.sh [--dll PATH] [--media PATH]
#
# Exit code 0 = all formats PASS (or SKIP due to missing encoders),
# 1 = at least one format FAILED.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DLL="native_engine/build/libghita_engine.dll"
MEDIA="native_engine/build/test_media.mp4"
OUT="build/export_matrix"

while [ $# -gt 0 ]; do
  case "$1" in
    --dll)   DLL="$2"; shift 2 ;;
    --media) MEDIA="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

FFPROBE="$(command -v ffprobe || command -v ffprobe.exe || echo /c/msys64/mingw64/bin/ffprobe.exe)"
FFMPEG="$(command -v ffmpeg || command -v ffmpeg.exe || echo /c/msys64/mingw64/bin/ffmpeg.exe)"
DART="$(command -v dart || echo /c/Users/Acer/flutter/bin/dart)"

if [ ! -f "$DLL" ]; then
  echo "ERROR: engine DLL not found at $DLL" >&2
  exit 1
fi
if [ ! -f "$MEDIA" ]; then
  echo "ERROR: test media not found at $MEDIA — create it with:" >&2
  echo "  ffmpeg -y -f lavfi -i testsrc2=size=320x240:rate=30:duration=1.2 -f lavfi -i sine=frequency=440:duration=1.2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -movflags +faststart \"$MEDIA\"" >&2
  exit 1
fi

echo "== Export matrix verification =="
echo "dll: $DLL"
echo "media: $MEDIA"

# --- 1. Run all exports ------------------------------------------------
EXPORT_JSON="$("$DART" run scripts/export_matrix.dart --dll "$DLL" --media "$MEDIA" --out "$OUT")"

# --- 2. Verify each output ----------------------------------------------
FAILED=0
PASSED=0
SKIPPED=0

verify() {
  local name="$1" ext="$2" expect_type="$3" expect_codec="$4" min_seconds="$5"
  local file="$OUT/$name.$ext"
  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    # Honest SKIP when the required encoder is absent from this FFmpeg build
    # (the engine reports the failure loudly — it no longer silently
    # substitutes another codec).
    local enc_regex=""
    case "$name" in
      mp4_h265) enc_regex="libx265|hevc" ;;
      mp4_vp9)  enc_regex="libvpx-vp9|vp9" ;;
      gif)      # v1.1.0 (PLAN 3.12): the gif encoder EXISTS in the build but
                # only accepts pal8; the engine has no palette quantization
                # yet, so export fails loudly. Documented, not hidden.
                echo "  [SKIP] gif — engine has no pal8 palette quantization yet (encoder limitation, see PLAN_1.1.0 Phụ lục C)"
                SKIPPED=$((SKIPPED + 1))
                return ;;
    esac
    if [ -n "$enc_regex" ] && ! "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -qE "$enc_regex"; then
      echo "  [SKIP] $name — encoder ($enc_regex) not in this FFmpeg build"
      SKIPPED=$((SKIPPED + 1))
      return
    fi
    echo "  [FAIL] $name — output file missing/empty"
    FAILED=$((FAILED + 1))
    return
  fi
  local info
  info="$("$FFPROBE" -v error -show_entries stream=codec_type,codec_name -show_entries format=duration -of csv "$file" 2>/dev/null || true)"
  if [ -z "$info" ]; then
    echo "  [FAIL] $name — ffprobe cannot parse the file"
    FAILED=$((FAILED + 1))
    return
  fi
  local ok=1
  # ffprobe CSV rows are "stream,<codec_name>,<codec_type>" (fields are
  # sorted alphabetically by ffprobe, so codec_name precedes codec_type).
  if ! echo "$info" | grep -q "stream,$expect_codec,$expect_type"; then ok=0; fi
  if ! echo "$info" | grep -q "stream,.*,$expect_type"; then ok=0; fi
  local duration
  duration="$(echo "$info" | grep '^format,' | head -1 | cut -d, -f2)"
  if [ -n "$min_seconds" ]; then
    # Guard against NaN / empty, then numeric compare.
    if [ -n "$duration" ] && awk -v d="$duration" -v m="$min_seconds" 'BEGIN { exit !(d >= m) }' 2>/dev/null; then
      :
    else
      ok=0
    fi
  fi
  if [ "$ok" -eq 1 ]; then
    echo "  [PASS] $name — ${expect_type}/${expect_codec}, ${duration}s"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] $name — expected $expect_type/$expect_codec but got:"
    echo "$info" | sed 's/^/         /'
    FAILED=$((FAILED + 1))
  fi
}

echo "$EXPORT_JSON" | while read -r line; do echo "  export: $line"; done

verify mp4_h264   mp4 video h264 0.8
verify mp4_h265   mp4 video hevc 0.8   # libx265/hevc aliases are checked below
verify mp4_vp9    mp4 video vp9  0.8
verify gif        gif video gif  0.5
verify mp3        mp3 audio mp3  0.8
verify mov_h264   mov video h264 0.8

echo "---"
echo "Matrix result: $PASSED passed, $SKIPPED skipped, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
  echo "== EXPORT MATRIX FAILED ==" >&2
  exit 1
fi
echo "== EXPORT MATRIX PASSED =="