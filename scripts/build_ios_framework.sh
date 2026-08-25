#!/bin/bash
# Build script for Ghita Edit — iOS native engine framework
# Requires: Xcode CLI tools with iOS SDK, FFmpeg (arm64 cross-compile)
# Usage: ./scripts/build_ios_framework.sh [Debug|Release]

set -euo pipefail

BUILD_TYPE="${1:-Release}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/native_engine/build_ios"
FRAMEWORK_DIR="$BUILD_DIR/ghita_engine.framework"

echo "=== Ghita Edit — iOS Native Engine Framework Build ==="
echo "Build type: $BUILD_TYPE"
echo "Project dir: $PROJECT_DIR"

# iOS toolchain file
cat > /tmp/ios-toolchain.cmake << 'TOOLCHAIN_EOF'
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
TOOLCHAIN_EOF

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "Configuring CMake for iOS arm64..."
cmake "$PROJECT_DIR/native_engine" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_TOOLCHAIN_FILE=/tmp/ios-toolchain.cmake \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_OSX_SYSROOT="iphoneos" \
    -DBUILD_TESTING=OFF \
    -DGHITA_NO_FFMPEG=ON

echo "Building..."
cmake --build . --config "$BUILD_TYPE" -j"$(sysctl -n hw.ncpu)"

# Create framework structure
mkdir -p "$FRAMEWORK_DIR/Headers"
cp "$BUILD_DIR/libghita_engine.a" "$FRAMEWORK_DIR/ghita_engine"
cp "$PROJECT_DIR/native_engine/include/ghita_c_api.h" "$FRAMEWORK_DIR/Headers/"
cp "$PROJECT_DIR/native_engine/include/ghita_engine.h" "$FRAMEWORK_DIR/Headers/"

# Engine version from single source of truth (same pattern as CI version gate)
ENGINE_VERSION="$(sed -n 's/.*kMajorVersion = \([0-9]*\).*/\1/p' "$PROJECT_DIR/lib/src/core/version.dart").$(sed -n 's/.*kMinorVersion = \([0-9]*\).*/\1/p' "$PROJECT_DIR/lib/src/core/version.dart").$(sed -n 's/.*kPatchVersion = \([0-9]*\).*/\1/p' "$PROJECT_DIR/lib/src/core/version.dart")"
if [ -z "${ENGINE_VERSION//./}" ]; then
    echo "ERROR: cannot parse version from lib/src/core/version.dart" >&2
    exit 1
fi

# Create Info.plist for framework
cat > "$FRAMEWORK_DIR/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentVersion</key>
    <string>$ENGINE_VERSION</string>
    <key>CFBundleExecutable</key>
    <string>ghita_engine</string>
    <key>CFBundleIdentifier</key>
    <string>com.ghita.ghita-engine</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Ghita Engine</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$ENGINE_VERSION</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>MinimumOSVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST_EOF

echo "=== iOS Framework Build Complete ==="
echo "Framework: $FRAMEWORK_DIR"
echo ""
echo "Note: Built without FFmpeg (GHITA_NO_FFMPEG=ON)"
echo "For FFmpeg support on iOS, see:"
echo "  https://ffmpeg.org/platform.html#iOS"
echo "  Then rebuild with GHITA_NO_FFMPEG=OFF and set FFMPEG_INCLUDE_DIRS"
