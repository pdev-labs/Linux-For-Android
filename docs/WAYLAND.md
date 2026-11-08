# Wayland sessions

`lfa wayland` runs a Wayland desktop inside Termux:X11. It installs a session
profile, starts a compositor, and reports which compositor is actually running.

The command exists because a phone can run a Wayland compositor nested on X11.
It cannot give that compositor a DRM device. Hyprland needs one, so on a stock
phone LFA starts Sway with a profile that matches the Hyprland look. When a
writable render node exists, the same command starts Hyprland inside a small
Sway host instead.

## What the phone provides

Termux:X11 is an X11 server. Sway has an X11 backend, so it starts nested in
that server with `WLR_BACKENDS=x11`. The phone has no usable DRM render node
for an app, so the nested Sway uses the pixman software renderer.

Hyprland uses Aquamarine for its back end. Aquamarine's Wayland back end asks
for `zwp_linux_dmabuf_v1` and opens a DRM render node while it initialises
dmabuf support. On the Vivo V2437 the only node is `/dev/dri/card0`, owned by
`system:system` with mode `660`, and `/dev/dri/renderD128` does not exist.
Opening the card fails with `EACCES`. Hyprland then aborts with:

```text
terminate called after throwing an instance of 'std::runtime_error'
  what():  CBackend::create() failed!
```

That is a device permission limit. The packages are installed and the config
parses. A rooted device, a vendor build that exposes a render node to apps, or
a future Android release can change it. LFA checks for a writable
`/dev/dri/renderD*` at start time and only then tries Hyprland.

## Commands

| Command | What it does |
| --- | --- |
| `lfa wayland status -i NAME` | show instance, distro, user, preference, session state, packages, and DRM nodes |
| `lfa wayland install -i NAME` | install the compositor packages and the session profile |
| `lfa wayland start -i NAME` | start Termux:X11 if needed, then the session |
| `lfa wayland stop -i NAME` | stop the session and any orphaned compositor |
| `lfa wayland doctor -i NAME` | status plus the launcher, X server, log tail, and the DRM explanation |
| `lfa wayland session [NAME]` | read or set `auto`, `hyprland`, `sway`, or `xfce` |
| `lfa wl ...` | alias for `lfa wayland` |

`lfa wayland start` refuses to run while an X11 or VNC desktop is already up
for the same instance. Use `--restart` to replace it.

## Install

```bash
lfa wayland install -i arch
lfa wayland install -i arch --resolution 2408x1080
lfa wayland install -i arch --wallpaper ~/Pictures/wall.jpg
lfa wayland install -i arch --config ~/hypr-config.tar.gz
```

`--config` accepts a directory or a `.tar.gz` with `hypr`, `waybar`, `kitty`,
`wofi`, or `swaync` subdirectories. Each one is copied into the guest user's
`~/.config`. That is how the host's Hyprland and Waybar files get in without a
manual `scp`.

`--resolution` appends an output rule to the Sway profile:

```text
output X11-1 resolution 2408x1080 position 0 0
```

The rule is rewritten on the next install, so it does not pile up. The phone
screen is 1080x2408, and the session uses 2408x1080 to match it in landscape.

On Arch the install adds `sway`, `swaybg`, `swaylock`, `waybar`, `swaync`,
`kitty`, `wofi`, `thunar`, the Adwaita and JetBrains Mono Nerd fonts, `grim`,
`slurp`, `wl-clipboard`, `xorg-xwayland`, and the Hyprland packages. Debian and
Ubuntu get the Sway side from apt where the package names exist. The Hyprland
packages are Arch only. Alpine, Fedora, Void, and the legacy images are not
handled yet; the command says so and exits.

## The profile

The Sway profile is written to `~/.config/lfa-wayland/sway/config` in the
guest. It sets:

- Super as the modifier, with the same keybinds as the Hyprland config:
  terminal, launcher, file manager, kill, fullscreen, floating, focus, move,
  resize, workspaces, audio, and screenshot.
- 3 px inner gaps, 6 px outer gaps, 2 px borders, and the graphite and teal
  colours from the host.
- `waybar` with a Sway workspace module, the launcher, media, tray, battery,
  audio, network, power, and clock.
- `swaync` for notifications and `swaybg` for the wallpaper.
- `dbus-update-activation-environment` so portals and the tray work.

The battery module reads `/tmp/lfa-android-battery.env`, which the Termux:API
bridge writes. It shows the real Android percentage and charging state.

The Hyprland host profile is `~/.config/lfa-wayland/sway-nest/config`. It runs
one window, Hyprland, fullscreen, with no bar and no wallpaper.

## Verified behaviour

On the Vivo V2437, Android 16, arm64:

- `lfa wayland install -i arch --resolution 2408x1080` installed the packages
  and the profile.
- `lfa wayland start -i arch` started Termux:X11 and Sway, with Waybar,
  SwayNC, SwayBG, and a working launcher.
- `swaymsg -t get_outputs` reported `2408x1080`.
- `grim` captured the session, and the screenshot showed the wallpaper, bar,
  and notification centre.
- `lfa wayland status -i arch` reported `session: running (Sway)` and
  `drm: render=none`.
- Hyprland 0.57.1 is installed and its config parses, but it aborts with
  `CBackend::create() failed!` on this device.

## Logs and recovery

| Path | Content |
| --- | --- |
| `~/lfa-wayland.log` | session output, D-Bus, portals |
| `~/.cache/lfa-wayland-sway-pixman.log` | Sway with the software renderer |
| `~/.cache/lfa-wayland-sway-gles2.log` | Sway when a render node was found |
| `~/.cache/lfa-wayland-host.log` | the Sway host for a nested Hyprland |

If the session dies, `lfa wayland doctor -i NAME` prints the last lines. A
killed proot parent can leave Sway behind; `lfa wayland stop` cleans those up
with `pkill` inside the guest.

To go back to XFCE for one session, run `lfa wayland session xfce` and start
again. To remove the preference, set it to `auto`.

## Limits

- Software rendering only on a stock phone. Expect slower video and no
  hardware GL in Wayland clients.
- No screen sharing through dmabuf. `grim` works; portal screencast may not.
- Hyprland's own features that need its renderer, such as blur and shadows,
  are unavailable while it cannot start.
- One Wayland session per instance, on display `:1`.
- The Sway profile copies the look and keybinds. The bar runs Waybar's Sway
  modules, so Hyprland-only modules are absent.
