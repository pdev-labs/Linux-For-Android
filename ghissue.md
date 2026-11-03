# GitHub repository improvements

This file lists what is missing from the repository itself, not the code, and
what affects a first-time visitor's trust in the first ten seconds.

Impact is scored from 1 to 5. Effort is a rough estimate. The status column is
maintained by hand; see `tracker.md` for code work.

## P0: repository facts are inconsistent

| # | Item | Impact | Effort | Status |
|---|---|---|---|---|
| G1 | Version numbering is broken. Tags run to `v4.6.0` in July, the current release is `v1.6.1` in October, and `v4.6.0` is an ancestor of `main`. Decide whether to renumber forward to `v5.0.0` or document the reset in `CHANGELOG.md` and mark v2 to v4 historical. | 5 | 1 h | partial: documented in `CHANGELOG.md`; renumbering the old tags is a history rewrite |
| G2 | The description is out of date. It lists Ubuntu, Debian, Arch, Fedora, openSUSE, and Void, but omits Kali, Alpine, Android 5/6, and GNOME. | 4 | 5 min | done: description names all 8 distros, Android 5.1 to 16, no root |
| G3 | Missing topics: `gnome`, `vnc`, `x11`, `android-5`, `termux-desktop`, `linux-desktop-android`, `alpine-linux`. | 3 | 5 min | done: 20 topics, including vnc, gnome, alpine-linux, and android-5 |
| G4 | The homepage URL is empty. Point it at the latest release or `docs/`. | 3 | 2 min | done: points at the latest release |
| G5 | 40 of 94 commits are authored by `pdev@local`, so half the contribution graph does not show pdev-labs. Re-attribute them to pdev-labs. | 4 | 30 min | open: history rewrite |

## P1: proof it works

| # | Item | Impact | Effort | Status |
|---|---|---|---|---|
| G6 | The README has no images. Add a hero screenshot with a phone frame and the XFCE desktop. | 5 | 30 min | done: hero screenshot |
| G7 | Add a 10 to 15 second GIF: clone, menu, desktop appearing. | 5 | 45 min | open: needs a recording |
| G8 | Add a distro screenshot grid for Ubuntu, Kali, Fedora, Arch, Void, and Alpine. Screenshots already exist. | 4 | 20 min | done: `docs/screenshots/` grid |
| G9 | Add a real-hardware photo of the phone showing the desktop. | 4 | 10 min | open: needs a photo |
| G10 | Put hard numbers in the README: install times (27m45s GNOME, 3m32s Alpine on Oppo), disk use (204 MB), RAM floor, and FPS. | 4 | 15 min | done: "Measured on hardware" table |
| G11 | Add a "Hard problems solved" section covering the missing system bus, snapd in proot, and the kernel 3.10 glibc issue. | 4 | 30 min | done: README section |
| G12 | Put the device matrix above the fold, with an "as of vX.Y.Z" column. | 4 | 10 min | done: matrix with "Verified on" |

## P2: repository health files

| # | Item | Impact | Effort | Status |
|---|---|---|---|---|
| G13 | Add `SECURITY.md`. A project that installs root needs one. | 5 | 10 min | done |
| G14 | Add `.github/ISSUE_TEMPLATE/` with a bug form that asks for device, Android version, distro, backend, and log. | 5 | 20 min | done |
| G15 | Add `CONTRIBUTING.md` with one command to run tests (`PASS=...`) and the style rules. | 4 | 20 min | done |
| G16 | Add `CHANGELOG.md` in Keep a Changelog format. | 4 | 30 min | done |
| G17 | Add `CODE_OF_CONDUCT.md`. | 2 | 5 min | done |
| G18 | Add `.github/PULL_REQUEST_TEMPLATE.md`. | 3 | 10 min | done |
| G19 | Add `.github/CODEOWNERS`, `.github/FUNDING.yml`, and `SUPPORT.md`. | 2 | 10 min | partial: CODEOWNERS added; FUNDING needs an account |
| G20 | Add `.gitattributes` with text and binary rules for wallpapers, plus `.editorconfig`. | 2 | 5 min | done |

