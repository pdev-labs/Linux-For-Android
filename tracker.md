# Progress tracker

Working document for the audit in `issues.md` and the repository work in
`ghissue.md`.

Status values:

| Status | Meaning |
|---|---|
| `done` | code changed, suite green (`PASS=627 FAIL=0`), lint clean |
| `partial` | the main risk is addressed; a documented remainder is listed |
| `deferred` | deliberately not fixed in this pass, with the reason recorded |
| `device` | also exercised on the Vivo V2437 |

Verification environment: Vivo V2437, Android 16 (SDK 36), aarch64, Termux
`u0_a302` over SSH, and the host suite on Linux. The Oppo A37fw (SDK 22) was
off the network during the 2026-11-05 pass.

## Summary

| Group | Total | Done | Partial | Deferred |
|---|---|---|---|---|
| Security (1-7) | 7 | 6 | 1 | 0 |
| Correctness (8-23) | 16 | 11 | 3 | 2 |
| Architecture (24-35) | 12 | 7 | 3 | 2 |
| Testing and CI (36-44) | 9 | 5 | 3 | 1 |
| UX and docs (45-54) | 10 | 9 | 1 | 0 |
| Code total | 54 | 38 | 11 | 5 |

Lint: `shellcheck -S warning` clean, `bash -n` clean, CI workflow added.

## Repository work (`ghissue.md`)

| Group | Total | Done | Partial | Open | Notes |
|---|---|---|---|---|---|
| G1-G5 repo facts | 5 | 3 | 1 | 1 | description, topics, and homepage done; version reset documented; commit re-attribution open |
| G6-G12 proof | 7 | 4 | 0 | 3 | screenshots, numbers, matrix, and hard-problems done; GIF and photo open |
| G13-G20 health files | 8 | 7 | 1 | 0 | only funding and SUPPORT account bits left |
| G21-G28 automation | 8 | 3 | 2 | 3 | CI, assets, and discussions done; protection, milestones, and automation left |
| G29-G35 docs | 7 | 7 | 0 | 0 | architecture, decisions, index, issues link, badges, ToC |
| G36-G40 polish | 5 | 3 | 1 | 1 | logo, GIF, and troubleshooting screenshots open |
| Total | 40 | 27 | 5 | 8 | |

## CLI and backend switching (2026-11-04)

| Item | Status | Notes |
|---|---|---|
| Unified `lfa` command line | `done` | install/list/status/start/shell/stop/switch/autostart/update/doctor/backup/restore/remove/diagnostics/notice/version/help |
| `linux` desktop shortcut | `done` | script wrapper around `start-linux --desktop`; no menu, works from widgets/SSH/boot |
| `-i` shorthand | `done` | accepted by every command and launcher that accepts `--instance` |
| Backend switching | `done` | `lfa switch` and menu 14; install-before-remove order; remembered choice cleared |
| Clean package removal | `done` | VNC guest packages + config, host Termux:X11; shared-X11 guard and `--force` |
| Android 5/6 refusal | `done` | explicit explanation, `--remove-old` warning, VNC restore command |
| `start-linux` notice | `done` | stderr, interactive classic runs only; `lfa notice`, `--no-notice`, `LFA_NO_NOTICE` |
| Boot script ownership | `done` | switching a non-autostart instance no longer hijacks another instance's boot script |
| Host suite | `done` | `PASS=627 FAIL=0`; Y1-Y10 cover CLI, switch, removal, guard, `-i`, legacy, SDK 24/25, compat/android, matrix, AppImage |
| Device verification | `done` | Vivo V2437 (SDK 36): VNC `PASS=14`, Both switch `PASS=22`, X11 `PASS=14`, VirGL fallback, shims, bridge, `--software`; Oppo SDK 22 pending (off network) |

## Android CI and compatibility layers (2026-11-05)

