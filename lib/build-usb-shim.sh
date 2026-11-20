#!/bin/sh
# Rebuild the prebuilt usbfs/session preload.
#
# lib/lfa-usb-node.c is freestanding: -nostdlib means the object has no
# DT_NEEDED entries and resolves the few libc symbols it uses (syscall,
# environ, __errno_location) from whichever glibc/musl/bionic it is
# preloaded into.  One build per CPU architecture is therefore enough.
#
# The installer uses clang (or the host cc) when it can build for the
# guest's architecture, and falls back to these files otherwise.  Keep
# them in sync with the source: run this script after editing the .c.
#
#   ./lib/build-usb-shim.sh            # host architecture
#   ./lib/build-usb-shim.sh aarch64    # cross compiler / clang target
#
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
src="$here/lfa-usb-node.c"
out_dir="$here/prebuilt"
arch=${1:-}

if [ -z "$arch" ]; then
    case "$(uname -m)" in
        aarch64|arm64) arch=aarch64 ;;
        armv7l|armv8l) arch=arm ;;
        x86_64|amd64) arch=x86_64 ;;
        i?86) arch=i386 ;;
        *) echo "build-usb-shim: unknown host architecture" >&2; exit 1 ;;
    esac
fi

cc=""
target=""
case "$arch" in
    aarch64)
        if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
            cc=aarch64-linux-gnu-gcc
        elif command -v clang >/dev/null 2>&1; then
            cc=clang; target="--target=aarch64-linux-gnu"
        elif [ "$(uname -m)" = "aarch64" ]; then
            cc=${CC:-cc}
        fi ;;
    arm)
        if command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
            cc=arm-linux-gnueabihf-gcc
        elif command -v clang >/dev/null 2>&1; then
            cc=clang; target="--target=armv7a-linux-gnueabihf"
        fi ;;
    x86_64)
        if command -v x86_64-linux-gnu-gcc >/dev/null 2>&1; then
            cc=x86_64-linux-gnu-gcc
        elif command -v clang >/dev/null 2>&1; then
            cc=clang; target="--target=x86_64-linux-gnu"
        elif [ "$(uname -m)" = "x86_64" ]; then
            cc=${CC:-cc}
        fi ;;
    i386)
        if command -v i686-linux-gnu-gcc >/dev/null 2>&1; then
            cc=i686-linux-gnu-gcc
        elif command -v clang >/dev/null 2>&1; then
            cc=clang; target="--target=i686-linux-gnu"
        fi ;;
    *)
        echo "build-usb-shim: unknown architecture '$arch'" >&2
        exit 1 ;;
esac

if [ -z "$cc" ]; then
    echo "build-usb-shim: no compiler for $arch" >&2
    exit 1
fi

mkdir -p "$out_dir"
# shellcheck disable=SC2086  # the target flag is optional
"$cc" $target -shared -fPIC -nostdlib -fno-builtin -O2 -fno-stack-protector \
    -Wl,-soname,liblfa-usb-node.so \
    -o "$out_dir/lfa-usb-node-$arch.so" "$src"

echo "built $out_dir/lfa-usb-node-$arch.so"
