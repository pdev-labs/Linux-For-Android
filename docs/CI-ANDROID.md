# Android CI

LFA's host suite (`tests/test-all.sh`) proves the shell logic with stubs. This
page describes the other half: running LFA on **real Android emulators** so a
release does not depend on manual phone testing.

## What runs, and when

| Tier | Workflow | Trigger | Scope | Approx. jobs |
|---|---|---|---|---|
| PR smoke | `android-e2e.yml` | PR touching the installer, launchers, tests or CI | CLI, VNC, X11, Both/switch, legacy refusal, software probe | 6 |
| Weekly reduced | `android-matrix.yml` | Sunday 02:00 UTC | every distro, every desktop, Android version sweep, switch, software | ~23 |
| Full matrix | `android-full.yml` | manual, sharded | every valid distro × desktop × backend × API level | ~674 |

The full matrix is deliberately **not** nightly. It is large, slow and
flaky by nature; shard it and run it before a release.

Generate any matrix locally:

```bash
python3 tests/generate-android-matrix.py --mode smoke --format list
python3 tests/generate-android-matrix.py --mode reduced --format json
python3 tests/generate-android-matrix.py --mode full --shard 0 --total-shards 8 --format json
```

Only combinations LFA claims to support are generated. Unsupported ones are
covered by the `legacy` scenario, which verifies the refusal message instead
of running a broken desktop.

## How a scenario works

```text
GitHub runner
  └─ Android emulator (KVM, x86/x86_64)
      ├─ install pinned Termux debug APK
      ├─ launch Termux once so it extracts its bootstrap
      ├─ run bootstrap over `adb shell run-as com.termux`
      ├─ install openssh and start sshd
      ├─ adb forward tcp:8022 -> device 8022
      ├─ copy the repository over scp
      ├─ run tests/termux-e2e.sh over ssh
      ├─ adb forward tcp:5901 -> device 5901
      ├─ run a real RFB handshake + framebuffer probe
      └─ collect logs, diagnostics and a screenshot
```

Why SSH and not `adb shell input text`: typing into the Termux UI is slow and
race-prone. `run-as` is used only for the bootstrap, then SSH carries the
long-running installs. The Termux **debug** APK is required because `run-as`
only works for a debuggable package.

### What `tests/termux-e2e.sh` checks

- `lfa install`, `list`, `status`, `version`, `notice`, `compat`, `android`
- the manager config values, not just exit codes
- real VNC server on `5901`, `Xvnc` process, desktop session process, and a
  session log without fatal errors
- real Termux:X11 `:1` socket, `termux-x11` process, desktop process, and
  `xdpyinfo` inside the guest
- Both install → start VNC → stop → start X11 → stop → switch to VNC with
  `--remove-old`
- on SDK < 26: X11/Both refusal, unchanged config, and the VNC restore hint
- compatibility shims: enable `systemctl`, verify the guest file, disable it
- diagnostics bundle creation (when enabled)
- optional software install and launch probes (`tests/software-probe.sh`)

### Real framebuffer check

A listening port is not proof that a desktop drew anything. The host-side
`vnc-probe.py` performs the RFB handshake, authenticates with VNC auth,
requests a raw framebuffer update, and fails if the frame is black or has
fewer than four colours. It uses `pycryptodome` if available and otherwise
falls back to `openssl`'s DES implementation.

## Android versions

| API | Android | Role |
|---|---|---|
| 21/22 | 5.0/5.1 | best effort, off by default; current Termux may refuse to install |
| 23 | 6.0 | canonical legacy target |
| 24/25 | 7.0/7.1 | boundary: modern Termux, **no** Termux:X11 or GNOME |
| 26 | 8.0 | minimum for X11 and GNOME |
| 29 | 10 | older modern |
| 31 | 12 | phantom-process changes |
| 33 | 13 | stable default |
| 34 | 14 | current restrictions |
| 35 | 15 | new |
| 36 | 16 | newest |

