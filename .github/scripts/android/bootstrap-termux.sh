#!/bin/bash
# Runs inside Termux through termux-exec.sh.
#
# $1 = SSH public key to authorize (optional)
set -uo pipefail
export PATH="$PREFIX/bin:$PATH"

AUTHORIZED_KEY="${1:-}"

# SSH must be able to start without a terminal. External app execution is
# also useful for debugging a failed run with `am broadcast`.
mkdir -p "$HOME/.termux"
cat > "$HOME/.termux/termux.properties" <<'EOF'
allow-external-apps=true
use-black-ui=true
EOF

echo "Updating Termux packages..."
for _i in 1 2 3; do
    if pkg update -y; then break; fi
    echo "pkg update failed (attempt $_i/3); retrying..." >&2
    sleep 5
done

# proot-distro may be missing on Android 5/6; LFA has a source fallback, so a
# failure here is not fatal.
pkg install -y proot wget curl tar openssh pulseaudio termux-api 2>/dev/null || true
pkg install -y proot-distro 2>/dev/null || echo "[i] proot-distro will be installed by LFA's fallback" >&2
pkg install -y x11-repo 2>/dev/null || true
pkg install -y termux-x11-nightly 2>/dev/null || echo "[i] termux-x11-nightly unavailable on this device" >&2

# Keep the emulator awake during long distro installs (-w would time out).
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

if [ -n "$AUTHORIZED_KEY" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    printf '%s\n' "$AUTHORIZED_KEY" > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
fi

# Make sure sshd is running on the standard Termux port. Generate host keys
# if the package did not ship them; sshd does not create them itself.
command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -A >/dev/null 2>&1 || true
if ! pgrep -x sshd >/dev/null 2>&1; then
    sshd 2>/dev/null || true
fi
if pgrep -x sshd >/dev/null 2>&1; then
    echo "sshd is running on port 8022."
else
    echo "sshd failed to start." >&2
    exit 1
fi

echo "Termux bootstrap complete: $(uname -m), Android SDK $(getprop ro.build.version.sdk 2>/dev/null)"
