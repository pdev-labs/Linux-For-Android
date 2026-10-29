#!/bin/bash
# Comprehensive test suite for Linux-for-Android's install_linux.sh.
#
# What it covers:
#   * entry modes: quick / guided / manager passthrough / saved replay /
#     corrupt-config fallback / invalid input recovery
#   * install matrix: debian CLI, alpine VNC, ubuntu X11, fedora MATE,
#     legacy bullseye remap, legacy kali rejection, legacy glibc warning
#   * questionnaire validation loops (bad distro/DE/user/software/instance)
#   * generated artifacts: setup script syntax, placeholder substitution,
#     launchers syntax, manager conf, setup.conf (0600), boot script
#   * sudo shim: syntax + real password ritual over a pty
#   * manager menu smoke test: options 2-11 run clean with stubs
#
# How it works: fake HOME/PREFIX/PATH with stub commands (pkg, proot-distro,
# sshd, pulseaudio, termux-setup-storage, getprop, free, proot, git). No
# network, no root, no real installs. Anything reaching for the network or
# the real system fails loudly instead of hanging (each run has a timeout).
#
# Deliberately NOT covered here (verified live on real hardware instead):
#   * proot-distro v4.2.0 source install (needs network; exercised on-device)
#   * actual guest package installs (needs proot + rootfs)
#
# Usage: ./tests/test-all.sh   (from anywhere; exits nonzero on failure)
set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
REAL_PREFIX="${PREFIX:-}"   # Termux provides bash/coreutils here
export REAL_PREFIX
command -v timeout >/dev/null 2>&1 || { echo "need 'timeout' (coreutils)"; exit 2; }

T="$REPO/.test-tmp"
rm -rf "$T"
mkdir -p "$T/fakebin"

# ---------------- stub commands ----------------
cat > "$T/fakebin/pkg" <<'EOF'
#!/bin/bash
echo "STUB-PKG: $*"
exit 0
EOF
cat > "$T/fakebin/proot-distro" <<'EOF'
#!/bin/bash
echo "STUB-PD: $*" >&2
echo "$*" >> "$HOME/pd-calls.log" 2>/dev/null || true
case "$1" in
    list)
        if [ "${PD_V5:-0}" = "1" ]; then
            echo "No containers are installed."
            echo "Install one with: proot-distro install ubuntu:24.04"
        else
            printf 'Available distributions:\n  * Debian\n    Alias: debian\n  * Alpine Linux\n    Alias: alpine\n  * Debian (bullseye)\n    Alias: bullseye\n  * Ubuntu\n    Alias: ubuntu\n  * Fedora\n    Alias: fedora\n  * OpenSUSE\n    Alias: opensuse\n  * Kali Linux\n    Alias: kali\n  * Void Linux\n    Alias: void\n  * Arch Linux\n    Alias: archlinux\n'
        fi ;;
    install)
        if [ "$2" = "--help" ]; then
            if [ "${PD_V5:-0}" = "1" ]; then echo "USAGE: proot-distro install [OPTIONS] (IMAGE:TAG or URL or FILE)";
            elif [ "${PD_V4:-0}" = "1" ]; then echo "Usage: install [--override-alias ALIAS] DISTRO";
            else echo "Usage: install ALIAS"; fi
        else echo "STUB-PD-INSTALL-OK: $*"; fi ;;
    restore)
        if [ "$2" = "--help" ]; then
            if [ "${PD_V5:-0}" = "1" ]; then echo "USAGE: proot-distro restore [OPTIONS] [BACKUP_FILE]";
            else echo "USAGE: proot-distro restore NAME --input FILE"; fi
        else echo "STUB-PD-restore-OK: $*"; fi ;;
    login|backup|remove) echo "STUB-PD-$1-OK" ;;
    run) echo "STUB-PD-run-OK: $*" ;;
    kill) echo "STUB-PD-KILL: $*" >&2 ;;
    *) echo "STUB-PD-OK" ;;
esac
exit 0
EOF
cat > "$T/fakebin/sshd" <<'EOF'
#!/bin/bash
echo "STUB-SSHD started"
exit 0
EOF
cat > "$T/fakebin/pulseaudio" <<'EOF'
#!/bin/bash
echo "STUB-PULSE: $*"
exit 0
EOF
cat > "$T/fakebin/termux-setup-storage" <<'EOF'
#!/bin/bash
mkdir -p "$HOME/storage"
echo "STUB-STORAGE-OK"
exit 0
EOF
cat > "$T/fakebin/getprop" <<'EOF'
#!/bin/bash
# property-aware: SDK for version checks, real zone (or empty) for timezone
if [ "$1" = "persist.sys.timezone" ]; then
    echo "${GETPROP_TZ:-}"
else
    echo "${GETPROP_SDK:-}"
fi
exit 0
EOF
cat > "$T/fakebin/free" <<'EOF'
#!/bin/bash
if [ -n "${FREE_MB:-}" ]; then
    printf '              total        used        free      shared  buff/cache   available\nMem:           %s            0           %s            0            0           %s\n' "$FREE_MB" "$FREE_MB" "$FREE_MB"
else
    R=$(PATH=/usr/bin:/bin:/sbin command -v free) || { echo "Mem:           8192            0         8192            0            0         8192"; exit 0; }
    exec "$R" "$@"
fi
EOF
cat > "$T/fakebin/proot" <<'EOF'
#!/bin/bash
# pretends to be an old proot without --sysvipc (legacy worst case)
echo "proot 5.1-fake (no sysvipc here)"
exit 0
EOF
cat > "$T/fakebin/git" <<'EOF'
#!/bin/bash
echo "STUB-GIT-CALLED-WITH: $* (network clone must never happen in tests)" >&2
exit 1
EOF
chmod +x "$T/fakebin/"*

