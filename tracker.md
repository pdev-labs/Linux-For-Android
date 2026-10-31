# Progress Tracker

Working document for the audit in `issues.md` and the repo work in `ghissue.md`.

Status values:

| Status | Meaning |
|---|---|
| `done` | code changed, suite green (`PASS=344 FAIL=0`), lint clean |
| `partial` | the main risk is addressed; a documented remainder is listed |
| `deferred` | deliberately not fixed in this pass, reason recorded |
| `device` | additionally exercised on the Vivo V2437 |

Verification environment: **Vivo V2437 · Android 16 (SDK 36) · aarch64**,
Termux `u0_a302` @ `10.26.39.163:8022`, and the host suite on Linux.

## Summary

| Group | Total | Done | Partial | Deferred |
|---|---|---|---|---|
| 🔴 Security (1–7) | 7 | 6 | 1 | 0 |
| 🟠 Correctness (8–23) | 16 | 11 | 3 | 2 |
| 🟡 Architecture (24–35) | 12 | 7 | 3 | 2 |
| 🔵 Testing/CI (36–44) | 9 | 5 | 3 | 1 |
| 🟣 UX/docs (45–54) | 10 | 9 | 1 | 0 |
| **Code total** | **54** | **38** | **11** | **5** |

Lint: `shellcheck -S warning` clean · `bash -n` clean · CI workflow added.

## Repository work (`ghissue.md`)

| Group | Total | Done | Partial | Open | Notes |
|---|---|---|---|---|---|
| G1–G5 repo facts | 5 | 3 | 1 | 1 | description/topics/homepage done; version reset documented; commit re-attribution open |
| G6–G12 proof | 7 | 4 | 0 | 3 | screenshots, numbers, matrix, hard-problems done; GIF/photo open |
| G13–G20 health files | 8 | 7 | 1 | 0 | only funding/SUPPORT account bits left |
| G21–G28 automation | 8 | 3 | 2 | 3 | CI + assets + discussions done; protection/milestones/automation left |
| G29–G35 docs | 7 | 7 | 0 | 0 | architecture, decisions, index, issues link, badges, ToC |
| G36–G40 polish | 5 | 3 | 1 | 1 | logo/GIF and troubleshooting screenshots open |
| **Total** | **40** | **27** | **5** | **8** | |

---

## 🔴 Security

| # | Item | Status | What changed |
|---|---|---|---|
| 1 | Secrets in world-readable temp file | `done` | Created with `umask 077` → mode 0600, tracked, deleted after use and by the `trap` on EXIT/INT/TERM |
| 2 | "base64 = not plaintext" wording | `done` | Comments and `setup.conf` header now say obfuscation, file mode is the protection |
| 3 | sudo password in a 0755 guest binary | `done` | Salted SHA-256 hash (`SUDO_SALT`/`SUDO_HASH`), shim is `0700` |
| 4 | No checksum/signature on downloads | `partial` | Microsoft key fingerprint verified; proot-distro tree validated; Firefox archive tested. Upstream publishes no checksums for the other two — documented in `SECURITY.md` |
| 5 | HTML scraping for Antigravity URL | `done` | Scraped URL must match a vendor host, otherwise the pinned release is used |
| 6 | Silent `pkg install` in the launcher | `done` | Logs to `$PREFIX/tmp/lfa-x11-install.log`, prints progress and a precise failure hint |
| 7 | `set -e` without `pipefail` | `done` | `set -o pipefail`; two latent dashboard bugs surfaced and were fixed |

## 🟠 Correctness / data loss

