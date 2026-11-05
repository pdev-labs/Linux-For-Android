#!/bin/bash
# Collect logs from the emulator and from Termux. Never fails the job just
# because one optional file is missing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-${RUNNER_TEMP:-/tmp}/lfa-artifacts}"
mkdir -p "$OUT"

echo "Collecting emulator logs into $OUT"
{
    adb shell getprop 2>/dev/null || true
    echo ""
    adb shell dumpsys activity activities 2>/dev/null | head -n 200 || true
    echo ""
    adb shell ps -A 2>/dev/null | head -n 300 || true
} > "$OUT/android-device.txt" 2>&1 || true

adb logcat -d -v threadtime > "$OUT/logcat.txt" 2>/dev/null || true
adb exec-out screencap -p > "$OUT/screen.png" 2>/dev/null || rm -f "$OUT/screen.png"

# Pull the Termux diagnostics tarball and session logs over run-as, so this
# works even when SSH is the thing that broke.
cat > "$OUT/.collect-termux.sh" <<'EOF'
cd "$HOME" || exit 0
ls -t lfa-diagnostics-*.tar.gz 2>/dev/null | head -n1
EOF
DIAG_PATH="$(bash "$HERE/termux-exec.sh" "$OUT/.collect-termux.sh" 2>/dev/null | tr -d '\r' | head -n1 || true)"
if [ -n "$DIAG_PATH" ]; then
    adb exec-out run-as com.termux cat "$DIAG_PATH" > "$OUT/lfa-diagnostics.tar.gz" 2>/dev/null || true
fi
rm -f "$OUT/.collect-termux.sh"

cat > "$OUT/.collect-logs.sh" <<'EOF'
cd "$HOME" || exit 0
tar -czf "$HOME/lfa-ci-logs.tar.gz" \
    .config/linux-for-android \
    start-linux-session.log \
    .termux/boot \
    2>/dev/null || true
ls -1 "$HOME/lfa-ci-logs.tar.gz" 2>/dev/null
EOF
LOG_PATH="$(bash "$HERE/termux-exec.sh" "$OUT/.collect-logs.sh" 2>/dev/null | tr -d '\r' | head -n1 || true)"
if [ -n "$LOG_PATH" ]; then
    adb exec-out run-as com.termux cat "$LOG_PATH" > "$OUT/termux-logs.tar.gz" 2>/dev/null || true
fi
rm -f "$OUT/.collect-logs.sh"

# Termux-side display log can be large; keep a tail for quick reading.
cat > "$OUT/.tail-session.sh" <<'EOF'
tail -n 200 start-linux-session.log 2>/dev/null || true
EOF
bash "$HERE/termux-exec.sh" "$OUT/.tail-session.sh" > "$OUT/start-linux-session-tail.txt" 2>/dev/null || true
rm -f "$OUT/.tail-session.sh"

echo "Artifacts:"
find "$OUT" -maxdepth 1 -type f -printf '  %f (%s bytes)\n' 2>/dev/null || ls -l "$OUT"
exit 0
