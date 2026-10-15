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
case "$1" in
    list) printf 'Available distributions:\n  * Debian\n    Alias: debian\n  * Alpine Linux\n    Alias: alpine\n  * Debian (bullseye)\n    Alias: bullseye\n  * Ubuntu\n    Alias: ubuntu\n  * Fedora\n    Alias: fedora\n' ;;
    install)
        if [ "$2" = "--help" ]; then
            if [ "${PD_V4:-0}" = "1" ]; then echo "Usage: install [--override-alias ALIAS] DISTRO";
            else echo "Usage: install ALIAS"; fi
        else echo "STUB-PD-INSTALL-OK"; fi ;;
    login|backup|remove|restore) echo "STUB-PD-$1-OK" ;;
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
printf '%s\n' 9 3 12 | bash "$REPO/install_linux.sh" > "$T/a.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run a exit $rc"; }
[ "$?" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: A exit code"; }
check "A reprompt" 'Invalid choice' "$T/a.log"
check "A menu shown" 'Linux for Termux Manager' "$T/a.log"

echo "===== B: quick mode ====="
fresh_env
printf '%s\n' 1 '' 12 | bash "$REPO/install_linux.sh" > "$T/b.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run b exit $rc"; }
check "B summary" 'Setup Summary' "$T/b.log"
check "B distro" 'DISTRO="debian"' "$T/home/.config/linux-for-android/setup.conf"
[ "$(stat -c %a "$T/home/.config/linux-for-android/setup.conf")" = "600" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: B conf perms"; }
check "B install done" 'Installation complete!' "$T/b.log"

echo "===== C: guided debian CLI, custom user, validation loops ====="
fresh_env
printf '%s\n' 2 9 2 4 99 'x y' '' '' 'Bad Name!' 'dev' '' 's3cret' '' 'oppo-test' 5 2 'y' '' 'n' 'n' '' '' '12' \
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
check "C informative prompt" 'Configuring informative shell prompt' "$S"
check "C hosts" '127.0.1.1 oppo-test' "$S"
check "C boot script" 'termux-wake-lock' "$T/home/.termux/boot/start-linux-services.sh"
bash -n "$S" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C setup syntax"; }
bash -n "$T/prefix/bin/start-linux" && bash -n "$T/prefix/bin/stop-linux" && bash -n "$T/prefix/bin/terminal-linux" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C launcher syntax"; }
[ "$(grep '^SETUP_ROOT_B64=' "$T/home/.config/linux-for-android/setup.conf" | cut -d'"' -f2 | base64 -d 2>/dev/null)" = "s3cret" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: C pw roundtrip"; }

echo "===== D: guided ubuntu xfce x11, hw off, software set ====="
fresh_env
printf '%s\n' 2 1 1 1 2 '2 12 14' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/d.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run d exit $rc"; }
S=$(setup_sh_of)
check "D apt mapping" 'apt-get install -y' "$S"
check "D vscode repo" 'packages.microsoft.com' "$S"
check "D x11 branch" 'startxfce4' "$T/prefix/bin/start-linux"
check_absent "D virgl skipped" 'virglrenderer-android' "$T/d.log"
check "D x11 pkg" 'x11-repo' "$T/d.log"

echo "===== E: guided fedora mate ====="
fresh_env
printf '%s\n' 2 4 3 1 1 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/e.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run e exit $rc"; }
S=$(setup_sh_of)
check "E dnf" 'dnf install' "$S"
check "E mate" 'mate-desktop' "$S"
check "E mate template" 'mate-session' "$T/prefix/bin/start-linux"

echo "===== F: guided alpine vnc (lxde remap) ====="
fresh_env
printf '%s\n' 2 8 2 2 1 1 '' 'myalpine' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
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
printf '%s\n' 2 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/g.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run g exit $rc"; }
check "G legacy banner" 'LEGACY MODE' "$T/g.log"
check "G bullseye notice" 'bullseye' "$T/g.log"
check "G plugin deployed" 'bullseye' "$T/prefix/etc/proot-distro/bullseye.sh"
grep -q "STUB-PD-INSTALL-OK" "$T/g.log" && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: G install ran"; }
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== H: legacy kali rejected, repick alpine ====="
fresh_env
export GETPROP_SDK=22 PD_V4=1 FREE_MB=1024
printf '%s\n' 2 3 8 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/h.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run h exit $rc"; }
check "H kali blocked" 'no legacy plugin' "$T/h.log"
check "H completes" 'Installation complete!' "$T/h.log"
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== I: legacy ubuntu glibc warning ====="
fresh_env
export GETPROP_SDK=22 PD_V4=1 FREE_MB=1024
printf '%s\n' 2 1 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/i.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run i exit $rc"; }
check "I warning" 'modern glibc' "$T/i.log"
check "I completes" 'Installation complete!' "$T/i.log"
unset GETPROP_SDK PD_V4 FREE_MB

echo "===== J: replay saved + corrupt fallback ====="
fresh_env
printf '%s\n' 2 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/j1.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run j1 exit $rc"; }
printf '%s\n' 4 '' '12' | bash "$REPO/install_linux.sh" > "$T/j2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run j2 exit $rc"; }
check "J replay" 'Loaded saved answers' "$T/j2.log"
if grep -q "Select Distro" "$T/j2.log"; then fail=$((fail+1)); echo "FAIL: J reprompted"; else pass=$((pass+1)); fi
echo "garbage" > "$T/home/.config/linux-for-android/setup.conf"
printf '%s\n' 4 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
| bash "$REPO/install_linux.sh" > "$T/j3.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run j3 exit $rc"; }
check "J corrupt fallback" 'incomplete' "$T/j3.log"
check "J corrupt completes" 'Installation complete!' "$T/j3.log"