| # | Item | Status | What changed |
|---|---|---|---|
| 8 | No `trap` cleanup | `done` | Global `lfa_cleanup` on EXIT/INT/TERM removes tracked temp artifacts |
| 9 | PID-reuse unsafe pidfile checks | `done` | New `lfa_pid_matches` verifies the command line before signalling; stale pidfiles are reported, not obeyed. Fixed on device (Termux coreutils breaks `exec -a sleep`) |
| 10 | `pkill -f "^termux-x11"` too broad | `done` | Only a real X server whose argv[0] basename is `Xvnc`/`termux-x11`/... and whose args contain `:1` is stopped; `/proc` is scanned instead of trusting `pgrep -f` |
| 11 | `:latest` image tags | `partial` | `LFA_IMAGE_<DISTRO>` overrides, and the resolved image is recorded in the manager conf. Rolling distros still publish only a moving tag |
| 12 | Fixed display `:1` / port 5901 | `deferred` | Documented in `docs/DECISIONS.md` D5; changing it is a redesign, not a fix |
| 13 | Fixed sleeps instead of readiness polling | `done` | X11 waits for the socket, VNC polls port 5901 (max 20 s) |
| 14 | No disk-space preflight | `done` | 900 MB / 2.5 GB / 3.5 GB thresholds, refusal with the exact numbers |
| 15 | Menu 12 misses new required packages | `partial` | It now detects missing session/VNC components and prints the exact install command; it does not install them automatically |
| 16 | UTF-8 locale only for GNOME | `done` | `LANG=C.UTF-8` for XFCE/LXDE/MATE launch paths too |
| 17 | Shared `XDG_RUNTIME_DIR` | `done` | `/tmp/xdg-$USER-$DISTRO` |
| 18 | `\|\| true` hides failures | `partial` | The polish step now warns loudly; wallpaper/uid0 remain best-effort by design |
| 19 | Unquoted `$PREFIX` in `sed -i` | `done` | All three launcher rewrites quoted |
| 20 | GNOME beta session model | `deferred` | Documented and gated; it is a support decision, not a bug |
| 21 | VNC password truncated to 8 chars | `done` | Warned at the password prompt with the exact 8 characters that VNC will use; README states it |
| 22 | SDK 0 treated as modern | `done` | One explicit warning per run |
| 23 | No password confirmation | `done` | `setup_confirm_secret` asks twice on a terminal |

## 🟡 Architecture / maintainability

| # | Item | Status | What changed |
|---|---|---|---|
| 24 | 3,311-line single file | `partial` | `docs/ARCHITECTURE.md` documents the shape and the cost; splitting it is a larger refactor |
| 25 | Questionnaire duplicated | `done` | `ask_desktop_environment` / `ask_display_server` are the single source for both paths |
| 26 | 34 nested heredocs | `deferred` | Documented as the main debt (D4); the uid0 snippet was extracted as the first step |
| 27 | Repeated `ui_select` guard blocks | `partial` | The two duplicated menus are gone; the remaining guards stay explicit |
| 28 | `show_menu` recursion | `deferred` | Works and is test-covered; converting to a dispatch loop touches every action |
| 29 | Version/count drift in docs | `done` | The suite fails when `README.md` does not state the real `PASS=` count |
| 30 | No CLI flags | `done` | `--help --version --list --doctor --yes --debug`; help/version work outside Termux |
| 31 | No update check | `done` | Cached 24 h, 3 s timeout, TTY-only, `LFA_NO_UPDATE_CHECK=1` to disable |
| 32 | Duplicated uid0 build | `done` | One guest-side `lib/uid0-build.sh` used by install and menu 12 |
| 33 | No CHANGELOG | `done` | `CHANGELOG.md` with the version-order note |
| 34 | Deep distro branching | `partial` | Image selection is now overridable/recorded; package-name branching remains |
| 35 | Version markers in source | `done` | No stale `v1.5.x` markers; history lives in git and `CHANGELOG.md` |

## 🔵 Testing / CI

| # | Item | Status | What changed |
|---|---|---|---|
| 36 | No CI | `done` | `.github/workflows/ci.yml`: shellcheck, `bash -n`, suite, CLI surface |
| 37 | No lint gate | `done` | `shellcheck -S warning` is clean and blocking |
| 38 | Tests assert text, not behaviour | `partial` | Added behavioural tests for pid matching, disk refusal, trap cleanup, CLI exit codes; older assertions are still text-based |
| 39 | Whole suite stubbed | `deferred` | By design (D8); real behaviour is covered by `tests/device-matrix.sh` on hardware |
| 40 | Suite writes into the repo | `done` | `mktemp -d` + `trap` cleanup |
| 41 | Hand-rolled assertion bookkeeping | `partial` | Kept the API for stability; sectioned output and exit codes are honest, no filter/timing yet |
| 42 | Major paths untested | `partial` | Added M5–M8 (CLI, pid, disk, interrupt); backup/restore round-trip still manual |
| 43 | Hardware matrix not automated | `done` | `tests/device-matrix.sh` collects the device profile and runs the suite on the phone |
| 44 | No regression corpus | `done` | M4 (stale `:1`), M6 (pid), M7 (disk), M8 (trap) plus the v1.6.1 bus/locale checks |

## 🟣 UX / docs / features

