# Linux for Android troubleshooting guide

This is the long-form troubleshooting guide. The [README](../README.md) has the
short answers and the [known issues](../issues.md) list has every defect and
limitation; this page explains how to diagnose a failure, what the error
means inside proot, and how to verify the fix.

Everything here is for the manager (v1.7.x) running in Termux on Android.
Commands that say *inside the distro* are run in a guest shell opened with
`start-linux` → 2) Root terminal (or `terminal-linux`). Commands that say
*in Termux* are run before you enter the distro.

> Before you change anything: run `./install_linux.sh --diagnostics`.
> It writes `~/lfa-diagnostics-<date>.tar.gz` with the version, device, free
> space, installed instances, display processes, logs and redacted configs.
> Passwords and tokens are removed. If a fix makes things worse, you still
> have the evidence.

## Find your symptom

| What you see | Go to |
|---|---|
| Installer exits immediately, unknown option, permission denied | [§2.1](#21-installer-exits-immediately-or-will-not-start) |
| Download fails, checksum mismatch, `git clone` fails | [§2.2](#22-download-or-checksum-failure) |
| "Not enough free space" | [§2.3](#23-not-enough-free-space) |
| Red `apt`/`dpkg` noise during install | [§2.4](#24-red-apt-and-dpkg-output-during-install) |
| `dpkg: requested operation requires superuser privilege` | [§2.5](#25-dpkg-requested-operation-requires-superuser-privilege) |
| `unknown system group 'messagebus' in statoverride` | [§2.6](#26-unknown-system-group-messagebus-in-statoverride) |
| `snapd` will not configure (`CAP_SETFCAP`) | [§2.7](#27-snapd-will-not-configure) |
| Install looks frozen at an icon theme | [§2.8](#28-install-looks-frozen) |
| Install was interrupted or the phone rebooted | [§2.9](#29-install-was-interrupted) |
| `Cannot establish any listening sockets` | [§3.1](#31-cannot-establish-any-listening-sockets) |
| `No distributions installed` | [§3.2](#32-no-distributions-installed) |
| `Multiple distributions found` / `Choose one with -i NAME` | [§3.10](#310-lfa-needs-an-instance-name) |
| `start-linux now opens the advanced menu` | [§3.11](#311-the-start-linux-change-notice) |
| `Termux:X11 is still used by another installed distro` | [§3.9](#39-how-do-i-switch-between-termuxx11-and-vnc) |
| `Termux:X11 requires Android 8 or newer` | [§3.9](#39-how-do-i-switch-between-termuxx11-and-vnc) |
| Black screen, `Unable to contact settings server` | [§3.3](#33-black-screen-or-unable-to-contact-settings-server) |
| Desktop dies with `Gtk:ERROR ... Bail out!` | [§3.4](#34-desktop-dies-with-a-gtk-bail-out) |
| `Non UTF-8 locale` or apps exit with status 8 | [§3.5](#35-non-utf-8-locale) |
| No panel, no wallpaper, no window borders | [§3.6](#36-panel-wallpaper-or-window-borders-are-missing) |
| `stop-linux` leaves Termux:X11 open | [§3.7](#37-stop-linux-leaves-termuxx11-open) |
| `start-linux` starts a second desktop | [§3.8](#38-start-linux-starts-a-second-desktop) |
| Need to switch between Termux:X11 and VNC | [§3.9](#39-how-do-i-switch-between-termuxx11-and-vnc) |
| `lfa` says no instance, or a command does nothing | [§3.10](#310-lfa-needs-an-instance-name) |
| `start-linux` shows a notice about `linux` and `lfa` | [§3.11](#311-the-start-linux-change-notice) |
| Termux:X11 shows "display :1 not found" | [§4.1](#41-termuxx11-says-display-1-not-found) |
| Screen is the wrong size or rotated | [§4.2](#42-wrong-resolution-or-rotation) |
| Touch pointer is offset, keys are missing | [§4.3](#43-touch-pointer-keyboard-and-clipboard) |
| VNC black screen or connection refused | [§4.4](#44-vnc-does-not-connect-or-shows-black) |
| Wayland session fails, or Hyprland prints `CBackend::create() failed!` | [§4.5](#45-a-wayland-session-or-hyprland-fails) |
| VS Code / Chromium / Antigravity do nothing | [§5.1](#51-electron-apps-do-nothing-at-all) |
| Firefox or Chromium shows a sandbox warning | [§5.2](#52-firefox-or-chromium-shows-a-sandbox-warning) |
| App is missing from the XFCE menu | [§5.3](#53-app-is-missing-from-the-menu) |
| App window is off-screen | [§5.4](#54-app-window-opens-off-screen) |
| App closes when the terminal closes | [§5.5](#55-app-closes-with-the-terminal) |
| No sound | [§5.6](#56-no-sound) |
| Chromium video is black or GPU rendering crashes | [§5.7](#57-chromium-video-is-black-or-crashes) |
| AppImage: `failed to open /dev/fuse` or nothing starts | [§5.9](#59-an-appimage-does-not-start) |
| GNOME does not start | [§6.1](#61-gnome-experimental-does-not-start) |
| `sudo` rejects the password or you forgot it | [§7.1](#71-sudo-rejects-the-password) |
| `groups: cannot find name for group ID` | [§7.2](#72-groups-cannot-find-name-for-group-id) |
| Permission denied writing files | [§7.3](#73-permission-denied-writing-files) |
| Android files are not visible in the distro | [§8.1](#81-android-files-are-not-visible-in-the-distro) |
| Disk full | [§8.2](#82-disk-full) |
| Backup, restore, export, import fails | [§8.3](#83-backup-restore-export-and-import) |
| Uninstalled distro still appears | [§8.4](#84-uninstalled-distro-still-appears) |
| Guest has no internet or DNS fails | [§9.1](#91-guest-has-no-internet) |
| `apt` TLS or clock errors | [§9.2](#92-apt-tls-or-clock-errors) |
| SSH from the PC fails | [§9.3](#93-ssh-from-the-pc-fails) |
| SSH dies after a few minutes | [§9.4](#94-ssh-dies-randomly) |
| Install or desktop is very slow | [§10.1](#101-everything-is-slow) |
| Android kills Termux (signal 9) | [§10.2](#102-android-kills-termux-signal-9) |
| Phone sleeps and the session dies | [§10.3](#103-phone-sleep-and-battery-optimisation) |
| Which update command should I use? | [§11.1](#111-manager-update-distro-update-or-menu-12) |
| Everything is broken, how do I recover? | [§12](#12-recovery-ladder) |
| I need to report this | [§13](#13-reporting-a-bug) |

## 1. Collect evidence first

Most failures have one line in a log that identifies them. Collect these
before guessing.

### 1.1 Version and inventory

```bash
cd ~/Linux-For-Android
./install_linux.sh --version
./install_linux.sh --list
```

`--list` prints the instance names exactly as `proot-distro` knows them. A
custom instance name (for example `ubuntu-2`) is not the same as `ubuntu`; use
the name from this output in every later command.

### 1.2 Where the logs are

| Log | Path | Written when |
|---|---|---|
| Manager debug log | `~/.config/linux-for-android/debug.log` | only with `--debug` |
| Desktop session | `~/start-linux-session.log` inside the distro | every `start-linux` |
| VNC server | `$PREFIX/tmp/lfa-vnc-<instance>.log` | VNC installs |
| VNC session | `~/.vnc/*.log` inside the distro | VNC installs |
| Guest setup script | printed by `--debug`; kept for inspection | `--debug` |
| Diagnostics bundle | `~/lfa-diagnostics-<date>.tar.gz` | on request |

Find the guest logs from Termux without knowing the rootfs layout:

```bash
find "$PREFIX/var/lib/proot-distro" -name start-linux-session.log 2>/dev/null
find "$PREFIX/var/lib/proot-distro" -path '*/.vnc/*.log' 2>/dev/null
```

Inside the distro, read the last lines first. The first error is often
buried above a cascade of warnings:

```bash
tail -n 60 ~/start-linux-session.log
```

### 1.3 Display checks

Inside the distro, with the desktop supposedly running:

```bash
echo "$DISPLAY"                       # expect :1
xdpyinfo >/dev/null 2>&1 && echo X-OK || echo X-FAIL
xwininfo -root -tree | head -n 40     # does your app have a window?
pgrep -af 'xfce4-session|xfwm4|xfce4-panel|Xvnc|gnome-shell'
```

In Termux, on the host side:

```bash
pgrep -af 'termux-x11|Xvnc'
ls -l "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.X1-lock" 2>/dev/null
```

A live server owns `X1` and `.X1-lock`. A stale socket with a dead PID is the
cause of the "listening sockets" error in §3.1.

### 1.4 Debug a first install

```bash
./install_linux.sh --debug
```

`--debug` keeps the generated guest script and appends a trace to
`~/.config/linux-for-android/debug.log`. Use it only while reproducing a
problem; normal installs stay quiet.

## 2. Installation problems

### 2.1 Installer exits immediately or will not start

Symptom: `./install_linux.sh` prints `Permission denied`, `No such file or
directory`, or `Unknown option`.

Why: the file was downloaded without the executable bit, the clone is
incomplete, or the command was run in the wrong directory.

Fix:

```bash
cd ~/Linux-For-Android
chmod +x install_linux.sh
bash install_linux.sh --version
```

If `--version` works, run `./install_linux.sh`. If it does not, re-clone:

```bash
cd ~
rm -rf Linux-For-Android
git clone --depth 1 https://github.com/pdev-labs/Linux-For-Android.git
cd Linux-For-Android && chmod +x install_linux.sh && ./install_linux.sh
```

Verify: `Linux for Android Manager 1.7.1` (or newer) is printed.

### 2.2 Download or checksum failure

Symptom: `wget`/`curl` errors, `proot-distro install` cannot fetch the
rootfs, or `sha256sum -c SHA256SUMS` fails.

Why: a mirror is unreachable, the connection dropped, or the asset was
truncated.

Fix:

1. Test the network in Termux: `curl -I https://github.com`.
2. Re-download the release asset and verify it:

   ```bash
   gh release download v1.7.1 -R pdev-labs/Linux-For-Android
   sha256sum -c SHA256SUMS
   ```

3. If GitHub is blocked, use a mirror or a VPN for the download; the rootfs
   itself comes from the distro's official image host.
4. Retry `proot-distro install <distro>`; a half-written rootfs is detected and
   the installer asks you to remove it.

Verify: the checksum prints `install_linux.sh: OK`.

### 2.3 Not enough free space

Symptom: the installer refuses to start and prints `Not enough free space:
this install needs about N MB`.

Why: proot copies the rootfs and then unpacks packages; a desktop needs
more than the downloaded image. Requirements: ~1 GB CLI, ~2.5 GB desktop,
~3.5 GB GNOME.

Fix:

```bash
df -h "$PREFIX"
du -sh "$PREFIX"/var/lib/proot-distro/* 2>/dev/null
```

Free space by removing unused instances or backups:

```bash
./install_linux.sh          # 3) Manager → 10) Uninstall
rm -f ~/*-backup.tar.gz
pkg clean
```

Inside an existing distro: `apt clean` (Debian family) or `apk cache clean`
(Alpine). Do not delete `$PREFIX/var/lib/proot-distro` by hand. That can leave
`proot-distro list` showing a ghost instance (§8.4).

### 2.4 Red `apt` and `dpkg` output during install

Symptom: messages such as:

- `Failed to scan devices: Permission denied`
- `Failed to write database /usr/lib/udev/hwdb.bin`
- `Failed to send reload request`
- `Creating group 'kvm' with GID 993`

Why: package post-install scripts talk to physical hardware, udev and
systemd. None of those exist inside proot. The hooks fail safely.

Fix: none. These lines are expected and do not mean the install failed.
Scroll to the final `Installation complete` message. Only act if `dpkg` exits
non-zero or leaves packages half-configured (§2.5, §2.6).

### 2.5 `dpkg: requested operation requires superuser privilege`

Symptom: `apt update` works, but `apt install` fails in a user shell
with this exact message.

Why: `dpkg` refuses to run unless uid is 0. The user shell runs as your
normal uid; proot cannot elevate it.

Fix: use the root terminal (option 2 in `start-linux`), or prefix with
the sudo shim:

```bash
sudo apt install -y <package>
```

The shim accepts the user password set during installation and emulates uid 0
for `dpkg`. It is not real privilege elevation; it cannot give you access to
anything you do not already own.

Verify: `dpkg -l <package>` shows `ii` (installed, configured).

### 2.6 `unknown system group 'messagebus' in statoverride`

Symptom: every `apt install` aborts with a `dpkg` fatal error naming a
group that does not exist, even as root. `apt update` still works.

Why: `/var/lib/dpkg/statoverride` contains a row for a user/group that is
missing in this guest. `dpkg` validates the file on every run and treats a
missing group as fatal. Old installers seeded dbus's `messagebus` row on
CLI-only installs where dbus was never installed.

Fix: update the manager (`git pull`), then run 3) Manager → 0) Repair a
Distro or 12) Apply Latest Fixes. The Doctor prunes bad rows, installs
the proot-safe `dpkg-statoverride` shim and finishes half-configured packages.

Manual one-liner inside the guest as root:

```bash
sed -i '/dbus-daemon-launch-helper/d' /var/lib/dpkg/statoverride
apt-get -f install
```

Verify: `apt install -y htop` completes without the statoverride error.

### 2.7 `snapd` will not configure

Symptom: `dpkg: error processing package snapd (--configure) ...
unable to set CAP_SETFCAP effective capability`, and every later `apt` command
stops on the same package.

Why: snapd needs setuid helpers, mount namespaces and a running systemd.
proot provides none of them. Snap packages cannot work here.

Fix: update the manager and run 0) Repair a Distro; it purges snapd and
pins it off. Manually:

```bash
sudo dpkg --purge --force-all snapd
sudo apt-get -f install
```

Verify: `apt install -y <something>` no longer warns about snapd.
Removing snapd does not remove an already-installed desktop; `ubuntu-desktop`
is only a metapackage.

### 2.8 Install looks frozen

Symptom: the log has not moved for several minutes, most often at
`Setting up elementary-xfce-icon-theme`.

Why: that package contains tens of thousands of tiny icon files, and proot
translates every file operation through the phone CPU. 10 to 20 minutes is
normal on mid-range hardware, and longer on Android 5/6.

Fix: leave Termux in the foreground, keep the phone charging and do not
kill the process. Check that it is alive and doing work:

```bash
ps -o pid,etime,pcpu,comm -C dpkg -C apt -C proot 2>/dev/null | tail -n 5
```

If there is no CPU use and no log growth for 20+ minutes, the install is
genuinely stuck. See §2.9. Do not interrupt an install that is still
unpacking.

### 2.9 Install was interrupted

Symptom: the phone rebooted, Termux was killed, or you pressed Ctrl+C
during package setup. `proot-distro list` shows the instance but
`start-linux` fails.

Why: the rootfs exists but package configuration did not finish.

Fix, in this order:

1. Update the manager and run 0) Repair a Distro. It runs
   `dpkg --configure -a`, `apt-get -f install` and the statoverride repair.
2. If the instance does not boot at all, back up what you can, then
   10) Uninstall, 1) Install and 7) Restore.
3. A backup made before the failure is the safest path; see §8.3.

Verify: `start-linux` reaches the desktop and the session log has no
`dpkg` or `apt` error.

### 2.10 Package not found after installation

Symptom: `apt install <app>` says `Unable to locate package`, or the ISO
of a distro release is EOL and its repositories return 404.

Why: the image is old, the package name differs by distro, or the clock is
wrong (§9.2).

Fix:

```bash
sudo apt update
sudo apt install -y <package>
```

Check the name for your distro (the README's [software
section](../README.md#software-and-app-fixes) has the table), then refresh the
manager with 12) Apply Latest Fixes if the image predates the current
package list. For Termux itself, `termux-change-repo` switches to a working
mirror.

## 3. Starting and stopping the desktop

### 3.1 `Cannot establish any listening sockets`

Symptom: `start-linux` immediately prints *"Cannot establish any listening
sockets - Make sure an X server isn't already running"*.

Why: a display server from an earlier session is still alive, or it died
and left `X1`/`.X1-lock` behind. Android can kill the server without letting it
clean up.

Fix:

```bash
stop-linux
```

`stop-linux` kills the session, the display server and PulseAudio, then
removes stale sockets. Start again. If it still fails, inspect and remove only
the stale files:

```bash
pgrep -af 'termux-x11|Xvnc'
ls -l "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.X1-lock"
```

If no matching process is alive, remove `$PREFIX/tmp/.X11-unix/X1` and
`$PREFIX/tmp/.X1-lock`, then run `start-linux`. Do not remove them while a
server is running. Two servers on `:1` cannot coexist.

Verify: `xdpyinfo` inside the distro prints dimensions.

### 3.2 `No distributions installed`

Symptom: `start-linux` prints that no distributions are installed, but the
installer said it finished.

Why: the instance name in the launcher does not match the folder
`proot-distro` created, or the install was into a custom name that was later
removed.

Fix:

```bash
./install_linux.sh --list
ls "$PREFIX/var/lib/proot-distro/containers" 2>/dev/null
ls "$PREFIX/var/lib/proot-distro/installed-rootfs" 2>/dev/null
```

Install again if the list is empty. If the name is present, run 12) Apply
Latest Fixes. It regenerates `start-linux` from the actual instance list.

### 3.3 Black screen or "Unable to contact settings server"

Symptom: Termux:X11 opens, `start-linux` says the desktop started, but you
see only black or an XFCE error. The log contains
`dbus-update-activation-environment: unable to connect to D-Bus`.

Why: `dbus-launch` forks a daemon that dies under proot, and some images
ship an empty `/etc/machine-id`, which prevents D-Bus from starting.

Fix: update to v1.5.6+ and run 12) Apply Latest Fixes. The launcher
prefers `dbus-run-session` and the installer generates `machine-id`. Then:

```bash
stop-linux
start-linux
```

Verify: `pgrep -af dbus-daemon` inside the distro shows a session bus, and
the desktop is visible.

### 3.4 Desktop dies with a GTK bail out

Symptom: the session starts and immediately disappears.
`~/start-linux-session.log` contains:

```
Gtk:ERROR:...ensure_surface_for_gicon: assertion failed
Bail out!
```

or a `bwrap` command line.

Why: modern GTK (Kali 2026, Arch, Fedora 44, Void) decodes images through
glycin, which uses bubblewrap to sandbox its loader. proot cannot create
the namespaces, so the loader aborts GTK.

Fix: update the manager and run 12) Apply Latest Fixes. It installs a
`/usr/local/bin/bwrap` shim so glycin falls back to in-process decoding, and
installs `glycin-loaders` where the distro splits it out. Restart the desktop.

Verify: the log contains `WARNING: Glycin running without sandbox.` and
the desktop stays up. The warning is expected.

### 3.5 Non UTF-8 locale

Symptom: `Non UTF-8 locale (ANSI_X3.4-1968) is not supported!`, or GUI
apps exit with status 8 right after launch.

Why: the session was started without a UTF-8 locale. Some minimal images
do not set `LANG`.

Fix: run 12) Apply Latest Fixes (current launchers export
`LANG=C.UTF-8`), then `stop-linux` and `start-linux`. To verify inside the
distro:

```bash
locale        # LANG and LC_* should contain UTF-8
```

If the image lacks the locale, install it (Debian/Ubuntu:
`sudo apt install -y locales && sudo locale-gen C.UTF-8`).

### 3.6 Panel, wallpaper or window borders are missing

Symptom: the desktop background renders but there is no panel, no
wallpaper, or windows have no title bar and cannot be moved.

Why: one session component crashed (often the panel) or the window manager
never started. proot makes some panel plugins fail on first run.

Fix:

```bash
# inside the distro, root or user shell
pgrep -af xfwm4 || xfwm4 --replace &
pgrep -af xfce4-panel || xfce4-panel --restart &
```

Then run 12) Apply Latest Fixes to restore the wallpaper and autostart
entries. If the panel keeps crashing, read its output:

```bash
xfce4-panel --quit
xfce4-panel
```

Missing borders specifically mean `xfwm4` is not running; the command above
fixes that until the next session. If it recurs, reinstall the desktop
packages through the manager.

### 3.7 `stop-linux` leaves Termux:X11 open

Symptom: `stop-linux` finished, but the Termux:X11 app window is still on
screen.

Why: Android does not allow one app to close another app's window.
`stop-linux` stops the Linux servers, not the Android activity.

Fix: swipe Termux:X11 away from Recents. The next `start-linux` reuses
the app. This is normal and not a leak.

### 3.8 `start-linux` starts a second desktop

Symptom: windows from two sessions appear, or the screen shows only a cross
cursor because no window manager won display `:1`.

Why: more than one `xfce4-session` (or LXDE/MATE session) was started for the
same instance. Two session managers compete for the window manager, and the
desktop that loses leaves the X root cursor, which is a cross.

Fix: current versions refuse to start a session when one is already running:

```text
A desktop for ubuntu is already running on display :1.
  stop it:    stop-linux -i ubuntu
  restart it: linux -i ubuntu --restart
```

`--restart` stops the old session (including its guest proot wrapper) and
starts a fresh one. `stop-linux` now kills the desktop session process, not
only the X server, so a stale session cannot survive a stop or a backend
switch.

If the screen is still a lone cross cursor with exactly one session, check
for a stuck session child:

```bash
ps -eo pid,ppid,stat,cmd | grep -E 'gpgconf|gpg-connect-agent'
```

`xfce4-session` runs `gpgconf --kill gpg-agent` and
`gpgconf --launch gpg-agent` before it starts `xfwm4`. Under proot both can
block forever, which is why the desktop never gets a window manager. Current
versions disable GPG/SSH agent startup in the user's `xfce4-session` channel
(`~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml`) and also
install `/usr/local/bin/gpgconf`, which stops the agent directly and starts
nothing inside a GUI session. If you upgraded from an older version, run
`lfa fix -i NAME` (or menu 12) once.

### 3.9 How do I switch between Termux:X11 and VNC?

If both backends are installed, `linux` and `start-linux` show a desktop entry
for each one. Pick the backend you want. After a desktop start, the manager
remembers the choice and preselects it next time. Terminal-only sessions do not
change it.

To change the installed backend itself:

```bash
lfa switch both -i <instance>          # install both, keep everything
lfa switch x11  -i <instance>          # use X11, keep VNC packages
lfa switch vnc  -i <instance> --remove-old
```

`--remove-old` removes the packages of the backend you are leaving. The new
backend is installed first. Termux:X11 is a host package shared by every
distro, so if another instance still uses it, the switch keeps the package and
reports `Termux:X11 is still used by another installed distro; keeping the host
packages`. This instance still switches to VNC; add `--force` to remove the
package anyway, which breaks the other distro's desktop. The same operation is
menu 14, **Change Display Backend**. The two backends share display `:1` and
port `5901` and cannot run together. Starting one backend stops the other
backend's server on `:1` automatically; if a different instance already serves
VNC on port `5901`, start refuses instead of connecting to it and reporting
success.

If a desktop was running when you switch, it is restarted on the new backend.
Use `--no-start` to leave it stopped, or start it yourself with
`linux -i <instance>`. A switch no longer leaves an empty display behind, so
opening Termux:X11 after the switch shows the desktop instead of a lone cross
cursor.

If only one backend was installed by an old version, menu 12 can add the other
one without touching packages. On Android 5/6, X11 and Both are refused with
an explanation; stay on VNC.

### 3.9a Android storage shows an X, and chmod fails

Symptom: Thunar shows a gray X on every folder under `/storage/emulated/0`
or `~/storage`, but the folders open and files read normally. `chmod +x`
does nothing.

The X is Thunar's `emblem-unreadable`. Android mounts shared storage as
`1023:1023` with mode `2770`, and the desktop user was outside group 1023.
The access itself works through proot, so the warning is false. Run:

```bash
lfa storage fix -i <instance>
lfa start -i <instance> --restart
```

The fix gives the desktop user gid 1023 as its primary group, recreates the
storage links, and adds a Thunar bookmark and desktop shortcut.

`chmod` cannot work on `/storage/emulated/0`. Android generates the permission
bits and mounts the tree `noexec`, so the mode is ignored even as root. Keep
scripts and binaries in the guest, or run them with:

```bash
lfa storage exec /storage/emulated/0/script.sh
lfa storage exec --interpreter python3 /storage/emulated/0/tool.py
```

`lfa storage status -i <instance>` shows the Termux permission, guest group,
write access, and the chmod result.

The same helper is installed in the guest as `lfa-run-file`. Thunar also gets
a **Run in Linux** entry in the right-click menu for files under shared
storage; it opens a terminal, runs the file from a copy in `/tmp`, and keeps
the output on screen.

### 3.9b Android/data and Android/obb print Permission denied

Symptom: `ls /storage/emulated/0/Android/data` prints `Permission denied`,
and the folders do not open in Thunar.

Android 11 and later block those two folders for every app, including Termux.
The guest inherits Termux's identity, so LFA cannot open them directly.
`chmod`, a bind mount, and "All files access" do not change this. adb runs as
the shell user, which is allowed in:

```bash
lfa storage data status
lfa storage data list
lfa storage data pull com.example.app both
```

The command copies the folders into
`/storage/emulated/0/Android-backup/<package>`, where the guest can read them.
From a PC, run `adb tcpip 5555` once to let Termux's adb connect to the phone.
The connection lasts until the phone reboots; after that, run the command
again or pair Termux's adb with Wireless debugging.

### 3.10 `lfa` needs an instance name

Symptom: `lfa switch vnc` prints `Multiple distributions found. Choose one
with -i NAME`, or a command reports that a name is not installed.

Why: `lfa` never guesses when a command changes one distribution. `lfa start`,
`lfa shell`, and `lfa stop` may reuse the last started instance, but install,
switch, autostart, update, doctor, backup, restore, and remove need an explicit
target when several exist.

Fix: add `-i` (short for `--instance`):

```bash
lfa switch vnc -i ubuntu
lfa status -i ubuntu --json
lfa list
```

`lfa list` shows the exact names. Names are also the directory names under
`$PREFIX/var/lib/proot-distro/`.

### 3.11 The `start-linux` change notice

Symptom: every interactive `start-linux` run prints a short notice about
`linux`, `lfa`, and the advanced menu.

Why: `start-linux` kept its old behaviour, but the new daily commands are
`linux` (desktop) and `lfa` (everything else). The notice is shown once per
interactive classic run so existing users can find them.

Fix: hide it permanently with `lfa notice off`. `lfa notice on` brings it back,
and `lfa notice status` reports the current value. For one run use
`start-linux --no-notice`; for scripts and widgets use `LFA_NO_NOTICE=1`.
`linux`, Termux:Boot, and non-interactive runs never print it. The preference
is stored in `~/.config/linux-for-android/preferences.conf`.

## 4. Display and input

### 4.0 X11 is refused on Android 7.0/7.1

Symptom: on a device reporting Android SDK 24 or 25, `lfa install --backend
x11`, `lfa switch x11`, `lfa autostart x11`, or menu 14 says:

```text
Termux:X11 requires Android 8 (SDK 26) or newer.
```

Why: Termux packages work on Android 7, but Termux:X11 and GNOME do not. LFA
tracks the package cutoff (SDK < 24 is legacy) separately from the X11 cutoff
(SDK >= 26). This is not a bug and there is no setting that makes X11 work on
Android 7.

Fix: use VNC. The installer already selects it automatically on these
devices:

```bash
lfa switch vnc -i <instance>
lfa start -i <instance> --vnc
```

If a config was copied from another device and says `SERVER="x11"`,
`start-linux` refuses with the same message instead of trying to install an
unusable package. Edit the config or run `lfa switch vnc -i <instance>`.

### 4.1 Termux:X11 says display :1 not found

Symptom: `xdpyinfo` fails with `unable to open display ":1"`, or
`start-linux` reports that `termux-x11` is missing.

Why: the Termux:X11 app and the `termux-x11` host package are two
different things. The app provides the Android display; the package provides
the server binary. The app must also be installed from the same source as
Termux (F-Droid builds match; mixed signatures cannot share files).

Fix:

1. Install Termux:X11 from F-Droid (or the project's releases) on the
   phone.
2. In Termux: `pkg install x11-repo && pkg install termux-x11-nightly`.
3. Open the Termux:X11 app once, then run `start-linux`.

Verify: `pgrep -af termux-x11` shows the server, and `xdpyinfo` prints
`dimensions`.

### 4.2 Wrong resolution or rotation

Symptom: the desktop is tiny, stretched, or rotated 90°.

Why: Termux:X11 uses the Android surface size, and the session was saved
with a geometry from a different orientation or a previous device.

Fix: rotate the phone to the orientation you want, then restart:

```bash
stop-linux
start-linux
```

For VNC installs the geometry is fixed at install time. Change it in
`~/.vnc/config` (inside the distro), then restart. For X11, Termux:X11's
preferences can override the resolution; matching the phone's aspect ratio
avoids black bars.

### 4.3 Touch pointer, keyboard and clipboard

Touch pointer offset: usually a Termux:X11 preference. Use "pointer" or
"touchpad" mode rather than direct touch, and restart the app after changing
it. A rotated session can also offset the pointer until both the app and the
desktop agree on the orientation.

Missing keys (`|`, `~`, arrows): use the extra-keys row above the keyboard.
For a physical keyboard, `setxkbmap us` inside the distro fixes a wrong layout.
For non-US layouts, `setxkbmap -layout <code>`.

Clipboard: bridging is provided by the Termux:X11 app, not by the distro.
Update the app if copy/paste between Android and Linux does nothing. Inside the
guest, `xclip`/`xsel` can move text between X11 applications.

### 4.4 VNC does not connect or shows black

Symptom: the VNC viewer says connection refused, or connects to a black
screen.

Why: the server is on port 5901 (`:1`), the password file is missing or
in the old location, or `xstartup` exited before starting the desktop.

Fix:

1. In Termux, check the server and the port:

   ```bash
   pgrep -af Xvnc
   (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null && echo PORT-OK || echo PORT-FAIL
   tail -n 40 "$PREFIX/tmp/lfa-vnc-"*.log
   ```

2. Read `~/start-linux-session.log` and `~/.vnc/*.log` inside the distro.
3. If the password is missing, recreate it inside the distro:

   ```bash
   vncpasswd ~/.vnc/passwd
   mkdir -p ~/.config/tigervnc
   cp ~/.vnc/passwd ~/.config/tigervnc/passwd
   chmod 600 ~/.vnc/passwd ~/.config/tigervnc/passwd
   ```

4. Run 12) Apply Latest Fixes to regenerate the `xstartup` in both the
   legacy and modern TigerVNC locations.

Connect from the phone: VNC viewer → `127.0.0.1:5901`.

Connect from a PC: keep the server bound to the phone and tunnel it:

```bash
ssh -N -L 5901:127.0.0.1:5901 -p 8022 u0_aNNN@PHONE_IP
```

Then point the viewer at `localhost:5901`. Do not expose 5901 to the network;
VNC's password is not a substitute for SSH.

### 4.5 A Wayland session or Hyprland fails

Symptom: `lfa wayland start` exits, the session dies after a few seconds, or
Hyprland prints `CBackend::create() failed!`.

Why: the phone has no DRM render node that an app can open. Aquamarine, the
Hyprland back end, needs one for dmabuf. Sway can fall back to its X11 backend
and the pixman renderer, so it works where Hyprland cannot.

Fix:

1. Read the state and the logs:

   ```bash
   lfa wayland status -i arch
   lfa wayland doctor -i arch
   tail -n 40 ~/lfa-wayland.log
   tail -n 40 ~/.cache/lfa-wayland-sway-pixman.log
   ```

2. Check the render nodes. `render=none` means Hyprland cannot start:

   ```bash
   ls -l /dev/dri/
   ```

   On the Vivo V2437, `card0` is `system:system` mode `660` and there is no
   `renderD128`. A rooted device or a vendor build with a render node may
   differ.

3. Use the Sway profile, which keeps the Hyprland keybinds and look:

   ```bash
   lfa wayland session sway
   lfa wayland start -i arch --restart
   ```

4. If the session was killed from outside, clear the leftover processes:

   ```bash
   lfa wayland stop -i arch
   lfa wayland start -i arch
   ```

5. To go back to XFCE, run `lfa wayland session xfce`, or stop the session and
   use `lfa start -i arch`.

The full explanation and the verified device results are in
[WAYLAND.md](WAYLAND.md).

## 5. Applications

### 5.0 `systemctl`, `snap`, Docker, or CUDA still fail

Symptom: `systemctl` says the system was not booted with systemd; `snap`
says snapd is unavailable; Docker or CUDA fails even after a compatibility
shim was enabled.

Why: the compatibility layer replaces **userspace expectations**, not kernel
facilities. `lfa compat` can map units to a small supervisor, answer
`loginctl`, read battery data, map a few snaps to distro packages, and provide
CPU Vulkan/OpenCL. It cannot create PID 1, namespaces, cgroups, TUN/TAP,
netfilter, GPU compute runtimes, or kernel modules.

Check what is real:

```bash
lfa compat list
lfa compat explain systemctl
lfa compat explain docker
lfa compat status
```

Use the specific command, not a version flag, to test it. `docker --version`
prints a string even when the daemon cannot run; `docker info` is the honest
test.

If a program needs a missing service, enable the matching shim and read the
`limit:` line in `explain`. If the entry says `unsupported`, nobody can shim
it safely. Use a native Android app, a userspace proxy, or CPU rendering
instead. The full list is in [INCOMPATIBLE.md](INCOMPATIBLE.md).

### 5.0a Battery or location data is missing in the guest

Symptom: `upower -d` shows `unknown`, or the guest bridge file is empty.

Fix:

```bash
lfa android status
lfa android install          # termux-api client package
# install the Termux:API app from F-Droid and grant permissions
lfa android permissions
lfa android test
lfa android enable battery -i <instance>
lfa android refresh
```

The bridge writes `$PREFIX/tmp/lfa-android-battery.env` (and JSON files for
location/clipboard). The guest sees `/tmp/...` because LFA uses `--shared-tmp`.
Termux:API exposes Android framework data; it does not create
`/dev/video*`, `/dev/iio`, TUN/TAP, or GPU devices.

### 5.1 Electron apps do nothing at all

Symptom: `code`, `chromium` or `antigravity` returns immediately, prints
nothing, and no window appears. `code` may exit with status 0.

Why: Electron and Chromium need a setuid sandbox helper. proot cannot
create setuid binaries, so the zygote aborts. VS Code is the confusing case:
the CLI still returns 0, so it looks like the app is missing.

Fix: v1.7.1 writes `/usr/local/bin` wrappers with `--no-sandbox` and points
the desktop entries at them. On an older install run 12) Apply Latest
Fixes. To test the real cause without changing anything:

```bash
/usr/share/code/code --no-sandbox --disable-gpu --user-data-dir=/tmp/code-test
```

If a window appears, the wrapper is missing or not first in `PATH`. Check:

```bash
command -v code          # expect /usr/local/bin/code
grep -n no-sandbox /usr/local/bin/code
```

Recreate the wrapper manually if needed:

```bash
sudo tee /usr/local/bin/code >/dev/null <<'EOF'
#!/bin/sh
exec /usr/share/code/code --no-sandbox --disable-gpu "$@"
EOF
sudo chmod 755 /usr/local/bin/code
```

Chromium also needs `--disable-dev-shm-usage` because `/dev/shm` is small in
proot. The same rule applies to Antigravity.

Verify: the window is listed:

```bash
xwininfo -root -tree | grep -i 'visual studio\|chromium\|antigravity'
```

### 5.2 Firefox or Chromium shows a sandbox warning

Symptom: Firefox displays *"The security sandbox is disabled. Your
configuration is unsupported and less secure."* Chromium displays *"You are
using an unsupported command-line flag: --no-sandbox."*

Why: both warnings are the truthful consequence of running without a
setuid sandbox under proot.

Fix: none; the browsers work. Do not remove `--no-sandbox` to silence the
warning. Without it the browser aborts. On Ubuntu, use the installer's
Firefox build: the archive's `firefox` package is a snap transitional package
and snaps cannot run in proot.

### 5.3 App is missing from the menu

Symptom: `command -v <app>` prints a path, but the XFCE application menu
does not list it.

Why: the package did not install a desktop entry, the entry is in a
directory XFCE does not scan, or the menu cache is stale.

Fix:

```bash
update-desktop-database /usr/share/applications 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

Then look for the entry:

```bash
grep -R "^Name=\|^Exec=" /usr/share/applications/<app>.desktop
```

If there is no `.desktop` file, the app is CLI-only (for example `htop`), or it
needs a manual entry. Antigravity is extracted into `/opt` and has no entry by
default; v1.7.1 creates `/usr/local/bin/antigravity`. You can always launch by
name from a guest terminal.

### 5.4 App window opens off-screen

Symptom: the window is mostly outside the visible area; only a strip or the
title bar is visible, often after changing resolution or orientation.

Why: the app saved window bounds from a larger virtual screen (for example
a 2312×726 session restored as `y=627`).

Fix: delete that app's window state, not its settings:

```bash
rm -rf ~/.config/Code           # VS Code window/profile state
rm -rf ~/.config/chromium       # Chromium profile (also clears the profile)
```

For a gentler test, start with a temporary profile:
`code --user-data-dir=/tmp/code-test`. For any X11 window, `wmctrl` or
`xdotool` can move it back:

```bash
xdotool search --name "Visual Studio Code" windowmove 0 0
```

### 5.5 App closes with the terminal

Symptom: a GUI app started from a one-off `terminal-linux` shell vanishes
when that shell exits.

Why: the app is a child of that shell's session. `start-linux` owns the
desktop session; a separate login is a different session and may be killed
when it exits.

Fix: start GUI apps from the desktop menu (or from a terminal opened
inside the running desktop), not from a throwaway shell. If you must use a
shell, `setsid` detaches the app:

```bash
setsid code >/tmp/code.log 2>&1 < /dev/null &
```

Closing the terminal still leaves the app in the desktop session, which is the
supported arrangement.

### 5.6 No sound

Symptom: the desktop is silent; VLC or Firefox shows a playing stream but
no audio.

Why: PulseAudio runs in Termux, and the guest reaches it over
`PULSE_SERVER=127.0.0.1`. If the host daemon died (Android killed it, or a
previous `stop-linux` left a stale socket), the guest has no server.

Fix:

1. In Termux, run 3) Manager → 5) Audio Fixer. It restarts PulseAudio with
   TCP access limited to `127.0.0.1`.
2. Or manually:

   ```bash
   pulseaudio -k
   pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
   ```

3. Restart the desktop (`stop-linux`, `start-linux`) so the session picks up
   `PULSE_SERVER`.
4. Test with a local file in VLC, not a streaming site, to separate network
   problems from audio problems.

If PulseAudio is unavailable on Android 5/6, installs continue without audio;
that is a documented limitation, not a broken session.

### 5.7 Chromium video is black or crashes

Symptom: Chromium opens but video is black, or the tab crashes when
hardware acceleration is enabled.

Why: VirGL is helpful on some GPUs and harmful on others. The manager's
11) Browser acceleration menu writes `/etc/lfa-chromium-flags`; it does not
change the app itself.

Fix: run 3) Manager → 11) Browser acceleration → 2) Disable, then
restart Chromium. This removes the flags file and returns to the default
software renderer. Re-enable it only if video was working before. Other apps
are unaffected because the flags are read only by the Chromium wrapper.

### 5.8 First start of LibreOffice or GIMP is slow

Symptom: LibreOffice or GIMP takes 30 to 60 seconds to show its window the
first time.

Why: both build font caches and scan plugins on first run; proot makes
that I/O much slower. Subsequent starts are faster.

Fix: wait for the first start. Do not kill it during profile creation. If
it never appears, check `xwininfo -root -tree` and the terminal output; a
missing library is a package problem, not a speed problem.

### 5.9 An AppImage does not start

Symptom: running `./Foo.AppImage` prints

```text
fuse: failed to open /dev/fuse: Permission denied
Cannot mount AppImage, please check your FUSE setup.
```

or the app simply exits with status 127.

Why: AppImage type 2 mounts its own squashfs through FUSE. proot does not pass
`/dev/fuse` into the guest, so the mount can never succeed. This is a kernel
boundary, not a missing package; installing `fuse` or `libfuse2` does not help.

Fix: run the AppImage extracted instead of mounted. LFA exports
`APPIMAGE_EXTRACT_AND_RUN=1` in every guest session, so this works as-is:

```bash
./Foo.AppImage
```

For a large AppImage, extract it once and use the menu entry:

```bash
lfa appimage add ~/Foo.AppImage
lfa appimage list
lfa appimage run Foo
```

`lfa appimage add` keeps the unpacked app in `~/.local/opt/appimages/<name>`,
writes a launcher to `~/.local/bin/<name>`, and adds
`~/.local/share/applications/<name>.desktop`. Direct execution re-extracts on
every launch and leaves nothing behind.

If `lfa run` says `No desktop is running`, start the desktop first
(`lfa start -i <instance>`). If extraction fails, the file is not a valid
AppImage or it is truncated; check it with `sha256sum` against the download
page. On a musl guest (Alpine), an AppImage that bundles glibc programs may
still fail to start after extraction; use a glibc distro for that app.

## 6. Desktop environments

### 6.1 GNOME (experimental) does not start

GNOME is documented as experimental. The full decision record is in
[DECISIONS.md](DECISIONS.md), and the short checklist is in the README
([§16](../README.md#16-gnome-experimental-does-not-start-or-the-desktop-is-broken)).

Quick order of operations:

1. `tail -n 80 ~/start-linux-session.log` inside the distro.
2. Run 12) Apply Latest Fixes (regenerates the session bus and locale).
3. Switch to VNC if X11 keeps crashing.
4. Run 0) Doctor, then start again.
5. If it still fails, reinstall with MATE  (option 3). It has the same GTK heritage,
   no systemd requirement.

Do not expect GNOME 49+ to work: it needs a session manager this container
does not provide.

### 6.2 XFCE starts but Settings or Thunar crashes

Symptom: the desktop is up, but opening Settings, Thunar or a portal-using
app exits immediately.

Why: proot lacks the system D-Bus, logind and portals that those apps
expect. Some crashes are cosmetic, some are permanent limitations.

Fix: check the app's stderr for `Failed to connect to bus` (expected, not
fatal). Run 0) Doctor after package upgrades. For a specific app, reinstall
it inside the distro; a half-configured package is more common than a proot
incompatibility.

## 7. Accounts, sudo and passwords

### 7.1 `sudo` rejects the password

Symptom: `sudo` prints `Sorry, try again` three times, although the
password worked at install time.

Why: the sudo shim stores a salted SHA-256 hash captured at install time.
Changing the Linux account password with `passwd` does not update the shim,
and a reinstall with a different password replaces it.

Fix: the root terminal (`start-linux` → 2) never asks for a password.
For the shim, reset its hash from the root terminal. This prompts without
echoing and does not put the password in your shell history:

```bash
read -rsp "New sudo password: " P; echo
S=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
H=$(printf '%s%s' "$S" "$P" | sha256sum | cut -d' ' -f1)
sed -i "s|^SUDO_SALT=.*|SUDO_SALT=\"$S\"|; s|^SUDO_HASH=.*|SUDO_HASH=\"$H\"|" /usr/local/bin/sudo
unset P S H
```

Verify: `sudo true` accepts the new password (it prints nothing and exits
0).

To change the actual account password (used by login managers and `su`):

```bash
sudo passwd <user>
```

This is separate from the shim hash; do both if you want them to match.

### 7.2 `groups: cannot find name for group ID`

Symptom: every user shell prints `groups: cannot find name for group ID
99909997` before the prompt.

Why: Android passes its supplementary GIDs into proot. Some have no name in
the distro's `/etc/group`. Cosmetic.

Fix: v1.6+ names the mapped GIDs during install/migration. If you still see
it, add them from the root terminal:

```bash
for g in $(id -G); do
  getent group "$g" >/dev/null 2>&1 || echo "android_$g:x:$g:" >> /etc/group
done
```

### 7.3 Permission denied writing files

Symptom: an app or `sudo` command cannot write a file, although you own the
distro.

Why: the file is owned by a numeric UID that does not match the account, or
it was created by root in a root shell and is not writable by the user.

Fix: check the owner and fix it from the root terminal:

```bash
ls -ln <file>
chown -R "$(id -un):$(id -gn)" ~
```

Do not `chmod 777` the whole home directory; that hides the cause and breaks
SSH key permissions. Android's own storage permissions are separate. See
§8.1.

## 8. Storage, backup, restore and uninstall

### 8.1 Android files are not visible in the distro

Symptom: `/sdcard`, `~/storage/shared` or the phone's Downloads folder is
missing inside Linux.

Why: the guest is a rootfs under Termux's private data. It does not
automatically mount Android storage, by design: that keeps the distro portable
and avoids Android's scoped-storage permissions leaking into every app.

Fix: use Termux as the bridge.

1. In Termux (not in the distro), grant storage access once:

   ```bash
   termux-setup-storage
   ```

2. Copy files through the shared `/tmp`, which `start-linux` already maps:

   ```bash
   # in Termux
   cp ~/storage/shared/photo.jpg "$PREFIX/tmp/"
   # inside the distro
   cp /tmp/photo.jpg ~/
   ```

3. Or download the file directly inside the distro with `curl`/`wget`; that
   avoids the phone's storage permission entirely.

Do not expect `adb push` paths or `/sdcard` inside the guest. The manager's
8) Export and 9) Import menus already move backups through
`~/storage/downloads`.

### 8.2 Disk full

Symptom: `No space left on device`, `dpkg` fails to unpack, or the desktop
cannot create temporary files.

Fix:

```bash
df -h "$PREFIX"
du -sh "$PREFIX"/var/lib/proot-distro/* 2>/dev/null
du -sh ~/* 2>/dev/null | sort -h | tail -n 10
```

Reclaim space inside the distro with `sudo apt clean` (Debian family) or
`sudo apk cache clean` (Alpine). In Termux, `pkg clean` removes package
archives. Delete unused backups and instances with menu 10. Do not delete
files inside a live rootfs to make room; stop the desktop first.

### 8.3 Backup, restore, export and import

| Action | Menu | Where the file goes |
|---|---|---|
| Backup | 3) Manager → 6) Backup | `~/<instance>-backup.tar.gz` in Termux |
| Restore | 3) Manager → 7) Restore | reads the same path; overwrites the instance |
| Export | 3) Manager → 8) Export | `~/storage/downloads/<instance>-shared.tar.gz` |
| Import | 3) Manager → 9) Import | reads `~/storage/downloads/<file>` |

Restore fails or the instance disappears: check that the backup was made
by the same manager generation and that the file is not truncated
(`tar -tzf <file> >/dev/null`). Restore stops the instance first; a running
desktop will make it fail.

Import fails: the name must match exactly, including `.tar.gz`, and the file
must be in `~/storage/downloads`. Run `termux-setup-storage` first. Import
overwrites an existing instance with the same name; rename the file or uninstall
the old instance first.

Always make a backup before changing the desktop server, resolution or distro
release.

### 8.4 Uninstalled distro still appears

Symptom: menu 10) Uninstall says the instance was removed, but
`proot-distro list` (or `start-linux`) still shows it.

Why: an older uninstall could stop half-way when a session was still
running or the rootfs was already damaged, leaving a ghost container.

Fix: update the manager and run 10) Uninstall again. It kills sessions,
finishes the deletion and removes legacy `installed-rootfs` stubs. If the
directory still exists:

```bash
ls -la "$PREFIX/var/lib/proot-distro/containers/<instance>"
```

Stop all sessions, then remove that directory only after confirming the name.
Never remove the whole `proot-distro` tree; other instances live there.

## 9. Network and SSH

### 9.1 Guest has no internet

Symptom: `apt update` cannot resolve hosts, `curl` hangs, but the phone's
browser works.

Why: DNS inside the guest is inherited from Android/proot-distro. A VPN,
private DNS setting or a broken `/etc/resolv.conf` can break only the guest.

Fix: test in layers.

```bash
# Termux
ping -c 1 1.1.1.1
getent hosts deb.debian.org
# inside the distro
getent hosts deb.debian.org
curl -I https://deb.debian.org
```

If the IP works but names do not, DNS is the problem. In the guest, as root:

```bash
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
```

Then retry. If `start-linux` resets the file, fix DNS on Android (turn off
Private DNS or the VPN) rather than fighting the container. If even the IP
fails, the problem is the phone's connection, not the distro.

### 9.2 `apt` TLS or clock errors

Symptom: `Release file ... is not valid yet`, certificate errors, or
`The following signatures were invalid`.

Why: the phone clock is wrong (common after a battery drain or a long
sleep), or the image predates the current CA bundle.

Fix: enable Automatic date and time in Android, then inside the distro:

```bash
date
sudo apt install -y ca-certificates
sudo apt update
```

For a mirror with a broken certificate, switch repositories rather than
disabling TLS verification. `termux-change-repo` fixes the Termux side.

### 9.3 SSH from the PC fails

Symptom: `ssh: connect to host ... port 8022: Connection refused` or the
password is rejected.

Why: `sshd` is not running (it does not start at boot unless you added the
boot script), the PC is on a different network, or the Termux account has no
password.

Fix:

1. In Termux, run 3) Manager → 3) Start SSH Server.
2. If you have never set a Termux password: `passwd`.
3. Find the phone's IP: `ifconfig` (look for `inet` on `wlan0`), or the
   manager prints it.
4. From the PC:

   ```bash
   ssh -p 8022 u0_aNNN@PHONE_IP
   ```

   The username is Termux's `whoami` (usually `u0_aNNN`), not the Linux
   account name.

Still refused: check that both devices are on the same Wi-Fi, that the
router does not isolate clients, and that `sshd` is alive:
`pgrep -af sshd`. Starting `sshd` without `-E` can block on the terminal on
some Termux builds; the manager starts it safely.

### 9.4 SSH dies randomly

Symptom: SSH works, then drops after a few minutes, often while the
desktop or the test suite is running. Termux may show
`[Process completed (signal 9)]`.

Why: Android's phantom-process killer. An XFCE session plus a build easily
exceeds the default child-process limit, and Android kills the surplus,
including `sshd`.

Fix: §10.2. Also keep Termux in the foreground while using SSH, disable
battery optimisation for Termux, and run `termux-wake-lock` before long
sessions.

### 9.5 VNC from another device

Do not open port 5901 to the LAN. Use the SSH tunnel from §4.4; it works with
the default localhost binding and keeps VNC traffic inside SSH. If you need VNC
without SSH, understand that the VNC password is the only protection and the
connection is unencrypted.

## 10. Performance and Android limits

### 10.1 Everything is slow

Why: proot translates every syscall in user space, and phone storage is
slower than a PC SSD. Installing a desktop and unpacking icons are the worst
cases; normal app use is much lighter.

What helps:

- Keep the phone charging and Termux in the foreground during installs.
- Use a lighter desktop (LXDE, or CLI) on 2 to 3 GB devices.
- Avoid concurrent `apt`/`npm`/browser installs.
- Do not run the test suite while the desktop is up; it is CPU-heavy.

What does not help: killing and restarting the install. That loses unpacked
work and can leave `dpkg` half-configured.

### 10.2 Android kills Termux (signal 9)

Symptom: Termux closes with `[Process completed (signal 9)]`, or `sshd` and
the desktop disappear together.

Why: Android 12+ limits background child processes. A Linux desktop looks
like a process storm to Android.

Fix (Android 14 and newer):

1. Settings → About phone → tap Build number seven times.
2. Settings → System → Developer options → enable Disable child process
   restrictions.
3. Restart Termux.

Fix with ADB (any supported Android):

```bash
adb shell settings put global settings_enable_monitor_phantom_procs false
adb shell device_config put activity_manager max_phantom_processes 2147483647
adb shell cmd deviceidle whitelist +com.termux
```

The first line is the Android 14+ switch; the second raises the limit on
Android 12/13. Verify with:

```bash
adb shell settings get global settings_enable_monitor_phantom_procs
# false
```

Also set Termux to Unrestricted battery usage (Settings → Apps → Termux →
Battery). None of this requires root.

### 10.3 Phone sleep and battery optimisation

Symptom: the desktop freezes when the screen turns off, or the session
dies overnight.

Fix: run `termux-wake-lock` before long sessions (or let the manager's boot
script do it), set the screen timeout long enough for installs, and exclude
Termux from battery optimisation. `termux-wake-unlock` releases the lock. A
charging phone is the most reliable setup for a long install.

Low memory: `free -m` shows the guest's view; Android may still kill
background apps. Close other apps, use a lighter desktop, and avoid swap tools.
They cannot create a real swap file inside proot.

## 11. Updates and migration

### 11.1 Manager update, distro update, or menu 12?

| Goal | Command |
|---|---|
| Get a newer manager | `cd ~/Linux-For-Android && git pull` |
| Update packages inside the distro | `./install_linux.sh` → 3) Manager → 2) Update a Distro |
| Reapply launchers/fixes to an existing install | `./install_linux.sh` → 3) Manager → 12) Apply Latest Fixes |
| Repair apt/dpkg/users | `./install_linux.sh --doctor` or menu 0 |
| Upgrade the distro release (e.g. 24.04 → 24.10) | Inside the distro: `sudo do-release-upgrade` (Ubuntu) or the distro's own tool |

`git pull` does not change an installed distro. Menu 12 is the bridge: it
regenerates `start-linux`, the VNC `xstartup`, the sudo shim support files, the
wallpaper and the proot-safe wrappers without reinstalling the rootfs.

### 11.2 An update broke the desktop

Run 0) Doctor, then 12) Apply Latest Fixes, then `stop-linux` and
`start-linux`. Package upgrades can replace a launcher or remove
`glycin-loaders`; menu 12 restores what this project adds. If the desktop is
still broken, restore the backup you made before the upgrade (§8.3).

### 11.3 Configuration was lost or the instance was renamed

The per-instance settings live in `/etc/termux-linux-manager.conf` inside the
rootfs. `--list` shows the real instance names. If you rename the directory by
hand, the launcher and the conf no longer agree; reinstall or run menu 12 to
regenerate the launchers from the actual name. Do not edit the conf while the
desktop is running.

## 12. Recovery ladder

Work down this list; stop as soon as the problem is fixed.

1. Stop everything: `stop-linux`.
2. Read the last 60 lines of `~/start-linux-session.log` (inside the
   distro) and the VNC log if applicable.
3. Repair: `./install_linux.sh --doctor` (or menu 0).
4. Reapply fixes: menu 12.
5. Collect evidence: `./install_linux.sh --diagnostics`.
6. Back up: menu 6 before anything destructive.
7. Reinstall the instance: menu 10 (Uninstall) → 1 (Install) →
   7 (Restore). Your files inside the rootfs are lost unless you backed
   them up; Android storage is not inside the rootfs.
8. Report with the diagnostics bundle and the exact steps (§13).

Never delete `$PREFIX/var/lib/proot-distro` wholesale, and never run `rm -rf`
on a path you have not confirmed with `ls`. Most "unfixable" installs are
recoverable with Doctor plus a reinstall.

## 13. Reporting a bug

Open an issue with the form:
<https://github.com/pdev-labs/Linux-For-Android/issues/new/choose>

Include:

- manager version (`./install_linux.sh --version`)
- device model and Android version:
  `getprop ro.product.model`, `getprop ro.build.version.release`
- Termux source and version (`termux-info`), and whether it is the F-Droid
  build
- distro, desktop and display server (`--list`, then the instance's
  `/etc/termux-linux-manager.conf`: `DE`, `SERVER`)
- the exact command, what you expected, and what happened
- the last 60 lines of `~/start-linux-session.log` and any VNC log
- `~/lfa-diagnostics-<date>.tar.gz` (it already redacts secrets)
- a screenshot if the failure is visual

Security problems go through [SECURITY.md](../SECURITY.md), never a public
issue. Known limitations and their status are in [issues.md](../issues.md);
please check there before filing a duplicate.

## Appendix A: command cheat sheet

In Termux (host):

```bash
./install_linux.sh --version        # manager version
./install_linux.sh --list           # instances
./install_linux.sh --doctor         # repair the selected instance
./install_linux.sh --diagnostics    # redacted support bundle
start-linux                         # desktop / root / user terminal menu
terminal-linux                      # shell only, no display
stop-linux                          # stop session, display and audio
pgrep -af 'termux-x11|Xvnc|sshd'   # what is running
```

Inside the distro:

```bash
tail -n 60 ~/start-linux-session.log
echo "$DISPLAY"; xdpyinfo >/dev/null && echo X-OK
xwininfo -root -tree | head -n 40
pgrep -af 'xfce4-session|xfwm4|xfce4-panel|gnome-shell'
sudo apt update && sudo apt install -y <package>
sudo dpkg --configure -a
sudo apt-get -f install
sudo apt clean
```

Android (ADB, optional):

```bash
adb shell settings get global settings_enable_monitor_phantom_procs
adb shell settings put global settings_enable_monitor_phantom_procs false
adb shell cmd deviceidle whitelist +com.termux
```

## Appendix B: error string index

| Exact text | Section |
|---|---|
| `Cannot establish any listening sockets` | [§3.1](#31-cannot-establish-any-listening-sockets) |
| `No distributions installed` | [§3.2](#32-no-distributions-installed) |
| `unable to connect to D-Bus` | [§3.3](#33-black-screen-or-unable-to-contact-settings-server) |
| `Gtk:ERROR` / `Bail out!` / `bwrap` | [§3.4](#34-desktop-dies-with-a-gtk-bail-out) |
| `Non UTF-8 locale` / exit status 8 | [§3.5](#35-non-utf-8-locale) |
| `requested operation requires superuser privilege` | [§2.5](#25-dpkg-requested-operation-requires-superuser-privilege) |
| `unknown system group 'messagebus'` | [§2.6](#26-unknown-system-group-messagebus-in-statoverride) |
| `CAP_SETFCAP` / `snapd` configure | [§2.7](#27-snapd-will-not-configure) |
| `Not enough free space` | [§2.3](#23-not-enough-free-space) |
| `No space left on device` | [§8.2](#82-disk-full) |
| `Connection refused` on port 8022 | [§9.3](#93-ssh-from-the-pc-fails) |
| `Process completed (signal 9)` | [§10.2](#102-android-kills-termux-signal-9) |
| `The security sandbox is disabled` | [§5.2](#52-firefox-or-chromium-shows-a-sandbox-warning) |
| `unsupported command-line flag: --no-sandbox` | [§5.2](#52-firefox-or-chromium-shows-a-sandbox-warning) |
| `CBackend::create() failed!` | [§4.5](#45-a-wayland-session-or-hyprland-fails) |
| `Unable to locate package` | [§2.10](#210-package-not-found-after-installation) |
| `Release file ... is not valid yet` | [§9.2](#92-apt-tls-or-clock-errors) |