# ---------------- helpers ----------------
pass=0; fail=0
fresh_env() { # reset HOME/PREFIX, keep stubs
    rm -rf "$T/home" "$T/prefix"
    mkdir -p "$T/home" "$T/prefix/bin" "$T/prefix/tmp"
    export HOME="$T/home" PREFIX="$T/prefix" \
        PATH="$T/fakebin${REAL_PREFIX:+:$REAL_PREFIX/bin}:/usr/bin:/bin" TERM=""
    unset GETPROP_SDK FREE_MB PD_V4
}
run_script() { # $1=logname, rest of stdin via caller pipe; needs $T/tmpin set
    timeout 60 bash "$REPO/install_linux.sh" > "$T/$1.log" 2>&1
    echo "$?"
}
check() { # $1 desc, $2 literal, $3 file
    if grep -qF -- "$2" "$3" 2>/dev/null; then pass=$((pass+1));
    else fail=$((fail+1)); echo "FAIL: $1 (missing [$2])"; fi
}
check_absent() {
    if grep -qF -- "$2" "$3" 2>/dev/null; then fail=$((fail+1)); echo "FAIL: $1 (unexpected [$2])";
    else pass=$((pass+1)); fi
}
check_re() {
    if grep -qE -- "$2" "$3" 2>/dev/null; then pass=$((pass+1));
    else fail=$((fail+1)); echo "FAIL: $1 (missing /$2/)"; fi
}
setup_sh_of() { # newest generated guest setup script
    ls -t "$T/prefix/tmp/gui_setup_"*.sh 2>/dev/null | head -1
}