| Item | Status | Notes |
|---|---|---|
| SDK 24/25 cutoff | `done` | `IS_LEGACY` (SDK < 24) separated from `X11_SUPPORTED` (SDK >= 26); install, switch, autostart, menu 14, quick setup, and `start-linux` agree |
| `lfa compat` | `done` | list/status/explain/enable/disable; systemctl, loginctl, upower, snap, bwrap, CPU Vulkan/OpenCL; kernel features reported unsupported |
| `lfa android` | `done` | status/install/permissions/test/refresh/enable/disable/pump; battery/location/clipboard/notification bridge |
| `lfa install --software` | `done` | comma-separated app list mapped to the existing selector |
| Matrix generator | `done` | smoke 6, reduced 23, full 674; sharding and best-effort API 21/22 |
| CI workflows | `done` | reusable scenario, PR smoke, weekly reduced, manual sharded full |
| On-device harness | `done` | `tests/termux-e2e.sh`, `tests/software-probe.sh`, `vnc-probe.py` |
| CI docs | `done` | `docs/CI-ANDROID.md`, `docs/INCOMPATIBLE.md` |
| Host suite | `done` | new Y7-Y9 cases for SDK 24/25, compat/android, matrix generator |
| Emulator run | `pending` | workflow has not run on GitHub Actions yet |
| Device run | `done` | Vivo V2437 (SDK 36): VNC, Both switch, X11, VirGL→llvmpipe fallback, shims, Android bridge, software install/probe |
| Legacy device run | `pending` | Oppo A37fw (SDK 22) was off the network; repeat refusal/VNC checks when reachable |

## Security

| # | Item | Status | What changed |
|---|---|---|---|
| 1 | Secrets in world-readable temp file | `done` | Created with `umask 077` (mode 0600), tracked, and deleted after use and by the `trap` on EXIT, INT, and TERM |
| 2 | "base64 = not plaintext" wording | `done` | Comments and the `setup.conf` header now say obfuscation; file mode is the protection |
| 3 | sudo password in a 0755 guest binary | `done` | Salted SHA-256 hash (`SUDO_SALT` and `SUDO_HASH`); shim is `0700` |
| 4 | No checksum or signature on downloads | `partial` | Microsoft key fingerprint verified, proot-distro tree validated, Firefox archive tested. Upstream publishes no checksums for the other two, documented in `SECURITY.md` |
| 5 | HTML scraping for Antigravity URL | `done` | Scraped URL must match a vendor host; otherwise the pinned release is used |
| 6 | Silent `pkg install` in the launcher | `done` | Logs to `$PREFIX/tmp/lfa-x11-install.log`, prints progress, and gives a precise failure hint |
| 7 | `set -e` without `pipefail` | `done` | `set -o pipefail`; two latent dashboard bugs surfaced and were fixed |

## Correctness and data loss

| # | Item | Status | What changed |
|---|---|---|---|
| 8 | No `trap` cleanup | `done` | Global `lfa_cleanup` on EXIT, INT, and TERM removes tracked temp artifacts |
| 9 | PID-reuse unsafe pidfile checks | `done` | New `lfa_pid_matches` verifies the command line before signalling; stale pidfiles are reported, not obeyed. Fixed on device because Termux coreutils breaks `exec -a sleep` |
| 10 | `pkill -f "^termux-x11"` too broad | `done` | Only a real X server whose argv[0] basename is `Xvnc`, `termux-x11`, or similar and whose args contain `:1` is stopped. `/proc` is scanned instead of trusting `pgrep -f` |
| 11 | `:latest` image tags | `partial` | `LFA_IMAGE_<DISTRO>` overrides, and the resolved image is recorded in the manager conf. Rolling distros still publish only a moving tag |
| 12 | Fixed display `:1` and port 5901 | `deferred` | Documented in `docs/DECISIONS.md` D5. Changing it is a redesign, not a fix |
| 13 | Fixed sleeps instead of readiness polling | `done` | X11 waits for the socket; VNC polls port 5901 for up to 20 seconds |
| 14 | No disk-space preflight | `done` | 900 MB, 2.5 GB, and 3.5 GB thresholds, with refusal that names the exact numbers |
| 15 | Menu 12 misses new required packages | `partial` | It detects missing session and VNC components and prints the exact install command. It does not install them automatically |
| 16 | UTF-8 locale only for GNOME | `done` | `LANG=C.UTF-8` for XFCE, LXDE, and MATE launch paths too |
| 17 | Shared `XDG_RUNTIME_DIR` | `done` | `/tmp/xdg-$USER-$DISTRO` |
| 18 | `\|\| true` hides failures | `partial` | The polish step now warns loudly; wallpaper and uid0 remain best-effort by design |
| 19 | Unquoted `$PREFIX` in `sed -i` | `done` | All three launcher rewrites are quoted |
| 20 | GNOME beta session model | `deferred` | Documented and gated. It is a support decision, not a bug |
| 21 | VNC password truncated to 8 characters | `done` | Warned at the password prompt with the exact 8 characters VNC will use; the README states it |
| 22 | SDK 0 treated as modern | `done` | One explicit warning per run |
| 23 | No password confirmation | `done` | `setup_confirm_secret` asks twice on a terminal |

