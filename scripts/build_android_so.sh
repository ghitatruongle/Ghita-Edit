#!/usr/bin/env bash
# Automated Android NDK cross-compilation script for Ghita Engine (.so binaries)
set -e

if [ -z "$ANDROID_NDK_HOME" ]; then
  echo "Error: ANDROID_NDK_HOME environment variable is not set."
  exit 1
fi

TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
API_LEVEL=21
BUILD_DIR="native_engine/build_android"

ABIS=("arm64-v8a" "armeabi-v7a" "x86" "x86_64")

for ABI in "${ABIS[@]}"; do
  echo "Building Ghita Engine for Android ABI: $ABI..."
  mkdir -p "$BUILD_DIR/$ABI"
  cmake -B "$BUILD_DIR/$ABI" -S native_engine \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM=android-$API_LEVEL \
    -DCMAKE_BUILD_TYPE=Release

  cmake --build "$BUILD_DIR/$ABI" --config Release
  
  # Copy output .so binary to Flutter android jniLibs folder
  TARGET_JNI_DIR="android/app/src/main/jniLibs/$ABI"
  mkdir -p "$TARGET_JNI_DIR"
  cp "$BUILD_DIR/$ABI/libghita_engine.so" "$TARGET_JNI_DIR/"
  echo "Copied libghita_engine.so to $TARGET_JNI_DIR"
done

echo "Android NDK multi-ABI cross-compilation completed successfully!"
