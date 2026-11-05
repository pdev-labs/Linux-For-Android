#!/bin/bash
# Bootstrap Termux and make it reachable over SSH through adb forward.
#
# Sets up a throwaway key at $RUNNER_TEMP/termux_key and forwards local
# 8022 -> device 8022. The rest of the CI talks to Termux with ssh, which is
# far less fragile than typing into the emulator UI.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${RUNNER_TEMP:-/tmp}/termux-ssh"
KEY="$RUN_DIR/id_ed25519"
mkdir -p "$RUN_DIR"

if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -N '' -C 'lfa-ci' -f "$KEY" >/dev/null
fi
PUB="$(cat "$KEY.pub")"

echo "Bootstrapping Termux over run-as..."
"$HERE/termux-exec.sh" "$HERE/bootstrap-termux.sh" "$PUB"

adb forward --remove tcp:8022 >/dev/null 2>&1 || true
adb forward tcp:8022 tcp:8022

SSH_OPTS=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=4
    -i "$KEY"
    -p 8022
)

echo "Waiting for SSH..."
for _i in $(seq 1 30); do
    if ssh "${SSH_OPTS[@]}" termux@127.0.0.1 'true' >/dev/null 2>&1; then
        echo "SSH is ready."
        # Expose the path for later steps.
        if [ -n "${GITHUB_ENV:-}" ]; then
            {
                echo "TERMUX_SSH_KEY=$KEY"
                echo "TERMUX_SSH_PORT=8022"
                echo "TERMUX_SSH_USER=termux"
            } >> "$GITHUB_ENV"
        fi
        exit 0
    fi
    sleep 2
done

echo "SSH did not become ready." >&2
adb shell run-as com.termux pgrep -x sshd 2>&1 || true
adb shell run-as com.termux cat /data/data/com.termux/files/usr/var/log/sshd.log 2>&1 | tail -n 40 || true
exit 1