## Architecture and maintainability

| # | Item | Status | What changed |
|---|---|---|---|
| 24 | 3,311-line single file | `partial` | `docs/ARCHITECTURE.md` documents the shape and the cost; splitting it is a larger refactor |
| 25 | Questionnaire duplicated | `done` | `ask_desktop_environment` and `ask_display_server` are the single source for both paths |
| 26 | 34 nested heredocs | `deferred` | Documented as the main debt (D4); the uid0 snippet was extracted as the first step |
| 27 | Repeated `ui_select` guard blocks | `partial` | The two duplicated menus are gone; the remaining guards stay explicit |
| 28 | `show_menu` recursion | `deferred` | Works and is test-covered; converting to a dispatch loop touches every action |
| 29 | Version and count drift in docs | `done` | The suite fails when `README.md` does not state the real `PASS=` count |
| 30 | No CLI flags | `done` | `--help --version --list --doctor --yes --debug`; help and version work outside Termux |
| 31 | No update check | `done` | Cached 24 h, 3 s timeout, TTY-only, `LFA_NO_UPDATE_CHECK=1` to disable |
| 32 | Duplicated uid0 build | `done` | One guest-side `lib/uid0-build.sh` used by install and menu 12 |
| 33 | No CHANGELOG | `done` | `CHANGELOG.md` with the version-order note |
| 34 | Deep distro branching | `partial` | Image selection is overridable and recorded; package-name branching remains |
| 35 | Version markers in source | `done` | No stale `v1.5.x` markers; history lives in git and `CHANGELOG.md` |

## Testing and CI

| # | Item | Status | What changed |
|---|---|---|---|
| 36 | No CI | `done` | `.github/workflows/ci.yml`: shellcheck, `bash -n`, suite, CLI surface |
| 37 | No lint gate | `done` | `shellcheck -S warning` is clean and blocking |
| 38 | Tests assert text, not behaviour | `partial` | Added behavioural tests for pid matching, disk refusal, trap cleanup, and CLI exit codes; older assertions are still text-based |
| 39 | Whole suite stubbed | `deferred` | By design (D8); real behaviour is covered by `tests/device-matrix.sh` on hardware |
| 40 | Suite writes into the repo | `done` | `mktemp -d` and `trap` cleanup |
| 41 | Hand-rolled assertion bookkeeping | `partial` | Kept the API for stability; sectioned output and exit codes are honest, but there is no filter or timing yet |
| 42 | Major paths untested | `partial` | Added M5 to M8 (CLI, pid, disk, interrupt); backup and restore round-trip is still manual |
| 43 | Hardware matrix not automated | `done` | `tests/device-matrix.sh` collects the device profile and runs the suite on the phone |
| 44 | No regression corpus | `done` | M4 (stale `:1`), M6 (pid), M7 (disk), M8 (trap), plus the v1.6.1 bus and locale checks |

## UX, docs, and features

| # | Item | Status | What changed |
|---|---|---|---|
| 45 | Misleading error messages | `done` | X11 and SSH messages now name the actual cause and the exact command |
| 46 | Default root/root with no warning | `done` | Printed at the prompt when the default is accepted |
| 47 | Docs overstate validation | `done` | Matrix has an "as of v1.7.0" column; Alpine and Void caveats are in the row, not a footnote |
| 48 | "Experimental" only after selecting GNOME | `done` | The menu entry reads `GNOME (experimental)` with `BETA - may crash` in the description, before selection |
| 49 | Uninstall leaves Termux artifacts | `done` | Removes pidfile, log, per-distro runtime dirs, and for the last distro the shortcut and boot script |
| 50 | No log capture or `--debug` | `done` | `--diagnostics` writes a redacted support bundle; `--debug` keeps the script and records an execution trace |
| 51 | README ToC and troubleshooting index | `done` | Symptom index table, stable anchors, links to issues, changelog, and architecture |
| 52 | No accessibility audit | `partial` | Plain mode (piped stdin) and `NO_COLOR` documented; no formal audit |
| 53 | Known-broken rows shipped as "verified" | `done` | Alpine panel and Void/VNC panel are marked with a warning inside the row and the reason |
| 54 | Full-resolution wallpapers in git | `done` | Checked: assets are already 1920x1080, 2.1 MB total. The original concern about 4K did not apply; `issues.md` corrected |

