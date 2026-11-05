#!/bin/bash
# Install the pinned Termux:X11 APK. The command-line package alone is not
# enough: the `termux-x11` launcher talks to this Android app.
#
# The upstream release tag is `nightly`, so the asset URL is stable but its
# contents are not. We verify a digest and fail loudly when upstream moves:
# that is the signal to review and bump the pin.
set -euo pipefail

API_LEVEL="${TERMUX_API_LEVEL:-33}"
if [ "$API_LEVEL" -lt 26 ]; then
    echo "Termux:X11 is not installed on API $API_LEVEL (requires 26)."
    exit 0
fi

TERMUX_X11_VERSION="${TERMUX_X11_VERSION:-1.03.01}"
TERMUX_X11_SHA256="${TERMUX_X11_SHA256:-a0cdf8da2ecebe17c3441faecd7e06a433d23d8da49c37c8945feeb5ced3e8fe}"
APK_NAME="termux-x11-universal-debug.apk"
URL="https://github.com/termux/termux-x11/releases/download/nightly/$APK_NAME"
CACHE="${RUNNER_TEMP:-/tmp}/termux-apks"
mkdir -p "$CACHE"
APK="$CACHE/$APK_NAME"

if [ ! -f "$APK" ]; then
    curl -fL --retry 3 --retry-delay 2 -o "$APK.part" "$URL"
    mv "$APK.part" "$APK"
fi

echo "$TERMUX_X11_SHA256  $APK" | sha256sum -c - || {
    echo "Termux:X11 asset changed upstream (expected $TERMUX_X11_VERSION, digest mismatch)." >&2
    echo "Review the new release, then bump TERMUX_X11_SHA256 in this file." >&2
    exit 1
}

adb install -r -g "$APK"
echo "Termux:X11 $TERMUX_X11_VERSION installed."
