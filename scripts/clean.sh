#!/usr/bin/env bash
# scripts/clean.sh — dọn rác build cục bộ (tất cả đều tái tạo được).
#
# The working tree used to carry ~15.7 GB of local junk (refer_project/,
# build/, dist/, gh.zip, ...). Nothing here is tracked by git; this script
# makes pruning it one deliberate command instead of manual rm -rf hunting.
#
# Usage:
#   bash scripts/clean.sh          # interactive: lists sizes, asks y/N
#   bash scripts/clean.sh -y       # no prompt
#   bash scripts/clean.sh --deep   # also removes native_engine_rust/target/
#                                  # and native_engine/build* (multi-GB;
#                                  # rebuilt by cargo/cmake on demand)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ASSUME_YES=0
DEEP=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)  ASSUME_YES=1 ;;
    --deep)    DEEP=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

TARGETS=(
  build
  dist
  coverage
  gh.zip
  debug.log
  test_out.mp4
  output.mp4
)
if [ "$DEEP" -eq 1 ]; then
  TARGETS+=(native_engine_rust/target native_engine/build native_engine/build_ios native_engine/build_assert)
fi

echo "== Clean targets under $ROOT =="
total=0
existing=()
for t in "${TARGETS[@]}"; do
  if [ -e "$t" ]; then
    size="$(du -sh "$t" 2>/dev/null | cut -f1)"
    echo "  $t  ($size)"
    existing+=("$t")
  fi
done

if [ "${#existing[@]}" -eq 0 ]; then
  echo "Nothing to clean."
  exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Delete the paths above? [y/N] " answer
  case "$answer" in
    y|Y|yes|Yes) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

for t in "${existing[@]}"; do
  rm -rf -- "$t"
  echo "  removed: $t"
done
echo "== Clean done =="
