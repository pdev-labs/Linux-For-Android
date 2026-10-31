# GitHub Repo Improvements

What is missing from the repository itself (not the code) and what makes a
first-time visitor trust the project within 10 seconds.

Legend: **★** = impact on first impression, **⏱** = rough effort.
Status column is maintained by hand; see `tracker.md` for code work.

---

## P0 — Repo is factually inconsistent

| # | Item | ★ | ⏱ | Status |
|---|---|---|---|---|
| G1 | **Version numbering is broken.** Tags run to `v4.6.0` (Jul), the current release is `v1.6.1` (Oct), and `v4.6.0` is an ancestor of `main`. Decide: renumber forward (v5.0.0) or document the reset in `CHANGELOG.md` and mark v2–v4 historical. | ★★★★★ | 1 h | partial — documented in `CHANGELOG.md`; renumbering the old tags is a history rewrite |
| G2 | **Description is out of date** — it lists Ubuntu/Debian/Arch/Fedora/openSUSE/Void but omits **Kali, Alpine, Android 5/6 and GNOME**. | ★★★★ | 5 min | done — description names all 8 distros, Android 5.1→16, no root |
| G3 | **Missing topics:** `gnome`, `vnc`, `x11`, `android-5`, `termux-desktop`, `linux-desktop-android`, `alpine-linux`. | ★★★ | 5 min | done — 20 topics, including vnc/gnome/alpine-linux/android-5 |
| G4 | **Homepage URL empty** — point it at the latest release or `docs/`. | ★★★ | 2 min | done — points at the latest release |
| G5 | **40 of 94 commits are authored by `pdev@local`**, so half the contribution graph is invisible. Re-attribute them. | ★★★★ | 30 min | open — history rewrite |

## P1 — Proof it works (highest visual impact)

| # | Item | ★ | ⏱ | Status |
|---|---|---|---|---|
| G6 | **README has zero images.** Add a hero screenshot (phone frame + XFCE desktop). | ★★★★★ | 30 min | done — hero screenshot |
| G7 | **Add a 10–15 s GIF**: clone → menu → desktop appearing. | ★★★★★ | 45 min | open — needs a recording |
| G8 | **Distro screenshot grid** (Ubuntu/Kali/Fedora/Arch/Void/Alpine) — screenshots already exist. | ★★★★ | 20 min | done — `docs/screenshots/` grid |
| G9 | **Real-hardware photo** (phone showing the desktop) — strongest possible proof. | ★★★★ | 10 min | open — needs a photo |
| G10 | **Hard numbers in the README**: install times (27m45s GNOME, 3m32s Alpine/Oppo), disk (204 MB), RAM floor, FPS. | ★★★★ | 15 min | done — "Measured on hardware" table |
| G11 | **"Hard problems solved" section** (missing system bus, snapd in proot, kernel 3.10 glibc). Reads like an engineer wrote it. | ★★★★ | 30 min | done — README section |
| G12 | **Device matrix above the fold**, with an "as of vX.Y.Z" column. | ★★★★ | 10 min | done — matrix with "Verified on" |

## P2 — Repository health files (GitHub "Community Standards" is 1/6)

| # | Item | ★ | ⏱ | Status |
|---|---|---|---|---|
| G13 | `SECURITY.md` — mandatory for a project that installs root. | ★★★★★ | 10 min | done |
| G14 | `.github/ISSUE_TEMPLATE/` — bug form asking device / Android version / distro / backend / log. | ★★★★★ | 20 min | done |
| G15 | `CONTRIBUTING.md` — one command to run tests (`PASS=...`), style rules. | ★★★★ | 20 min | done |
| G16 | `CHANGELOG.md` (Keep a Changelog). | ★★★★ | 30 min | done |
| G17 | `CODE_OF_CONDUCT.md` | ★★ | 5 min | done |
| G18 | `.github/PULL_REQUEST_TEMPLATE.md` | ★★★ | 10 min | done |
| G19 | `.github/CODEOWNERS`, `.github/FUNDING.yml`, `SUPPORT.md` | ★★ | 10 min | partial — CODEOWNERS added; FUNDING needs an account |
| G20 | `.gitattributes` (text/binary rules for wallpapers) + `.editorconfig` | ★★ | 5 min | done |

