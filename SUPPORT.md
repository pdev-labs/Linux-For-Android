# Support

This is a volunteer project with no paid support. The fastest route to an
answer depends on what you need.

## "It does not work on my phone"

1. Read the [detailed troubleshooting guide](docs/TROUBLESHOOTING.md). The
   [short index](README.md#troubleshooting-index) is in the README.
2. Check [issues.md](issues.md). The limitation may be known and deliberate
   (for example, no DRM access for Hyprland, no real `sudo`, GNOME is beta).
3. Collect a support bundle and open a bug report:

   ```bash
   ./install_linux.sh --diagnostics
   ```

   That writes `~/lfa-diagnostics-<date>.tar.gz` with the version, device,
   available space, installed distributions, launcher scripts, and logs. It
   contains no passwords. Attach it to the issue.

## "I want to ask a question or show my setup"

Use [Discussions](https://github.com/pdev-labs/Linux-For-Android/discussions)
once enabled. Until then, a bug report with the question label is fine.

## "I found a security problem"

Do not open a public issue. Use the private advisory link in
[SECURITY.md](SECURITY.md).

## "Can you add distro X or desktop Y?"

Open a feature request. Adding a distro is a self-contained change: one `case`
block plus a stub test. A pull request is welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## What is out of scope

- Hyprland on a phone that does not expose a DRM render node to apps (see
  [docs/WAYLAND.md](docs/WAYLAND.md))
- real privilege escalation or `systemctl` inside the guest (D10)
- Play Store Termux. It is broken by design and not supported.