| # | Item | Status | What changed |
|---|---|---|---|
| 45 | Misleading error messages | `done` | X11 and SSH messages now name the actual cause and the exact command |
| 46 | Default root/root with no warning | `done` | Printed at the prompt when the default is accepted |
| 47 | Docs overstate validation | `done` | Matrix has an "as of v1.7.0" column; Alpine/Void caveats are in the row, not a footnote |
| 48 | "Experimental" only after selecting GNOME | `done` | The menu entry reads `GNOME (experimental)` with `BETA - may crash` in the description, before selection |
| 49 | Uninstall leaves Termux artifacts | `done` | Removes pidfile, log, per-distro runtime dirs, and (last distro) shortcut + boot script |
| 50 | No log capture / `--debug` | `done` | `--diagnostics` writes a redacted support bundle; `--debug` keeps the script and records an execution trace |
| 51 | README ToC / troubleshooting index | `done` | Symptom index table, stable anchors, links to issues/changelog/architecture |
| 52 | No accessibility audit | `partial` | Plain mode (piped stdin) and `NO_COLOR` documented; no formal audit |
| 53 | Known-broken rows shipped as "verified" | `done` | Alpine panel and Void/VNC panel are marked ⚠️ inside the row with the reason |
| 54 | Full-resolution wallpapers in git | `done` | Checked: assets are already 1920×1080, 2.1 MB total. The original concern (4K) did not apply; `issues.md` corrected |

---

## Verification log

| When | What | Result |
|---|---|---|
| 2026-10-31 | Host suite, every change | `PASS=344 FAIL=0` |
| 2026-10-31 | `shellcheck -S warning` (install + lib + tests) | clean |
| 2026-10-31 | `bash -n` / `sh -n` on every script | clean |
| 2026-10-31 | CLI surface on host | `--version`, `--help`, `--bogus` → exit 2 |
| 2026-10-31 | **Device suite** (Vivo V2437, Android 16) | `PASS=344 FAIL=0` |
| 2026-10-31 | Device CLI | `--version`, `--help`, `--list`, `--diagnostics` OK |
| 2026-10-31 | Device diagnostics bundle | `report.txt`, launchers, redacted conf; mode 0600 |
| 2026-10-31 | Menu 12 on the existing Ubuntu install | statoverride sanitised, snapd pinned, launchers regenerated |
| 2026-10-31 | Ubuntu 24.04 · XFCE4 · Termux:X11 on device | desktop live; screenshot in `docs/screenshots/vivo-ubuntu-xfce-x11-v170.png` |
| 2026-10-31 | `stop-linux` on device | `termux-x11` gone, `.X11-unix` empty, `.X1-lock` removed |
| 2026-10-31 | Alpine CLI install on device | `Installation complete! (5m 11s)`, user + sudo ritual work |
| 2026-10-31 | Alpine uninstall on device | rootfs, pidfile, log and `xdg-*` runtime dir removed (#49) |
| 2026-10-31 | GitHub repo metadata | description, homepage, 20 topics, Discussions enabled |

### Findings that only appeared on hardware

1. **`pipefail` + `grep -q` broke every fresh install on proot-distro v5.**
   `proot-distro install --help | grep -q IMAGE:TAG` returns 141 because grep
   exits early and the producer gets SIGPIPE, so the v5 branch was skipped and
   the installer rejected `alpine` with "knows no 'alpine' distribution".
   Fixed with a pipeline-free `lfa_match` helper plus an M10 regression test
   (64 KiB+ help text). The host suite could not see it: its stub help is one
   line.
2. **`exec -a` cannot spawn a multicall binary on Termux** (`sleep` is
   coreutils and rejects the invented argv[0]). The M4/M6 fixtures now exec
   bash instead, which is a real ELF.
3. **Anchored `pgrep -f '^Xvnc '` misses a guest X server.** Under proot the
   binary is exec'd with an absolute path, so `lfa_x1_server_pid` now compares
   the basename of argv[0] and scans `/proc` rather than trusting `pgrep`.
4. **The "sshd hangs" symptom was Android's phantom-process killer**, not the
   project: an XFCE session plus the stub suite exceeds the default child
   limit and Android kills the surplus, including `sshd`. Documented in
   `docs/TEST-REPORT.md`; the README already tells users to disable it.

## Next actions

Done in this pass: tag `v1.7.0` with `install_linux.sh` + `SHA256SUMS`, green
CI, description/topics/homepage, Discussions on, Wiki off, delete-branch-on-merge.

Remaining, all of which need an upload or an owner decision:

1. Protect `main` (require the CI check, block force-push) — changes how the
   maintainer pushes, so it was left to the owner.
2. Social preview image, demo GIF and a real-hardware photo.
3. Re-attribute the `pdev@local` commits (history rewrite).