## P3 — Automation and release engineering

| # | Item | ★ | ⏱ | Status |
|---|---|---|---|---|
| G21 | **CI workflow**: `shellcheck` + `bash -n` + `tests/test-all.sh` on push/PR. Add the badge. | ★★★★★ | 1 h | done — `.github/workflows/ci.yml` |
| G22 | **Protect `main`** (require PR + passing checks, block force-push) and enable delete-branch-on-merge. | ★★★★ | 5 min | partial — delete-branch-on-merge enabled; branch protection left to the owner |
| G23 | **Release assets**: versioned `install_linux.sh` + `SHA256SUMS` attached to every release. | ★★★★ | 30 min | done — v1.7.0 ships `install_linux.sh` + `SHA256SUMS` |
| G24 | **Pinned install instructions** (`git clone --branch vX.Y.Z`), so users do not install an unreviewed HEAD. | ★★★★ | 10 min | done — pinned `--branch` clone |
| G25 | **Release automation** (tag → notes → assets) instead of manual `gh release create`. | ★★★ | 2 h | partial — `gh release create` is scripted by hand, not by a workflow |
| G26 | **Milestones per release** (Projects is enabled but empty). | ★★★ | 15 min | open |
| G27 | **Area labels**: `area: installer`, `distro: alpine`, `backend: vnc`, `needs-hardware`, `regression`. | ★★★ | 10 min | open |
| G28 | **Enable Discussions** + pinned "post your device" thread; disable the empty Wiki. | ★★★ | 10 min | done — Discussions on, empty Wiki disabled |

## P4 — Documentation inside the repo

| # | Item | ★ | ⏱ | Status |
|---|---|---|---|---|
| G29 | `docs/ARCHITECTURE.md` — the generator-inside-generator design, session model, why proot/X11 only. | ★★★★ | 1 h | done |
| G30 | `docs/DECISIONS.md` — why proot, why no Wayland, why ritual sudo, why GNOME is beta. | ★★★★ | 45 min | done |
| G31 | `docs/` index; `docs/TEST-REPORT.md` linked from the first screen. | ★★★ | 15 min | done — `docs/README.md` index |
| G32 | Link `issues.md` (known issues) from the README with severities. | ★★★★ | 10 min | done |
| G33 | Badges: release version, CI status, downloads, license — replace the three static ones. | ★★★★ | 15 min | done — CI, release, Android range, distros |
| G34 | Custom **social preview image** (Discord/Reddit shares currently show a grey card). | ★★★★★ | 10 min | open — needs an image upload |
| G35 | Fix README ToC anchors (currently depend on emoji headings) + symptom index for the 16 troubleshooting entries. | ★★★ | 30 min | done — symptom index with stable anchors |

## P5 — Polish

| # | Item | ★ | ⏱ | Status |
|---|---|---|---|---|
| G36 | 60-second quickstart (max 3 code blocks) above the deep explanation. | ★★★★ | 15 min | done — Quick start |
| G37 | Screenshots inside the troubleshooting section (black screen, panel missing). | ★★★ | 20 min | open |
| G38 | Rename consistency: repo `Linux-For-Android`, product "Linux for Android Manager", command `start-linux`. Pick one story. | ★★ | 30 min | partial — naming explained in CONTRIBUTING |
| G39 | Add a logo/icon file to the repo (banner is inline HTML only). | ★★★ | 20 min | open |
| G40 | "Known issues" banner at the top, linking `issues.md`. | ★★★ | 10 min | done — banner above the fold |

---

## The five that change everything

1. **G6 + G7** — hero screenshot and GIF. Images already exist on disk.
2. **G21 + G22** — real CI with a green badge, protected `main`.
3. **G13 + G14** — `SECURITY.md` and issue templates (30 minutes total).
4. **G1 + G16** — fix version numbering, add `CHANGELOG.md`.
5. **G23 + G24** — release assets with checksums and pinned install commands.

## Notes

- Stars/forks (5/1) cannot be "fixed" in the repo; one good post to
  r/termux or r/linux_on_android moves more than any README edit.
- Every claim added to the README must name the version it was verified on,
  otherwise the matrix rots silently (see `issues.md` #47).
