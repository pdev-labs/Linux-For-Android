#!/bin/bash
# Software compatibility probe. Runs in Termux and inspects a guest distro.
#
# The goal is to catch false claims in both directions:
#   * software that LFA says works should actually run
#   * software that needs kernel features should fail, not pretend to work
#
# Environment:
#   LFA_E2E_INSTANCE   instance to inspect (default: ci-<distro>)
#   LFA_E2E_DISTRO     distro name for the default instance
#
# Exit status: 0 when every required probe passed.
set -uo pipefail

DISTRO="${LFA_E2E_DISTRO:-debian}"
INSTANCE="${LFA_E2E_INSTANCE:-ci-$DISTRO}"
PASS=0
FAIL=0
SKIP=0

ok()   { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$*" >&2; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP: %s\n' "$*"; }

pd_flag() {
    if proot --help 2>&1 | grep -q sysvipc; then return 0; fi
    if [ -f "$PREFIX/bin/proot-distro" ] && grep -q no-sysvipc "$PREFIX/bin/proot-distro" 2>/dev/null; then
        printf '%s' '--no-sysvipc'
    fi
}

guest() { # $* command
    local _f
    _f="$(pd_flag)"
    # shellcheck disable=SC2086
    proot-distro login $_f "$INSTANCE" --shared-tmp -- bash -lc "$*"
}

guest_user() { # $* command
    local _f
    _f="$(pd_flag)"
    # shellcheck disable=SC2086
    proot-distro login $_f "$INSTANCE" --user "${USER_NAME:-user}" --shared-tmp -- bash -lc "$*"
}

guest_has() { guest "command -v $1 >/dev/null 2>&1"; }

require_version() { # $1 command, $2 description
    if ! guest_has "$1"; then
        bad "$2: $1 is not installed"
        return
    fi
    local _out
    _out="$(guest "$1 --version 2>&1 | head -n1" 2>/dev/null || true)"
    if [ -n "$_out" ]; then ok "$2: $_out"; else bad "$2: $1 produced no version"; fi
}

expect_unsupported() { # $1 command, $2 description, $3 probe command
    local _cmd="$1" _label="$2" _probe="${3:-$1 --version}"
    if ! guest_has "$_cmd"; then
        ok "$_label: not present (expected)"
        return
    fi
    # A daemon binary may exist but cannot work. It is a pass only when the
    # actual operation fails, not when `--version` merely prints a string.
    if guest "$_probe >/dev/null 2>&1"; then
        bad "$_label: the real operation succeeded; review docs/INCOMPATIBLE.md"
    else
        ok "$_label: present but not usable (expected)"
    fi
}

echo "Software probe for $INSTANCE ($DISTRO)"
echo "Guest: $(guest 'uname -m; cat /etc/os-release 2>/dev/null | sed -n "s/^PRETTY_NAME=//p" | head -n1' 2>/dev/null | tr '\n' ' ')"

# These are installed by the software scenario.
require_version python3 "Python"
require_version git "Git"
require_version htop "htop"

# Optional tools: report honestly when the scenario did not install them.
for _pair in "node:Node.js" "curl:curl" "wget:wget" "firefox:Firefox" "chromium:Chromium" "code:VS Code" "vlc:VLC" "gimp:GIMP" "libreoffice:LibreOffice"; do
    _cmd="${_pair%%:*}"
    _label="${_pair#*:}"
    if guest_has "$_cmd"; then
        _v="$(guest "$_cmd --version 2>&1 | head -n1" 2>/dev/null || true)"
        [ -n "$_v" ] && ok "$_label: $_v" || bad "$_label: no version output"
    else
        skip "$_label is not installed"
    fi
done

# Kernel-bound software must not be presented as working.
expect_unsupported docker "Docker" "docker info"
expect_unsupported podman "Podman" "podman info"
expect_unsupported snap "snapd/snap" "snap install definitely-not-a-real-snap"
expect_unsupported flatpak "Flatpak" "flatpak list"
expect_unsupported systemctl "systemd/systemctl" "systemctl status"
expect_unsupported nvidia-smi "CUDA (nvidia-smi)" "nvidia-smi"
expect_unsupported rocminfo "ROCm" "rocminfo"

# Software renderers may be installed by `lfa compat enable`.
if guest_has vulkaninfo; then
    _v="$(guest 'vulkaninfo --summary 2>/dev/null | grep -m1 "deviceName"' 2>/dev/null || true)"
    case "$_v" in
        *llvmpipe*|*lavapipe*|*swrast*) ok "Vulkan is software-only: $_v" ;;
        '') skip "vulkaninfo is present but produced no device; the loader may have no ICD" ;;
        *) bad "Vulkan reports a hardware device inside the guest: $_v" ;;
    esac
else
    skip "Vulkan tools are not installed"
fi
if guest_has clinfo; then
    _v="$(guest 'clinfo 2>/dev/null | grep -m1 "Device Name"' 2>/dev/null || true)"
    case "$_v" in
        *pocl*|*POCL*|*CPU*|*pthread*) ok "OpenCL is CPU-only: $_v" ;;
        '') skip "clinfo produced no device" ;;
        *) bad "OpenCL reports a GPU device inside the guest: $_v" ;;
    esac
else
    skip "OpenCL tools are not installed"
fi

# The desktop user must not be able to elevate for real.
if guest_user 'sudo -n true >/dev/null 2>&1'; then
    # LFA's sudo is a ritual; -n should fail rather than silently authorize.
    bad "sudo -n succeeded; the shim should require the password ritual"
else
    ok "sudo -n does not grant silent root"
fi

printf '\nPASS=%s FAIL=%s SKIP=%s\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" = "0" ]