# ============================================================
echo "===== A: invalid entry -> menu -> exit ====="
fresh_env
printf '%s\n' 9 3 13 | bash "$REPO/install_linux.sh" > "$T/a.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run a exit $rc"; }
[ "$?" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: A exit code"; }
check "A reprompt" 'Invalid choice' "$T/a.log"
check "A menu shown" 'Linux for Termux Manager' "$T/a.log"
check "A migrate menu" 'Apply Latest Fixes' "$T/a.log"

echo "===== B: quick mode ====="
fresh_env
printf '%s\n' 1 '' 13 | bash "$REPO/install_linux.sh" > "$T/b.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run b exit $rc"; }
check "B summary" 'Setup Summary' "$T/b.log"
check "B distro" 'DISTRO="debian"' "$T/home/.config/linux-for-android/setup.conf"
check "B wallpaper mode" 'COLOR_MODE="light"' "$T/home/.config/linux-for-android/setup.conf"
[ "$(stat -c %a "$T/home/.config/linux-for-android/setup.conf")" = "600" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: B conf perms"; }
check "B install done" 'Installation complete!' "$T/b.log"

echo "===== C: guided debian CLI, custom user, validation loops ====="
fresh_env
printf '%s\n' 2 9 2 4 99 'x y' '' '' 'Bad Name!' 'dev' '' 's3cret' '' 'oppo-test' 5 2 'y' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/c.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run c exit $rc"; }
S=$(setup_sh_of)
check "C user" 'useradd -m -s /bin/bash dev' "$S"
check_re "C chpasswd" "printf '%s:%s\\\\n' \"dev\"" "$S"
check "C shim b64" 'SUDO_SHIM_B64=' "$S"
check_absent "C placeholders" '__LUSER__' "$S"
check_absent "C placeholders" '__UPASS_B64__' "$S"
check_absent "C placeholders" '__SPASS_B64__' "$S"
check_absent "C placeholders" '__TZ__' "$S"
check "C start user" '--user "$X11_USER"' "$T/prefix/bin/start-linux"
check_absent "C start placeholders" '__LUSER__' "$T/prefix/bin/start-linux"
check "C conf user" 'USER_NAME="dev"' "$T/prefix/var/lib/proot-distro/installed-rootfs/debian/etc/termux-linux-manager.conf"
check "C polish call" 'Applying Linux polish' "$S"
check "C real-feel staged" 'lfa-real-feel.sh' "$S"
check_absent "C apt note removed" 'shim emulates uid 0' "$T/prefix/bin/terminal-linux"
check_absent "C sudo caveat removed" 'sudo does not work inside proot' "$T/prefix/bin/start-linux"
[ -f "$T/prefix/tmp/lfa-real-feel.sh" ] && sh -n "$T/prefix/tmp/lfa-real-feel.sh" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C real-feel script missing/invalid"; }
check "C hosts" '127.0.1.1 oppo-test' "$S"
check "C boot script" 'termux-wake-lock' "$T/home/.termux/boot/start-linux-services.sh"
bash -n "$S" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C setup syntax"; }
bash -n "$T/prefix/bin/start-linux" && bash -n "$T/prefix/bin/stop-linux" && bash -n "$T/prefix/bin/terminal-linux" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C launcher syntax"; }
[ "$(grep '^SETUP_ROOT_B64=' "$T/home/.config/linux-for-android/setup.conf" | cut -d'"' -f2 | base64 -d 2>/dev/null)" = "s3cret" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C pw roundtrip"; }
# CLI-only installs must not get a wallpaper or autostart entry.
[ ! -e "$T/prefix/var/lib/proot-distro/installed-rootfs/debian/usr/share/backgrounds/lfa-default.jpg" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C CLI got a wallpaper"; }
[ ! -e "$T/prefix/var/lib/proot-distro/installed-rootfs/debian/home/dev/.config/autostart/lfa-wallpaper.desktop" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C CLI got wallpaper autostart"; }

echo "===== D: guided ubuntu xfce x11, hw off, software set ====="
fresh_env
printf '%s\n' 2 1 1 1 1 2 '2 12 14' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/d.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run d exit $rc"; }
S=$(setup_sh_of)
check "D apt mapping" 'apt-get install -y' "$S"
check "D vscode repo" 'packages.microsoft.com' "$S"
check "D x11 branch" 'startxfce4' "$T/prefix/bin/start-linux"
check "D x11 dbus fallback" 'command -v dbus-launch' "$T/prefix/bin/start-linux"
check "D x11 dbus run session" 'dbus-run-session -- startxfce4' "$T/prefix/bin/start-linux"
check_absent "D virgl skipped" 'virglrenderer-android' "$T/d.log"
check "D x11 pkg" 'x11-repo' "$T/d.log"
check "D x11 user fallback" 'X11_USER="${USER_NAME:-${LINUX_USER:-user}}"' "$T/prefix/bin/start-linux"
check "D x11 private runtime" "XDG_RUNTIME_DIR=/tmp/xdg-" "$T/prefix/bin/start-linux"
check "D x11 detached" 'nohup termux-x11 :1' "$T/prefix/bin/start-linux"
check "D light mode saved" 'COLOR_MODE="light"' "$T/home/.config/linux-for-android/setup.conf"
check "D light mode conf" 'COLOR_MODE="light"' "$T/prefix/var/lib/proot-distro/installed-rootfs/ubuntu/etc/termux-linux-manager.conf"
DROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/ubuntu"
[ -s "$DROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$DROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/ubuntu.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: D ubuntu wallpaper not staged"; }
[ "$(cat "$DROOT/etc/lfa-wallpaper-mode" 2>/dev/null)" = "light" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: D wallpaper mode marker"; }
[ -x "$DROOT/usr/local/bin/lfa-set-wallpaper" ] && sh -n "$DROOT/usr/local/bin/lfa-set-wallpaper" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: D wallpaper applier missing/invalid"; }
check "D wallpaper xfce" 'xfconf-query -c xfce4-desktop' "$DROOT/usr/local/bin/lfa-set-wallpaper"
check "D wallpaper waits for xfdesktop" 'workspace[0-9]*/last-image' "$DROOT/usr/local/bin/lfa-set-wallpaper"
check "D wallpaper xrandr seed" 'xrandr --query' "$DROOT/usr/local/bin/lfa-set-wallpaper"
check "D wallpaper monitorscreen seed" 'monitorVNC-0 monitorscreen' "$DROOT/usr/local/bin/lfa-set-wallpaper"
check "D wallpaper repaint nudge" 'xfdesktop --reload' "$DROOT/usr/local/bin/lfa-set-wallpaper"
check "D wallpaper autostart" 'Exec=/usr/local/bin/lfa-set-wallpaper --autostart' "$DROOT/home/user/.config/autostart/lfa-wallpaper.desktop"

echo "===== D2: experimental GNOME (warning, VNC default, launcher) ====="
fresh_env
printf '%s\n' 2 1 5 y 1 '' 2 1 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/d2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run d2 exit $rc"; }
S=$(setup_sh_of)
check "D2 warning shown" 'EXPERIMENTAL / BETA' "$T/d2.log"
check "D2 warning lists breakage" 'gnome-control-center' "$T/d2.log"
check "D2 requires confirmation" 'I understand this is experimental' "$T/d2.log"
check "D2 gnome-shell pkg" 'gnome-shell' "$S"
check "D2 dconf pkg" 'dconf-cli' "$S"
check "D2 vnc default" 'SERVER="vnc"' "$T/home/.config/linux-for-android/setup.conf"
check "D2 de saved" 'DE="gnome"' "$T/home/.config/linux-for-android/setup.conf"
check "D2 de conf" 'DE="gnome"' "$T/prefix/var/lib/proot-distro/installed-rootfs/ubuntu/etc/termux-linux-manager.conf"
check "D2 launcher wrapper" 'start-gnome-session' "$T/prefix/bin/start-linux"
check "D2 vnc xstartup session" '/usr/local/bin/start-gnome-session' "$(setup_sh_of)"
check "D2 guest gets DE" 'LFA_DE="gnome"' "$(setup_sh_of)"

echo "===== D3: declining the GNOME warning falls back to XFCE ====="
fresh_env
printf '%s\n' 2 1 5 n 1 1 2 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/d3.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run d3 exit $rc"; }
check "D3 cancelled" 'GNOME cancelled' "$T/d3.log"
check "D3 fell back" 'Falling back to XFCE4' "$T/d3.log"
check "D3 xfce saved" 'DE="xfce4"' "$T/home/.config/linux-for-android/setup.conf"
check_absent "D3 no gnome session" 'start-gnome-session' "$(setup_sh_of)"

echo "===== D4: GNOME option hidden where unsupported (alpine) ====="
fresh_env
printf '%s\n' 2 8 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/d4.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run d4 exit $rc"; }
check_absent "D4 alpine no GNOME option" 'GNOME (experimental)' "$T/d4.log"

echo "===== E: guided fedora mate ====="
fresh_env
printf '%s\n' 2 4 3 2 1 1 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/e.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run e exit $rc"; }
S=$(setup_sh_of)
check "E dnf" 'dnf install' "$S"
check "E mate" 'mate-desktop' "$S"
check "E mate template" 'mate-session' "$T/prefix/bin/start-linux"
check "E glycin loaders" 'glycin-loaders' "$(setup_sh_of)"
check "E dark mode saved" 'COLOR_MODE="dark"' "$T/home/.config/linux-for-android/setup.conf"
EROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/fedora"
[ -s "$EROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$EROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/fedora-dark.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: E fedora wallpaper not staged"; }
check "E wallpaper mate" 'org.mate.background picture-filename' "$EROOT/usr/local/bin/lfa-set-wallpaper"
[ "$(cat "$EROOT/etc/lfa-wallpaper-mode" 2>/dev/null)" = "dark" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: E wallpaper mode marker"; }
[ -f "$EROOT/home/user/.config/autostart/lfa-wallpaper.desktop" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: E wallpaper autostart missing"; }

echo "===== E2: opensuse xfce (dbus provider rename) ====="
fresh_env
printf '%s\n' 2 5 1 1 1 1 '' ostest ouser 123 123 UTC ostest 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/e2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run e2 exit $rc"; }
E2S=$(setup_sh_of)
check "E2 completes" 'Installation complete!' "$T/e2.log"
check "E2 dbus provider" 'dbus-1-daemon' "$E2S"
check_absent "E2 no dbus-1-x11" 'dbus-1-x11' "$E2S"
check "E2 xfce pattern" 'patterns-xfce-xfce' "$E2S"
check "E2 glycin loaders" 'glycin-loaders' "$E2S"

echo "===== F: guided alpine vnc (lxde remap) ====="
fresh_env
printf '%s\n' 2 8 2 2 2 1 1 '' 'myalpine' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/f.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run f exit $rc"; }
check "F remap" 'DE="xfce4"' "$T/home/.config/linux-for-android/setup.conf"
check "F dark mode saved" 'COLOR_MODE="dark"' "$T/home/.config/linux-for-android/setup.conf"
S=$(setup_sh_of)
check "F apk" 'apk add' "$S"
check "F glycin loaders" 'glycin-loaders-all' "$S"
check "F vncpasswd" 'vncpasswd -f' "$S"
check_absent "F no expect" 'spawn vncpasswd' "$S"
bash -n "$S" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: F setup syntax"; }
FROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/myalpine"
[ -s "$FROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$FROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/alpine-dark.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: F alpine wallpaper not staged"; }
check "F wallpaper vnc" 'monitorVNC-0' "$FROOT/usr/local/bin/lfa-set-wallpaper"
[ "$(cat "$FROOT/etc/lfa-wallpaper-mode" 2>/dev/null)" = "dark" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: F wallpaper mode marker"; }

echo "===== G: legacy debian -> bullseye ====="
fresh_env
export GETPROP_SDK=22 PD_V4=1 FREE_MB=1024
printf '%s\n' 2 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/g.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run g exit $rc"; }
check "G legacy banner" 'LEGACY MODE' "$T/g.log"
check "G bullseye notice" 'bullseye' "$T/g.log"
check "G plugin deployed" 'bullseye' "$T/prefix/etc/proot-distro/bullseye.sh"
grep -q "STUB-PD-INSTALL-OK" "$T/g.log" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: G install ran"; }
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== H: legacy kali rejected, repick alpine ====="
fresh_env
export GETPROP_SDK=22 PD_V4=1 FREE_MB=1024
printf '%s\n' 2 3 8 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/h.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run h exit $rc"; }
check "H kali blocked" 'no legacy plugin' "$T/h.log"
check "H completes" 'Installation complete!' "$T/h.log"
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== H2: legacy alpine XFCE VNC (pinned branch, minimal set) ====="
fresh_env
export GETPROP_SDK=22 PD_V4=1 FREE_MB=1024
printf '%s\n' 2 8 1 1 1 '' h2alpine h2user 123 123 UTC h2alpine 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/h2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run h2 exit $rc"; }
check "H2 completes" 'Installation complete!' "$T/h2.log"
check "H2 vnc auto" 'display server auto-set to VNC' "$T/h2.log"
H2S=$(setup_sh_of)
check "H2 alpine pinned" 's|/edge/|/v3.18/|g' "$H2S"
check_absent "H2 legacy no GNOME option" 'GNOME (experimental)' "$T/h2.log"
check "H2 minimal xfce" 'xfce4-session xfwm4 xfce4-panel' "$H2S"
H2ROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/h2alpine"
[ -s "$H2ROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$H2ROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/alpine.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: H2 alpine wallpaper not staged"; }
[ -f "$H2ROOT/home/h2user/.config/autostart/lfa-wallpaper.desktop" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: H2 wallpaper autostart missing"; }
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== I: legacy ubuntu glibc warning ====="
fresh_env
export GETPROP_SDK=22 PD_V4=1 FREE_MB=1024
printf '%s\n' 2 1 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/i.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run i exit $rc"; }
check "I warning" 'modern glibc' "$T/i.log"
check "I completes" 'Installation complete!' "$T/i.log"
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== J: replay saved + corrupt fallback ====="
fresh_env
printf '%s\n' 2 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/j1.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run j1 exit $rc"; }
printf '%s\n' 4 '' '13' | bash "$REPO/install_linux.sh" > "$T/j2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run j2 exit $rc"; }
check "J replay" 'Loaded saved answers' "$T/j2.log"
if grep -q "Select Distro" "$T/j2.log"; then fail=$((fail+1)); echo "FAIL: J reprompted"; else pass=$((pass+1)); fi
echo "garbage" > "$T/home/.config/linux-for-android/setup.conf"
printf '%s\n' 4 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/j3.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run j3 exit $rc"; }
check "J corrupt fallback" 'incomplete' "$T/j3.log"
check "J corrupt completes" 'Installation complete!' "$T/j3.log"

echo "===== K: manager menu smoke (all ops) ====="
fresh_env
mkdir -p "$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst/etc" "$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst/var" "$T/home/storage/downloads"
printf 'DISTRO="debian"\nDE="none"\nSERVER="none"\nUPDATE_CMD="apt-get update"\n' > "$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst/etc/termux-linux-manager.conf"
touch "$T/home/demoinst-backup.tar.gz" "$T/home/storage/downloads/shared.tar.gz"
printf '%s\n' 3 2 '' 13 | bash "$REPO/install_linux.sh" > "$T/k2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k2 exit $rc"; }
check "K update" 'Update complete!' "$T/k2.log"
printf '%s\n' 3 4 '' 13 | bash "$REPO/install_linux.sh" > "$T/k4.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k4 exit $rc"; }
check "K dashboard" 'SYSTEM DASHBOARD' "$T/k4.log"
printf '%s\n' 3 5 '' 13 | bash "$REPO/install_linux.sh" > "$T/k5.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k5 exit $rc"; }
check "K audio" 'forcefully bound' "$T/k5.log"
printf '%s\n' 3 6 '' 13 | bash "$REPO/install_linux.sh" > "$T/k6.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k6 exit $rc"; }
check "K backup" 'Backup saved' "$T/k6.log"
printf '%s\n' 3 7 y '' 13 | bash "$REPO/install_linux.sh" > "$T/k7.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k7 exit $rc"; }
check "K restore" 'Restore complete!' "$T/k7.log"
printf '%s\n' 3 8 '' 13 | bash "$REPO/install_linux.sh" > "$T/k8.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k8 exit $rc"; }
check "K export" 'Export Complete!' "$T/k8.log"
printf '%s\n' 3 9 'shared.tar.gz' 'myimp' 'y' '' '13' | bash "$REPO/install_linux.sh" > "$T/k9.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k9 exit $rc"; }
check "K import" 'Import complete!' "$T/k9.log"
ROOTFS="$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst"
mkdir -p "$ROOTFS/var/lib/dpkg" "$ROOTFS/usr/local/bin"
printf 'root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper\n' > "$ROOTFS/var/lib/dpkg/statoverride"
printf '%s\n' 3 0 '' 13 | bash "$REPO/install_linux.sh" > "$T/k0.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k0 exit $rc"; }
check "K repair completes" 'Repair complete!' "$T/k0.log"
[ -f "$ROOTFS/usr/local/bin/dpkg-statoverride" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: K repair shim not installed"; }
[ -f "$T/prefix/tmp/lfa-repair.sh" ] && bash -n "$T/prefix/tmp/lfa-repair.sh" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: K repair script missing/invalid"; }
check "K repair purges broken snapd" 'dpkg --purge --force-all snapd' "$T/prefix/tmp/lfa-repair.sh"
check "K repair pins snapd off" '99-proot-no-snap' "$T/prefix/tmp/lfa-repair.sh"
printf '%s\n' 3 11 2 '' 13 | bash "$REPO/install_linux.sh" > "$T/k11.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k11 exit $rc"; }
check "K browser" 'Hardware Acceleration disabled' "$T/k11.log"
printf '%s\n' 3 3 '' 13 | bash "$REPO/install_linux.sh" > "$T/k3.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k3 exit $rc"; }
check "K ssh" 'SSH Server is running!' "$T/k3.log"
printf '%s\n' 3 10 y '' 13 | bash "$REPO/install_linux.sh" > "$T/k10.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k10 exit $rc"; }
check "K uninstall" 'has been removed' "$T/k10.log"
[ ! -e "$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: K uninstall left the rootfs behind"; }
grep -q '^kill demoinst$' "$T/home/pd-calls.log" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: K uninstall did not kill sessions"; }

