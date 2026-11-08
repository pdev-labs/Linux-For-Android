# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## A note on version numbering

Tags `v2.0.0` to `v4.6.0` from July 2026 predate a renumbering of the project.
The current line restarted at `v1.5.0` in October 2026 and continues upward.
`v1.6.1` is newer than `v4.6.0` despite the smaller number. Git tag dates, not
tag names, define the order. See the table at the bottom.

## [Unreleased]

### Added

- `lfa wayland` (alias `lfa wl`) adds a nested Wayland session. It installs
  Sway with a profile that copies the Hyprland keybinds, gaps, borders,
  colours, Waybar bar, notification centre, and wallpaper; starts it on
  Termux:X11; and stops it cleanly. `--config` imports hypr, waybar, kitty,
  wofi, and swaync configs, `--resolution` sets the nested output size, and
  `--wallpaper` replaces the background. Hyprland is installed and used when a
  writable `/dev/dri/renderD*` exists. A stock phone has no such node, so
  Hyprland aborts with `CBackend::create() failed!` and the Sway profile runs
  instead. `status`, `doctor`, and `session` report which compositor is live.
- `lfa appimage` (alias `lfa app`) adds first-class AppImage support. `add`
  extracts an AppImage once into `~/.local/opt/appimages`, writes a launcher
  in `~/.local/bin`, and adds a desktop entry; `list`, `run`, and `remove`
  manage it. `lfa run FILE` runs an AppImage once without installing it.
- `lfa fix -i NAME` runs "Apply Latest Fixes" without the interactive
  manager, so upgrades over SSH or from a script are deterministic.
- `lfa storage status|fix|exec|open` handles Android shared storage. `fix`
  gives the desktop user gid 1023, recreates the Termux links, and adds a
  Thunar bookmark, a desktop shortcut, and a **Run in Linux** right-click
  action. `exec` runs a script from shared storage without needing `chmod`.
  `status` shows the permission, group, write access, and the chmod result.
- `lfa storage data status|list|pull` copies an app's `Android/data` and
  `Android/obb` folders through adb into shared storage. Android blocks both
  folders for apps, including Termux, so direct access is not possible without
  shell access.
- Guest sessions now export `APPIMAGE_EXTRACT_AND_RUN=1`, because proot does
  not expose `/dev/fuse` and an AppImage cannot self-mount. A direct
  `./Foo.AppImage`, a file-manager double-click, and a menu entry all work.
  Every distro gets the setting at install time, and `lfa appimage` adds it to
  existing instances on demand.
- New `lfa` command line: `install`, `list`, `status`, `start`, `shell`,
  `stop`, `switch`, `autostart`, `update`, `fix`, `doctor`, `backup`,
  `restore`, `remove`, `compat`, `android`, `appimage`, `run`, `diagnostics`,
  `notice`, `version`, and `help`. `-i` is shorthand for `--instance`
  everywhere the
  long form is accepted.
- New `linux` shortcut starts the desktop directly without the classic
  terminal/desktop menu. It is a script, not an alias, so it works from
  widgets, SSH, and boot scripts. `start-linux` keeps the full advanced menu.
- `lfa switch x11|vnc|both` changes the backend in place. `--remove-old`
  removes the packages of the backend being left, and `--keep-packages` is
  the default. The new backend is installed before anything is removed.
- `lfa switch` keeps the shared Termux:X11 host package when another
  installed distro still uses it, and switches this instance anyway. `--force`
  removes the package and warns that the other distro's desktop will break.
  VNC removal also deletes the per-user `.vnc` and `.config/tigervnc`
  directories.
- Menu 14, Change Display Backend, wraps the same switch and removal logic.
- A short change notice is printed by interactive `start-linux` runs. Hide it
  with `lfa notice off`, `start-linux --no-notice`, or `LFA_NO_NOTICE=1`;
  restore it with `lfa notice on`. The preference is stored per user, not per
  distro.
- Android 5/6 refuses X11 and Both switches and installer requests with an
  explanation. If `--remove-old` was requested, the manager warns that
  deleting VNC would leave no desktop and prints the command that reinstalls
  VNC.
- Guided setup can install Termux:X11, VNC, or both. With both, `start-linux`
  asks which backend to use, remembers the last desktop choice, and
  `stop-linux` stops either or both.
- Apply Latest Fixes (menu 12) can add the missing backend to an existing
  single-backend install after confirmation.
- Termux:Boot can start either backend when both are installed. X11 autostart
  starts the server and desktop in the background; open the Termux:X11 app
  when you want to see it.
- `lfa compat` lists, explains, enables, and disables optional compatibility
  shims for `systemctl`, `loginctl`, `upower`, `snap`, `bwrap`, CPU Vulkan, and
  CPU OpenCL. Unsupported kernel features (Docker, Flatpak, TUN/TAP, CUDA,
  ROCm, KVM, modules) are reported honestly instead of faked.
