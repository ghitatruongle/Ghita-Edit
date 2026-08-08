#!/usr/bin/env bash
# run_engine_smoke_test.sh — real-engine smoke test for Windows Release builds (v1.0.1).
#
# Verifies, against the ACTUAL built Release output:
#   * the engine DLL loads and initializes (create/init/version/destroy),
#   * the FFmpeg runtime DLLs are bundled next to the engine when it needs
#     them (the "silent Demo Mode" regression from v1.0.1),
#   * a real MP3 can be imported and played with a clean log (no FFmpeg
#     warning spam per frame),
#   * a real MP4 (video + audio tracks) plays with live non-black frames,
#     changing frame content, and audio decoding in sync with the playhead.
#
# Usage:
#   bash scripts/run_engine_smoke_test.sh [--dll PATH] [--seconds N] [--quick]
#
#   --dll      path to ghita_engine.dll (default: build/windows/x64/runner/Release)
#   --seconds  media playback length in seconds (default 10)
#   --quick    engine load/init checks only (no media import/playback)
#
# Notes:
#   * Run `flutter build windows --release` first — this script checks the
#     built output, it does not build.
#   * If a real ffmpeg CLI is available, a short test-tone MP3 is generated
#     so the full import/playback path is exercised. Without ffmpeg the
#     engine-only checks still run (with a warning).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DLL="build/windows/x64/runner/Release/ghita_engine.dll"
SECONDS=10
QUICK=0
MP3_OUT="build/test_media/test_tone.mp3"
VIDEO_OUT="build/test_media/test_video.mp4"

# Locate the Dart SDK (PATH, then common Flutter installs).
DART="$(command -v dart || true)"
if [ -z "$DART" ]; then
  for cand in "$HOME/flutter/bin/dart" "/c/flutter/bin/dart"; do
    if [ -x "$cand" ]; then DART="$cand"; break; fi
  done
fi
if [ -z "$DART" ]; then
  echo "ERROR: dart not found — install Flutter and put dart on PATH" >&2
  exit 1
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --dll)    DLL="$2"; shift 2 ;;
    --seconds) SECONDS="$2"; shift 2 ;;
    --quick)  QUICK=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "== Engine smoke test (release check) =="
echo "DLL: $DLL"

if [ ! -f "$DLL" ]; then
  echo "ERROR: engine DLL not found at $DLL" >&2
  echo "Build the Release app first: flutter build windows --release" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# 1. Generate a real MP3 and a real MP4 (video + audio) when an ffmpeg CLI
#    is available, so the full import + playback path is exercised.
# --------------------------------------------------------------------------
FFMPEG="$(command -v ffmpeg || command -v ffmpeg.exe || true)"
MEDIA_ARGS=()
if [ "$QUICK" -eq 0 ]; then
  if [ -n "$FFMPEG" ]; then
    # Always regenerate — a stale file from a previous --seconds run would
    # mismatch the clip duration this invocation claims to test.
    mkdir -p "$(dirname "$MP3_OUT")"
    echo "-- generating ${SECONDS}s test tone: $MP3_OUT"
    # Native 'mp3' encoder is built into every ffmpeg — no libmp3lame dep.
    "$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=$SECONDS" \
      -filter:a "volume=-18dB" -c:a mp3 -b:a 128k "$MP3_OUT" >/dev/null 2>&1
    if [ -s "$MP3_OUT" ]; then
      MEDIA_ARGS=(--mp3 "$MP3_OUT" --seconds "$SECONDS")
    else
      echo "-- WARN: MP3 generation failed (no mp3 encoder?) — audio checks skipped"
    fi
    # testsrc2 = moving test pattern with a clock; the H.264/AAC stream is
    # decoded by the engine's FFmpeg path (both tracks, in sync).
    echo "-- generating ${SECONDS}s test video: $VIDEO_OUT"
    "$FFMPEG" -y -f lavfi -i "testsrc2=size=320x240:rate=30:duration=$SECONDS" \
      -f lavfi -i "sine=frequency=440:duration=$SECONDS" \
      -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k \
      -shortest -movflags +faststart "$VIDEO_OUT" >/dev/null 2>&1
    if [ -s "$VIDEO_OUT" ]; then
      MEDIA_ARGS+=(--video "$VIDEO_OUT")
    else
      echo "-- WARN: MP4 generation failed (missing libx264?) — video checks skipped"
    fi
  else
    echo "-- WARN: no ffmpeg CLI found — skipping media import/playback checks (engine-only)"
    MEDIA_ARGS=(--quick)
  fi
fi

# --------------------------------------------------------------------------
# 2. Run the smoke test, capturing stderr so FFmpeg log spam can be checked.
# --------------------------------------------------------------------------
STDERR_FILE="$(mktemp)"
trap 'rm -f "$STDERR_FILE"' EXIT
set +e
if [ "$QUICK" -eq 1 ]; then
  "$DART" run scripts/engine_smoke_test.dart --dll "$DLL" --quick 2>"$STDERR_FILE"
else
  "$DART" run scripts/engine_smoke_test.dart --dll "$DLL" "${MEDIA_ARGS[@]}" 2>"$STDERR_FILE"
fi
TEST_CODE=$?
set -e

# --------------------------------------------------------------------------
# 3. Fail on FFmpeg log spam (the per-frame warning flood fixed in v1.0.1).
# --------------------------------------------------------------------------
SPAM="$(grep -E "\[(mp3float|swscaler|mp3|h264|aac|hevc)\]|Could not update timestamps|deprecated pixel format" "$STDERR_FILE" | grep -v "Running build hooks" || true)"
if [ -n "$SPAM" ]; then
  echo "FAIL: FFmpeg log spam detected in stderr:" >&2
  echo "$SPAM" | head -20 >&2
  TEST_CODE=1
fi

if [ "$TEST_CODE" -ne 0 ]; then
  echo "== ENGINE SMOKE TEST FAILED (exit $TEST_CODE) ==" >&2
  exit "$TEST_CODE"
fi
echo "== ENGINE SMOKE TEST PASSED =="