API 24/25 used to be treated as "modern" and were offered X11. LFA now keeps
`IS_LEGACY` (Termux package cutoff, SDK < 24) separate from
`X11_SUPPORTED` (SDK >= 26). The CI includes boundary scenarios so this
cannot regress silently.

## Pinned downloads

The workflow never downloads `latest` at runtime.

| Artifact | Version | Where |
|---|---|---|
| Termux debug APK, API >= 24 | `0.118.3` | `.github/scripts/android/install-termux.sh` |
| Termux debug APK, API < 24 | `0.118.0` (last Android 5 build) | `.github/scripts/android/install-termux.sh` |
| Termux:X11 debug APK | nightly `1.03.01` with a pinned SHA-256 | `.github/scripts/android/install-termux-x11.sh` |

The Termux releases publish a `sha256sums` asset; the digests are copied into
the script. The Termux:X11 release uses the moving `nightly` tag, so the
script verifies the digest and fails loudly when upstream moves. That failure
is the signal to review and bump the pin in one PR.

API 21/22/23 use Termux 0.118.0; API 24+ uses 0.118.3. A single "latest"
APK would make the legacy jobs fail before the installer even runs. Legacy
jobs are also the most fragile: their Termux repositories are archived, and a
dead mirror fails `pkg update` before LFA starts. The logs and
`lfa-diagnostics.tar.gz` artifact are there to tell those failures apart from
installer bugs.

APKs are cached with `actions/cache`; the cache key includes the pinned
versions.

## Reproducing a scenario locally

Prerequisites: Linux with `/dev/kvm`, Android SDK platform tools, an emulator
system image and Python 3.

```bash
# Boot the emulator yourself, then:
export ANDROID_SERIAL=emulator-5554
export TERMUX_API_LEVEL=33 TERMUX_ARCH=x86_64
bash .github/scripts/android/install-termux.sh
bash .github/scripts/android/install-termux-x11.sh
bash .github/scripts/android/start-termux-ssh.sh

tar -czf /tmp/lfa-repo.tar.gz --exclude=.git .
scp -i "$RUNNER_TEMP/termux-ssh/id_ed25519" -P 8022 /tmp/lfa-repo.tar.gz termux@127.0.0.1:
ssh -i "$RUNNER_TEMP/termux-ssh/id_ed25519" -p 8022 termux@127.0.0.1 \
  'rm -rf ~/lfa && mkdir ~/lfa && tar -xzf ~/lfa-repo.tar.gz -C ~/lfa'

ssh -i "$RUNNER_TEMP/termux-ssh/id_ed25519" -p 8022 termux@127.0.0.1 \
  'cd ~/lfa && LFA_E2E_DISTRO=debian LFA_E2E_BACKEND=vnc bash tests/termux-e2e.sh'
```

On a real phone with Termux and SSH already running, only the last command is
needed:

```bash
cd ~/lfa
LFA_E2E_DISTRO=debian LFA_E2E_DESKTOP=xfce4 LFA_E2E_BACKEND=vnc \
  bash tests/termux-e2e.sh
```

## Known gaps

GitHub-hosted emulators are x86/x86_64 and use software GPU rendering. They
do not cover:

- ARM64-only vendor builds (VS Code ARM64, Firefox ARM64 tarball, Antigravity)
- real ARM64 package availability
- Android 5/6 frozen Termux repositories in full (API 23 is the reliable
  target; API 21/22 are best effort)
- OEM phantom-process killers and battery policies
- real GPU, audio, thermal and performance behaviour
- real camera, Bluetooth, USB and sensor hardware

Those remain device checks. A self-hosted runner with a phone attached would
close most of the gap, but it is not required for the emulator matrix.

The workflow also does not claim that the **phone GPU** is used. VirGL
accelerates rendering in the emulator only when the emulator image and host
support it; the compatibility page documents GPU compute as unavailable.