- `lfa android` reports Termux:API state and provides a real bridge for
  battery, location, clipboard, and notifications. Data is written to
  `$PREFIX/tmp`, which the guest sees as `/tmp` under `--shared-tmp`.
- `lfa install --software` accepts a comma-separated app list for unattended
  installs.
- Android CI: a reusable emulator scenario plus PR smoke, weekly reduced, and
  manual sharded full matrices. The on-device harness covers real VNC RFB
  handshakes, framebuffer pixels, X11 `xdpyinfo`, backend switching, legacy
  refusal, shims, and software probes.
- New `docs/INCOMPATIBLE.md` and `docs/CI-ANDROID.md`.

### Changed

- `lfa` and its aliases run from a private copy under
  `$PREFIX/lib/linux-for-android`, so the command line keeps working after
  the cloned repository is moved or deleted. The copy is refreshed on install
  and on menu 12.
- The generated launchers now reject unknown options instead of silently
  starting a desktop. Explicit `-i` names are validated even when only one
  distro is installed, and non-interactive Both starts fail rather than
  guessing a backend.
- A backend switch no longer rewrites a Termux:Boot script that belongs to a
  different instance.
- Diagnostics bundles now include the `lfa`, `linux`, `switch-linux`, and
  `autostart-linux` wrappers.

### Fixed

- Starting a desktop twice for the same instance left two session managers on
  display `:1`. They competed for the window manager, and the screen showed
  only the X root cross cursor. `start-linux` now refuses a second session,
  `--restart` replaces one, and `stop-linux` also stops the guest session
  process instead of only the X server.
- `xfce4-session` waits for `gpgconf` before launching `xfwm4`. Under proot,
  both `gpgconf --kill gpg-agent` and `gpgconf --launch gpg-agent` can block
  forever (the second because the daemonized agent keeps the pipe open), so
  the desktop stayed on the root cross cursor. The manager now disables
  GPG/SSH agent startup in the user's `xfce4-session` channel and keeps a
  scoped `gpgconf` guard as a fallback; outside a session the real `gpgconf`
  is untouched.
- `stop-linux` now recognises a desktop session by `/proc/<pid>/cwd`, so an
  orphaned `xfce4-session` whose proot wrapper died is stopped too. This was
  the remaining way to end up with two sessions and no window manager.
- Desktop sessions disable GNOME compatibility and XFCE session save/restore.
  There is no PAM conversation to unlock a keyring under proot, and restoring
  a stopped session kept relaunching the locked keyring prompt (and Remmina)
  on every login. The saved session is cleared during install/upgrade.
- Thunar marked every folder on Android shared storage with a false
  "unreadable" X. Android mounts the tree as `1023:1023` with mode `2770`,
  and the desktop user was outside group 1023. The user's primary group is
  now gid 1023, so the mode check passes. Reads and writes worked all along.
- `chmod` on `/storage/emulated/0` is documented as impossible. The FUSE
  mount fixes the mode and is `noexec`; `lfa storage exec` provides the
  working alternative.
- `lfa switch` stopped the running desktop and left the display empty. When a
  desktop was running, the switch now restarts it on the new backend;
  `--no-start` keeps it stopped.
- Sessions apply a cursor theme (`XCURSOR_THEME`, `xsettings`, and an
  `lfa-set-cursor` autostart helper), so a desktop that starts before its
  theme is available no longer stays on the root cross cursor.
- `lfa status` failed on a fresh install because its PID helper only existed
  in the generated launcher library, not in the CLI's private runtime. The
  helper now lives in both. X11 is also reported only for the instance whose
  rootfs is actually running, instead of for every installed distro.
- `start-linux --vnc` printed "VNC server started" even when nothing was
  listening on 5901. It now verifies the port, prints the log path, and exits
  non-zero on failure. A VNC server owned by another instance is refused
  instead of being mistaken for this one.
- VNC and Termux:X11 both use display `:1`. A leftover server from the other
  backend made the guest attach to the wrong X server, so xfwm4 died with a
  GLX `BadValue` and the VNC desktop appeared without a window manager.
  `start` now frees `:1` from the other backend before starting.
- Some Android GPU drivers expose `virgl_test_server_android` but cannot
  create a GLX context. The desktop now detects the failure in the session
  log, switches that instance to llvmpipe, and restarts it once. The choice
  is stored as `NEED_VIRGL="0"` so later starts are reliable.
- Termux:API helpers can block forever when the app was killed or a
  permission prompt is waiting. `lfa android test`, `refresh`, and `pump`
  now apply short timeouts. `refresh` only probes location, clipboard, and
  Wi-Fi when the matching capability is enabled.
