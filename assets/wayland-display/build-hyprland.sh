#!/bin/bash
# Build patched Aquamarine and Hyprland inside an Arch guest.
#
# Hyprland cannot start without a DRM render node, and a nested compositor that
# only offers wl_shm needs the shm patch series (see apply-shm-patches.py).
# This script builds both from pinned upstream tags and installs them under
# /usr/local, leaving the distro packages untouched.
#
# Run as root inside the guest:
#   bash /tmp/lfa-wd/build-hyprland.sh
#
# Environment:
#   LFA_WD_SRC      build tree (default /opt/lfa-wd-build)
#   LFA_WD_PATCH    patch script (default /tmp/lfa-wd/apply-shm-patches.py)
#   LFA_WD_JOBS     parallel jobs (default nproc)
set -euo pipefail

AQ_VERSION="${AQ_VERSION:-0.15.1}"
HL_VERSION="${HL_VERSION:-0.56.2}"
SRC="${LFA_WD_SRC:-/opt/lfa-wd-build}"
PATCH="${LFA_WD_PATCH:-/tmp/lfa-wd/apply-shm-patches.py}"
JOBS="${LFA_WD_JOBS:-$(nproc)}"

say() { printf '\n[*] %s\n' "$*"; }

[ -f "$PATCH" ] || { echo "patch script missing: $PATCH" >&2; exit 1; }
command -v pacman >/dev/null 2>&1 || { echo "this script expects an Arch guest" >&2; exit 1; }

say "Installing build dependencies"
pacman -S --needed --noconfirm \
    base-devel cmake ninja git python3 \
    aquamarine hyprlang hyprcursor hyprutils hyprgraphics hyprwayland-scanner \
    glaze glslang libdisplay-info libdrm libinput seatd libliftoff \
    mesa libxkbcommon pixman tomlplusplus wayland wayland-protocols hwdata \
    pugixml libxcb xcb-util-wm xcb-util-errors xcb-util-cursor

mkdir -p "$SRC"
cd "$SRC"

if [ ! -d aquamarine ]; then
    say "Fetching Aquamarine $AQ_VERSION"
    git clone -q --depth 1 --branch "v$AQ_VERSION" https://github.com/hyprwm/aquamarine.git
fi
if [ ! -d Hyprland ]; then
    say "Fetching Hyprland $HL_VERSION"
    git clone -q --depth 1 --branch "v$HL_VERSION" https://github.com/hyprwm/Hyprland.git
fi
git -C Hyprland submodule update --init --recursive >/dev/null 2>&1 || true

say "Applying the shm patch series"
python3 "$PATCH" "$SRC/aquamarine" "$SRC/Hyprland"

say "Building Aquamarine (jobs: $JOBS)"
cmake -S aquamarine -B aquamarine/build \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local >/dev/null
cmake --build aquamarine/build -j"$JOBS" >/dev/null
cmake --install aquamarine/build >/dev/null

say "Building Hyprland (jobs: $JOBS)"
PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
cmake -S Hyprland -B Hyprland/build \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DNO_XWAYLAND=ON -DNO_SYSTEMD=ON -DNO_HYPRPM=ON >/dev/null
cmake --build Hyprland/build -j"$JOBS" >/dev/null
cmake --install Hyprland/build >/dev/null

ldconfig 2>/dev/null || true

say "Installed"
printf '  aquamarine: %s\n' "$(/usr/local/bin/hyprctl --version 2>/dev/null | head -n1 || echo '')"
printf '  binary:     %s\n' "$(command -v Hyprland || echo /usr/local/bin/Hyprland)"
printf '  library:    %s\n' "$(ls /usr/local/lib/libaquamarine.so.* 2>/dev/null | head -n1)"
