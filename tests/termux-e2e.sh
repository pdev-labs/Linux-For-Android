#!/bin/bash
# End-to-end tests that run *inside Termux on Android*.
#
# This is the script the GitHub Actions Android workflow runs over SSH. It
# exercises the installer, the lfa CLI, the launchers, backend switching and
# actual VNC/X11 startup. It is also safe to run by hand on a phone:
#
#   LFA_E2E_DISTRO=debian LFA_E2E_BACKEND=vnc \
#   LFA_E2E_DESKTOP=xfce4 bash tests/termux-e2e.sh
#
# Environment:
#   LFA_E2E_DISTRO      distro (default: debian)
#   LFA_E2E_DESKTOP     xfce4|lxde|mate|gnome|none (default: xfce4)
#   LFA_E2E_BACKEND     x11|vnc|both|none (default: vnc)
#   LFA_E2E_SCENARIO    install|legacy|switch|software (default: install)
#   LFA_E2E_INSTANCE    instance name (default: ci-<distro>)
#   LFA_E2E_MODE        all|stop (default: all)
#   LFA_E2E_LEAVE_RUNNING 1 leaves the desktop up for a host-side probe
#   LFA_E2E_DIAGNOSTICS   1 also builds a diagnostics bundle
#
# Exit status: 0 when every check passed, 1 otherwise.
set -uo pipefail

REPO="${LFA_REPO:-$HOME/lfa}"
DISTRO="${LFA_E2E_DISTRO:-debian}"
DESKTOP="${LFA_E2E_DESKTOP:-xfce4}"
BACKEND="${LFA_E2E_BACKEND:-vnc}"
SCENARIO="${LFA_E2E_SCENARIO:-install}"
INSTANCE="${LFA_E2E_INSTANCE:-ci-$DISTRO}"
MODE="${LFA_E2E_MODE:-all}"
LEAVE_RUNNING="${LFA_E2E_LEAVE_RUNNING:-0}"
DIAGNOSTICS="${LFA_E2E_DIAGNOSTICS:-0}"
VNC_PASSWORD="${LFA_VNC_PASSWORD:-lfaci}"
SDK="$(getprop ro.build.version.sdk 2>/dev/null | tr -cd '0-9')"
[ -n "$SDK" ] || SDK=0
ARCH="$(uname -m)"
PASS=0
FAIL=0
LFA=(bash "$REPO/install_linux.sh" --cli)

say()  { printf '\n=== %s ===\n' "$*"; }
ok()   { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$*" >&2; }
check_contains() { # $1 label, $2 literal, $3 file
    if grep -qF -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 (missing [$2])"; fi
}
check_not_contains() { # $1 label, $2 literal, $3 file
    if grep -qF -- "$2" "$3" 2>/dev/null; then bad "$1 (unexpected [$2])"; else ok "$1"; fi
}
need_cmd() { command -v "$1" >/dev/null 2>&1; }

rootfs_for() { # $1 instance
    local base="$PREFIX/var/lib/proot-distro"
    if [ -d "$base/containers/$1/rootfs" ]; then printf '%s' "$base/containers/$1/rootfs"
    else printf '%s' "$base/installed-rootfs/$1"; fi
}
conf_for() { printf '%s/etc/termux-linux-manager.conf' "$(rootfs_for "$1")"; }

pd_flag() {
    if proot --help 2>&1 | grep -q sysvipc; then return 0; fi
    if [ -f "$PREFIX/bin/proot-distro" ] && grep -q no-sysvipc "$PREFIX/bin/proot-distro" 2>/dev/null; then
        printf '%s' '--no-sysvipc'
    fi
}

guest_root() { # $* command
    local _f
    _f="$(pd_flag)"
    # shellcheck disable=SC2086  # the flag is either empty or one argument
    proot-distro login $_f "$INSTANCE" --shared-tmp -- bash -lc "$*"
}
guest_user() { # $* command
    local _f
    _f="$(pd_flag)"
    # shellcheck disable=SC2086
    proot-distro login $_f "$INSTANCE" --user "${USER_NAME:-user}" --shared-tmp -- bash -lc "$*"
}

install_guest_test_tools() {
    case "$DISTRO" in
        ubuntu|debian|kali) guest_root 'apt-get update -qq >/dev/null 2>&1 || true; apt-get install -y x11-utils procps >/dev/null 2>&1 || true' ;;
        fedora) guest_root 'dnf install -y xorg-x11-utils procps-ng >/dev/null 2>&1 || true' ;;
        opensuse) guest_root 'zypper install -y xdpyinfo procps >/dev/null 2>&1 || true' ;;
        archlinux) guest_root 'pacman -S --noconfirm xorg-x11-utils procps-ng >/dev/null 2>&1 || true' ;;
        void) guest_root 'xbps-install -Sy xdpyinfo procps-ng >/dev/null 2>&1 || true' ;;
        alpine) guest_root 'apk add --no-cache xdpyinfo procps >/dev/null 2>&1 || true' ;;
    esac
}