- `lfa compat status` printed `(target: rootfs)` instead of the instance
  name, and `lfa compat enable vulkan|opencl` marked the shim enabled even
  when no packages could be installed. The target label is fixed, Alpine's
  lavapipe packages are supported, and a failed install leaves the shim
  disabled.
- `lfa remove` could exit silently without deleting anything. The size
  preflight ran `du -sh` inside `set -e`/`pipefail`; Android's `du` can print
  a size and still exit non-zero when a few entries are unreadable, which
  aborted the function before the first prompt. The size is now best-effort.
- Android 7.0/7.1 (SDK 24/25) was treated as fully modern and offered
  Termux:X11, Both, and GNOME even though all three require Android 8 (SDK 26).
  The package/repo cutoff (`IS_LEGACY`, SDK < 24) and the X11 cutoff
  (`X11_SUPPORTED`, SDK >= 26) are now tracked separately. The installer,
  `lfa install`, `lfa switch`, `lfa autostart`, menu 14, quick setup, and the
  generated `start-linux` all select or refuse VNC correctly on those devices.
- Android 5's toybox `df` ignores `-Pk` and prints human units. The disk
  preflight read `3.6G` as zero and refused every legacy install. It now
  falls back to `stat -f` and then to the human value.
- Legacy Alpine's TigerVNC has no `-kill`, and its Xvnc reparents to init and
  survives the proot wrapper, so `stop-linux` left the desktop running. It now
  stops the managed `:1` processes directly as a fallback.
- Menu 12 clamped `SERVER="both"` to VNC in memory on Android 5/6 but did not
  write it back, so the next `start-linux` offered the unsupported X11 choice
  again. The clamp is now persisted and the autostart backend is forced to VNC.
- `stop-linux` could leave the VNC proot wrapper behind. The keepalive used a
  shell loop around `sleep`, which defers SIGTERM; it is now a single
  `exec sleep`, with a SIGKILL fallback for a wedged wrapper.
- Menu 12 reported `tigervnc` missing on healthy installs. `vncserver` is an
  absolute symlink into `/etc/alternatives`, so checking it from the host
  followed the link into the host filesystem.

### Documentation

- Credited pdev-labs as the solo author and maintainer in the README,
  contributing guide, code of conduct, and new `AUTHORS.md`.
- Removed first-person plural wording from project documentation and code
  comments.
- Rewrote the Markdown documentation to remove AI-style prose patterns and
  decorative formatting.

## [1.7.1] - 2026-11-01

### Fixed

- VS Code did not open. Electron's setuid sandbox cannot work under proot, so
  `/usr/share/code/code` aborted in the zygote while the `code` CLI still
  returned 0. From the user's side nothing happened; from the shell nothing
  was printed. `/usr/local/bin/code` is now a wrapper that passes
  `--no-sandbox --disable-gpu`, and the desktop entries in
  `/usr/local/share/applications` point at it, so the menu works too.
  Applying `menu 12` or reinstalling fixes an existing distro.
- Chromium's proot-safe launcher is now written by the shared guest polish in
  `lib/real-feel.sh`, not only by menu 11. A fresh Chromium install gets
  `--no-sandbox --disable-dev-shm-usage` immediately.
- Antigravity's launcher is recreated during migration if `/opt` survived but
  `/usr/local/bin/antigravity` did not.

### Documentation

- New README section, "Software and app fixes": installing anything the
  optional selector skipped, per-distro package names, the extra steps for VS
  Code, Firefox, Chromium, and Antigravity, why an app "does not open", and
  screenshots of every application running on the phone.
- New `docs/TROUBLESHOOTING.md`: evidence collection, installation and apt
  repair, X11 and VNC, sandboxed apps, audio, storage, SSH, Android process
  limits, a recovery ladder, and an error-string index.
- Device screenshots no longer show notification-bar app icons or the status
  chip. The session itself is unchanged.

### Verified

- Every application in the install menu on the Vivo V2437: Python 3.12.3, Git
  2.43.0, Node 26.13.0/npm 11.20.0, curl 8.5.0, wget 1.21.4, neofetch 7.1.0,
  htop 3.3.0, VS Code 1.144.0, Firefox, Chromium, LibreOffice Writer 24.2,
  VLC, GIMP, and Antigravity IDE. All launch.

## [1.7.0] - 2026-10-31

Security and correctness pass over the whole installer, based on the audit in
[issues.md](issues.md). There were 54 review findings: 38 fixed, 11 partial,
and 5 deliberately deferred. See `tracker.md`.

### Security

- Install secrets are written to a mode-`0600` file that is deleted after use
  and on interrupt. They used to survive forever in shared `/tmp`.
- The `sudo` shim stores a salted SHA-256 hash instead of a base64 copy of the
  password, and is mode `0700`.