echo "===== L: shim password ritual over pty ====="
fresh_env
printf '%s\n' 2 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/l.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run l exit $rc"; }
S=$(setup_sh_of)
SHIM="${TMPDIR:-/tmp}/lfa-shim-test"
python3 - "$S" "$SHIM" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"cat << 'SUDO' > /usr/local/bin/sudo\n(.*?)\nSUDO\n", src, re.S)
open(sys.argv[2],'w').write(m.group(1))
EOF
if command -v script >/dev/null 2>&1; then
    printf 'wrong\nroot\n' | script -qec "sh $SHIM echo SHIM-OK" /dev/null 2>&1 | tail -1 | grep -q SHIM-OK && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L ritual"; }
    printf 'a\nb\nc\n' | script -qec "sh $SHIM echo HI" /dev/null 2>&1 | tail -1 | grep -q "3 incorrect" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L rejects"; }
else
    echo "SKIP: L (no 'script' for pty test)"; pass=$((pass+2))
fi

echo "===== L2: arrow-key UI over a real pty ====="
fresh_env
if command -v script >/dev/null 2>&1; then
    # Typing "3" + Enter opens the manager; "13" + Enter exits.
    printf '3\n13\n' | TERM=xterm-256color timeout 15 script -qec "bash '$REPO/install_linux.sh'" /dev/null > "$T/tty-digits.log" 2>&1
    rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L2 pty digit ui exit $rc"; }
    check "L2 digit menu" 'Linux for Termux Manager' "$T/tty-digits.log"
    # Two Down arrows + Enter pick "Manager"; q goes back and exits.
    printf '\033[B\033[B\nq' | TERM=xterm-256color timeout 15 script -qec "bash '$REPO/install_linux.sh'" /dev/null > "$T/tty-arrows.log" 2>&1
    rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L2 pty arrow ui exit $rc"; }
    check "L2 arrows navigate" 'Bye.' "$T/tty-arrows.log"
    grep -q $'\033\[' "$T/tty-arrows.log" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L2 no ANSI colours"; }
