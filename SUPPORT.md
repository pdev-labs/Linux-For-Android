# Support

This is a volunteer project with no paid support. The fastest route to an
answer depends on what you need.

## "It does not work on my phone"

1. Read the troubleshooting index in the [README](../README.md#-troubleshooting-index).
2. Check [issues.md](../issues.md) — the limitation may be known and deliberate
   (for example, no Wayland, no real `sudo`, GNOME is beta).
3. Collect a support bundle and open a bug report:

   ```bash
   ./install_linux.sh --diagnostics
   ```

   That writes `~/lfa-diagnostics-<date>.tar.gz` with the version, device,
   available space, installed distributions, launcher scripts and logs — and
   **no passwords**. Attach it to the issue.

## "I want to ask a question / show my setup"

Use [Discussions](https://github.com/pdev-labs/Linux-For-Android/discussions)
once enabled; until then, a bug report with the *question* label is fine.

## "I found a security problem"

Do **not** open a public issue. Use the private advisory link in
[SECURITY.md](../SECURITY.md).

## "Can you add distro X / desktop Y?"

Open a feature request. Adding a distro is a self-contained change (one `case`
block plus a stub test), so a pull request is welcome — see
[CONTRIBUTING.md](../CONTRIBUTING.md).

## What is out of scope

- Wayland sessions (see [DECISIONS.md](DECISIONS.md), D2)
- real privilege escalation or `systemctl` inside the guest (D10)
- Play Store Termux: it is broken by design and not supported
