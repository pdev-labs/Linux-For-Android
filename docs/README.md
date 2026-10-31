# Documentation index

Start here if you want to understand the project rather than install it.

| Document | What it answers |
|---|---|
| [README](../README.md) | What it does, screenshots, install, troubleshooting |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the installer, launchers and display back ends fit together |
| [DECISIONS.md](DECISIONS.md) | Why proot, why no Wayland, why the sudo shim is a ritual |
| [TEST-REPORT.md](TEST-REPORT.md) | What was verified, on which device, with which version |
| [issues.md](../issues.md) | Every known defect and limitation, with severity and status |
| [ghissue.md](../ghissue.md) | Repository-level improvements (metadata, CI, releases) |
| [tracker.md](../tracker.md) | Live progress for the audit above |
| [CHANGELOG.md](../CHANGELOG.md) | Release history and the version-numbering note |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | How to change code and test it on a real device |
| [SECURITY.md](../SECURITY.md) | Threat model, what is deliberately not protected, how to report |

## Reading order for a new contributor

1. `README.md` quick start — you should be able to run the suite.
2. `ARCHITECTURE.md` — the mental model in ten minutes.
3. `DECISIONS.md` — so you do not re-propose Wayland or systemd.
4. `issues.md` — pick something marked *partial* or *deferred*.
5. `CONTRIBUTING.md` — the lint and device-test gate before a pull request.
