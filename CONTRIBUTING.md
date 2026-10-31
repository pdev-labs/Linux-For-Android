# Contributing

Thanks for helping. This project installs real things on real phones, so the
bar is "does it work on a device", not "does it look right".

## Quick rules

- **One change per pull request.** A fix plus a refactor plus a new feature is
  three pull requests.
- **Never commit secrets** — no passwords, no `setup.conf`, no logs containing
  them.
- **Keep the docs honest.** If you change behaviour, change the text that
  describes it, including the verified matrix.
- **Say what you tested.** "Works on my machine" is not a test report.

## Set up

Only Termux is required to *use* the script; a normal Linux machine is enough
to *develop* it.

```bash
git clone https://github.com/pdev-labs/Linux-For-Android.git
cd Linux-For-Android
./install_linux.sh --help          # works outside Termux
./tests/test-all.sh                # stub-based suite, no device needed
```

The suite prints `PASS=<n> FAIL=<m>` and exits non-zero on failure. It also
fails when `README.md` still advertises the old numbers, so update the docs in
the same commit.

## Lint

```bash
shellcheck -S warning install_linux.sh lib/*.sh tests/*.sh
bash -n install_linux.sh
```

CI runs exactly these, so run them before pushing.

## Testing on a device

1. Install Termux from **F-Droid** (not Google Play).
2. `pkg install git openssh`, then `git clone` your branch.
3. Run the suite on the phone as well: `./tests/test-all.sh`.
4. Actually install a distribution and start the desktop. Capture
   `~/start-linux-session.log` if it fails.
5. Report the device, Android version, distro, desktop and backend in the PR.

## Adding a distribution

Everything a distro needs lives in one `case "$DISTRO"` block in
`install_linux.sh` (update command, package names, session command). Add it
there, add a stub test in `tests/test-all.sh`, and add a row to the verified
matrix only after a real install.

## Adding a desktop environment

1. Extend `gnome_available`-style gating if the desktop cannot run everywhere.
2. Add the package set for each distro family.
3. Add the session command in **both** places: `start-linux` and the VNC
   `xstartup` generator. `ask_desktop_environment` is the single menu source.
4. Add a test that the generated launcher and xstartup both reference it.

## Reporting bugs

Use the issue form: it asks for the version, device, distro and logs up front.
Security problems go through [SECURITY.md](SECURITY.md), never a public issue.

## Commit messages

Conventional Commits, one line, imperative:

```
fix: release display :1 after a killed X server
feat: add --list for scripted installs
docs: state which version the matrix was verified on
```

## Licence

Contributions are accepted under GPL-3.0. By opening a pull request you agree
to license your work under the same terms.
