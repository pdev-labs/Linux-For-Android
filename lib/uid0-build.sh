#!/bin/sh
# Build the uid0 emulation library inside the guest. Runs as root in the
# distro, with /tmp/uid0.c already staged by the caller.
#
# Real setuid is impossible under proot, so dpkg refuses to run as a
# non-root uid. libuid0.c is a tiny LD_PRELOAD shim that reports uid 0 to
# uid-gated tools. It is rebuilt only when missing.
#
# This file exists so the install path and the "apply latest fixes" path
# share one implementation instead of duplicating the gcc command line.

if [ -s /usr/local/lib/libuid0.so ]; then
    echo "    uid0 library already present."
    exit 0
fi

if [ ! -f /tmp/uid0.c ]; then
    echo "[!] uid0 source missing; sudo stays ritual-only."
    exit 0
fi

if ! command -v gcc >/dev/null 2>&1; then
    echo " -> Installing gcc for the uid0 library..."
    case "$(command -v apt-get >/dev/null 2>&1 && echo apt || echo none)" in
        apt) apt-get install -y gcc >/dev/null 2>&1 || true ;;
        *)   ;;
    esac
fi

if command -v gcc >/dev/null 2>&1; then
    mkdir -p /usr/local/lib
    if gcc -shared -nostdlib -O2 -o /usr/local/lib/libuid0.so /tmp/uid0.c 2>/dev/null; then
        chmod 644 /usr/local/lib/libuid0.so
        echo "    uid0 library ready."
    else
        echo "[!] uid0 build failed; sudo stays ritual-only."
    fi
    # gcc is a large dependency; drop it again on apt systems.
    if command -v apt-get >/dev/null 2>&1; then
        apt-get purge -y gcc >/dev/null 2>&1 || true
    fi
else
    echo "[!] gcc unavailable; sudo stays ritual-only."
fi

rm -f /tmp/uid0.c
