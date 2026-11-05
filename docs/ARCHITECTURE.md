# Architecture

This document explains how the installer is built and why. It should let you
change the design without reading the whole 3,000-line script first.

## The shape of the thing

```
Termux (Android app, one UID)
│
├── install_linux.sh          the manager: menus, install, repair, backup
│   ├── lib/real-feel.sh      writes the guest shell/desktop wrappers
│   ├── lib/wallpaper.sh      stages the distro wallpaper, first-login hook
│   ├── lib/uid0.c            tiny LD_PRELOAD shim so dpkg accepts uid 0
│   └── lib/dpkg-statoverride.sh  proot-safe statoverride replacement
│
├── $PREFIX/bin/start-linux   classic launcher (X11 or VNC, desktop or shell)
├── $PREFIX/bin/linux         desktop shortcut: start-linux --desktop
├── $PREFIX/bin/stop-linux    generated teardown
├── $PREFIX/bin/terminal-linux  shell only, no display/audio servers
├── $PREFIX/bin/lfa           unified command line (install/list/status/...)
├── $PREFIX/bin/switch-linux  alias for lfa switch
├── $PREFIX/bin/autostart-linux  alias for lfa autostart
├── $PREFIX/bin/lfa-lib.sh    shared layout/pid/display helpers
├── $PREFIX/lib/linux-for-android/  private runtime used by lfa
│   ├── install_linux.sh      copied manager (works after the repo moves)
│   ├── lib/                  guest helper scripts and C sources
│   ├── plugins/              legacy proot-distro plugins
│   └── assets/               wallpapers used by the runtime
│
└── proot-distro containers
    └── <name>/rootfs         the guest filesystem
        └── /etc/termux-linux-manager.conf   per-instance settings
```

There is no daemon and no state beyond those files. Everything is
regenerated from `install_linux.sh` on every install or repair, which is why
`menu 12 (Apply Latest Fixes)` can migrate an old distro: it rewrites the
generated files rather than patching them.

## Why the installer is one file

`proot-distro` runs on Android 5 devices with a minimal Termux userland. A
multi-file installer would need a stable path to its own resources before it
has installed anything, and `curl | bash` gives it no directory at all. The
single-file design keeps the script self-contained and lets `lib/` be optional
(the installer works, with degraded polish, if `lib/` is missing).

The cost is size. This is the main maintainability debt, tracked as issue #24.

## The install pipeline

```
guided setup ─┐
quick setup  ─┼─> install_linux()
saved config ─┘        │
                       ├─ 1. resolve distro, legacy mapping, disk space
                       ├─ 2. proot-distro install  (OCI image or plugin)
                       ├─ 3. build $PREFIX/tmp/gui_setup_<pid>.sh  (0600)
                       ├─ 4. proot-distro login ... bash /tmp/gui_setup_<pid>.sh
                       ├─ 5. delete the setup script
                       ├─ 6. write launchers + wallpaper + extras
                       └─ 7. verify core components, then "Installation complete"
```

