#!/usr/bin/env bash
# build_release.sh — one-command Windows release pipeline for Ghita Edit.
#
#   1. flutter build windows --release        (app + native engine + FFmpeg DLLs)
#   2. Inno Setup (ISCC) installer compile    (installer/ghita_edit_setup.iss)
#   3. Copy the installer to dist/
#
# Usage:
#   bash scripts/build_release.sh [--skip-smoke] [--keep-installer-output]
#
#   --skip-smoke              skip the engine smoke test after the build.
#   --keep-installer-output   also keep the copy in installer/output/ (default:
#                             dist/ is the canonical location; installer/output
#                             is deleted after copying).
#
# Requirements:
#   * Flutter SDK on PATH (or in $HOME/flutter/bin or /c/flutter/bin)
#   * Inno Setup 6 installed at one of the common ISCC locations
#   * Bash (Git Bash / MSYS2) — the repo scripts already assume this
#
# Notes:
#   * A running ghita_edit.exe locks the engine DLL and breaks the build —
#     the script asks to close it (and, with --force-kill, terminates it).
#   * The .iss uses OutputDir=output relative to the .iss file, so the raw
#     installer is produced in installer/output/ before being moved to dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_SMOKE=0
KEEP_INSTALLER_OUTPUT=0
FORCE_KILL=0
for arg in "$@"; do
  case "$arg" in
    --skip-smoke)            SKIP_SMOKE=1 ;;
    --keep-installer-output) KEEP_INSTALLER_OUTPUT=1 ;;
    --force-kill)            FORCE_KILL=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

RELEASE_DIR="build/windows/x64/runner/Release"
EXE="$RELEASE_DIR/ghita_edit.exe"
ISS="installer/ghita_edit_setup.iss"
DIST_DIR="dist"
INSTALLER_OUT="installer/output"

# ---------------------------------------------------------------------------
# Locate tools
# ---------------------------------------------------------------------------
FLUTTER="$(command -v flutter || true)"
if [ -z "$FLUTTER" ]; then
  for cand in "$HOME/flutter/bin/flutter" "/c/flutter/bin/flutter"; do
    if [ -x "$cand" ]; then FLUTTER="$cand"; break; fi
  done
fi
if [ -z "$FLUTTER" ]; then
  echo "ERROR: flutter not found — add it to PATH or install under \$HOME/flutter" >&2
  exit 1
fi

ISCC=""
for cand in \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe" \
    "${LOCALAPPDATA:-}/Programs/Inno Setup 6/ISCC.exe"; do
  if [ -f "$cand" ]; then ISCC="$cand"; break; fi
done
if [ -z "$ISCC" ]; then
  echo "ERROR: ISCC.exe not found — install Inno Setup 6" >&2
  exit 1
fi

echo "== Ghita Edit — Windows Release Pipeline =="
echo "Flutter: $FLUTTER"
echo "ISCC:    $ISCC"

# ---------------------------------------------------------------------------
# 0. A running app locks ghita_engine.dll and breaks the build — resolve it.
# ---------------------------------------------------------------------------
# grep -c (not -q) so the pipeline can't SIGPIPE tasklist and silently skip
# the lock check under `set -o pipefail`.
APP_RUNNING="$(tasklist 2>/dev/null | grep -ci "ghita_edit\.exe" || true)"
if [ "${APP_RUNNING:-0}" -gt 0 ]; then
  if [ "$FORCE_KILL" -eq 1 ]; then
    echo "-- closing running ghita_edit.exe ..."
    taskkill //IM ghita_edit.exe //F >/dev/null 2>&1 || true
    sleep 1
  else
    echo "ERROR: ghita_edit.exe is running and would lock the engine DLL." >&2
    echo "       Close the app, or re-run with --force-kill." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 1. Build the Release app (native engine + FFmpeg DLLs included)
# ---------------------------------------------------------------------------
echo "-- flutter build windows --release ..."
"$FLUTTER" build windows --release

if [ ! -f "$EXE" ]; then
  echo "ERROR: build did not produce $EXE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Optional: engine smoke test (catches Demo-Mode regressions before the
#    installer is made). Requires ffmpeg CLI for full media checks; the
#    engine-only path still runs without it.
# ---------------------------------------------------------------------------
if [ "$SKIP_SMOKE" -eq 0 ]; then
  echo "-- engine smoke test ..."
  if ! bash scripts/run_engine_smoke_test.sh; then
    echo "ERROR: engine smoke test failed — installer NOT produced." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 3. Compile the Inno Setup installer
# ---------------------------------------------------------------------------
echo "-- compiling installer: $ISS ..."
mkdir -p "$INSTALLER_OUT"
# Drop stale installers from previous builds/versions so the glob below can
# never select an old one. The .iss writes OutputDir=output relative to the
# .iss file, so the fresh installer lands in installer/output/.
rm -f "$INSTALLER_OUT"/*.exe 2>/dev/null || true
ISCC_LOG="$(mktemp)"
# ISCC emits CRLF paths in its log; just pass the Windows-style path.
if ! "$ISCC" "$(cygpath -w "$ISS")" >"$ISCC_LOG" 2>&1; then
  echo "ERROR: ISCC failed — log:" >&2
  tail -30 "$ISCC_LOG" >&2
  rm -f "$ISCC_LOG"
  exit 1
fi
rm -f "$ISCC_LOG"

INSTALLER="$(ls "$INSTALLER_OUT"/GhitaEdit-*-Setup.exe 2>/dev/null | head -1 || true)"
if [ -z "$INSTALLER" ]; then
  echo "ERROR: ISCC did not produce an installer in $INSTALLER_OUT" >&2
  exit 1
fi
echo "-- installer built: $INSTALLER"

# ---------------------------------------------------------------------------
# 4. Copy to dist/ (canonical location)
# ---------------------------------------------------------------------------
mkdir -p "$DIST_DIR"
DIST_TARGET="$DIST_DIR/$(basename "$INSTALLER")"
cp -f "$INSTALLER" "$DIST_TARGET"

if [ "$KEEP_INSTALLER_OUTPUT" -eq 0 ]; then
  rm -f "$INSTALLER"
  echo "-- removed intermediate copy ($INSTALLER_OUT)"
fi

echo ""
echo "== Release pipeline complete =="
echo "Installer: $DIST_TARGET"
echo "App:       $RELEASE_DIR/ghita_edit.exe"
ls -lh "$DIST_TARGET"
