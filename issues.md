# Issues and improvement backlog

Senior-developer review of Linux-For-Android (`install_linux.sh` 3,311 lines,
`lib/` 4 files, `tests/test-all.sh` 733 lines) at v1.6.1.

Reference format is `file:line` at v1.6.1. Severity markers:

| Marker | Meaning |
|---|---|
| P1 | Security or data-loss risk. Fix before the next release. |
| P2 | Correctness or robustness issue that causes real user-visible failures. |
| P3 | Architecture or maintainability issue that slows every future change. |
| P4 | Testing, CI, or release engineering issue. |
| P5 | UX, docs, or feature gap. |

Status legend, updated 2026-10-31 after the v1.7.0 hardening pass:

| Status | Meaning |
|---|---|
| fixed in v1.7.0 | code changed, covered by the suite, listed in `CHANGELOG.md` |
| partial in v1.7.0 | the main risk is addressed; the remainder is written in the entry |
| deferred by design | a deliberate product decision or a redesign, not a bug |

Work-in-progress state for each item lives in `tracker.md`.

## Security

### 1. Secrets left in a world-readable temp file (fixed in v1.7.0)

`install_linux.sh:2417` writes `$PREFIX/tmp/gui_setup_$$.sh`, which contains
`__UPASS_B64__`, `__RPASS_B64__`, and `__SPASS_B64__`. The file is created with
the default umask (0644), is never `chmod`ed, and is never deleted, neither on
success (`:3296`) nor on failure because there is no `trap`.

### 2. "base64 is not plaintext" is misleading (fixed in v1.7.0)

Comments and docs at `:546`, `:664`, and `:2857` present base64 as protection.
It is reversible encoding. `setup.conf` is correctly `0600` (`:684`), but the
wording overstates the guarantee and invites users to trust it with reused
passwords.

### 3. The sudo password is embedded in a world-readable guest binary (fixed in v1.7.0)

`install_linux.sh:2859` bakes `SUDO_SHIM_B64` into `/usr/local/bin/sudo`
(mode `0755`, `:2988`). Any process inside the guest can read and decode it.
It is the same password used for root and, by default, for VNC.

### 4. No checksum or signature verification on any download (partial in v1.7.0)

- `:386` proot-distro v4.2.0 tarball, HTTPS only
- `:2773` Microsoft GPG key piped straight into `gpg --dearmor`
- `:3002` and `:3009` Antigravity archive
- `:3042` Firefox "latest" archive

The project contains no `sha256`, `sha512`, or `gpg --verify` calls.

### 5. HTML scraping to obtain an executable URL (fixed in v1.7.0)

`:3002` scrapes `antigravity.google/download/` for a link, then downloads and
installs it. That is fragile against page changes and an injection surface if
the page is ever compromised or intercepted.

### 6. Silent package installation inside the launcher (fixed in v1.7.0)

The v1.6.1 auto-install path in `start-linux` runs
`pkg install -y x11-repo && pkg install -y termux-x11-nightly` with all output
redirected to `/dev/null`. On a slow or broken mirror this looks like a hang,
and it installs software without asking.

### 7. `set -e` without `pipefail` (fixed in v1.7.0)

`:4` enables `set -e` only. Failures in any pipeline (`cmd | head`,
`cmd | grep -q`) are swallowed, so many guard checks pass regardless of the
underlying command's status.

## Correctness, data loss, and recovery

### 8. No `trap` for INT, TERM, or EXIT (fixed in v1.7.0)

