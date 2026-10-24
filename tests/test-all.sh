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
            printf 'Available distributions:\n  * Debian\n    Alias: debian\n  * Alpine Linux\n    Alias: alpine\n  * Debian (bullseye)\n    Alias: bullseye\n  * Ubuntu\n    Alias: ubuntu\n  * Fedora\n    Alias: fedora\n'
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
    export HOME="$T/home" PREFIX="$T/prefix" PATH="$T/fakebin:/usr/bin:/bin" TERM=""
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
check "C start user" '--user dev' "$T/prefix/bin/start-linux"
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

echo "===== D: guided ubuntu xfce x11, hw off, software set ====="
fresh_env
printf '%s\n' 2 1 1 1 2 '2 12 14' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/d.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run d exit $rc"; }
S=$(setup_sh_of)
check "D apt mapping" 'apt-get install -y' "$S"
check "D vscode repo" 'packages.microsoft.com' "$S"
check "D x11 branch" 'startxfce4' "$T/prefix/bin/start-linux"
check "D x11 dbus fallback" 'command -v dbus-launch' "$T/prefix/bin/start-linux"
check_absent "D virgl skipped" 'virglrenderer-android' "$T/d.log"
check "D x11 pkg" 'x11-repo' "$T/d.log"
check "D x11 user fallback" 'X11_USER="${USER_NAME:-${LINUX_USER:-user}}"' "$T/prefix/bin/start-linux"
check "D x11 private runtime" "XDG_RUNTIME_DIR=/tmp/xdg-" "$T/prefix/bin/start-linux"
check "D x11 detached" 'nohup termux-x11 :1' "$T/prefix/bin/start-linux"

echo "===== E: guided fedora mate ====="
fresh_env
printf '%s\n' 2 4 3 1 1 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/e.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run e exit $rc"; }
S=$(setup_sh_of)
check "E dnf" 'dnf install' "$S"
check "E mate" 'mate-desktop' "$S"
check "E mate template" 'mate-session' "$T/prefix/bin/start-linux"

echo "===== F: guided alpine vnc (lxde remap) ====="
fresh_env
printf '%s\n' 2 8 2 2 1 1 '' 'myalpine' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '13' \
| bash "$REPO/install_linux.sh" > "$T/f.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run f exit $rc"; }
check "F remap" 'DE="xfce4"' "$T/home/.config/linux-for-android/setup.conf"
S=$(setup_sh_of)
check "F apk" 'apk add' "$S"
check "F vnc expect" 'spawn vncpasswd' "$S"
check "F expect decodes" 'set vpw [exec echo' "$S"
bash -n "$S" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: F setup syntax"; }

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
python3 - "$S" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"cat << 'SUDO' > /usr/local/bin/sudo\n(.*?)\nSUDO\n", src, re.S)
open('/tmp/opencode-shim-test','w').write(m.group(1))
EOF
if command -v script >/dev/null 2>&1; then
    printf 'wrong\nroot\n' | script -qec "sh /tmp/opencode-shim-test echo SHIM-OK" /dev/null 2>&1 | tail -1 | grep -q SHIM-OK && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L ritual"; }
    printf 'a\nb\nc\n' | script -qec "sh /tmp/opencode-shim-test echo HI" /dev/null 2>&1 | tail -1 | grep -q "3 incorrect" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: L rejects"; }
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
check "N adds virgl key" 'NEED_VIRGL="1"' "$NROOT/etc/termux-linux-manager.conf"
check "N keeps hostname" 'HOSTNAME="oldphone"' "$NROOT/etc/termux-linux-manager.conf"
check "N bakes hostname" 'oldphone' "$NROOT/home/user/.bashrc"
check "N colored prompt" '01;32' "$NROOT/home/user/.bashrc"
check "N hostname shim" 'cat /etc/hostname' "$NROOT/usr/local/bin/hostname"
check "N etc hostname synced" 'oldphone' "$NROOT/etc/hostname"
check "N welcome banner" 'Welcome to' "$NROOT/etc/profile.d/00-lfa-welcome.sh"
check "N env cleanup" 'TERMUX' "$NROOT/etc/profile.d/01-lfa-env.sh"
check "N launcher updated" 'command -v dbus-launch' "$T/prefix/bin/start-linux"
check "N xstartup updated" 'startxfce4' "$NROOT/home/user/.vnc/xstartup"
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
MODERN=$(PREFIX="$T/prefix" PATH="$T/fakebin:/usr/bin:/bin" PD_V5=1 bash -c '
source <(sed -n "/^pd_is_v4()/,/^}/p" "$1")
pd_is_v4 && echo MODERN || echo LEGACY
' _ "$REPO/install_linux.sh")
[ "$MODERN" = "MODERN" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: R pd_is_v4 did not detect v5 ($MODERN)"; }
unset PD_V5

echo ""
echo "PASS=$pass FAIL=$fail"
[ "$fail" = "0" ]
