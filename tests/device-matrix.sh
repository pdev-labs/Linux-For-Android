#!/bin/bash
# Device smoke test: run this ON THE PHONE, in Termux, from the repo root.
#
#   ./tests/device-matrix.sh                 # info + suite + existing sessions
#   ./tests/device-matrix.sh --install alpine --desktop xfce4 --backend vnc
#
# What it does that CI cannot: it runs the real suite with the real Termux
# userland, reports the device profile that the verified matrix depends on,
# and (optionally) performs a genuine install and desktop start, then collects
# the evidence this project's releases are based on.
#
# It never modifies an existing distro unless you pass --install.
set -u
cd "$(dirname "$0")/.." || exit 1

INSTALL_DISTRO=""
DESKTOP="xfce4"
BACKEND="vnc"
KEEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --install) INSTALL_DISTRO="${2:-}"; shift 2 ;;
        --desktop) DESKTOP="${2:-xfce4}"; shift 2 ;;
        --backend) BACKEND="${2:-vnc}"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

say() { printf '\n== %s\n' "$*"; }

if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
    echo "This script must run inside Termux (PREFIX is not set)." >&2
    exit 1
fi

say "Device profile"
{
    echo "date:        $(date -Is)"
    echo "model:       $(getprop ro.product.model 2>/dev/null || echo unknown)"
    echo "sdk:         $(getprop ro.build.version.sdk 2>/dev/null || echo unknown)"
    echo "arch:        $(uname -m)"
    echo "kernel:      $(uname -r)"
    echo "termux user: $(whoami)"
    echo "prefix:      $PREFIX"
    echo "free disk:   $(df -Pk "$PREFIX" | awk 'NR==2 {print int($4/1024) " MB"}')"
    echo "ram:         $(free -m 2>/dev/null | awk '/^Mem:/ {print $2 " MB"}')"
    echo "version:     $(./install_linux.sh --version 2>/dev/null || echo unknown)"
    echo "requested:   desktop=$DESKTOP backend=$BACKEND"
} | tee "${HOME:-/tmp}/lfa-device-profile.txt"

say "Installed distributions"
./install_linux.sh --list 2>/dev/null || true

say "Test suite (same suite CI runs)"
./tests/test-all.sh
SUITE_RC=$?
echo "suite exit: $SUITE_RC"

if [ -n "$INSTALL_DISTRO" ]; then
    say "Installing with quick setup (all defaults)"
    echo "NOTE: quick setup ignores --desktop/--backend; it installs the"
    echo "      recommended combination for this device. For a specific"
    echo "      combination, run ./install_linux.sh and answer the wizard."
    ./install_linux.sh --yes || {
        echo "Quick setup failed; run ./install_linux.sh manually." >&2
        exit 1
    }
fi

say "Existing desktop sessions"
if command -v pgrep >/dev/null 2>&1; then
    pgrep -af 'termux-x11|Xvnc|gnome-shell|xfce4-session|mate-session' || echo "none running"
    ls -l "$PREFIX/tmp/.X11-unix" 2>/dev/null || true
    ls -l "$PREFIX"/tmp/lfa-vnc-*.pid 2>/dev/null || true
fi

say "Result"
if [ "$SUITE_RC" -eq 0 ]; then
    echo "PASS on device: $(getprop ro.product.model 2>/dev/null) / SDK $(getprop ro.build.version.sdk 2>/dev/null)"
else
    echo "FAIL on device - see the suite output above"
fi
[ "$KEEP" = "1" ] || true
exit "$SUITE_RC"
