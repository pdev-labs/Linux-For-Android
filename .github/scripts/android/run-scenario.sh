#!/bin/bash
# Drive one CI scenario inside a booted Android emulator.
#
# Environment (set by the workflow):
#   SCENARIO_API, SCENARIO_ARCH, SCENARIO_TARGET
#   SCENARIO_DISTRO, SCENARIO_DESKTOP, SCENARIO_BACKEND, SCENARIO_KIND
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
API="${SCENARIO_API:-33}"
ARCH="${SCENARIO_ARCH:-x86_64}"
DISTRO="${SCENARIO_DISTRO:-debian}"
DESKTOP="${SCENARIO_DESKTOP:-xfce4}"
BACKEND="${SCENARIO_BACKEND:-vnc}"
KIND="${SCENARIO_KIND:-install}"
INSTANCE="${SCENARIO_INSTANCE:-ci-$DISTRO}"
VNC_PASSWORD="${LFA_VNC_PASSWORD:-lfaci}"
KEY="${RUNNER_TEMP:-/tmp}/termux-ssh/id_ed25519"
SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=15 -o ServerAliveInterval=15 -i "$KEY" -p 8022 termux@127.0.0.1)

log() { printf '\n[scenario] %s\n' "$*"; }

export TERMUX_API_LEVEL="$API" TERMUX_ARCH="$ARCH"
log "Preparing emulator: API $API, $ARCH, $DISTRO/$DESKTOP/$BACKEND, kind=$KIND"
bash "$HERE/install-termux.sh" || { log "Termux install failed"; exit 1; }
bash "$HERE/install-termux-x11.sh" || { log "Termux:X11 install failed"; exit 1; }
bash "$HERE/start-termux-ssh.sh" || { log "Termux SSH setup failed"; exit 1; }

log "Pushing the repository"
tar --exclude=.git --exclude=.test-tmp --exclude='*.log' -czf "${RUNNER_TEMP:-/tmp}/lfa-repo.tar.gz" -C "$ROOT" .
scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY" -P 8022 \
    "${RUNNER_TEMP:-/tmp}/lfa-repo.tar.gz" termux@127.0.0.1:lfa-repo.tar.gz || {
    log "Could not copy the repository over SSH"; exit 1;
}
"${SSH[@]}" 'rm -rf ~/lfa && mkdir -p ~/lfa && tar -xzf ~/lfa-repo.tar.gz -C ~/lfa && rm -f ~/lfa-repo.tar.gz' || {
    log "Could not unpack the repository"; exit 1;
}

log "Running tests/termux-e2e.sh"
set +e
"${SSH[@]}" "cd ~/lfa && \
    LFA_E2E_DISTRO='$DISTRO' \
    LFA_E2E_DESKTOP='$DESKTOP' \
    LFA_E2E_BACKEND='$BACKEND' \
    LFA_E2E_SCENARIO='$KIND' \
    LFA_E2E_INSTANCE='$INSTANCE' \
    LFA_VNC_PASSWORD='$VNC_PASSWORD' \
    LFA_E2E_DIAGNOSTICS=1 \
    bash tests/termux-e2e.sh"
E2E_RC=$?
set -e

if [ "$BACKEND" = "vnc" ] || [ "$BACKEND" = "both" ]; then
    if [ "$E2E_RC" = "0" ] || [ "${LFA_CI_PROBE_ON_FAILURE:-0}" = "1" ]; then
        log "Starting VNC for the framebuffer probe"
        set +e
        "${SSH[@]}" "cd ~/lfa && LFA_VNC_PASSWORD='$VNC_PASSWORD' bash install_linux.sh --cli start -i '$INSTANCE' --vnc"
        adb forward --remove tcp:5901 >/dev/null 2>&1 || true
        adb forward tcp:5901 tcp:5901
        python3 "$HERE/vnc-probe.py" --password "$VNC_PASSWORD" --wait 90
        PROBE_RC=$?
        adb forward --remove tcp:5901 >/dev/null 2>&1 || true
        "${SSH[@]}" "cd ~/lfa && bash install_linux.sh --cli stop -i '$INSTANCE'" >/dev/null 2>&1 || true
        set -e
        if [ "$PROBE_RC" != "0" ]; then
            log "VNC framebuffer probe failed"
            E2E_RC=1
        fi
    fi
fi

log "Collecting artifacts"
bash "$HERE/collect-artifacts.sh" "${RUNNER_TEMP:-/tmp}/lfa-artifacts" || true

log "Scenario result: $E2E_RC"
exit "$E2E_RC"