port_open() { (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null; }

wait_for() { # $1 seconds, $2 command string
    local _i=0
    while [ "$_i" -lt "$1" ]; do
        if eval "$2" >/dev/null 2>&1; then return 0; fi
        sleep 2
        _i=$((_i + 2))
    done
    return 1
}

stop_desktop() {
    "${LFA[@]}" stop -i "$INSTANCE" >/tmp/lfa-e2e-stop.log 2>&1 || true
    if port_open; then bad "VNC port 5901 is still open after stop"; else ok "VNC port 5901 is closed after stop"; fi
}

start_vnc() {
    say "Starting VNC desktop"
    "${LFA[@]}" start -i "$INSTANCE" --vnc >/tmp/lfa-e2e-start-vnc.log 2>&1 || true
    if wait_for 90 'port_open'; then ok "VNC is listening on 5901"; else
        bad "VNC did not listen on 5901"
        tail -n 40 /tmp/lfa-e2e-start-vnc.log >&2 || true
    fi
    if pgrep -af 'Xvnc|Xtigervnc' >/dev/null 2>&1; then ok "an Xvnc process is running"; else bad "no Xvnc process"; fi
    if pgrep -af 'xfce4-session|xfwm4|startlxde|mate-session|gnome-shell' >/dev/null 2>&1; then
        ok "a desktop session process is running"
    else
        bad "no desktop session process"
        pgrep -af 'proot|Xvnc' | tail -n 20 >&2 || true
    fi
    local _log
    _log="$(rootfs_for "$INSTANCE")/home/${USER_NAME:-user}/start-linux-session.log"
    if [ -f "$_log" ]; then
        if grep -qiE 'fatal|Oh no! Something has gone wrong|Cannot open display' "$_log"; then
            bad "desktop session log contains a fatal error"
            tail -n 30 "$_log" >&2 || true
        else ok "desktop session log has no fatal error"; fi
    fi
}

start_x11() {
    say "Starting Termux:X11 desktop"
    "${LFA[@]}" start -i "$INSTANCE" --x11 >/tmp/lfa-e2e-start-x11.log 2>&1 || true
    if wait_for 60 '[ -S "$PREFIX/tmp/.X11-unix/X1" ]'; then ok "display :1 socket exists"; else
        bad "display :1 socket did not appear"
        tail -n 40 /tmp/lfa-e2e-start-x11.log >&2 || true
    fi
    if pgrep -af 'termux-x11 .*:1' >/dev/null 2>&1; then ok "termux-x11 is running"; else bad "termux-x11 is not running"; fi
    if pgrep -af 'xfce4-session|xfwm4|startlxde|mate-session|gnome-shell' >/dev/null 2>&1; then
        ok "a desktop session process is running"
    else bad "no desktop session process"; fi
    if guest_user 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1'; then
        ok "xdpyinfo can talk to display :1"
    else
        install_guest_test_tools
        if guest_user 'DISPLAY=:1 xdpyinfo >/dev/null 2>&1'; then ok "xdpyinfo can talk to display :1"; else bad "xdpyinfo cannot talk to display :1"; fi
    fi
}

test_cli_surface() {
    say "CLI surface"
    "${LFA[@]}" version >/tmp/lfa-e2e-version.log 2>&1
    check_contains "lfa version" "Linux for Android Manager" /tmp/lfa-e2e-version.log
    "${LFA[@]}" list >/tmp/lfa-e2e-list.log 2>&1
    check_contains "lfa list shows the instance" "$INSTANCE" /tmp/lfa-e2e-list.log
    "${LFA[@]}" status -i "$INSTANCE" --json >/tmp/lfa-e2e-status.log 2>&1
    check_contains "lfa status reports the backend" "\"backend\":\"$BACKEND\"" /tmp/lfa-e2e-status.log
    "${LFA[@]}" notice status >/tmp/lfa-e2e-notice.log 2>&1
    check_contains "lfa notice status" "start-linux notice:" /tmp/lfa-e2e-notice.log
    "${LFA[@]}" compat list >/tmp/lfa-e2e-compat.log 2>&1
    check_contains "compat list names docker" "docker" /tmp/lfa-e2e-compat.log
    "${LFA[@]}" compat explain docker >/tmp/lfa-e2e-explain.log 2>&1
    check_contains "compat explains docker honestly" "not shimmable" /tmp/lfa-e2e-explain.log
    "${LFA[@]}" compat enable systemctl -i "$INSTANCE" >/tmp/lfa-e2e-compat-enable.log 2>&1
    [ -f "$(rootfs_for "$INSTANCE")/usr/local/bin/systemctl" ] && ok "systemctl shim was installed" || bad "systemctl shim missing"
    "${LFA[@]}" compat disable systemctl -i "$INSTANCE" >/tmp/lfa-e2e-compat-disable.log 2>&1
    [ ! -e "$(rootfs_for "$INSTANCE")/usr/local/bin/systemctl" ] && ok "systemctl shim was removed" || bad "systemctl shim survived disable"
    "${LFA[@]}" android status >/tmp/lfa-e2e-android.log 2>&1
    check_contains "android status" "termux-api package:" /tmp/lfa-e2e-android.log
}

test_legacy_refusal() {
    say "Unsupported-X11 refusal (SDK $SDK)"
    "${LFA[@]}" switch x11 -i "$INSTANCE" --remove-old >/tmp/lfa-e2e-refusal.log 2>&1
    local _rc=$?
    if [ "$_rc" = "1" ]; then ok "switch x11 refused"; else bad "switch x11 exit $_rc (expected 1)"; fi
    check_contains "refusal explains the requirement" "Termux:X11 requires Android 8" /tmp/lfa-e2e-refusal.log
    check_contains "refusal keeps the current backend" "Nothing was changed" /tmp/lfa-e2e-refusal.log
    check_contains "refusal warns about --remove-old" "--remove-old was ignored on purpose" /tmp/lfa-e2e-refusal.log
    check_contains "VNC is still configured" 'SERVER="vnc"' "$(conf_for "$INSTANCE")"
}

test_switch() {
    say "Backend switching"
    "${LFA[@]}" switch both -i "$INSTANCE" >/tmp/lfa-e2e-switch-both.log 2>&1
    check_contains "both backend installed" 'SERVER="both"' "$(conf_for "$INSTANCE")"
    start_vnc
    stop_desktop
    # The scenario is only generated for SDK >= 26, because Both itself is
    # refused on older devices.
    start_x11
    stop_desktop
    "${LFA[@]}" switch vnc -i "$INSTANCE" --remove-old >/tmp/lfa-e2e-switch-vnc.log 2>&1
    check_contains "vnc backend selected" 'SERVER="vnc"' "$(conf_for "$INSTANCE")"
    if [ "$SDK" -ge 26 ]; then
        check_contains "x11 packages removed" "uninstall -y termux-x11-nightly" /tmp/lfa-e2e-switch-vnc.log
    fi
}

test_software() {
    say "Software probes"
    bash "$REPO/tests/software-probe.sh" || bad "software-probe.sh reported failures"
    [ "$FAIL" -eq 0 ] && ok "software probe passed" || true
}

run_install() {
    say "Installing $DISTRO ($DESKTOP, $BACKEND) as $INSTANCE"
    local -a _args=(install --distro "$DISTRO" --desktop "$DESKTOP" -i "$INSTANCE" --user tester)
    [ "$BACKEND" = "none" ] || _args+=(--backend "$BACKEND")
    [ "$SCENARIO" = "software" ] && _args+=(--software "python,git,htop")
    if ! LFA_NONINTERACTIVE=1 LFA_ASSUME_YES=1 LFA_VNC_PASSWORD="$VNC_PASSWORD" \
        "${LFA[@]}" "${_args[@]}" >/tmp/lfa-e2e-install.log 2>&1; then
        bad "lfa install failed"
        tail -n 60 /tmp/lfa-e2e-install.log >&2 || true
        return 1
    fi
    ok "lfa install completed"
    check_contains "manager config exists" "DISTRO=\"$DISTRO\"" "$(conf_for "$INSTANCE")"
    if [ "$DESKTOP" != "none" ]; then
        check_contains "desktop recorded" "DE=\"$DESKTOP\"" "$(conf_for "$INSTANCE")"
        check_contains "backend recorded" "SERVER=\"$BACKEND\"" "$(conf_for "$INSTANCE")"
    fi
    "${LFA[@]}" status -i "$INSTANCE" >/tmp/lfa-e2e-status-text.log 2>&1
    check_contains "status is readable" "instance:" /tmp/lfa-e2e-status-text.log
}

main() {
    if [ ! -f "$REPO/install_linux.sh" ]; then
        echo "Repository not found at $REPO (set LFA_REPO)." >&2
        exit 1
    fi
    if [ "$MODE" = "stop" ]; then
        say "Stopping the desktop"
        stop_desktop
        printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
        [ "$FAIL" = "0" ]
        return
    fi

    say "Device: $ARCH, Android SDK $SDK, Termux ${TERMUX_VERSION:-unknown}"
    if ! pgrep -x sshd >/dev/null 2>&1 && [ -n "${SSH_CONNECTION:-}" ]; then
        ok "running over SSH"
    fi

    if [ "$DESKTOP" != "none" ] && [ "$SDK" -gt 0 ] && [ "$SDK" -lt 26 ] && { [ "$BACKEND" = "x11" ] || [ "$BACKEND" = "both" ]; }; then
        say "Unsupported combination: SDK $SDK with backend $BACKEND"
        bad "the harness was asked for X11 on a device that cannot run it"
        printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
        return 1
    fi

    if [ "${LFA_E2E_SKIP_INSTALL:-0}" != "1" ]; then
        run_install || true
    fi
    if [ ! -f "$(conf_for "$INSTANCE")" ]; then
        say "Install did not produce a config; stopping"
        printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
        return 1
    fi

    test_cli_surface || true

    if [ "$DESKTOP" != "none" ]; then
        case "$SCENARIO" in
            legacy)
                test_legacy_refusal
                # The refusal path is only half the story: prove the VNC
                # desktop it keeps still starts on the legacy device.
                start_vnc
                stop_desktop
                [ "$LEAVE_RUNNING" = "1" ] && start_vnc
                ;;
            switch) test_switch ;;
            software) start_vnc; test_software; stop_desktop ;;
            *)
                if [ "$BACKEND" = "vnc" ]; then
                    start_vnc
                    stop_desktop
                    if [ "$LEAVE_RUNNING" = "1" ]; then
                        start_vnc
                    fi
                elif [ "$BACKEND" = "x11" ]; then
                    start_x11
                    stop_desktop
                elif [ "$BACKEND" = "both" ]; then
                    test_switch
                fi
                ;;
        esac
    fi

    if [ "$DIAGNOSTICS" = "1" ]; then
        say "Diagnostics bundle"
        "${LFA[@]}" diagnostics >/tmp/lfa-e2e-diagnostics.log 2>&1 && ok "diagnostics bundle created" || bad "diagnostics failed"
        check_contains "diagnostics path" "Diagnostics written to:" /tmp/lfa-e2e-diagnostics.log
    fi

    printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
    [ "$FAIL" = "0" ]
}

main "$@"