## Verification log

| When | What | Result |
|---|---|---|
| 2026-10-31 | Host suite, every change | `PASS=356 FAIL=0` |
| 2026-10-31 | `shellcheck -S warning` on install, lib, and tests | clean |
| 2026-10-31 | `bash -n` and `sh -n` on every script | clean |
| 2026-10-31 | CLI surface on host | `--version`, `--help`, `--bogus`, exit 2 for the last one |
| 2026-10-31 | Device suite, Vivo V2437, Android 16 | `PASS=356 FAIL=0` |
| 2026-10-31 | Device CLI | `--version`, `--help`, `--list`, `--diagnostics` OK |
| 2026-10-31 | Device diagnostics bundle | `report.txt`, launchers, redacted conf, mode 0600 |
| 2026-10-31 | Menu 12 on the existing Ubuntu install | statoverride sanitised, snapd pinned, launchers regenerated |
| 2026-10-31 | Ubuntu 24.04, XFCE4, Termux:X11 on device | desktop live; screenshot in `docs/screenshots/vivo-ubuntu-xfce-x11-v170.png` |
| 2026-10-31 | `stop-linux` on device | `termux-x11` gone, `.X11-unix` empty, `.X1-lock` removed |
| 2026-10-31 | Alpine CLI install on device | `Installation complete! (5m 11s)`, user and sudo ritual work |
| 2026-10-31 | Alpine uninstall on device | rootfs, pidfile, log, and `xdg-*` runtime dir removed (#49) |
| 2026-10-31 | GitHub repo metadata | description, homepage, 20 topics, Discussions enabled |
| 2026-11-01 | All install-menu software on the Vivo | Python 3.12.3, Git 2.43.0, Node 26.13.0/npm 11.20.0, curl 8.5.0, wget 1.21.4, neofetch 7.1.0, htop 3.3.0, VS Code 1.144.0, Firefox, Chromium, LibreOffice 24.2, VLC, GIMP, and Antigravity all launch |
| 2026-11-01 | VS Code via the desktop entry | window opens after the `--no-sandbox` wrapper (#55) |
| 2026-11-01 | Detailed troubleshooting guide | `docs/TROUBLESHOOTING.md`: 13 areas, 47 internal links, error-string index, recovery ladder |
| 2026-11-01 | Documentation link gate | suite checks the guide, both index links, and every relative doc link (`PASS=356 FAIL=0`) |
| 2026-11-01 | Screenshot privacy pass | notification-bar app icons and the "3 devices" chip removed from all nine phone screenshots |
| 2026-11-04 | Device suite, Vivo V2437, Android 16 | `PASS=404 FAIL=0` |
| 2026-11-04 | Both install on device | Ubuntu 24.04 + XFCE4, `bothdev`, 40m27s; host and guest packages present |
| 2026-11-04 | X11 and VNC on device | each desktop reached display `:1`; VNC RFB banner on `127.0.0.1:5901` |
| 2026-11-04 | Remembered backend on device | blank first start refused; later starts reused the stored X11/VNC choice |
| 2026-11-04 | `stop-linux` on device | X11 and VNC both fully stopped; no proot wrapper or keepalive left |
| 2026-11-04 | Menu 12 backend migration on device | X11-only gained VNC; VNC-only gained X11; stale remembered choice cleared |
| 2026-11-04 | Both autostart menu on device | VNC, Termux:X11, and None offered; summary cancel left setup.conf unchanged |
| 2026-11-04 | Device suite, Oppo A37fw, Android 5.1.1 | `PASS=404 FAIL=0` (python3 installed for test shims) |
| 2026-11-04 | Legacy guided setup | X11 and Both hidden, VNC selected automatically |
| 2026-11-04 | Legacy Alpine 3.18 + XFCE4 + VNC | installed in 9m38s; RFB banner and XFCE session on display `:1` |
| 2026-11-04 | Legacy `stop-linux` | Xvnc, vncserver, xinit, xfce4-session, and proot wrapper all stopped |
| 2026-11-04 | Legacy both config through Menu 12 | persisted `SERVER="vnc"`, `AUTOSTART_SERVER="vnc"`, cleared remembered choice |
| 2026-11-04 | Android 5 bugs fixed | toybox df free space, legacy VNC stop, persisted clamp, anchored kill patterns |
| 2026-11-04 | `bash -n` after the backend change | install script and test suite clean |
| 2026-11-05 | AppImage support | `APPIMAGE_EXTRACT_AND_RUN=1` in every guest session; `lfa appimage add/list/run/remove` and `lfa run`; official Prism Launcher 11.1.1 AppImage extracted and launched under XFCE on the Vivo |
| 2026-11-05 | Duplicate-session fix | `start-linux` refuses a second session, `--restart` replaces one, and `stop-linux` now stops the guest session wrapper |
| 2026-11-05 | Cursor theme fix | `XCURSOR_THEME=Adwaita` in X11/VNC launches plus `lfa-set-cursor` autostart |
| 2026-11-05 | Cross cursor root cause | `xfce4-session` blocks on `gpgconf --kill`/`--launch gpg-agent` under proot before starting `xfwm4`; a scoped, versioned `gpgconf` guard removes the hang |
| 2026-11-05 | Non-interactive fixes | Added `lfa fix -i NAME` (runs the menu 12 upgrade path headless); `lfa start --restart` now forwards the flag |
| 2026-11-06 | Android storage | `lfa storage` with status, fix, exec, and open; gid 1023 as the desktop user's primary group removes Thunar's false unreadable X; exec works around the impossible chmod on `/storage/emulated/0` |
| 2026-11-06 | Android data and obb | `lfa storage data status|list|pull` uses adb (shell user) to copy the protected Android/data and Android/obb folders into shared storage |

### Findings that only appeared on hardware

1. `pipefail` with `grep -q` broke every fresh install on proot-distro v5.
   `proot-distro install --help | grep -q IMAGE:TAG` returns 141 because grep
   exits early and the producer gets SIGPIPE. The v5 branch was skipped and
   the installer rejected `alpine` with "knows no 'alpine' distribution".
   Fixed with a pipeline-free `lfa_match` helper and an M10 regression test
   that feeds 64 KiB or more of help text. The host suite could not see it
   because its stub help is one line.
2. `exec -a` cannot spawn a multicall binary on Termux. `sleep` is coreutils
   and rejects the invented argv[0]. The M4 and M6 fixtures now exec bash,
   which is a real ELF.
3. Anchored `pgrep -f '^Xvnc '` misses a guest X server. Under proot the
   binary is exec'd with an absolute path, so `lfa_x1_server_pid` now compares
   the basename of argv[0] and scans `/proc` instead of trusting `pgrep`.
4. The "sshd hangs" symptom came from Android's phantom-process killer. An
   XFCE session plus the stub suite exceeds the default child limit, and
   Android kills the surplus, including `sshd`. Documented in
   `docs/TEST-REPORT.md`; the README tells users to disable it.
5. VS Code, Chromium, and Antigravity cannot use their setuid sandbox under
   proot. VS Code is the dangerous case: the CLI returns 0 and prints nothing,
   so it looks like a missing app. v1.7.1 writes `/usr/local/bin` wrappers with
   `--no-sandbox` and repoints the desktop entries (#55, #56).

## Next actions

Done in this pass: tag `v1.7.0` with `install_linux.sh` and `SHA256SUMS`, green
CI, description, topics, homepage, Discussions on, Wiki off, and
delete-branch-on-merge.

Remaining, all of which need an upload or a maintainer decision:

1. Protect `main` (require the CI check, block force-push). This changes how
   pdev-labs pushes, so it remains a maintainer decision.
2. Social preview image, demo GIF, and a real-hardware photo.
3. Re-attribute the `pdev@local` commits. This needs a history rewrite.