- VS Code's repository is only added after the Microsoft signing key's
  fingerprint (`BC528686B50D79E339D3721CEB3E94ADBE1229CF`) is verified.
- Antigravity download URLs from the scraped page are restricted to vendor
  hosts before anything is downloaded.
- The legacy `proot-distro` source tree is validated after download.
- `set -o pipefail` is enabled, so a failure inside a pipeline is no longer
  swallowed. This caught two real bugs in the dashboard. It also exposed the
  `proot-distro ... --help | grep -q` idiom: `grep -q` exits at the first
  match, the producer dies with SIGPIPE, and the pipeline reports failure.
  That made every fresh install on proot-distro v5 abort with "knows no
  'alpine' distribution". All capability probes now use a pipeline-free
  `lfa_match` helper, with a regression test that feeds 64 KiB or more of help
  text through the probe.

### Added

- `--help`, `--version`, `--list`, `--doctor`, `--yes`, and `--debug`
  command-line flags. `--help` and `--version` work outside Termux.
- A cached, non-blocking "newer release available" notice.
- Free-space preflight before an install: 900 MB for CLI, 2.5 GB for desktop,
  3.5 GB for GNOME. The installer refuses clearly instead of leaving a
  half-installed rootfs.
- `LFA_IMAGE_<DISTRO>` environment variables to pin rolling container images.
  The image reference used is recorded in the manager config.
- `CHANGELOG.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  issue and pull-request templates, `.editorconfig`, and `.gitattributes`.
- GitHub Actions CI: `shellcheck -S warning`, `bash -n`, the full test suite,
  and the CLI surface.

### Fixed

- VNC refused to start after an X11 session with "display :1 is taken". Display
  `:1` is now released on stop, and only when no real X server holds it.
- PID files are verified against the process command line before signalling,
  so a recycled PID can no longer kill an unrelated process.
- `stop-linux` only stops the Termux:X11 instance for display `:1`, not every
  instance on the device.
- UTF-8 locale is set for XFCE, LXDE, and MATE too. GTK apps used to fail with
  "Non UTF-8 locale".
- `XDG_RUNTIME_DIR` is per distro, so two distros no longer share bus sockets.
- Menu 12 reports components a newer release needs, with the exact install
  command, instead of silently leaving a half-migrated distro.
- Uninstall removes the Termux-side leftovers: pidfiles, logs, runtime dirs,
  and the shortcut and boot script when the last distro is gone.
- Password prompts ask twice on a terminal. The default `root` password and
  the 8-character VNC password limit are called out at the point of choice.
- Unquoted `$PREFIX` in generated-launcher `sed` calls.
- The X11 backend installs `termux-x11` on demand and logs the attempt.

### Changed

- The desktop and display-server menus are a single implementation shared by
  guided setup and the install wizard.
- `--help` and `--version` answer before the device probe, so they print one
  line on any machine instead of a "could not read Android version" warning.
- `README.md` numbers are enforced by the test suite, which fails when the
  documented `PASS=` count goes stale.

## [1.6.1] - 2026-10-29

### Fixed

- GNOME (experimental) starts. A private system D-Bus is created so
  `gnome-shell` stops dying on `Gio.DBus.system`, and the session publishes a
  UTF-8 locale so GTK apps stop exiting with status 8.
- Stale `/tmp/.X11-unix/X1` and `.X1-lock` are released when no real X server
  holds display `:1`. This fixes VNC after X11 for every desktop.
- Switching an existing distro to Termux:X11 installs the X11 packages on
  demand instead of dead-ending.

## [1.6.0] - 2026-10-29

### Added

- GNOME Shell as an explicitly experimental and beta desktop. It is hidden on
  Android 5/6, Alpine, and Void, and gated by a full warning and a
  confirmation.

## [1.5.8] - 2026-10-29

### Fixed

- Doctor purges a broken `snapd` and pins it, so `apt` stops failing.
- `reboot`, `poweroff`, `halt`, and `shutdown` inside the guest give guidance
  instead of failing silently.

## [1.5.7] - 2026-10-28

### Fixed

- A stale `/tmp/.X11-unix/X1` is cleared when no `termux-x11 :1` is running.

## [1.5.6] - 2026-10-28

### Fixed

- Desktop launch reliability: `dbus-run-session` launchers, machine-id
  generation, and stale session cleanup.
- openSUSE `dbus-1-daemon`, Void fonts, TigerVNC 1.15 and later geometry,
  `Xvnc` fallback, and legacy Alpine pinned to 3.18 with a minimal XFCE set.
- First-login wallpaper race.

## Version order

Newest first. `v4.x` is older than `v1.5.x`; see the note at the top.

| Tag | Date |
|---|---|
| v1.7.1 | 2026-11-01 |
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
