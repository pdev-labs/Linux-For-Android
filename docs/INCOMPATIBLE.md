# Software that LFA cannot run

This page lists software and capabilities that **cannot work** inside
Linux-for-Android (LFA), or that work only in a reduced form. It is deliberately
blunt: a false "it works" is worse than an honest failure.

LFA runs a Linux userspace under Termux and `proot` on top of Android. That
gives you paths, a root filesystem, users and most ordinary programs. It does
**not** give you the Android kernel, real init, namespaces, device nodes, or
the phone's GPU/userland drivers.

> Short rule: **userspace-visible state can be shimmed; kernel-visible
> capabilities cannot.** `lfa compat` can make a program believe a missing
> *service* exists. It cannot make the kernel provide a missing *facility*.

## Hard blockers

These need something the Android app sandbox does not expose. They fail even
on a fast phone.

| Software or category | Why it cannot work |
|---|---|
| `systemd`, `systemctl`, `journalctl`, `loginctl`, `systemd-networkd`, `systemd-resolved`, `systemd-timesyncd` | proot has no PID 1, cgroups, unit dependency graph, or real service manager. `lfa compat` provides a small optional CLI supervisor, not systemd. |
| `snapd`, Snap Store, all snap packages, Ubuntu's snap-only Firefox/Chromium | snapd needs systemd, mounts and `CAP_SETFCAP`. There is no confinement. `lfa compat` maps a few named snaps to distro packages instead. |
| Flatpak, Flathub applications, any bubblewrap-sandboxed application | needs user namespaces and a working sandbox. LFA can only run the program unsandboxed when the program has a fallback. |
| Docker, Podman, containerd, LXC/LXD, libvirt, VirtualBox, VMware, QEMU/KVM, the Android Emulator, Waydroid | need namespaces, cgroups, `/dev/kvm`, or a host daemon. A proot wrapper is not Docker-compatible and is not presented as one. |
| Sway, Hyprland, Wayfire, GNOME Wayland, KDE Wayland, any Wayland compositor | LFA provides X11 (Termux:X11) or VNC. There is no Wayland compositor integration. |
| Real `sudo`/`su`/setuid, PAM, real `mount`, real `chroot`, `unshare` | Android marks app processes `NO_NEW_PRIVS`; setuid cannot elevate. LFA's `sudo` is a password ritual plus a narrow `uid0` library for tools such as `dpkg`. |
| Kernel modules, DKMS, eBPF, `perf`, `ftrace` | an Android app cannot load modules or control the kernel. |
| `tcpdump`, packet capture, `nmap -sS`, raw sockets | Termux has no raw-socket capability. `nmap -sT` (a normal connect scan) may work. |
| `iptables`, `nftables`, `ufw`, `firewalld` enforcement | no `CAP_NET_ADMIN` and no netfilter control. A "success" stub would be a dangerous no-op, so LFA does not provide one. |
| WireGuard, OpenVPN, Tailscale/ZeroTier **inside the guest** | no `/dev/net/tun` or TUN/TAP. Userspace proxies are the only workaround. |
| CUDA, ROCm/HIP, GPU compute through the vendor runtime | no CUDA/ROCm runtime for Android, and no GPU device passthrough to the proot guest. See [GPU acceleration vs GPU compute](#gpu-acceleration-vs-gpu-compute). |
| VA-API, V4L2, NVDEC, hardware video encode/decode | the guest does not receive the hardware codec devices. Software decoding works. |
| Bluetooth/BlueZ, NFC, GPS as kernel devices, camera as `/dev/video*`, sensors, USB host as `/dev/bus/usb`, IR, fingerprint, telephony, Wi-Fi control | Android owns the hardware. Termux:API can expose some **Android framework** data (battery, location, camera files, sensor values), not kernel devices. |
| Real reboot/shutdown/suspend/hibernate, `fastboot`/flashing, ADB host, Magisk modules, real root | an app cannot control the Android system or bootloader. |
| Simultaneous X11 + VNC, or multiple displays | LFA uses display `:1` and VNC port `5901` only. |
| Foreign-architecture binaries: x86 on ARM, ARM on x86, ARM64 on 32-bit ARM | there is no CPU emulation. The guest runs at the phone's architecture. |

## Not supported or unreliable

These may start, or may work on some distros, but LFA does not promise them.

| Software or category | Caveat |
|---|---|
| Full GNOME session | experimental. `gnome-session` needs systemd/logind, so LFA starts `gnome-shell --x11` directly. Login/logout, screen locking, suspend/inhibit, UPower, portals, notifications and some Settings panels are missing or unstable. GNOME 49+ removed X11. Not offered on Alpine/Void or Android 5/6/7. |
| KDE Plasma, Cinnamon, Budgie, Deepin, Pantheon, LXQt | not offered or tested. Many assume systemd, Wayland, or a full session manager. |
| Steam, Proton, Wine games with anti-cheat or DXVK | no GPU/anti-cheat environment. Simple Wine applications may work, but this is not a supported target. |
| Blender GPU/Cycles CUDA/OptiX, DaVinci Resolve, OBS hardware encoders, GPU video editors | no CUDA/OptiX and no hardware encode. CPU rendering may work but is slow. |
| CUPS/USB printing, SANE scanners, Bluetooth audio | no hardware passthrough. |
| Android Studio with its emulator, VS Code Dev Containers, Docker Desktop | need KVM, Docker, or namespaces. |
| Snap-only Firefox/Chromium on Ubuntu | use Mozilla's tarball or the Debian Chromium build, as LFA's installer does. |
| VS Code on Alpine | no ARM64 build of the Microsoft package. Use `code-oss`. |
| VLC on Fedora default repositories | needs RPM Fusion. |
| GNOME Software, Ubuntu App Center, snap/Flatpak stores | depend on snapd or Flatpak. |
| Hardware-accelerated video in browsers | VirGL accelerates **rendering**, not the video decode block. Some sites still decode in software. |

## Android 5/6 and Android 7 limitations

| Item | Android 5/6 (SDK < 24) | Android 7.0/7.1 (SDK 24/25) |
|---|---|---|
| Termux packages | frozen/archived repositories; `proot-distro` may need the source fallback | modern packages |
| Ubuntu, Fedora, openSUSE, Void, Arch | modern glibc usually fails on the 3.10 kernel. Debian maps to bullseye; Alpine works. | generally usable |
| Kali | no legacy proot-distro plugin | usable |
| Termux:X11 | unavailable | **unavailable** (needs SDK 26) |
| Both backend | unavailable | **unavailable** |
| GNOME | unavailable | **unavailable** |
| VirGL / hardware acceleration | unavailable | may work, but not promised |
| Modern Electron apps and browsers | not guaranteed; old glibc and CPU limits | likely, subject to distro packages |

Android 7.0/7.1 is a real gap that older LFA versions missed: it is **not**
"legacy" for Termux packages, but it **is** too old for Termux:X11. LFA now
tracks those two cutoffs separately and automatically selects VNC.

## 32-bit ARM

Fedora, openSUSE, Void and Arch may not publish 32-bit ARM images. ARM64-only
vendor builds (VS Code, Firefox tarball, Antigravity) are unavailable on a
32-bit guest. Alpine, Debian, Ubuntu and Kali have 32-bit builds.

## GPU acceleration vs GPU compute

LFA's GPU path is **rendering acceleration**:

```text
guest app -> Mesa virpipe -> virgl -> virgl_test_server_android
          -> Android EGL/GLES -> phone GPU
```

It gives OpenGL/GLES drawing for desktops, browsers and editors. It does not
expose the vendor compute runtime, GPU device nodes, or command queues.

| Technology | Status in LFA |
|---|---|
| OpenGL/GLES rendering through VirGL | supported where the device supports VirGL |
| Software rendering (llvmpipe) | supported fallback |
| OpenCL on the CPU through POCL | optional, via `lfa compat enable opencl` |
| Vulkan on the CPU through Mesa lavapipe | optional, via `lfa compat enable vulkan` |
| OpenCL/Vulkan on the phone GPU | not enabled; research only |
| CUDA / ROCm / vendor GPU compute | unavailable |

## What Termux:API can and cannot provide

Termux:API talks to **Android framework services** under the normal app UID.
It is not a kernel or root bridge.

| Capability | Termux:API | What LFA gets |
|---|---|---|
| Battery / AC state | yes | real data for the `upower` shim |
| Location / GPS | yes | JSON bridge file |
| Camera | yes | a photo file, not `/dev/video0` |
| Sensors | yes | readings, not `/dev/iio` |
| Microphone / speaker | yes | recordings and Android playback, not ALSA/PulseAudio devices |
| Clipboard, notifications, vibrate, torch, share | yes | Android-side actions |
| Wi-Fi information | yes | connection/scan data, not full control |
| Telephony / SMS / contacts | yes, with permissions | Android APIs |
| USB | partial | `termux-usb` file descriptor + libusb, not `/dev/bus/usb` |
| Bluetooth | partial / version dependent | some Android APIs, not BlueZ HCI |
| Kernel modules, `mount`, namespaces, cgroups | no | unavailable |
| Raw sockets, TUN/TAP, iptables | no | unavailable |
| GPU/CUDA/ROCm, hardware codecs | no | unavailable |
| Real root or SELinux control | no | unavailable |

Use `lfa android status`, `lfa android test`, and `lfa android install` to see
what this device actually provides. The bridge writes files into
`$PREFIX/tmp`, which the guest sees as `/tmp` because LFA launches proot with
`--shared-tmp`.

## Emulator-verified vs device-verified

The CI matrix runs on GitHub-hosted Android emulators. That covers the
installer, CLI, backend switching, VNC/X11 startup, distro installs and most
API-level behaviour.

It does **not** fully cover:

- ARM64-only vendor builds and real ARM64 package availability
- Android 5/6 frozen Termux repositories (API 23 is the canonical legacy
  target; API 21/22 are best-effort)
- OEM phantom-process killers and battery policies
- real GPU, audio, thermal and performance behaviour
- real camera, Bluetooth, USB and sensor hardware

Those remain device checks. `docs/TEST-REPORT.md` records which claims are
emulator-verified and which are device-verified.

## Reporting a wrong entry

If a program in this list now works, or a program not listed fails, open an
issue with:

- distro and version
- Android version and architecture
- the exact command
- the relevant part of `~/start-linux-session.log` or the program's error
- the output of `lfa diagnostics`
