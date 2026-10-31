# Architecture

This document explains how the installer is put together and why. It exists so
that a change can be made without re-deriving the design from 3,000 lines of
bash.

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
├── $PREFIX/bin/start-linux   generated launcher (X11 or VNC, desktop or shell)
├── $PREFIX/bin/stop-linux    generated teardown
├── $PREFIX/bin/terminal-linux  shell only, no display/audio servers
├── $PREFIX/bin/lfa-lib.sh    shared layout/pid/display helpers
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

Step 3 is the controversial one: instead of a long chain of `proot-distro login
... -- cmd` calls (each paying proot startup and losing environment), the
installer writes one guest bash script and runs it once. It is fast and
survives interruption per step, but it means four levels of quoting
(issue #26). Two rules keep it safe:

- the file is created `0600` before the first byte is written,
- it is deleted after the run and on interrupt via `trap`.

## Display model

Both back ends use display `:1` and port `5901`. This is a decision, not an
accident: one device rarely runs two desktops, and a fixed display keeps the
launchers simple. The cost is that a dead server can poison the next start, so
`lfa_clear_stale_x1` releases the socket and lock **only** when no process
whose argv[0] is a real X server holds `:1`. `pgrep -f` alone is not enough:
the launcher's own command line contains the string `Xvnc`.

```
X11:  termux-x11 :1 ──socket──> proot-distro login --user <u> -- dbus-run-session -- <session>
VNC:  Xvnc :1 (inside proot, keepalive loop) ──> <session>
```

The VNC server runs inside the proot session, which is why the launcher keeps a
`while :; do sleep 3600; done` alive: `proot --kill-on-exit` would otherwise
reap the server when the login command returns.

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
| VNC password | `~/.vnc/passwd` in the guest | TigerVNC's own encryption, **8 characters only** |
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
matrix. The suite enforces that the documented `PASS=` count matches reality,
so the docs cannot drift silently.
