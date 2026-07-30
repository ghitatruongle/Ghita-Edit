#!/bin/bash
# Build script for Ghita Edit — macOS native engine
# Requires: Xcode CLI tools, Homebrew, FFmpeg
# Usage: ./scripts/build_macos.sh [Debug|Release]

set -euo pipefail

BUILD_TYPE="${1:-Release}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/native_engine/build_macos"

echo "=== Ghita Edit — macOS Native Engine Build ==="
echo "Build type: $BUILD_TYPE"
echo "Project dir: $PROJECT_DIR"

# Check for FFmpeg
if ! command -v pkg-config &> /dev/null; then
    echo "pkg-config not found. Installing via Homebrew..."
    brew install pkg-config
fi

if ! pkg-config --exists libavcodec libavformat libavutil libswscale libswresample; then
    echo "FFmpeg libraries not found. Installing via Homebrew..."
    brew install ffmpeg
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure with CMake
echo "Configuring CMake..."
cmake "$PROJECT_DIR/native_engine" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DBUILD_TESTING=ON

# Build
echo "Building..."
cmake --build . --config "$BUILD_TYPE" -j"$(sysctl -n hw.ncpu)"

# Run self-tests
echo "Running native engine self-tests..."
./native_engine_test

echo "=== macOS Build Complete ==="
echo "Output: $BUILD_DIR/libghita_engine.dylib"
