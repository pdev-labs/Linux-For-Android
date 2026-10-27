# Bundled distro wallpapers

These images are shipped so a GUI install looks like the distro it installs
without downloading a large wallpaper package or depending on a mirror at
install time. Every image is a 1920x1080 JPEG.

Naming:

- `<distro>.jpg` — light/default wallpaper
- `<distro>-dark.jpg` — dark wallpaper

The selected image is copied into the guest as
`/usr/share/backgrounds/lfa-default.jpg`, and the chosen mode is recorded in
`/etc/lfa-wallpaper-mode`.

| File | Source | License / attribution |
| --- | --- | --- |
| `ubuntu.jpg` | `ubuntu-wallpapers` 24.04.2, `warty-final-ubuntu.png` (Ubuntu archive) — the official 24.04 default | CC-BY-SA-3.0, Ubuntu community contributors |
| `ubuntu-dark.jpg` | `ubuntu-wallpapers` 24.04.2, `ubuntu-wallpaper-d.png` | CC-BY-SA-3.0, Ubuntu community contributors |
| `debian.jpg` | `desktop-base` 13.0.4, `ceratopsian-theme` (Debian archive) | GPL-2+, Debian Desktop Team / Jonathan Carter |
| `debian-dark.jpg` | `desktop-base` 13.0.4, `moonlight-theme` (Debian archive) | GPL-2+, Juliette Taka Belin / Debian Desktop Team |
| `kali.jpg` | `kali-wallpapers-2026` 2026.3.0, `kali-cubes-16x9.jpg` — the default selected by `kali-themes-common` | GPL-3.0+, Offensive Security (Kali trademarks apply) |
| `kali-dark.jpg` | `kali-wallpapers-2026` 2026.3.0, `kali-hack-16x9.jpg` | GPL-3.0+, Offensive Security (Kali trademarks apply) |
| `fedora.jpg` | `f44-backgrounds-base` 44.0.0, `f44-01-day.jxl` (Fedora archive) | CC-BY-SA-4.0, Fedora Design Team |
| `fedora-dark.jpg` | `f44-backgrounds-base` 44.0.0, `f44-01-night.jxl` | CC-BY-SA-4.0, Fedora Design Team |
| `opensuse.jpg` | `wallpaper-branding-openSUSE` 84.87.20240405, `openSUSEdefault` light | openSUSE branding package; see the source package metadata |
| `opensuse-dark.jpg` | `wallpaper-branding-openSUSE` 84.87.20240405, `openSUSEdefault` dark | openSUSE branding package; see the source package metadata |
| `archlinux.jpg` | `archlinux-wallpaper` 1.6.1-7 (official Arch package), `archwaveinv.png` (light) | CC0, rhysperry111 / Arch Linux |
| `archlinux-dark.jpg` | `archlinux-wallpaper` 1.6.1-7 (official Arch package), `archwave.png` (dark) | CC0, rhysperry111 / Arch Linux |
| `void.jpg` | `void-artwork` 20221013 (official Void package), `void-logo.svg`, composed on a light background | Public Domain, Void Linux |
| `void-dark.jpg` | `void-artwork` 20221013 (official Void package), `void-logo.svg`, composed on a dark background | Public Domain, Void Linux |
| `alpine.jpg` | Official Alpine Linux logo from alpinelinux.org, composed on a light background | Alpine Linux logo / trademark belongs to the Alpine Linux project |
| `alpine-dark.jpg` | Official Alpine Linux logo from alpinelinux.org, composed on a dark background | Alpine Linux logo / trademark belongs to the Alpine Linux project |

Arch ships `archlinux-wallpaper`, and its official light/dark wave pair is
used above. Void and Alpine do not ship a desktop wallpaper package: the
Void images use the distro's official `void-artwork` logo, and the Alpine
images use the official Alpine logo, both composed on neutral backgrounds.
Distro names and logos are trademarks of their respective owners; these
assets are used only to identify the distro being installed.

The installer and these assets are distributed under the project's GPL-3.0
license. The wallpaper images above remain under their respective licenses.
