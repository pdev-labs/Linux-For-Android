#!/bin/bash
# Install the pinned Termux debug APK on the emulator and wait for the
# bootstrap to finish.
#
# Pinned on purpose: a moving "latest" download makes old Android results
# impossible to reproduce. Bump the version and SHA together in one PR.
set -euo pipefail

ARCH="${TERMUX_ARCH:-x86_64}"
API_LEVEL="${TERMUX_API_LEVEL:-33}"

# Termux 0.118.0 was the last build with Android 5 (minSdk 21); 0.118.3
# requires Android 7 (API 24). Pick the matching debug APK for the device.
if [ "$API_LEVEL" -lt 24 ]; then
    TERMUX_VERSION="${TERMUX_LEGACY_VERSION:-0.118.0}"
else
    TERMUX_VERSION="${TERMUX_VERSION:-0.118.3}"
fi

case "${TERMUX_VERSION}:${ARCH}" in
    0.118.3:x86_64)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_x86_64.apk"
        APK_SHA256="3550e61f4d9eb49b712fd1bd9519dc37085a4d8eb597c57a340f0a64859b7144"
        ;;
    0.118.3:x86)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_x86.apk"
        APK_SHA256="b6a980ac2fbda1c61edc7be389ce69da9a90af8444d27164b5e20b7a22442570"
        ;;
    0.118.3:arm64-v8a)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_arm64-v8a.apk"
        APK_SHA256="72fdb596045116bf5ba1b5bdf5b26fddb9acc0bd074ad9f2da9eb0ae85e83a4e"
        ;;
    0.118.3:armeabi-v7a)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_armeabi-v7a.apk"
        APK_SHA256="89416397b70f9ff67a0044e8abe6ef82487cd48fcf543e2d23e02688cc541cf0"
        ;;
    0.118.0:x86_64)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_x86_64.apk"
        APK_SHA256="90c1e62bcede3897cf097d179658f08340d5adde84d50bfae7af056d6dd6c32e"
        ;;
    0.118.0:x86)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_x86.apk"
        APK_SHA256="a5cbc3aea8c199c4db5fbc3697ad8e92117d354ada845a03713e000950a8574f"
        ;;
    0.118.0:arm64-v8a)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_arm64-v8a.apk"
        APK_SHA256="10b412fa0aca5a4585c367a446f8e63525bdc9a7b8dfce2d3f84c2f148e19e21"
        ;;
    0.118.0:armeabi-v7a)
        APK_NAME="termux-app_v${TERMUX_VERSION}+github-debug_armeabi-v7a.apk"
        APK_SHA256="84f1d108c1bfb8aed3c0f61253b778ca1d6dfbb2deec2a7f8d1ab89b2c9c7a52"
        ;;
    *)
        echo "Unsupported Termux version/arch: $TERMUX_VERSION / $ARCH" >&2
        echo "Add the pinned SHA-256 to install-termux.sh before using it." >&2
        exit 2
        ;;
esac

URL="https://github.com/termux/termux-app/releases/download/v${TERMUX_VERSION}/${APK_NAME//+/%2B}"
CACHE="${RUNNER_TEMP:-/tmp}/termux-apks"
mkdir -p "$CACHE"
APK="$CACHE/$APK_NAME"

if [ ! -f "$APK" ]; then
    echo "Downloading Termux $TERMUX_VERSION ($ARCH)..."
    curl -fL --retry 3 --retry-delay 2 -o "$APK.part" "$URL"
    mv "$APK.part" "$APK"
fi

echo "$APK_SHA256  $APK" | sha256sum -c -

command -v adb >/dev/null 2>&1 || { echo "adb is required" >&2; exit 2; }
adb wait-for-device

echo "Installing $APK_NAME on API $API_LEVEL..."
if ! adb install -r -g "$APK"; then
    echo "Termux $TERMUX_VERSION could not be installed on API $API_LEVEL." >&2
    echo "Older releases may be required for API 21/22/23; see docs/CI-ANDROID.md." >&2
    exit 1
fi

# Keep the emulator quiet and the clock stable.
adb shell settings put global window_animation_scale 0 >/dev/null 2>&1 || true
adb shell settings put global transition_animation_scale 0 >/dev/null 2>&1 || true
adb shell settings put global animator_duration_scale 0 >/dev/null 2>&1 || true

# Launch once so Termux extracts its bootstrap. `run-as` cannot do that for
# us: the extraction happens in the app process.
adb shell am start -n com.termux/.app.TermuxActivity >/dev/null 2>&1 || true

echo "Waiting for the Termux bootstrap..."
for _i in $(seq 1 120); do
    if adb shell run-as com.termux test -x /data/data/com.termux/files/usr/bin/bash >/dev/null 2>&1; then
        echo "Termux bootstrap is ready."
        adb shell am force-stop com.termux >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 2
done

echo "Termux bootstrap did not appear within 240 seconds." >&2
adb shell run-as com.termux ls /data/data/com.termux/files 2>&1 || true
adb logcat -d -s Termux:Boot Termux 2>/dev/null | tail -n 80 || true
exit 1
