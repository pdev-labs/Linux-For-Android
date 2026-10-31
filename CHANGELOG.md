# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## A note on version numbering

Tags `v2.0.0` … `v4.6.0` (July 2026) predate a renumbering of the project; the
current line restarted at `v1.5.0` in October 2026 and continues upward from
there. `v1.6.1` is newer than `v4.6.0` despite the smaller number. Git tag
dates, not tag names, define the order — see the table at the bottom.

## [Unreleased]

## [1.7.0] - 2026-10-31

Security and correctness pass over the whole installer, from the audit in
[issues.md](issues.md). 54 review findings: 38 fixed, 11 partial and 5
deliberately deferred (see `tracker.md`).

### Security

- Install secrets are written to a mode-`0600` file that is **deleted after
  use and on interrupt**; they used to survive forever in shared `/tmp`.
- The `sudo` shim stores a **salted SHA-256 hash** instead of a base64 copy of
  the password, and is mode `0700`.
- VS Code's repository is only added after the Microsoft signing key's
  fingerprint (`BC528686B50D79E339D3721CEB3E94ADBE1229CF`) is verified.
- Antigravity download URLs from the scraped page are restricted to vendor
  hosts before anything is downloaded.
- The legacy `proot-distro` source tree is validated after download.
- `set -o pipefail` is enabled, so a failure inside a pipeline is no longer
  swallowed (this already caught two real bugs in the dashboard). It also
  exposed the `proot-distro ... --help | grep -q` idiom: `grep -q` exits at
  the first match, the producer dies with SIGPIPE, and the pipeline reports
  failure — which made every fresh install on proot-distro v5 abort with
  "knows no 'alpine' distribution". All capability probes now use a
  pipeline-free `lfa_match` helper, with a regression test that feeds 64 KiB+
  of help text through the probe.

### Added

- `--help`, `--version`, `--list`, `--doctor`, `--yes`, `--debug` command-line
  flags; `--help`/`--version` work outside Termux.
- A cached, non-blocking "newer release available" notice.
- Free-space preflight before an install (900 MB CLI / 2.5 GB desktop /
  3.5 GB GNOME), with a clear refusal instead of a half-installed rootfs.
- Guideline: `LFA_IMAGE_<DISTRO>` environment variables pin rolling container
  images; the image reference used is recorded in the manager config.
- `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  issue and pull-request templates, `.editorconfig`, `.gitattributes`.
- GitHub Actions CI: `shellcheck -S warning`, `bash -n`, full test suite and the
  CLI surface.

### Fixed

- VNC refused to start after an X11 session ("display :1 is taken") — display
  `:1` is now released on stop and only when no real X server holds it.
- PID files are verified against the process command line before signalling,
  so a recycled PID can no longer kill an unrelated process.
- `stop-linux` only stops the Termux:X11 instance for display `:1` instead of
  every instance on the device.
- UTF-8 locale is set for XFCE/LXDE/MATE too (GTK apps used to fail with
  "Non UTF-8 locale").
- `XDG_RUNTIME_DIR` is per distro, so two distros no longer share bus sockets.
- Menu 12 reports components a newer release needs, with the exact install
  command, instead of silently leaving a half-migrated distro.
- Uninstall removes the Termux-side leftovers (pidfiles, logs, runtime dirs,
  shortcut and boot script when the last distro is gone).
- Password prompts ask twice on a terminal; the default `root` password and
  the 8-character VNC password limit are now called out at the point of choice.
- Unquoted `$PREFIX` in generated-launcher `sed` calls.
- The X11 backend installs `termux-x11` on demand and logs the attempt.

### Changed

- The desktop and display-server menus are a single implementation shared by
  guided setup and the install wizard.
- `README.md` numbers are enforced by the test suite, which fails when the
  documented `PASS=` count goes stale.

## [1.6.1] - 2026-10-29

### Fixed

- GNOME (experimental) actually starts: a private system D-Bus is created so
  `gnome-shell` stops dying on `Gio.DBus.system`, and the session publishes a
  UTF-8 locale so GTK apps stop exiting with status 8.
- Stale `/tmp/.X11-unix/X1` and `.X1-lock` are released when no real X server
  holds display `:1` (fixes VNC after X11, for every desktop).
- Switching an existing distro to Termux:X11 installs the X11 packages on
  demand instead of dead-ending.

## [1.6.0] - 2026-10-29

### Added

- GNOME Shell as an explicitly **experimental / beta** desktop, hidden on
  Android 5/6, Alpine and Void, gated by a full warning and a confirmation.

## [1.5.8] - 2026-10-29

### Fixed

- Doctor purges a broken `snapd` and pins it, so `apt` stops failing.
- `reboot`/`poweroff`/`halt`/`shutdown` inside the guest give guidance instead
  of failing silently.

## [1.5.7] - 2026-10-28

### Fixed

- A stale `/tmp/.X11-unix/X1` is cleared when no `termux-x11 :1` is running.

## [1.5.6] - 2026-10-28

### Fixed

- Desktop launch reliability: `dbus-run-session` launchers, machine-id
  generation, stale session cleanup.
- openSUSE `dbus-1-daemon`, Void fonts, TigerVNC ≥ 1.15 geometry, `Xvnc`
  fallback, legacy Alpine pinned to 3.18 with a minimal XFCE set.
- First-login wallpaper race.

## Version order

Newest first. `v4.x` is *older* than `v1.5.x`; see the note at the top.

| Tag | Date |
|---|---|
| v1.7.0 | 2026-10-31 |
| v1.6.1 | 2026-10-29 |
| v1.6.0 | 2026-10-29 |
| v1.5.8 | 2026-10-29 |
| v1.5.7 | 2026-10-28 |
| v1.5.6 | 2026-10-28 |
| v1.5.5 | 2026-10-27 |
| v1.5.0 | 2026-10-23 |
| v4.6.0 | 2026-07-29 (pre-renumbering) |
| v2.0.0 | 2026-07-29 (pre-renumbering) |
| v1.0.0 | 2026-07 (initial) |