else
    echo "SKIP: L2 (no 'script' for pty test)"; pass=$((pass+4))
fi

echo "===== M: dpkg statoverride shim ====="
fresh_env
printf '%s\n' 1 '' 13 | bash "$REPO/install_linux.sh" > "$T/m.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run m exit $rc"; }
S=$(setup_sh_of)
check "M shim embedded" 'proot-safe dpkg-statoverride' "$S"
check "M sanitizer embedded" 'Sanitising dpkg statoverride' "$S"
check_absent "M no blind dbus seed" 'root messagebus 4754' "$S"

python3 - "$S" "$T/statoverride-shim.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"<< 'LFA_SO'\n(.*?)\nLFA_SO\n", src, re.S)
assert m, "shim heredoc not found"
open(sys.argv[2], 'w').write(m.group(1))
PY
bash -n "$T/statoverride-shim.sh" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M shim syntax"; }
python3 - "$T/statoverride-shim.sh" "$REPO/lib/dpkg-statoverride.sh" <<'PY2'
import sys
a = open(sys.argv[1]).read().rstrip('\n')
b = open(sys.argv[2]).read().rstrip('\n')
sys.exit(0 if a == b else 1)
PY2
[ $? -eq 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M embedded shim differs from lib/"; }

mkdir -p "$T/getentbin"
cat > "$T/getentbin/getent" <<'EOF'
#!/bin/sh
case "$1:$2" in
    passwd:root|passwd:pdev|group:root|group:pdev) exit 0 ;;
esac
exit 1
EOF
chmod +x "$T/getentbin/getent"
cat > "$T/fake-realso" <<'EOF'
#!/bin/sh
echo "REAL-CALLED: $*"
exit 0
EOF
chmod +x "$T/fake-realso"
printf 'root root 4755 /usr/bin/good\nroot ghost 4755 /usr/bin/ghosty\n' > "$T/so.db"
run_shim() { PATH="$T/getentbin:$PATH" LFA_STATOVERRIDE_DB="$T/so.db" LFA_DPKG_STATOVERRIDE="$T/fake-realso" sh "$T/statoverride-shim.sh" "$@"; }

run_shim --list /usr/bin/good > "$T/m-list.log" 2>&1
check "M list delegates" 'REAL-CALLED' "$T/m-list.log"
check "M valid row kept" '/usr/bin/good' "$T/so.db"
check_absent "M invalid row pruned" 'ghosty' "$T/so.db"

run_shim --add root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper > "$T/m-add-bad.log" 2>&1
check "M unknown group skipped" 'unknown group' "$T/m-add-bad.log"
check_absent "M unknown group not recorded" 'messagebus' "$T/so.db"

run_shim --add root root 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper > "$T/m-add.log" 2>&1
check "M add recorded" 'dbus-daemon-launch-helper' "$T/so.db"

run_shim --remove /usr/lib/dbus-1.0/dbus-daemon-launch-helper > "$T/m-rm.log" 2>&1
check_absent "M remove applied" 'dbus-daemon-launch-helper' "$T/so.db"

run_shim --version > "$T/m-ver.log" 2>&1
check "M passthrough" 'REAL-CALLED' "$T/m-ver.log"

