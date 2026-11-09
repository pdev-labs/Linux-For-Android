#!/usr/bin/env bash
# Build the Android native side of the display app:
#   * libffi for arm64-v8a
#   * libwayland-server for arm64-v8a
#   * libwayland-compositor.so from the vendored sources
# and copy everything into app/src/main/jniLibs/arm64-v8a/.
#
# Requirements: Android NDK (ANDROID_NDK_HOME or /opt/android-ndk), meson,
# ninja, a host wayland-scanner matching the wayland source version, curl.
#
# Usage: scripts/build-native.sh [ndk-path]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JNI="$ROOT/app/src/main/jni"
OUT="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="${LFA_WD_WORK:-$HOME/.cache/lfa-wd/native}"

NDK="${1:-${ANDROID_NDK_HOME:-/opt/android-ndk}}"
[ -d "$NDK" ] || { echo "NDK not found: $NDK" >&2; exit 1; }

HOST_TAG=linux-x86_64
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) HOST_TAG=darwin-arm64 ;;
  Darwin-*)     HOST_TAG=darwin-x86_64 ;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
CLANG="$TOOLCHAIN/bin/aarch64-linux-android26-clang"
[ -x "$CLANG" ] || { echo "clang not found: $CLANG" >&2; exit 1; }

WAYLAND_VERSION="${WAYLAND_VERSION:-$(pkg-config --modversion wayland-scanner 2>/dev/null || echo 1.26.0)}"
FFI_VERSION="${FFI_VERSION:-3.4.6}"
API=26

mkdir -p "$WORK" "$OUT"

# ---------------------------------------------------------------- libffi
if [ ! -f "$WORK/libffi-install/lib/libffi.so" ]; then
  cd "$WORK"
  [ -f "libffi-$FFI_VERSION.tar.gz" ] || \
    curl -sL "https://github.com/libffi/libffi/releases/download/v$FFI_VERSION/libffi-$FFI_VERSION.tar.gz" -o "libffi-$FFI_VERSION.tar.gz"
  rm -rf "libffi-$FFI_VERSION" libffi-install
  tar xzf "libffi-$FFI_VERSION.tar.gz"
  mkdir -p "libffi-$FFI_VERSION/build-android"
  (
    cd "libffi-$FFI_VERSION/build-android"
    CC="$TOOLCHAIN/bin/aarch64-linux-android$API-clang" \
    CFLAGS="-DANDROID -fPIC -std=gnu11" LDFLAGS="-fPIC" \
      ../configure --host=aarch64-linux-android --prefix="$WORK/libffi-install" \
        --disable-docs --disable-multi-os-directory --disable-static
    make -j"$(nproc)"
    make install
  )
fi

# ------------------------------------------------------------- wayland
if [ ! -f "$WORK/wayland-prefix/lib/libwayland-server.so" ]; then
  cd "$WORK"
  [ -d wayland ] || git clone -q --depth 1 --branch "$WAYLAND_VERSION" https://gitlab.freedesktop.org/wayland/wayland.git
  cat > android-arm64.txt <<EOF
[binaries]
c = '$CLANG'
cpp = '$TOOLCHAIN/bin/aarch64-linux-android$API-clang++'
ar = '$TOOLCHAIN/bin/llvm-ar'
strip = '$TOOLCHAIN/bin/llvm-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-fPIC']
cpp_args = ['-fPIC']
EOF
  rm -rf wayland/build-android
  (
    export PKG_CONFIG_PATH="$WORK/libffi-install/lib/pkgconfig"
    meson setup wayland/build-android --cross-file android-arm64.txt \
      -Dlibraries=true -Dscanner=false -Dtests=false -Ddocumentation=false \
      -Ddtd_validation=false --prefix="$WORK/wayland-prefix"
    ninja -C wayland/build-android
    ninja -C wayland/build-android install
  )
fi

# ---------------------------------------------------------- compositor
cd "$WORK"
cmake -S "$JNI" -B compositor-build \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-$API \
  -DCMAKE_BUILD_TYPE=Release \
  -DWAYLAND_PREFIX="$WORK/wayland-prefix" >/dev/null
cmake --build compositor-build -j"$(nproc)"

cp compositor-build/libwayland-compositor.so "$OUT/"
cp compositor-build/liblfabridge.so "$OUT/"
cp "$WORK/wayland-prefix/lib/libwayland-server.so" "$OUT/"
cp "$WORK/libffi-install/lib/libffi.so" "$OUT/"

echo "native libs in $OUT:"
ls -l "$OUT"