Step 3 is the unusual one. Instead of a long chain of `proot-distro login
... -- cmd` calls (each paying proot startup and losing environment), the
installer writes one guest bash script and runs it once. It is fast and can
resume after an interrupted step, but it needs four levels of quoting
(issue #26). Two rules keep it safe:

- the file is created `0600` before the first byte is written,
- it is deleted after the run and on interrupt via `trap`.

## Display model

Both back ends use display `:1` and port `5901`. One device rarely runs two
desktops, and a fixed display keeps the launchers simple. The cost is that a
dead server can poison the next start, so `lfa_clear_stale_x1` releases the
socket and lock only when no process whose argv[0] is a real X server holds
`:1`. `pgrep -f` alone is not enough: the launcher's own command line contains
the string `Xvnc`.

```
X11:  termux-x11 :1 ──socket──> proot-distro login --user <u> -- dbus-run-session -- <session>
VNC:  Xvnc :1 (inside proot, exec sleep keepalive) ──> <session>
```

The VNC server runs inside the proot session, which is why the launcher keeps an
`exec sleep 2147483647` alive: `proot --kill-on-exit` would otherwise reap
the server when the login command returns. `exec` matters for shutdown: a
shell loop defers SIGTERM until its current `sleep` returns, so `stop-linux`
could leave the proot wrapper behind. The single sleep process dies at once.

An install can carry both back ends. `SERVER="both"` installs both package
sets, and `start-linux` resolves the choice to `x11` or `vnc` before starting.
Only one runs at a time because they share `:1` and port `5901`. The last
desktop choice is stored per instance under
`~/.config/linux-for-android/last-server-<instance>`. Terminal-only sessions
do not update it. `stop-linux` handles both values, so a both install can stop
whichever server is running without leaving the other behind.

`lfa switch` changes `SERVER` in the guest config, installs the backend being
entered first, and only then removes the backend being left when
`--remove-old` is given. Termux:X11 is a host package shared by every distro,
so removal scans the other installed configs first; `--force` overrides that
guard. VNC removal runs the guest package manager and deletes the per-user
`.vnc` and `.config/tigervnc` directories.

The generated launchers are deliberately small and self-contained. They read
`lfa-lib.sh` when present and fall back to inline helpers, so a damaged or
partially upgraded install still starts. `lfa` is different: it uses the
private runtime copy under `$PREFIX/lib/linux-for-android`, which is refreshed
on every install and on menu 12. That copy is what lets the command line keep
working after the repository is moved, renamed, or deleted.

Preferences that are not tied to one distro live in
`~/.config/linux-for-android/preferences.conf`. The only key today is
`START_NOTICE`, written by `lfa notice on|off`. The notice is printed to
stderr by the classic `start-linux` path only; `linux`, non-interactive runs,
and Termux:Boot are silent.

## Android version cutoffs

Two cutoffs are tracked separately because they moved at different times:

| Name | Value | Controls |
|---|---|---|
| `IS_LEGACY` | SDK < 24 | archived Termux repos, proot-distro v4.2.0 source install, Alpine/Debian bullseye recommendations |
| `X11_SUPPORTED` | SDK >= 26 (or SDK 0 for non-Android shells) | Termux:X11, Both, GNOME, VirGL expectations |

Android 7.0/7.1 (SDK 24/25) has modern Termux packages but no Termux:X11.
Installer defaults, `lfa install`, `lfa switch`, `lfa autostart`, menu 14,
quick setup, and the generated `start-linux` all consult `X11_SUPPORTED`, so
the two paths cannot disagree.

## Compatibility and Android bridge layers

```
lfa compat                          lfa android
  systemctl -> LFA supervisor          termux-battery-status
  loginctl  -> CLI answers             termux-location
  upower    -> /tmp battery data       termux-clipboard-get
  snap      -> apt/tarball mapping     termux-notification
  bwrap     -> unsandboxed fallback    termux-wifi-connectioninfo
  vulkan    -> lavapipe (CPU)                 │
  opencl    -> POCL (CPU)                     ▼
        │                            $PREFIX/tmp/lfa-android-*
        ▼                                     │
  guest /usr/local/bin shims  <───────────────┘
```

They are separate commands on purpose. `lfa compat` changes Linux-side
expectations and may lie about a service; `lfa android` exposes real Android
data and never claims to be a kernel device. The guest sees bridge files as
`/tmp/...` because proot runs with `--shared-tmp`.

Neither layer may fake a kernel facility. Docker, Podman, Flatpak, TUN/TAP,
iptables, CUDA, ROCm, KVM, and modules are listed as unsupported by
`lfa compat list` and explained by `lfa compat explain`.

## CI model

## Session wrappers

`lib/real-feel.sh` writes `/usr/local/bin/lfa-set-wallpaper` and, for GNOME,
`/usr/local/bin/start-gnome-session`. Wrappers exist because
`gnome-session` cannot run without systemd/logind: the wrapper substitutes for
the two things `gnome-session` would have done (a system bus and an
environment published to the session bus) and then `exec`s the shell.

For XFCE/LXDE/MATE the session is started directly by `dbus-run-session`, and
the launcher sets the locale.

## Secrets

| Secret | Where it lives | Protection |
|---|---|---|
| user/root password | guest `/etc/shadow` | hashed by the guest |
| install passwords (transient) | `$PREFIX/tmp/gui_setup_<pid>.sh` | mode 0600, deleted after use and on interrupt |
| sudo ritual password | salted SHA-256 in `/usr/local/bin/sudo` | mode 0700, one-way hash |
| VNC password | `~/.vnc/passwd` in the guest | TigerVNC's own encryption, 8 characters only |
| saved answers | `~/.config/linux-for-android/setup.conf` | mode 0600, base64 (obfuscation only) |

The sudo shim is not a security boundary: inside proot every process is the
same UID. It exists to make the ritual familiar, not to protect anything.

## Testing model

`tests/test-all.sh` runs the installer against a fake `HOME`, `PREFIX` and
`PATH`, with stub `pkg`, `proot-distro`, `sshd`, `pulseaudio`, `getprop`,
`free` and `df`. It asserts on generated files and on exit codes, never on a
real container. That is deliberate: it must run in CI in seconds.

Everything that needs a real kernel, a real package manager or a real display
is verified on devices and recorded in `docs/TEST-REPORT.md` and the README
matrix. The suite checks that the documented `PASS=` count matches the real
count, so the docs cannot drift silently.

The Android CI layer boots emulators and runs `tests/termux-e2e.sh` over SSH.
A small PR smoke matrix, a weekly reduced matrix, and a manual sharded full
matrix share one reusable scenario workflow. The host-side VNC probe performs
a real RFB handshake and checks the framebuffer pixels; the X11 check runs
`xdpyinfo` inside the guest. `docs/CI-ANDROID.md` explains the tiers and the
known emulator gaps.
