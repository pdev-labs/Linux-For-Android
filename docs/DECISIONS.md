# Design decisions

Short records of choices that look strange until you know why. Each entry has
the decision, the reason, and what it costs.

## D1: proot-distro instead of chroot or a VM

Decision: run the guest under `proot` via `proot-distro`.

Why: no root, no bootloader, works on a stock phone, one command.

Cost: no real UIDs, no systemd, no loop mounts, no kernel modules. Every other
decision below follows from this one.

## D2: Wayland runs nested, and Hyprland waits for a DRM node

Decision: ship `lfa wayland` as a nested session. Sway is the compositor on a
stock phone. Hyprland starts only when the app can open a DRM render node.

Why: Termux:X11 is an X11 server, and Sway has an X11 backend, so a nested
session works without root. Hyprland's Aquamarine back end asks for
`zwp_linux_dmabuf_v1` and a render node while it starts. A stock Android app
cannot open `/dev/dri/card0`, and there is no `/dev/dri/renderD128`, so
Hyprland aborts with `CBackend::create() failed!`. A profile that copies the
Hyprland keybinds, gaps, borders, and colours gives the same look on Sway.

Cost: software rendering with pixman, no hardware GL in Wayland clients, and no
promise that Hyprland's blur, shadows, or screencast work. The Sway profile has
to be kept in step with the Hyprland config by hand. X11 is still the default
session for every distro.

## D3: the sudo ritual instead of a real sudo

Decision: ship a shim that asks for the install password and then runs the
command, with no privilege change.

Why: `NO_NEW_PRIVS` makes setuid binaries inert inside proot, and every guest
file is already owned by the Termux user. A real `sudo` cannot work. A
silently broken one is worse than an honest ritual.

Cost: it looks like authentication but does not change privileges. Documented
in `SECURITY.md`; do not build anything security-relevant on it.

## D4: one guest setup script instead of many `proot-distro login` calls

Decision: generate one bash script and execute it once in the guest.

Why: each `proot-distro login` costs seconds and loses environment. An install
with 40 steps would take minutes of pure startup time.

