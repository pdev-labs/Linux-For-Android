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

download_apk() { # $1=url $2=output
    local _url="$1" _out="$2"
    if curl -fL --retry 8 --retry-all-errors --retry-delay 5 \
        --connect-timeout 20 -o "$_out.part" "$_url"; then
        mv "$_out.part" "$_out"
        return 0
    fi
    rm -f "$_out.part"
    return 1
}

if [ ! -f "$APK" ]; then
    echo "Downloading Termux $TERMUX_VERSION ($ARCH)..."
    if ! download_apk "$URL" "$APK"; then
        # GitHub's release CDN occasionally returns 502/504 to hosted
        # runners. The API path is authenticated and more reliable.
        if command -v gh >/dev/null 2>&1 && [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
            echo "Direct download failed; trying the GitHub API..."
            GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}" \
                gh release download "v${TERMUX_VERSION}" --repo termux/termux-app \
                --pattern "$APK_NAME" --dir "$CACHE" --clobber
        fi
    fi
fi
[ -f "$APK" ] || {
    echo "Could not download $APK_NAME from $URL" >&2
    exit 1
}

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
adb shell am start -W -n com.termux/.app.TermuxActivity 2>&1 | sed 's/^/[termux] /' || true

bootstrap_ready() {
    adb shell run-as com.termux test -x /data/data/com.termux/files/usr/bin/bash >/dev/null 2>&1
}

# The app normally extracts the bundled bootstrap on first launch. Some
# emulator images fail there (native-library load, background kill, or a
# dialog that never gets dismissed). The APK also carries the same bootstrap
# zip as lib/<abi>/libtermux-bootstrap.so, so install it through `run-as`
# instead of leaving the whole scenario dead.
manual_bootstrap() {
    local _zip="$CACHE/bootstrap-$ARCH.zip"
    local _script="$CACHE/lfa-bootstrap.sh"
    if [ ! -s "$_zip" ]; then
        unzip -p "$APK" "lib/$ARCH/libtermux-bootstrap.so" > "$_zip" 2>/dev/null || return 1
    fi
    [ -s "$_zip" ] || return 1
    adb shell am force-stop com.termux >/dev/null 2>&1 || true
    adb push "$_zip" /data/local/tmp/lfa-bootstrap.zip >/dev/null || return 1
    cat > "$_script" <<'SH'
#!/system/bin/sh
set -e
FILES=/data/data/com.termux/files
STAGE=$FILES/usr-staging
ZIP=/data/local/tmp/lfa-bootstrap.zip
rm -rf "$STAGE" "$FILES/usr"
mkdir -p "$STAGE" "$FILES/home"
cd "$STAGE"
# The bundled .so is an ELF header followed by the zip; unzip warns about
# the extra bytes and exits non-zero even when extraction is complete.
if [ -x /system/bin/unzip ]; then
    /system/bin/unzip -q "$ZIP" || true
elif [ -x /system/xbin/unzip ]; then
    /system/xbin/unzip -q "$ZIP" || true
elif [ -x /system/bin/toybox ]; then
    /system/bin/toybox unzip -q "$ZIP" || true
else
    echo "no unzip binary on this image" >&2
    exit 1
fi
[ -f bin/bash ] || { echo "bootstrap extraction did not produce bin/bash" >&2; exit 1; }
if [ -f SYMLINKS.txt ]; then
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        old="${line%%←*}"
        new="${line#*←}"
        [ "$old" != "$line" ] || continue
        mkdir -p "$(dirname "$new")"
        ln -sf "$old" "$new"
    done < SYMLINKS.txt
    rm -f SYMLINKS.txt
fi
chmod 700 bin/* 2>/dev/null || true
[ -d libexec ] && chmod -R 700 libexec
[ -f lib/apt/apt-helper ] && chmod 700 lib/apt/apt-helper
[ -d lib/apt/methods ] && chmod -R 700 lib/apt/methods
[ -f etc/termux/bootstrap/termux-bootstrap-second-stage.sh ] && \
    chmod 700 etc/termux/bootstrap/termux-bootstrap-second-stage.sh
mv "$STAGE" "$FILES/usr"
PREFIX=$FILES/usr HOME=$FILES/home TMPDIR=$FILES/usr/tmp TERMUX_PREFIX=$FILES/usr \
    "$FILES/usr/bin/bash" "$FILES/usr/etc/termux/bootstrap/termux-bootstrap-second-stage.sh" || true
SH
    adb push "$_script" /data/local/tmp/lfa-bootstrap.sh >/dev/null || return 1
    adb shell run-as com.termux sh /data/local/tmp/lfa-bootstrap.sh || return 1
    bootstrap_ready
}

echo "Waiting for the Termux bootstrap..."
for _i in $(seq 1 120); do
    if bootstrap_ready; then
        echo "Termux bootstrap is ready."
        adb shell am force-stop com.termux >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 2
done

echo "Termux bootstrap did not appear within 240 seconds; installing the bundled copy." >&2
if manual_bootstrap; then
    echo "Termux bootstrap installed from the APK."
    adb shell am force-stop com.termux >/dev/null 2>&1 || true
    exit 0
fi

echo "Manual bootstrap also failed." >&2
adb shell run-as com.termux ls -la /data/data/com.termux/files 2>&1 || true
adb logcat -d -t 400 2>/dev/null \
    | grep -iE 'TermuxInstaller|Termux|AndroidRuntime|FATAL EXCEPTION|UnsatisfiedLinkError' \
    | tail -n 120 || true
exit 1