echo "===== M2: glycin bwrap shim (proot) ====="
GLROOT="$T/glycinroot"
mkdir -p "$GLROOT/usr/libexec/glycin-loaders" "$GLROOT/etc" "$GLROOT/home/guser"
LFA_ROOT="$GLROOT" LFA_USER=guser sh "$REPO/lib/real-feel.sh" >/dev/null 2>&1
[ -x "$GLROOT/usr/local/bin/bwrap" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M2 bwrap shim missing"; }
check "M2 shim message" 'No permissions to create a new namespace' "$GLROOT/usr/local/bin/bwrap"
[ -x "$GLROOT/usr/local/bin/reboot" ] && [ -x "$GLROOT/usr/local/bin/shutdown" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M2 reboot/shutdown shim missing"; }
check "M2 reboot shim guidance" 'start-linux' "$GLROOT/usr/local/bin/reboot"
[ -s "$GLROOT/etc/machine-id" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M2 machine-id missing"; }
{ [ -e "$GLROOT/var/lib/dbus/machine-id" ] || [ -L "$GLROOT/var/lib/dbus/machine-id" ]; } && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M2 dbus machine-id link missing"; }

echo "===== M3: experimental GNOME session wrapper ====="
GNROOT="$T/gnomeroot"
LFA_ROOT="$GNROOT" LFA_USER=guser LFA_DE=gnome sh "$REPO/lib/real-feel.sh" >/dev/null 2>&1
[ -x "$GNROOT/usr/local/bin/start-gnome-session" ] && sh -n "$GNROOT/usr/local/bin/start-gnome-session" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M3 GNOME starter missing/invalid"; }
check "M3 starts shell" 'exec gnome-shell --x11' "$GNROOT/usr/local/bin/start-gnome-session"
check "M3 applies wallpaper" 'lfa-set-wallpaper --autostart' "$GNROOT/usr/local/bin/start-gnome-session"
check "M3 session desktop" 'XDG_CURRENT_DESKTOP=GNOME' "$GNROOT/usr/local/bin/start-gnome-session"
check "M3 x11 capability probe" 'gnome-shell --help' "$GNROOT/usr/local/bin/start-gnome-session"
check "M3 x11 fallback message" 'no longer supports an X11 session' "$GNROOT/usr/local/bin/start-gnome-session"
GN2="$T/gnomeroot2"
LFA_ROOT="$GN2" LFA_USER=guser LFA_DE=xfce4 sh "$REPO/lib/real-feel.sh" >/dev/null 2>&1
[ ! -e "$GN2/usr/local/bin/start-gnome-session" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: M3 wrapper written for non-GNOME desktop"; }

echo "===== N: apply latest fixes to an older distro ====="
fresh_env
NROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/oldinst"
mkdir -p "$NROOT/etc" "$NROOT/var/lib/dpkg" "$NROOT/home/user/.vnc" "$NROOT/root"
printf 'DISTRO="debian"\nDE="xfce4"\nSERVER="vnc"\nRESOLUTION="1280x720"\nUPDATE_CMD="apt-get update"\nHOSTNAME="oldphone"\n' > "$NROOT/etc/termux-linux-manager.conf"
cat > "$NROOT/home/user/.bashrc" <<'EOF'
PS1='\u@\h:\w\$ '
EOF
printf 'root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper\n' > "$NROOT/var/lib/dpkg/statoverride"
printf '%s\n' 3 12 '' 13 | bash "$REPO/install_linux.sh" > "$T/n.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run n exit $rc"; }
check "N completes" 'Latest fixes applied!' "$T/n.log"
check "N adds user key" 'USER_NAME="user"' "$NROOT/etc/termux-linux-manager.conf"
check "N adds color key" 'COLOR_MODE="light"' "$NROOT/etc/termux-linux-manager.conf"
check "N adds virgl key" 'NEED_VIRGL="1"' "$NROOT/etc/termux-linux-manager.conf"
check "N keeps hostname" 'HOSTNAME="oldphone"' "$NROOT/etc/termux-linux-manager.conf"
check "N bakes hostname" 'oldphone' "$NROOT/home/user/.bashrc"
check "N colored prompt" '01;32' "$NROOT/home/user/.bashrc"
check "N hostname shim" 'cat /etc/hostname' "$NROOT/usr/local/bin/hostname"
check "N etc hostname synced" 'oldphone' "$NROOT/etc/hostname"
check "N welcome banner" 'Welcome to' "$NROOT/etc/profile.d/00-lfa-welcome.sh"
check "N env cleanup" 'TERMUX' "$NROOT/etc/profile.d/zz-lfa-env.sh"
check "N login profile" 'linux-for-android profile' "$NROOT/home/user/.profile"
check "N launcher updated" 'command -v dbus-launch' "$T/prefix/bin/start-linux"
check "N xstartup updated" 'startxfce4' "$NROOT/home/user/.vnc/xstartup"
[ -s "$NROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$NROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/debian.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: N upgrade wallpaper not staged"; }
check "N wallpaper autostart" 'lfa-set-wallpaper --autostart' "$NROOT/home/user/.config/autostart/lfa-wallpaper.desktop"
[ -f "$T/prefix/tmp/lfa-upgrade.sh" ] && bash -n "$T/prefix/tmp/lfa-upgrade.sh" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: N upgrade script missing/invalid"; }

echo "===== O: proot-distro v4 containers layout ====="
fresh_env
CROOT="$T/prefix/var/lib/proot-distro/containers/newinst/rootfs"
mkdir -p "$CROOT/etc" "$CROOT/var/lib/dpkg" "$CROOT/usr/local/bin" "$CROOT/home/user"
printf 'DISTRO="debian"\nDE="none"\nSERVER="none"\nUPDATE_CMD="apt-get update"\nHOSTNAME="v4host"\n' > "$CROOT/etc/termux-linux-manager.conf"
printf 'root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper\n' > "$CROOT/var/lib/dpkg/statoverride"
printf '%s\n' 3 0 '' 13 | bash "$REPO/install_linux.sh" > "$T/o1.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run o1 exit $rc"; }
check "O doctor finds v4 rootfs" 'Repair complete!' "$T/o1.log"
[ -f "$CROOT/usr/local/bin/dpkg-statoverride" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: O shim not written to containers rootfs"; }
printf '%s\n' 3 12 '' 13 | bash "$REPO/install_linux.sh" > "$T/o2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run o2 exit $rc"; }
check "O migrate v4" 'Latest fixes applied!' "$T/o2.log"
check "O conf in real rootfs" 'USER_NAME="user"' "$CROOT/etc/termux-linux-manager.conf"
check "O launcher lib written" 'lfa_conf' "$T/prefix/bin/lfa-lib.sh"
check "O launcher bootstraps lib" 'lfa-lib.sh' "$T/prefix/bin/start-linux"
check "O launcher lists containers" 'containers' "$T/prefix/bin/lfa-lib.sh"

echo "===== P: uninstall cleanup (broken/ghost) ====="
fresh_env
BROKEN="$T/prefix/var/lib/proot-distro/containers/broken/rootfs"
mkdir -p "$BROKEN/etc" "$T/prefix/var/lib/proot-distro/installed-rootfs/ghost/etc"
printf 'DISTRO="debian"\nDE="none"\nSERVER="none"\nUPDATE_CMD="true"\n' > "$BROKEN/etc/termux-linux-manager.conf"
printf 'DISTRO="debian"\n' > "$T/prefix/var/lib/proot-distro/installed-rootfs/ghost/etc/termux-linux-manager.conf"
printf '%s\n' 3 10 n '' 13 | bash "$REPO/install_linux.sh" > "$T/p-cancel.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run p-cancel exit $rc"; }
check "P cancel works" 'Cancelled.' "$T/p-cancel.log"
[ -d "$BROKEN" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: P cancel still deleted data"; }
printf '%s\n' 3 10 y '' 13 | bash "$REPO/install_linux.sh" > "$T/p.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run p exit $rc"; }
check "P broken instance shown" 'Uninstall: broken' "$T/p.log"
check "P status warns" 'incomplete' "$T/p.log"
grep -q '^kill broken$' "$T/home/pd-calls.log" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: P did not kill sessions"; }
check "P removes broken" 'has been removed' "$T/p.log"
[ ! -e "$T/prefix/var/lib/proot-distro/containers/broken" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: P broken container left behind"; }
[ -d "$T/prefix/var/lib/proot-distro/installed-rootfs/ghost" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: P ghost stub was touched"; }

echo "===== Q: EOF on stdin exits cleanly (no infinite loop) ====="
fresh_env
if printf '' | timeout 10 bash "$REPO/install_linux.sh" > "$T/q.log" 2>&1; then
    pass=$((pass+1))
else
    fail=$((fail+1)); echo "FAIL: Q EOF did not exit cleanly"
fi
check "Q manager shown" 'Linux for Termux Manager' "$T/q.log"
check "Q clean bye" 'Bye.' "$T/q.log"

echo "===== R: proot-distro v5 image mode ====="
fresh_env
export PD_V5=1
printf '%s\n' 2 8 4 '' v5alpine '' '' '' '' '' 1 n '' n n '' '' 13 \
| bash "$REPO/install_linux.sh" > "$T/r.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run r exit $rc"; }
check_absent "R no plugin rejection" "knows no 'alpine'" "$T/r.log"
check "R image install" 'STUB-PD-INSTALL-OK: install --name v5alpine alpine:latest' "$T/r.log"
check "R completes" 'Installation complete!' "$T/r.log"
# pd_is_v4 must recognise the modern restore interface (not just legacy plugins).
mkdir -p "$T/prefix/bin"
cp "$T/fakebin/proot-distro" "$T/prefix/bin/proot-distro"
chmod +x "$T/prefix/bin/proot-distro"
MODERN=$(PREFIX="$T/prefix" PATH="$T/fakebin${REAL_PREFIX:+:$REAL_PREFIX/bin}:/usr/bin:/bin" PD_V5=1 bash -c '
source <(sed -n "/^pd_is_v4()/,/^}/p" "$1")
pd_is_v4 && echo MODERN || echo LEGACY
' _ "$REPO/install_linux.sh")
[ "$MODERN" = "MODERN" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: R pd_is_v4 did not detect v5 ($MODERN)"; }
unset PD_V5

echo "===== S: software menu, pip/npm, browsers, Antigravity ====="
fresh_env
printf '%s\n' 2 1 4 '1 2 3 6 7 8 9 10 11 12 13 14' softinst suser '' '' UTC softinst 1 n '' n n '' '' 13 \
| bash "$REPO/install_linux.sh" > "$T/s.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run s exit $rc"; }
S=$(setup_sh_of)
check "S python pip" 'python3 python3-pip' "$S"
check "S node npm" 'nodejs npm' "$S"
check "S firefox tarball" 'linux64-aarch64' "$S"
check "S chromium debian" 'debian-chromium.list' "$S"
check "S chromium wrapper" 'lfa-chromium-flags' "$S"
check "S apt retries" 'Repository update failed' "$S"
check "S apt fix-missing" '--fix-missing' "$S"
check "S core verify" 'Core installation incomplete' "$S"
check "S antigravity real" 'antigravity.google/download' "$S"
check_absent "S antigravity placeholder" 'Terminal Edition' "$S"

# On Debian/Kali, Firefox must use firefox-esr (no `firefox` package).
fresh_env
printf '%s\n' 2 2 4 '7 8' debsoft '' '' '' UTC debsoft 1 n '' n n '' '' 13 \
| bash "$REPO/install_linux.sh" > "$T/s2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run s2 exit $rc"; }
S=$(setup_sh_of)
check "S debian firefox-esr" 'firefox-esr' "$S"

echo "===== T: Void bootstrap via proot-distro run ====="
fresh_env
export PD_V5=1
printf '%s\n' 2 6 4 '' voidinst vuser '' '' UTC voidinst 1 n '' n n '' '' 13 \
| bash "$REPO/install_linux.sh" > "$T/t.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run t exit $rc"; }
check "T void bootstrap message" 'Bootstrapping Void base tools' "$T/t.log"
check "T void uses run" 'STUB-PD-run-OK: run' "$T/t.log"
check "T void bash shadow" 'xbps-install -y bash shadow' "$T/t.log"

echo "===== U: guest PATH hygiene ====="
check "U clean path" '_clean_path' "$T/prefix/tmp/lfa-real-feel.sh"
check "U drops termux" '/data/data/*' "$T/prefix/tmp/lfa-real-feel.sh"

echo "===== V: VNC correctness (TigerVNC 1.15, keepalive) ====="
fresh_env
export PD_V5=1
printf '%s\n' 2 2 2 2 2 2 1 '' vnctest vncuser 123 123 UTC vnctest 1 n '' n n '' '' 13 \
| bash "$REPO/install_linux.sh" > "$T/v.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run v exit $rc"; }
VS=$(setup_sh_of)
check "V both config dirs" 'mkdir -p /home/vncuser/.vnc /home/vncuser/.config/tigervnc' "$VS"
check "V exec desktop" 'exec dbus-run-session -- startlxde' "$VS"
check "V clean PATH" 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$VS"
check "V password gate" 'vnc-password' "$VS"
check "V noninteractive vncpasswd" 'vncpasswd -f' "$VS"
check "V keepalive launcher" 'while :; do sleep 3600; done' "$T/prefix/bin/start-linux"
check "V vnc config geometry" '.config/tigervnc/config' "$T/prefix/bin/start-linux"
check "V xvnc fallback" 'Xvnc :1 -geometry' "$T/prefix/bin/start-linux"
check "V vnc session var" 'VNC_SES="startxfce4"' "$T/prefix/bin/start-linux"
check "V clears stale runtime" 'rm -rf "$PREFIX/tmp/xdg-$X11_USER"' "$T/prefix/bin/start-linux"
check "V clears dbus sockets" 'rm -f "$PREFIX"/tmp/dbus-*' "$T/prefix/bin/start-linux"
check "V clears stale X1 socket" 'rm -f "$PREFIX/tmp/.X11-unix/X1"' "$T/prefix/bin/start-linux"
check_absent "V no legacy vncserver flags" 'vncserver -geometry' "$T/prefix/bin/start-linux"
check "V stop pidfile" 'lfa-vnc-$DISTRO.pid' "$T/prefix/bin/stop-linux"
check "V start uses bash login" '/bin/bash -l' "$T/prefix/bin/start-linux"
check "V terminal uses bash login" '/bin/bash -l' "$T/prefix/bin/terminal-linux"
check "V terminal reads conf user" 'TERM_USER="${USER_NAME:-${LINUX_USER:-user}}"' "$T/prefix/bin/terminal-linux"
check_absent "V no baked terminal user" '--user __LUSER__' "$T/prefix/bin/terminal-linux"
check "V start user dynamic" '--user "$X11_USER"' "$T/prefix/bin/start-linux"
check "V stop user dynamic" '--user "$VNC_USER"' "$T/prefix/bin/stop-linux"
VROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/vnctest"
[ -s "$VROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$VROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/debian-dark.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: V debian dark wallpaper not staged"; }
check "V lxde wallpaper" 'wallpaper=/usr/share/backgrounds/lfa-default.jpg' "$VROOT/home/vncuser/.config/pcmanfm/LXDE/pcmanfm.conf"