Cost: four levels of quoting, and a secret-bearing file that must be protected
and deleted (issues #1, #26).

## D5: fixed display `:1` and port `5901`

Decision: every distro uses the same display and port.

Why: the launchers stay simple and predictable, and a phone rarely runs two
desktops at once.

Cost: the shared socket and lock are a recurring failure mode, and two distros
cannot run together (issue #12).

## D6: GNOME ships as beta, with a warning

Decision: offer GNOME Shell on six distros, behind a full warning and an
explicit confirmation. Hide it where it cannot work.

Why: it runs on the Vivo, but only because `gnome-session` is bypassed.
Calling it supported would mean owning a session manager that proot cannot
provide.

Cost: a user can install something that will misbehave. The warning is the
mitigation (issue #20).

## D7: no package signing for this project's own releases

Decision: ship releases with notes only, no signed binaries, no assets.

Why: there was nothing to sign. The product is the script in the repo.

Cost: no reproducibility and no way to install a pinned version without git.
Tracked as G23/G24. A signed `install_linux.sh` and `SHA256SUMS` per release is
the intended fix.

## D8: the test suite is stubbed, not containerised

Decision: test with fake `proot-distro`, `pkg`, `df`, `free`, and `getprop`.

Why: CI has no Android kernel and no 3 GB rootfs. A containerised test would be
slow and would still not prove the thing that matters: a real phone.

Cost: the suite proves the installer's logic, not the guest's behaviour. Device
runs cover that (issue #39).

## D9: legacy support is a first-class path

Decision: Android 5/6 gets `proot-distro` v4.2.0 from source, forced VNC, no
VirGL, and Alpine or Debian bullseye recommendations.

Why: modern glibc aborts on a 3.10 kernel at the first guest command. musl and
glibc 2.31 do not. The alternative is telling those users no.

Cost: a second code path in every package decision, and a frozen
`proot-distro` release that will never get fixes.

## D10: what is not attempted

Explicitly out of scope, so it does not get proposed again every month:

- real `systemctl` and systemd (there is no PID 1)
- real logind session locking and suspend control
- auto-mounting USB or SD cards
- exposing Android sensors, GPS or camera as Linux kernel devices
- nested virtualisation or Docker inside the guest
- faking kernel facilities (namespaces, TUN/TAP, netfilter, modules, GPU
  compute) just to make a program start

The optional `lfa compat` supervisor and `lfa android` bridge were added later
(D14). They answer userspace expectations and expose Android framework data;
they do not change this list.

## D11: one distro can carry both display back ends

Decision: `SERVER` accepts `x11`, `vnc`, `both`, or `none`. `both` installs
Termux:X11 support and the guest VNC packages, then shows a backend menu at
each desktop start.

Why: some users want X11 speed at home and VNC when they need to connect from
another device. Reinstalling to switch was unnecessary.

Cost: the package, password, xstartup, verification, and autostart paths all
check for VNC rather than comparing `SERVER` to `vnc`. The two back ends still
share display `:1` and port `5901`, so they cannot run at the same time.
Android 5/6 keeps VNC only because Termux:X11 requires Android 8 or newer.

## D12: a unified `lfa` command, a `linux` shortcut, and explicit removal

Decision: `lfa` is the command-line surface, `linux` starts the desktop, and
`lfa switch` handles backend changes. Backend packages are kept by default and
removed only with `--remove-old`.

Why: `start-linux` is a good menu but a poor scripting target. Users who live
in the terminal need stable commands with predictable exit codes, and widget
users need a desktop shortcut that does not stop at a menu. Keeping old
packages by default makes switching reversible and avoids re-downloading a
large VNC or X11 package set because a user wanted to try the other backend.
Removal stays explicit because it crosses an instance boundary: the host X11
package is shared, and a guest VNC removal deletes the user's VNC password and
xstartup.

Cost: `lfa` needs a private runtime copy rather than calling the clone, so an
upgrade has one more directory to refresh. The shared-X11 guard has to inspect
every installed config before removing a host package. Android 5/6 needs an
extra refusal path with a recovery instruction instead of a generic "not
supported" message.

The `linux` wrapper is a real script in `$PREFIX/bin`, not a shell alias. That
is deliberate: aliases do not exist in widgets, SSH commands, `nohup`, or
Termux:Boot scripts.

The notice about the new layout is printed by `start-linux` to stderr on
interactive classic runs only. It can be hidden for one run with
`--no-notice` or `LFA_NO_NOTICE=1`, and permanently with `lfa notice off`.
The preference is stored outside the guest so it survives distro reinstalls.

## D13: Android 7 is not "legacy", but it still has no X11

Decision: keep two independent Android cutoffs. `IS_LEGACY` means SDK < 24
(archived Termux repositories). `X11_SUPPORTED` means SDK >= 26 (Termux:X11,
Both, and GNOME). SDK 24/25 gets modern packages and VNC only.

Why: the old single `IS_LEGACY` flag answered two different questions. Android
7.0/7.1 has working modern Termux packages, so treating it as legacy would
force obsolete repos and the proot-distro source path for no reason. But
Termux:X11 genuinely needs Android 8, so treating it as fully modern offered a
desktop that could never start. Two flags describe the two realities.

Cost: six call sites had to change (installer defaults, guided server choice,
configured-setup clamp, `lfa install`, `lfa switch`, `lfa autostart`, menu 14,
and the generated launcher). The CI includes API 24 and 25 boundary scenarios
so the two flags cannot drift back together.

## D14: `lfa compat` and `lfa android` are separate commands

Decision: `lfa compat` shims Linux-side expectations; `lfa android` exposes
real Android framework data through files in `$PREFIX/tmp`. They share a
status view but not an implementation, and risky shims are opt-in.

Why: the failure modes are different. A compatibility shim may deliberately
lie about a service, and users need to disable it without losing battery or
location data. The Android bridge touches privacy-sensitive permissions and
depends on an app the user may not want. Merging them would make the risky
part harder to audit and the safe part harder to use.

Cost: two command names and two config files instead of one. The alternative,
a single "make everything work" switch, would hide which part is real and
which part is a fallback.

The rules are strict:

- no silent faking of security controls (`sudo`, sandboxing, firewall rules)
- prefer a real fallback over a success stub
- report the limit in `lfa compat explain`
- never claim a kernel facility the app sandbox cannot provide
- test the actual operation, not `--version`

`lfa android` is not a kernel bridge. Termux:API talks to Android framework
services under the normal app UID; it cannot create TUN/TAP, GPU devices, or
`/dev` nodes.

## D15: VirGL is optional and self-healing

Decision: keep VirGL as the preferred renderer, but verify it against the
running session. If the session log shows a GLX context failure, write
`NEED_VIRGL="0"` for that instance and restart it once with llvmpipe.

Why: `virgl_test_server_android` can be running on a device whose driver
cannot create a GLX context. The old code assumed that a running server meant
a working renderer, so xfwm4 died with `BadValue` and the desktop had no
window manager. A software fallback is slower but usable; an undecorated
desktop is not. The fallback is recorded so later starts skip the broken path
instead of retrying it every time.

Cost: one background watcher per instance/backend for 12 seconds after a
start, plus a per-instance config write. The watcher is locked so repeated
starts cannot stop each other's fresh session, and it does nothing after a
deliberate `lfa stop`.

## D16: AppImages are extracted, not FUSE-mounted

Decision: run AppImages by extracting them. Guest sessions export
`APPIMAGE_EXTRACT_AND_RUN=1`, and `lfa appimage add` extracts a large app once
into `~/.local/opt/appimages` with a launcher and a desktop entry.

Why: an AppImage type 2 mounts its own squashfs through FUSE. proot does not
expose `/dev/fuse` (`Permission denied`), and no guest package can change
that. The runtime already supports extraction for exactly this case, so LFA
uses the supported path instead of claiming FUSE works or asking users to pass
an undocumented flag. This is the same rule as `lfa compat`: report the
missing kernel facility, offer the real fallback.

Cost: direct execution re-extracts on every launch, which is fine for small
tools and slow for a 100 MB app. `lfa appimage add` pays that cost once and
keeps the menu entry working. Extraction also needs temporary space in `/tmp`
(the shared Termux tmp). Licensing and architecture do not change: the AppImage
content still has to be legitimate and built for the phone's CPU.

## D17: Android storage uses gid 1023 as the desktop user's primary group

Decision: give the desktop user gid 1023 (the group Android uses for
`/storage/emulated/0`) as its primary group. The group name is cosmetic: use
the name already assigned to 1023, or create `lfa_storage`.

Why: Android mounts shared storage as `1023:1023` with mode `2770`. proot
lets reads and writes through because the real process is the Termux uid, but
Thunar checks the Unix mode and draws `emblem-unreadable` on every folder.
Adding the user as a secondary group did not work because proot only maps the
primary gid. Reads and writes were never broken; the X was false.

Cost: new files in the guest home are group `media_rw` instead of the user's
private group. The private group still exists, and the change is applied by
install/upgrade and by `lfa storage fix`. `chmod` on shared storage remains
impossible because the FUSE mount fixes the mode and is `noexec`;
`lfa storage exec` is the working alternative.

## D18: Android/data and Android/obb are copied through adb

Decision: leave the two protected folders out of the guest and copy an app's
folders on demand with `lfa storage data pull`. The command uses adb, which
runs as the shell user.

Why: Android 11 and later deny `/storage/emulated/0/Android/data` and
`Android/obb` to every app, including Termux. The guest runs as Termux, so a
bind mount, a group change, or `chmod` cannot pass the check. Granting "All
files access" did not help on the Vivo. adb is the only unrooted path, and the
shell user is allowed in.

Cost: the copy is not live, and it needs the adb client in Termux plus one
`adb tcpip 5555` from a PC after each reboot. Wireless debugging removes the
PC requirement but needs a one-time pairing. Root or Shizuku would allow live
access; neither is present on the test device.
