# Security Policy

## Supported versions

Only the latest release receives fixes. If you are on an older tag, update
first (see *Reporting a vulnerability*).

| Version | Supported |
|---|---|
| latest release | ✅ |
| `main` | ✅ (development) |
| older tags | ❌ |

## What this project does that matters for security

`install_linux.sh` runs with your Termux user's privileges, installs packages,
writes launchers into `$PREFIX/bin`, and creates a `sudo`-like shim inside the
guest. It does **not** require root on the device and never uses `su`.

Known, deliberate design limits — please read these before reporting them:

1. **`sudo` cannot elevate.** Android's `NO_NEW_PRIVS` makes setuid binaries
   useless inside proot, so the shim only performs the password ritual. It is
   not a privilege boundary and must not be treated as one.
2. **Everyone inside the guest is the same UID.** proot maps all guest users
   onto the Termux app UID. File ownership inside the guest is cosmetic.
3. **The guest is not a sandbox.** Anything running in the guest can read the
   Termux home directory that is bind-mounted into it.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

- Open a private report: <https://github.com/pdev-labs/Linux-For-Android/security/advisories/new>
- Include: affected version (`./install_linux.sh --version`), Android version,
  distro/desktop, and the smallest reproduction you can manage.

You can expect an initial reply within **7 days**. If the issue is confirmed,
a fix ships in the next release and the advisory is published with credit
unless you ask to stay anonymous.

## Scope

In scope:

- command injection or path traversal through installer inputs (distro name,
  instance name, hostname, username, timezone)
- secret leakage: install passwords, the VNC password, or the sudo shim secret
  ending up readable outside the intended mode-`0600` file
- trusting a downloaded artifact from a host we should not trust
- anything that runs code as the *Termux* user without the user asking

Out of scope:

- the documented proot limitations above
- attacks that already require code execution inside the guest
- vulnerabilities in upstream packages, Termux, or the distros themselves

## Hardening already in place

- Install-time secrets are written to a mode-`0600` file that is deleted after
  use and on interrupt (`trap`).
- The sudo shim stores a **salted SHA-256 hash**, never the password, and is
  mode `0700`.
- The Microsoft package-signing key is verified by fingerprint before the
  VS Code repository is added.
- Scraped download URLs are restricted to the vendor's own hosts.
- `:latest` container images can be pinned with `LFA_IMAGE_<DISTRO>`.
