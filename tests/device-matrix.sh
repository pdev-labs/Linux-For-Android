#!/bin/bash
# Device smoke test: run this ON THE PHONE, in Termux, from the repo root.
#
#   ./tests/device-matrix.sh                 # info + suite + existing sessions
#   ./tests/device-matrix.sh --install alpine --desktop xfce4 --backend vnc
#   ./tests/device-matrix.sh --install debian --e2e
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
E2E=0

while [ $# -gt 0 ]; do
    case "$1" in
        --install) INSTALL_DISTRO="${2:-}"; shift 2 ;;
        --desktop) DESKTOP="${2:-xfce4}"; shift 2 ;;
        --backend) BACKEND="${2:-vnc}"; shift 2 ;;
        --e2e)     E2E=1; shift ;;
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
    say "Installing $INSTALL_DISTRO ($DESKTOP, $BACKEND) through lfa"
    INSTANCE="device-$INSTALL_DISTRO"
    ./install_linux.sh --cli install --distro "$INSTALL_DISTRO" \
        --desktop "$DESKTOP" --backend "$BACKEND" -i "$INSTANCE" || {
        echo "lfa install failed; run ./install_linux.sh manually." >&2
        exit 1
    }
    if [ "$E2E" = "1" ]; then
        say "Running the on-device E2E harness"
        LFA_E2E_DISTRO="$INSTALL_DISTRO" LFA_E2E_DESKTOP="$DESKTOP" \
        LFA_E2E_BACKEND="$BACKEND" LFA_E2E_INSTANCE="$INSTANCE" \
        LFA_E2E_SKIP_INSTALL=1 LFA_E2E_DIAGNOSTICS=1 \
            bash tests/termux-e2e.sh
        E2E_RC=$?
        echo "e2e exit: $E2E_RC"
        [ "$E2E_RC" = "0" ] || SUITE_RC=1
    fi
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