echo "===== K: manager menu smoke (all ops) ====="
fresh_env
mkdir -p "$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst/etc" "$T/home/storage/downloads"
printf 'DISTRO="debian"\nDE="none"\nSERVER="none"\nUPDATE_CMD="apt-get update"\n' > "$T/prefix/var/lib/proot-distro/installed-rootfs/demoinst/etc/termux-linux-manager.conf"
touch "$T/home/demoinst-backup.tar.gz" "$T/home/storage/downloads/shared.tar.gz"
printf '%s\n' 3 2 '' 12 | bash "$REPO/install_linux.sh" > "$T/k2.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k2 exit $rc"; }
check "K update" 'Update complete!' "$T/k2.log"
printf '%s\n' 3 4 '' 12 | bash "$REPO/install_linux.sh" > "$T/k4.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k4 exit $rc"; }
check "K dashboard" 'SYSTEM DASHBOARD' "$T/k4.log"
printf '%s\n' 3 5 '' 12 | bash "$REPO/install_linux.sh" > "$T/k5.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k5 exit $rc"; }
check "K audio" 'forcefully bound' "$T/k5.log"
printf '%s\n' 3 6 '' 12 | bash "$REPO/install_linux.sh" > "$T/k6.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k6 exit $rc"; }
check "K backup" 'Backup saved' "$T/k6.log"
printf '%s\n' 3 7 y '' 12 | bash "$REPO/install_linux.sh" > "$T/k7.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k7 exit $rc"; }
check "K restore" 'Restore complete!' "$T/k7.log"
printf '%s\n' 3 8 '' 12 | bash "$REPO/install_linux.sh" > "$T/k8.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k8 exit $rc"; }
check "K export" 'Export Complete!' "$T/k8.log"
printf '%s\n' 3 9 'shared.tar.gz' 'myimp' 'y' '' '12' | bash "$REPO/install_linux.sh" > "$T/k9.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k9 exit $rc"; }
check "K import" 'Import complete!' "$T/k9.log"
printf '%s\n' 3 10 y '' 12 | bash "$REPO/install_linux.sh" > "$T/k10.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k10 exit $rc"; }
check "K uninstall" 'has been removed' "$T/k10.log"
printf '%s\n' 3 11 2 '' 12 | bash "$REPO/install_linux.sh" > "$T/k11.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k11 exit $rc"; }
check "K browser" 'Hardware Acceleration disabled' "$T/k11.log"
printf '%s\n' 3 3 '' 12 | bash "$REPO/install_linux.sh" > "$T/k3.log" 2>&1; rc=$?; [ "$rc" = "0" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: run k3 exit $rc"; }
check "K ssh" 'SSH Server is running!' "$T/k3.log"

echo "===== L: shim password ritual over pty ====="
fresh_env
printf '%s\n' 2 2 4 '' '' '' '' '' '' '' 1 'n' '' 'n' 'n' '' '' '12' \
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

echo ""
echo "PASS=$pass FAIL=$fail"
[ "$fail" = "0" ]