## P3: automation and release engineering

| # | Item | Impact | Effort | Status |
|---|---|---|---|---|
| G21 | Add a CI workflow that runs `shellcheck`, `bash -n`, and `tests/test-all.sh` on push and pull request. Add the badge. | 5 | 1 h | done: `.github/workflows/ci.yml` |
| G22 | Protect `main` (require a pull request and passing checks, block force-push) and enable delete-branch-on-merge. | 4 | 5 min | partial: delete-branch-on-merge enabled; branch protection is a maintainer decision |
| G23 | Attach a versioned `install_linux.sh` and `SHA256SUMS` to every release. | 4 | 30 min | done: v1.7.0 ships `install_linux.sh` and `SHA256SUMS` |
| G24 | Publish pinned install instructions (`git clone --branch vX.Y.Z`), so users do not install an unreviewed HEAD. | 4 | 10 min | done: pinned `--branch` clone |
| G25 | Automate releases (tag, notes, assets) instead of running `gh release create` by hand. | 3 | 2 h | partial: `gh release create` is scripted by hand, not by a workflow |
| G26 | Add milestones per release. Projects is enabled but empty. | 3 | 15 min | open |
| G27 | Add area labels: `area: installer`, `distro: alpine`, `backend: vnc`, `needs-hardware`, `regression`. | 3 | 10 min | open |
| G28 | Enable Discussions and pin a "post your device" thread. Disable the empty Wiki. | 3 | 10 min | done: Discussions on, empty Wiki disabled |

## P4: documentation inside the repository

| # | Item | Impact | Effort | Status |
|---|---|---|---|---|
| G29 | Add `docs/ARCHITECTURE.md`: the generator-inside-generator design, session model, and why proot and X11 are used. | 4 | 1 h | done |
| G30 | Add `docs/DECISIONS.md`: why proot, why no Wayland, why ritual sudo, why GNOME is beta. | 4 | 45 min | done |
| G31 | Add a `docs/` index and link `docs/TEST-REPORT.md` from the first screen. | 3 | 15 min | done: `docs/README.md` index |
| G32 | Link `issues.md` from the README with severities. | 4 | 10 min | done |
| G33 | Add badges for release version, CI status, downloads, and license. Replace the three static ones. | 4 | 15 min | done: CI, release, Android range, distros |
| G34 | Add a custom social preview image. Discord and Reddit shares currently show a grey card. | 5 | 10 min | open: needs an image upload |
| G35 | Fix README table-of-contents anchors and add a symptom index for the 16 troubleshooting entries. | 3 | 30 min | done: symptom index with stable anchors |

## P5: polish

| # | Item | Impact | Effort | Status |
|---|---|---|---|---|
| G36 | Add a 60-second quickstart with at most three code blocks, above the deep explanation. | 4 | 15 min | done: Quick start |
| G37 | Add screenshots inside the troubleshooting section for a black screen and a missing panel. | 3 | 20 min | open |
| G38 | Make naming consistent: repo `Linux-For-Android`, product "Linux for Android Manager", command `start-linux`. Pick one story. | 2 | 30 min | partial: naming explained in CONTRIBUTING |
| G39 | Add a logo or icon file to the repo. The banner is inline HTML only. | 3 | 20 min | open |
| G40 | Add a known-issues banner at the top, linking `issues.md`. | 3 | 10 min | done: banner above the fold |

## Five changes with the biggest effect

1. G6 and G7: hero screenshot and GIF. The images already exist on disk.
2. G21 and G22: real CI with a green badge and a protected `main`.
3. G13 and G14: `SECURITY.md` and issue templates, 30 minutes total.
4. G1 and G16: fix version numbering and add `CHANGELOG.md`.
5. G23 and G24: release assets with checksums and pinned install commands.

## Notes

- Stars and forks (5/1) cannot be fixed in the repo. One good post to
  r/termux or r/linux_on_android moves more than any README edit.
- Every claim added to the README must name the version it was verified on.
  Otherwise the matrix rots silently (see `issues.md` #47).