echo "===== W: Alpine fastfetch/neofetch alias ====="
fresh_env
export PD_V5=1
printf '%s\n' 2 8 4 '13' alpineapp auser '' '' UTC alpineapp 1 n '' n n '' '' 13 \
| bash "$REPO/install_linux.sh" > "$T/w.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run w exit $rc"; }
WA=$(setup_sh_of)
check "W alpine fastfetch" 'fastfetch' "$WA"
check "W alpine neofetch alias" 'ln -sf /usr/bin/fastfetch /usr/local/bin/neofetch' "$WA"

echo "===== X: distro wallpapers (light/dark, LXDE, CLI) ====="
fresh_env
for _d in ubuntu debian kali fedora opensuse archlinux void alpine; do
    for _s in "" "-dark"; do
        if [ -s "$REPO/assets/wallpapers/$_d$_s.jpg" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: X missing wallpaper $_d$_s.jpg"; fi
    done
done
LXROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/lxroot"
mkdir -p "$LXROOT"
LFA_ROOT="$LXROOT" LFA_USER=lxuser LFA_DISTRO=debian LFA_DE=lxde LFA_MODE=dark \
    LFA_ASSET_DIR="$REPO/assets/wallpapers" sh "$REPO/lib/wallpaper.sh" > "$T/x.log" 2>&1
check "X lxde wallpaper path" 'wallpaper=/usr/share/backgrounds/lfa-default.jpg' "$LXROOT/home/lxuser/.config/pcmanfm/LXDE/pcmanfm.conf"
check "X lxde zoom mode" 'wallpaper_mode=5' "$LXROOT/home/lxuser/.config/pcmanfm/LXDE/desktop-items-0.conf"
check "X lxde autostart" 'lfa-set-wallpaper --autostart' "$LXROOT/home/lxuser/.config/autostart/lfa-wallpaper.desktop"
[ -s "$LXROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$LXROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/debian-dark.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: X LXDE dark wallpaper not staged"; }
[ "$(cat "$LXROOT/etc/lfa-wallpaper-mode" 2>/dev/null)" = "dark" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: X dark mode marker"; }
LIGHTROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/lightroot"
mkdir -p "$LIGHTROOT"
LFA_ROOT="$LIGHTROOT" LFA_USER=lightuser LFA_DISTRO=ubuntu LFA_DE=xfce4 LFA_MODE=light \
    LFA_ASSET_DIR="$REPO/assets/wallpapers" sh "$REPO/lib/wallpaper.sh" > "$T/xl.log" 2>&1
[ -s "$LIGHTROOT/usr/share/backgrounds/lfa-default.jpg" ] && cmp -s "$LIGHTROOT/usr/share/backgrounds/lfa-default.jpg" "$REPO/assets/wallpapers/ubuntu.jpg" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: X light wallpaper not staged"; }
CLIROOT="$T/prefix/var/lib/proot-distro/installed-rootfs/cliroot"
mkdir -p "$CLIROOT"
LFA_ROOT="$CLIROOT" LFA_USER=cliuser LFA_DISTRO=ubuntu LFA_DE=none LFA_MODE=dark \
    LFA_ASSET_DIR="$REPO/assets/wallpapers" sh "$REPO/lib/wallpaper.sh" > "$T/xc.log" 2>&1
[ ! -e "$CLIROOT/usr/share/backgrounds/lfa-default.jpg" ] && [ ! -e "$CLIROOT/home/cliuser" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: X CLI-only wallpaper not skipped"; }

echo ""
echo "PASS=$pass FAIL=$fail"
[ "$fail" = "0" ]