Ctrl-C during install leaves half-created containers, `$PREFIX/tmp` scripts
with passwords (see #1), stale `/tmp/.X11-unix/X1` and `/tmp/.X1-lock`, and
orphaned `proot` keepalive loops. Observed live: six orphaned sessions held
`proot-distro` locks, which made `proot-distro remove` fail with "container is
busy" until they were killed by hand.

### 9. PID-file liveness checks are naive (fixed in v1.7.0)

`stop-linux` and the VNC path trust `kill -0 "$(cat "$pidfile")"` (`:1881`,
`:1927`). After a reboot the PID may belong to an unrelated process, and
`stop-linux` would kill it.

### 10. `pkill -f "^termux-x11"` is too broad (fixed in v1.7.0)

The X11 stop path kills any Termux:X11 instance, including one the user started
for another purpose.

### 11. `:latest` image tags make installs non-reproducible (partial in v1.7.0)

`:2395-2405` uses `kalilinux/kali-rolling:latest`, `fedora:latest`,
`opensuse/tumbleweed:latest`, `void-musl:latest`, `alpine:latest`, and
`archlinuxarm:latest`. A verified matrix row can silently stop being true.

### 12. Fixed display `:1` and fixed VNC port 5901 (deferred by design)

Two distros can never run simultaneously, and every backend shares one socket
and one lock file. That is the source of the "display :1 is taken" class of bug
fixed in v1.6.1. There is no port negotiation or `-displayfd` usage.

### 13. Fixed sleeps used as synchronization (fixed in v1.7.0)

`sleep 2`, `sleep 3`, and `sleep 45` after starting X, VNC, and servers
(`:1856`, `:1925`, `:2918`, and launchers). There is no readiness polling, so
slow devices get races and fast devices waste time.

### 14. No disk-space preflight (fixed in v1.7.0)

Nothing checks for the 2.5 to 3 GB a GUI or GNOME install needs. A full device
dies mid-`apt` and leaves a half-configured rootfs that only Doctor can repair.

### 15. Menu 12 does not install packages added by newer releases (partial in v1.7.0)

`upgrade_existing()` (`:1353`) refreshes config keys, prompt, xstartup,
wallpaper, and launchers, but never installs newly required packages such as
`dconf-cli` for GNOME. It also never re-runs the install verification block.

### 16. UTF-8 locale fix only covers GNOME (fixed in v1.7.0)

The `LANG=C.UTF-8` and `dbus-update-activation-environment` fix lives only in
`lib/real-feel.sh`'s GNOME wrapper. XFCE, LXDE, and MATE sessions still start
with `ANSI_X3.4-1968`, so GTK apps that require UTF-8, such as editors,
terminals, and input methods, can fail there too.

### 17. Shared `XDG_RUNTIME_DIR` across distros (fixed in v1.7.0)

`/tmp/xdg-$USER` is used by every distro (`:1872`, launchers). Because all
distros share `/tmp`, bus sockets and runtime state can collide.

### 18. `|| true` on critical steps hides failures (partial in v1.7.0)

The `real-feel.sh` invocation (`:1417`), gid mapping, wallpaper application,
and `uid0` build (`:2742`) all end in `|| true`. The user still sees
"Installation complete" with a broken prompt or missing wallpaper.

### 19. Unquoted `$PREFIX` in `sed -i` (fixed in v1.7.0)

`:1933`, `:2013`, and `:2073` run `sed -i ... $PREFIX/bin/...` unquoted. Any
prefix containing spaces breaks launcher generation.

### 20. GNOME is shipped beta with a known-incomplete session (deferred by design)

There is no logout, session restore, or locking. GNOME 49 and later cannot run
at all. It is gated by a warning but still presented as an installable desktop
in the same menu as stable ones.

### 21. VNC password is silently truncated to 8 characters (fixed in v1.7.0)

`:3102` pipes the user's password into `vncpasswd -f`. VNC auth uses only the
first 8 characters, so a longer password "doesn't work" with no explanation.
`README.md:176` sidesteps it with "accepts the default short passwords"
instead of warning.

### 22. `detect_environment` treats SDK 0 as modern (fixed in v1.7.0)

`:307-330`. Running outside Termux, or on a ROM where `getprop` is
unavailable, silently changes behaviour instead of refusing to run.

### 23. No password confirmation in guided setup (fixed in v1.7.0)

`:899-910` accepts the user and root password once, with no re-type loop. A
typo locks the user out of both the account and the sudo ritual, with no
recovery path in the UI.

## Architecture and maintainability

### 24. 3,311-line single-file installer (partial in v1.7.0)

`lib/` covers only 4 concerns: wallpaper, real-feel, uid0, and dpkg
statoverride. The installer, menu, driver, doctor, backup, apps, and launchers
all live inline.

### 25. The questionnaire exists twice (fixed in v1.7.0)

"Choose Desktop Environment" appears at `:715` and `:2160`. "Choose Display
Server" appears at `:825` and `:2186`. Adding GNOME required editing both
copies, and they will drift.

### 26. 34 heredocs generating scripts inside scripts (deferred by design)

The chain runs from setup script to launcher to xstartup to upgrade script,
with up to four quoting levels (`\\$`, `\$`). Every bug fixed in v1.6.x
originated in this layer.

### 27. Repeated `if ! ui_select ...; then show_menu; return; fi` (partial in v1.7.0)

The guard appears about 15 times. Every new menu step is a chance to forget it
and dead-end the wizard.

### 28. `show_menu` recursion for back navigation (deferred by design)

Every back or exit path calls `show_menu` again. The stack grows and control
flow becomes hard to follow or test.

### 29. Version and count strings duplicated across files (fixed in v1.7.0)

`LFA_VERSION`, `PASS=313`, "313 checks", and troubleshooting numbering are all
hand-maintained in `README.md`, `docs/TEST-REPORT.md`, and release notes.

### 30. No CLI flags or non-interactive mode (fixed in v1.7.0)

A 3.3k-line tool was only usable interactively, or by faking stdin. There was
no way to script an install, choose a distro from the command line, or print
the version.

### 31. No self-update or update check (fixed in v1.7.0)

`LFA_VERSION` (`:13`) was only printed in the banner. Users on an old clone got
no signal that a newer release existed.

### 32. Duplicated uid0 build invocation (fixed in v1.7.0)

`gcc -shared -nostdlib -O2 ...` appears at `:1333` and `:2742` with the same
flags. A change to one will miss the other.

### 33. No CHANGELOG file (fixed in v1.7.0)

Release history existed only as GitHub release notes. The repo had no
`CHANGELOG.md`, so offline users saw nothing.

### 34. Deep distro-specific branching (partial in v1.7.0)

`tigervnc` versus `tigervnc-standalone-server`, `Xvnc` versus `vncserver`,
`/usr/libexec/gnome-terminal-server`, `dbus-1-daemon`, `firefox-esr` versus
`firefox`, and `libreoffice-fresh` versus `libreoffice`. Each new distro
multiplies `case` arms in three separate places.

### 35. Inconsistent comment density (fixed in v1.7.0)

Some functions carry 10-line rationale blocks; others have none. The file read
like a patch log, with inline version markers (`v1.5.6`, `v1.5.7`, `v1.5.8`)
left in place. That history belongs in git, not in the source.

## Testing, CI, and release engineering

### 36. No CI at all (fixed in v1.7.0)

There was no `.github/workflows`. The 313 checks ran only when a human
remembered to run them, and nothing blocked a broken merge.

### 37. No linting or formatting gate (fixed in v1.7.0)

There was no `shellcheck`, no `shfmt`, and no `bash -n` in any automated path,
despite this being a pure-bash project. `shellcheck` was not even installed on
the dev box.

### 38. Tests assert generated text, not behaviour (partial in v1.7.0)

For example, `check "D2 warning shown" 'EXPERIMENTAL / BETA' "$T/d2.log"`. A
function can be functionally broken and still pass as long as the string is
printed.

### 39. The whole suite is stubbed (deferred by design)

`pkg`, `proot-distro`, `sshd`, `pulseaudio`, `getprop`, `free`, `proot`, and
`git` are all fakes (`tests/test-all.sh:36-80`). Nothing exercises a real
rootfs, a real package manager, real VNC, or real X.

### 40. The suite writes into the repo (fixed in v1.7.0)

`T="$REPO/.test-tmp"` was gitignored but still in the working tree. A killed
run left state that the next run depended on being wiped.

### 41. Hand-rolled assertion bookkeeping (partial in v1.7.0)

`pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: ..."; }` is copy-pasted
about 179 times. There are no test names, IDs, timings, parallelism, or
`--filter`.

### 42. Major paths are untested (partial in v1.7.0)

Backup and restore round-trip, export and import, uninstall including ghost
entries, Doctor against a genuinely broken dpkg, menu 12 per distro family,
and GNOME under VNC are all manual-only.

### 43. The hardware matrix is not automated (fixed in v1.7.0)

There was no `tests/device-matrix.sh`. "Verified on real hardware" was a human
promise with no reproducible script, device config, or captured logs in the
repo.

### 44. No regression corpus for the bugs already fixed (fixed in v1.7.0)

Stale `:1` release, missing system bus, locale, and snapd purge each got a
string-level test after the fact. Nothing guarded the behaviour they fixed.

## UX, docs, and feature gaps

### 45. Misleading error messages (fixed in v1.7.0)

`:1864` said "Re-install with VNC instead" for what was merely a missing
package. That was fixed to a two-part message in v1.6.1, but the pattern
remains: several messages guess at the cause.

### 46. Default `root`/`root` credentials with no on-screen warning (fixed in v1.7.0)

This is documented in the README, but the installer never warned at the point
of choice, and the same password became the VNC password and the sudo shim
secret.

### 47. Docs overstate validation (fixed in v1.7.0)

The hardware matrix had no "as of version" column, so it silently went stale.
GNOME was listed as verified in prose while the caveat said the opposite until
v1.6.1.

### 48. "Experimental" is only visible after selecting GNOME (fixed in v1.7.0)

The option text said BETA, but the menu had no visual class distinction, and
other gated paths such as legacy glibc distros and forced VNC carried no such
marking.

### 49. Uninstall leaves Termux-side artifacts (fixed in v1.7.0)

Boot scripts, `~/.shortcuts` widgets, `$PREFIX/tmp/*` leftovers, and stale
pidfiles were not cleaned up.

### 50. No log capture or `--debug` mode (fixed in v1.7.0)

Bug reports required reproducing and copying terminal output by hand. There was
no "collect diagnostics" command.

### 51. README structure is brittle (fixed in v1.7.0)

The table-of-contents anchors depended on emoji headings, and troubleshooting
was 16 prose entries with no symptom index or searchable titles.

### 52. No accessibility audit (partial in v1.7.0)

`NO_COLOR` is honoured, but the UI relies on arrow keys, inverse video, and
colour to convey state. There is no screen-reader or plain-text mode beyond
piped stdin.

### 53. Known-broken rows shipped as "verified" (fixed in v1.7.0)

Alpine edge: the panel never starts. Void over VNC: the panel is inconsistent.
Both were documented as footnotes rather than fixed or excluded from the
matrix.

### 54. Wallpapers are full-resolution in git (fixed in v1.7.0)

Verified on 2026-10-31: the 17 assets are already 1920x1080 (2.1 MB total),
not 4K as originally assumed. There are no per-resolution variants, so a 720p
session decodes a 1080p image, which is a negligible cost. No change was made;
the original finding was wrong.

## Post-release findings (v1.7.1, 2026-11-01)

These were found by launching every application in the install menu on the
Vivo after v1.7.0 shipped. The first two are fixed in v1.7.1; the third is
documented.

### 55. Electron apps fail silently under proot (fixed in v1.7.1)

VS Code's zygote aborts because proot cannot provide the setuid sandbox, but
the `code` CLI returns 0 and prints nothing. The user sees "VS Code does not
open". The same applies to Chromium and Antigravity. Fixed by writing
`/usr/local/bin/{code,chromium,antigravity}` wrappers with `--no-sandbox` and
`--disable-gpu` or `--disable-dev-shm-usage`, and pointing the desktop entries
at the wrapper.

### 56. Chromium's safe launcher only existed after menu 11 (fixed in v1.7.1)

A fresh install that selected Chromium got the package but no `--no-sandbox`
wrapper, so the browser aborted with the SUID sandbox error. The wrapper is
now created by the shared guest polish, so install and migration both produce
it.

### 57. VS Code can restore an off-screen window position (documented)

A user-data directory created against a taller virtual screen can restore
bounds that put the window at `y=627` on a 726-pixel-tall Termux:X11 screen,
leaving only a strip visible. Deleting `~/.config/Code` or using
`--user-data-dir` restores the default bounds. The new `--no-sandbox` wrapper
and the troubleshooting entry make the normal case reliable.

## Android CI and compatibility findings (2026-11-05)

### 58. Android 7 was offered X11 it cannot run (fixed)

The installer used one `IS_LEGACY` flag (SDK < 24) for both the archived
Termux repository path and Termux:X11 availability. Android 7.0/7.1 (SDK
24/25) therefore got modern packages and was offered X11, Both, and GNOME,
although all three need Android 8 (SDK 26). The install would only fail when
the desktop was started. Fixed by adding `X11_SUPPORTED` and using it in the
installer, CLI, switch/autostart paths, menu 14, quick setup, and the
generated launcher. API 24/25 boundary scenarios are now in the CI matrix.

### 59. No honest compatibility layer for missing services (addressed)

Users saw `systemctl`, `snap`, `upower`, and sandbox errors with no way to
tell which failures were fixable and which were kernel limits. `lfa compat`
now lists, explains, and optionally enables small, visible fallbacks, and
refuses to fake Docker, Flatpak, TUN/TAP, netfilter, CUDA, ROCm, KVM, or kernel
modules. `docs/INCOMPATIBLE.md` records the reasons.

### 60. Manual phone testing was the only real-device gate (ongoing)

The host suite is stubbed and every real display check depended on a person
with a phone. Android emulator workflows and `tests/termux-e2e.sh` now cover
CLI, VNC, X11, switching, refusal, shims, software probes, and a real VNC
framebuffer. ARM64-only vendor builds, real Android 5/6 Termux repos, OEM
process killers, and real hardware remain device checks; the CI has not run on
GitHub Actions yet.
