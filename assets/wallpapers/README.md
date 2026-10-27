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
| `archlinux.jpg` | Generated for Linux-for-Android from the Arch Linux logo (Simple Icons), light background | Logo: Simple Icons (CC0-1.0); Arch Linux trademark belongs to Arch Linux |
| `archlinux-dark.jpg` | Generated for Linux-for-Android from the Arch Linux logo (Simple Icons), dark background | Logo: Simple Icons (CC0-1.0); Arch Linux trademark belongs to Arch Linux |
| `void.jpg` | Generated for Linux-for-Android from the Void Linux logo (Simple Icons), light background | Logo: Simple Icons (CC0-1.0); Void Linux trademark belongs to the Void Linux project |
| `void-dark.jpg` | Generated for Linux-for-Android from the Void Linux logo (Simple Icons), dark background | Logo: Simple Icons (CC0-1.0); Void Linux trademark belongs to the Void Linux project |
| `alpine.jpg` | Generated for Linux-for-Android from the Alpine Linux logo (Simple Icons), light background | Logo: Simple Icons (CC0-1.0); Alpine Linux trademark belongs to the Alpine Linux project |
| `alpine-dark.jpg` | Generated for Linux-for-Android from the Alpine Linux logo (Simple Icons), dark background | Logo: Simple Icons (CC0-1.0); Alpine Linux trademark belongs to the Alpine Linux project |

Arch, Void and Alpine do not ship a single canonical desktop wallpaper, so
the generated images provide a recognisable branded default while keeping the
install small and deterministic. Distro names and logos are trademarks of
their respective owners; these assets are used only to identify the distro
being installed.

The installer and these assets are distributed under the project's GPL-3.0
license. The wallpaper images above remain under their respective licenses.
