<div align="center">
  <h1>🐧 Linux for Android Manager</h1>
  <p><b>The ultimate automated script to install, manage, and configure a full Linux desktop environment on Android via Termux.</b></p>
  <p>
    <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Termux-blue?style=for-the-badge&logo=android" alt="Platform">
    <img src="https://img.shields.io/badge/Language-Bash-green?style=for-the-badge&logo=gnu-bash" alt="Language">
    <img src="https://img.shields.io/badge/License-GPL%203.0-orange?style=for-the-badge&logo=gnu" alt="License">
  </p>
</div>

<hr>

## 📖 Table of Contents
- [About the Project](#-about-the-project)
- [Key Features](#-key-features)
- [Installation](#-installation)
- [Older Devices (Android 5/6)](#-older-devices-android-56-eg-oppo-a37fw--verified-guide)
- [Usage Guide](#-usage-guide)
- [Troubleshooting](#-troubleshooting-phantom-process-killer)
- [Contributing](#-contributing)
- [License](#-license)

## 🌟 About the Project

Turning your Android device into a full-fledged Linux workstation has never been easier. **Linux for Android Manager** is a fully automated, interactive bash script that wraps around `proot-distro` to install, manage, backup, share, update, and configure highly customized graphical Linux environments directly on your smartphone or tablet.

Currently supported distributions:
- **Ubuntu** (apt)
- **Debian** (apt)
- **Kali Linux** (apt)
- **Arch Linux** (pacman)
- **Fedora** (dnf)
- **OpenSUSE** (zypper)
- **Void Linux** (xbps)
- **Alpine Linux** (apk, musl — recommended for Android 5/6, tiny & fast)

> **Android 5/6 devices (e.g. kernel 3.10):** the script auto-detects legacy
> devices, installs `proot-distro` v4.2.0 from source when the package is
> missing, forces VNC instead of Termux:X11, and skips VirGL. Only **Alpine**
> is verified working there — modern glibc distros (Debian bookworm, Ubuntu
> mantic, Fedora 39, …) fail at the first guest command on a 3.10 kernel.

## 🚀 Key Features

### The Ultimate Experience
- **True Linux Experience (Sudo):** Sets up a proper non-root user (`user`) with `sudo` privileges. Install packages just like on a real PC!
- **VirGL 3D Hardware Acceleration:** Automatically configures `virglrenderer-android`, passing 3D OpenGL rendering directly to your phone's physical GPU for incredibly smooth graphics.
- **Hardware Acceleration (Termux:X11):** Choose between traditional VNC (software rendering) or Termux:X11 for a much smoother, hardware-accelerated desktop experience.
- **Dynamic Display Settings:** Dynamically pick your screen resolution and UI scaling (Auto, 720p, 1080p, or Tablet size) to perfectly fit your device.

### Automation & Management
- **1-Click Universal Updater:** Never manually type update commands again! The Manager Menu automatically detects your distro and updates it in the background.
- **System Dashboard:** Instantly view your Android phone's RAM availability, Termux storage consumption, and CPU architecture right from the manager menu.
- **Advanced Audio Fixer:** A built-in debugger that dynamically restarts PulseAudio and forcefully binds it to TCP protocols to instantly resolve any audio crackling issues.
- **Hardware Accelerated Web Browsing:** Easily optimize Chromium directly from the menu to force hardware-accelerated video decoding (`--enable-gpu-rasterization`, `--use-gl=egl`), giving you silky smooth YouTube playback over VirGL.
- **Instant SSH Server:** Start a native SSH server on port 8022 directly from the menu, allowing you to seamlessly remote into your phone from your PC.

### Portability & Convenience
- **Portable Export & Import (Share with Friends!):** Export your fully customized Linux OS as a `.tar.gz` file into your Android `Downloads` folder. Your friends can place the file in their `Downloads` folder and use the "Import" button to instantly clone your exact setup!
- **Home-Screen Widgets:** If you use the `Termux:Widget` app, the script automatically generates a shortcut so you can launch your Linux desktop with one tap straight from your Android home screen!

## ⚙️ Installation

### Prerequisites
1. Download and install [Termux](https://f-droid.org/en/packages/com.termux/) from **F-Droid**. 
   > ⚠️ **Warning:** Do NOT use the Google Play Store version of Termux, as it is outdated and severely broken.

### Quick Start
Copy and paste this snippet into your Termux terminal:

```bash
pkg update -y && pkg install git -y
git clone https://github.com/pdev-labs/Linux-For-Android.git
cd Linux-For-Android
chmod +x install_linux.sh
./install_linux.sh
```

## 📱 Older Devices (Android 5/6, e.g. Oppo A37fw) — Verified Guide

This configuration was tested end-to-end on Android 5.1.1 (kernel 3.10, aarch64).

### 1. Install the right Termux
- Current Termux requires Android 7+. On Android 5/6 install **Termux 0.118**
  (last build with Android 5 support) from the **F-Droid archive** — not the
  Play Store, not the latest F-Droid build.
- If packages 404, run `termux-change-repo` and pick a working mirror.

### 2. What the script handles automatically
- Detects legacy devices (`LEGACY MODE` banner) and installs **proot-distro
  v4.2.0** from source when the package is missing or broken.
- Forces **VNC** (Termux:X11 needs Android 8+, VirGL is unavailable).
- Skips GPU/audio backends gracefully when their packages don't exist.

### 3. Recommended choices in the wizard
- **Distro:** Alpine (option 8, musl — tiny, ~35 MB) or Debian, which
  auto-switches to **bullseye** on legacy devices. Do NOT pick Ubuntu,
  Fedora, Kali, Arch or Void here: their modern glibc cannot execute on a
  3.10 kernel (verified: instant failure at the first guest command), and
  Kali has no legacy plugin at all.
- **Desktop:** `None (CLI only)` for 1–2 GB RAM phones; LXDE/XFCE + VNC only
  if you have headroom (needs a VNC Viewer app, password `root`).
- **Software selector:** keep it light (`git`, `htop`…). Skip browsers and
  LibreOffice on old phones.
- Keep **~1 GB free** before installing; CLI systems are small (Alpine
  ~35 MB, Debian ~150 MB plus package cache).

### 4. Day-to-day notes
- `start-linux` / `terminal-linux` always ask: **root** or **user** terminal.
  Root is the default; pick user when you want the restricted-feeling shell.
- Install packages directly (`apk add` / `apt install`) — never `sudo`/`su`.
  From EITHER terminal you CAN: edit any file, configure services, and on
  Alpine also install packages (`apk` has no uid check). On apt distros
  (Debian/Ubuntu/Kali) installs need the ROOT terminal: `dpkg` refuses to
  run unless uid is 0, and the user shell runs as your normal uid. (The
  launchers warn you when you pick a user terminal there.)
  You CANNOT anywhere in proot: `sudo`/`su` or user
  switching (kernel `NO_NEW_PRIVS` flag — setuid can never work), `ping` /
  raw sockets, `mount`. The user shell is not restricted: it owns every
  file, so elevation is simply unnecessary.
- On Debian bullseye the installer already points `bullseye-security` at
  `archive.debian.org` (the suite is EOL and pruned from the main mirror).
- `fastfetch` does not exist in bullseye — use `neofetch`.
- Ignore `apt`/`dpkg` warnings about hardware, `systemd`, or `dbus` hooks
  failing — post-install hooks can't reach real hardware from proot and fail
  safely (a half-configured `dbus` daemon is normal and harmless).

## 💻 Usage Guide

When you run `./install_linux.sh`, it will launch the interactive Manager Menu where you can Install, Update, SSH, view the Dashboard, Export, Import, Backup, Restore, or Uninstall any supported distribution.

### Starting your Linux Desktop
Once installed, you never need to run the setup script again. Just type this anywhere in Termux:
```bash
start-linux
```
*(If you installed multiple OSs, it will automatically pop up a menu asking which one you want to boot!)*
If the install has a GUI, `start-linux` asks what you want: full desktop,
**root terminal only**, or **user terminal only** (no display/audio servers
started in terminal modes). CLI-only installs ask root vs user terminal.
Terminal choices default to root when you just press Enter (script-safe).

### Quick terminal without servers
```bash
terminal-linux
```
Opens a shell in a distro without touching PulseAudio, VirGL, or the
display server, then lets you pick the **root** or **user** terminal.
Handy for quick admin work and as a Termux:Widget shortcut (auto-created).

### Default Credentials & Privileges
- **GUI sessions run as:** `user` (VNC password: `root`)
- **`start-linux` / `terminal-linux` ask every time:** **root** terminal
  (default, full admin) or **user** terminal. Install packages directly
  (`apk add` on Alpine, `apt install` on Debian/Ubuntu, …).
- **`sudo` is a ritual-only shim** (`/usr/local/bin/sudo`, password `root`):
  it asks for the password, then runs your command unchanged. Real setuid
  elevation is impossible inside proot (see below) — and unnecessary, since
  you already own every file.
- **Why no sudo?** Android app processes carry the `NO_NEW_PRIVS` flag and
  proot cannot grant real root, so `sudo`/`su` can never work inside proot
  on any device. You already own every file, so elevation is unnecessary.
  (On Alpine the manager is `apk`, not `apt` — bare `apt` would resolve to
  Termux's host copy and fail to link.)

### Stopping your Linux Desktop
To safely kill the desktop, display servers, and audio systems, type:
```bash
stop-linux
```

## 🛠️ Comprehensive Troubleshooting Guide

This section covers common issues, warnings, and how to resolve them:

### 1. The "Phantom Process Killer" (Termux randomly crashes)
Starting in Android 12, Android limits background child processes. Since a Linux desktop requires many processes, Android may suddenly kill Termux (`[Process completed (signal 9)]`).
**Fix (Android 14+):**
1. Open Android **Settings** > **About phone** > tap **Build number** 7 times.
2. Go to **Settings** > **System** > **Developer options**.
3. Toggle **Disable child process restrictions** to **ON** and restart Termux.
*(For Android 12/13, search online for "Termux ADB disable phantom process" to apply the fix via a PC).*

### 2. `sudo` / `su` fail inside the distro ("no new privileges", wrong ownership)
The real binaries can never work here, so every install now ships a
**ritual-only `sudo` shim** instead (no real `sudo` package is installed):
- `sudo <cmd>` asks for the install-time password (`root`, 3 tries like
  the real thing) and then runs the command with your current identity,
  passing through its exit status. Flags `-i`/`-s` (shell), `-u` (only
  yourself/root), `-v`, `-n`, `-p`, `-E` behave sanely; switching to any
  other account is refused with an explanation.
- **Why?** Android app processes carry the `NO_NEW_PRIVS` flag and proot
  cannot grant real root, so `sudo`/`su` can never elevate inside proot on
  any device (verified: even nested re-execution fails, since no host
  binary can link under the outer session). You already own every file, so
  elevation is unnecessary — the shim exists so muscle memory keeps working.

### 3. Scary `apt` errors during installation
While installing packages, you might see red errors like:
- `Failed to scan devices: Permission denied`
- `Failed to write database /usr/lib/udev/hwdb.bin`
- `Failed to send reload request`
**Fix:** Ignore them! These are completely normal. Linux packages try to communicate with physical hardware or the `systemd` init process during installation. Since you are safely contained on Android without direct hardware/init access, these post-installation hooks fail safely without affecting your desktop.

### 4. "Cannot establish any listening sockets - Make sure an X server isn't already running"
**Symptom:** You type `start-linux` but it immediately fails with this error.
**Fix:** The Termux:X11 display server is stuck running in the background from a previous session. Simply run `stop-linux` in your terminal to easily clean up the ghost processes, then run `start-linux` again.

### 5. Termux:X11 app stays open after running `stop-linux`
**Fix:** This is normal! `stop-linux` safely shuts down the background Linux servers, but it cannot forcefully close the Android App window itself due to Android security sandboxing. Simply swipe the Termux:X11 app away in your Android "Recent Apps" menu.

### 6. Installation seems frozen at "Setting up elementary-xfce-icon-theme..."
**Fix:** Be patient! This specific package contains tens of thousands of tiny icon files. Because `proot` must translate every single file operation via your phone's CPU, unpacking thousands of files takes significantly longer than on a native PC (sometimes 10 to 20 minutes on mid-range phones). Keep Termux open and let it finish!

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! 
If you want to improve this project, please fork the repository and submit a pull request.

## 📝 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. 
Any derivatives, forks, or modifications of this project must also remain open-source and be distributed under the same license.
