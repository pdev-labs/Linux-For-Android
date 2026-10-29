# Test report — v1.5.7

Live validation on two physical devices, 28–29 October 2026. Every item below
was reproduced on hardware, fixed, then re-verified on the device. Nothing in
this report is inferred from the unit suite alone.

- **Suite:** `tests/test-all.sh` — **PASS=273 FAIL=0** (host, Vivo, Oppo)
- **Versions:** v1.5.6 and v1.5.7
- **Scope:** X11 (Termux:X11) and VNC, all 8 supported distributions, plus
  Android 5.1.1 legacy mode

## Devices

| | Vivo V2437 | Oppo A37fw |
|---|---|---|
| Android | 16 (SDK 36) | 5.1.1 (SDK 22) |
| ABI / kernel | aarch64 / 6.1.145 | aarch64 / 3.10 |
| RAM | 7.5 GB + 8 GB swap | 1.8 GB, no swap |
| proot-distro | v4 (containers layout) | 4.2.0 (installed-rootfs layout) |
| Backend | Termux:X11 and VNC | VNC only |

## Defects found and fixed

### Desktop startup

| # | Defect | Root cause | Fix |
|---|---|---|---|
| 1 | Black desktop, "Unable to contact settings server" (openSUSE, Arch) | `dbus-launch`'s forked daemon dies immediately under proot | Launchers use `dbus-run-session -- <session>`, `dbus-launch` kept as fallback |
| 2 | No session at all on openSUSE | `/etc/machine-id` empty and read-only | Generated once per rootfs (install + menu 12) |
| 3 | `start-linux` hangs on a dead desktop after switching distros | Shared `$PREFIX/tmp` keeps dead D-Bus and `/tmp/.X11-unix/X1` sockets | Cleared before each X11 start, only when no `termux-x11 :1` is running |

### Image decoding

| # | Defect | Root cause | Fix |
|---|---|---|---|
| 4 | Whole session aborts: `Gtk:ERROR ... Bail out!` (Kali, Arch, Fedora, Void) | glycin decodes PNG/JPEG in a bubblewrap sandbox; proot cannot create namespaces | `/usr/local/bin/bwrap` shim triggers glycin's unsandboxed fallback |
| 5 | Every icon missing (Fedora 44, Void) | gdk-pixbuf ships without PNG/JPEG backends | `glycin-loaders` / `glycin-loaders-all` installed when available |

### Wallpaper

| # | Defect | Root cause | Fix |
|---|---|---|---|
| 6 | First login is black until re-applied | Applier ran before xfdesktop created its backdrop keys | Waits for `workspace*/last-image`, seeds `monitorscreen`, nudges `xfdesktop --reload` |
| 7 | No wallpaper on Arch | No `xrandr`, so the real connector was never seeded | Seeding no longer depends on `xrandr` |

### Distro specific

| # | Distro | Defect | Fix |
|---|---|---|---|
| 8 | openSUSE Tumbleweed | `dbus-1-x11` removed upstream, install failed 3× | `dbus-1-daemon dbus-1-tools` |
| 9 | Void | No fonts (text rendered as boxes) | `dejavu-fonts-ttf` |
| 10 | Void | No `vncserver` wrapper, VNC could not start | Direct `Xvnc` fallback with same password/geometry/session |
| 11 | All VNC | TigerVNC ≥ 1.15 rejects `-geometry` | Geometry written to `~/.vnc/config` + `~/.config/tigervnc/config` |
| 12 | Alpine on Android 5/6 | Image ships *edge* repos; edge glib/GTK abort on kernel 3.10 (`ENOSYS`) | Legacy installs pin `v3.18`, minimal XFCE set, `font-dejavu` |

Legacy Alpine result: **11m13s / 956 MB with a crashing desktop** →
**3m32s / 204 MB with a working VNC desktop**.

## Install and live-desktop matrix (Vivo, XFCE, Termux:X11)

| Distro | Install | Time | Size | Live desktop |
|---|---|---|---|---|
| Ubuntu 24.04 | pass | — | 1.9 G | **pass** — light and dark, clean first login |
| Kali Rolling | pass | 38m | 1.8 G | **pass** |
| Fedora 44 | pass | 12m | 1.1 G | **pass** |
| openSUSE Tumbleweed | pass | 11m | 831 M | **pass** |
| Arch Linux ARM | pass | 18m | 1.6 G | **pass** |
| Void Linux | pass | 10m | 1.1 G | **pass** |
| Alpine edge | pass | 3m | 649 M | **partial** — desktop and wallpaper render, `xfce4-panel` does not start |
| Debian (CLI) | pass | — | 195 M | CLI only, by design |

VNC backend verified live on Void (direct `Xvnc`) and on legacy Alpine 3.18
(Oppo): wallpaper, panel, clock and menus all correct.

## Android 5.1.1 (Oppo A37fw)

- `debian-4452` CLI: realistic prompt, `hostname`, ritual `sudo` password
  prompt, in-place upgrade through menu 12 applied cleanly.
- `lfa5` (Alpine 3.18 + XFCE + VNC): 3m32s, 204 MB, desktop confirmed by
  screenshot.

## Known limitations

- **Alpine edge on the Vivo:** session and wallpaper render, `xfce4-panel`
  does not start. Not reproduced on legacy Alpine 3.18, which is correct —
  appears to be an edge packaging issue rather than a launcher issue.
- **Void over VNC:** window manager and desktop start, panel inconsistent.
  Void over X11 is fully correct.
- **Wayland:** intentionally not supported; all work is X11/VNC.
- **GNOME (experimental):** validated on the Vivo (Android 16) with Ubuntu
  24.04 / GNOME 46. `gnome-shell --x11` renders over both Termux:X11 and VNC,
  and `gnome-terminal` + Nautilus launch from the session. Session services
  (logind, portals, session manager) are still absent, so login/logout,
  screen locking and settings panels remain broken. Two proot patches were
  required and are documented in the README: a private system D-Bus (the shell
  otherwise dies with "A connection to the bus can't be made"), and a UTF-8
  locale published to the session bus (GTK apps otherwise exit with status 8).
  First-login overview and black window shadows under software rendering are
  cosmetic and expected.
