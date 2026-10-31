# Design decisions

Short records of choices that look strange until you know why. Each entry:
the decision, the reason, and what it costs.

## D1 — proot-distro instead of chroot or a VM

**Decision:** run the guest under `proot` via `proot-distro`.
**Why:** no root, no bootloader, works on a stock phone, one command.
**Cost:** no real UIDs, no systemd, no loop mounts, no kernel modules. Every
other decision below follows from this one.

## D2 — X11 and VNC only, no Wayland

**Decision:** no Wayland backend is planned.
**Why:** Wayland needs a compositor with a real session, DRM access and often
systemd. Under proot the best case is a nested compositor on top of X, which is
slower and more fragile than the X11 session it replaces.
**Cost:** X11 is legacy upstream; some modern toolkits deprecate it.

## D3 — the sudo ritual instead of a real sudo

**Decision:** ship a shim that asks for the install password and then runs the
command, with no privilege change.
**Why:** `NO_NEW_PRIVS` makes setuid binaries inert inside proot, and every
guest file is already owned by the Termux user. A real `sudo` cannot work; a
silently broken one is worse than an honest ritual.
**Cost:** it looks like authentication but is not. Documented in
`SECURITY.md`; do not build anything security-relevant on it.

## D4 — one guest setup script instead of many `proot-distro login` calls

**Decision:** generate one bash script and execute it once in the guest.
**Why:** each `proot-distro login` costs seconds and loses environment; an
install with 40 steps would take minutes of pure startup time.
**Cost:** four levels of quoting, and a secret-bearing file that must be
protected and deleted (issues #1, #26).

## D5 — fixed display `:1` and port `5901`

**Decision:** every distro uses the same display and port.
**Why:** the launchers stay simple and predictable; a phone rarely runs two
desktops at once.
**Cost:** the shared socket and lock are a recurring failure mode, and two
distros cannot run together (issue #12).

## D6 — GNOME ships as beta, with a warning

**Decision:** offer GNOME Shell on six distros, behind a full warning and an
explicit confirmation; hide it where it cannot work.
**Why:** it does run — verified on the Vivo — but only because `gnome-session`
is bypassed. Calling it supported would mean owning a session manager that
proot cannot provide.
**Cost:** a user can install something that will misbehave; the warning is the
mitigation (issue #20).

## D7 — no package signing for our own releases

**Decision:** ship releases with notes only, no signed binaries, no assets.
**Why:** there was nothing to sign — the "product" is the script in the repo.
**Cost:** no reproducibility and no way to install a pinned version without
git. Tracked as G23/G24; a signed `install_linux.sh` + `SHA256SUMS` per release
is the intended fix.

## D8 — the test suite is stubbed, not containerised

**Decision:** test with fake `proot-distro`, `pkg`, `df`, `free`, `getprop`.
**Why:** CI has no Android kernel and no 3 GB rootfs; a containerised test
would be slow and still not prove the thing that matters (a real phone).
**Cost:** the suite proves the installer's logic, not the guest's behaviour.
Device runs cover that (issue #39).

## D9 — legacy support is a first-class path

**Decision:** Android 5/6 gets `proot-distro` v4.2.0 from source, forced VNC, no
VirGL, Alpine/Debian-bullseye recommendations.
**Why:** modern glibc aborts on a 3.10 kernel at the first guest command; musl
and glibc 2.31 do not. The alternative is telling those users no.
**Cost:** a second code path in every package decision, and a frozen
`proot-distro` release that will never get fixes.

## D10 — no Wayland, no root, no systemd: what is *not* attempted

Explicitly out of scope, so it does not get re-proposed every month:

- running `systemctl` (there is no PID 1)
- screen locking through logind
- auto-mounting USB or SD cards
- Android hardware sensors, GPS, camera bridging
- nested virtualisation or Docker inside the guest
