#!/bin/bash
# Run a script inside the Termux app context, without opening a terminal.
#
# Requires the Termux *debug* APK, because `run-as com.termux` only works for
# a debuggable package. This is the bootstrap path; the rest of the CI uses
# SSH over adb forward, which is easier to quote and to keep alive.
#
# Usage: termux-exec.sh SCRIPT [args...]
set -euo pipefail

script="${1:?usage: termux-exec.sh SCRIPT [args...]}"
[ -f "$script" ] || { echo "No such script: $script" >&2; exit 2; }
shift

command -v adb >/dev/null 2>&1 || { echo "adb is required" >&2; exit 2; }

pkg="com.termux"
home="/data/data/$pkg/files/home"
prefix="/data/data/$pkg/files/usr"

# adb exec-out keeps stdout/stderr separate and avoids CRLF mangling.
adb exec-out run-as "$pkg" env \
    HOME="$home" \
    PREFIX="$prefix" \
    TMPDIR="$prefix/tmp" \
    PATH="$prefix/bin:/system/bin:/system/xbin" \
    LD_LIBRARY_PATH="$prefix/lib" \
    TERM=xterm-256color \
    LANG=C.UTF-8 \
    "$prefix/bin/bash" -s -- "$@" < "$script"
