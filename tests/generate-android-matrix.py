#!/usr/bin/env python3
"""Generate the Android CI scenario matrix.

Modes:
  smoke    ~6 jobs, suitable for pull requests
  reduced  ~40 jobs, suitable for a weekly run
  full     every valid distro x desktop x backend x Android version

The output is a GitHub Actions matrix object:

  {"include": [{"name": "...", "api": "33", ...}, ...]}

Only combinations LFA claims to support are generated. Unsupported ones are
tested by the `legacy` and refusal scenarios instead of being silently run.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, asdict

MODERN_APIS = [26, 29, 31, 33, 34, 35, 36]
BOUNDARY_APIS = [24, 25]
LEGACY_API = 23
BEST_EFFORT_APIS = [21, 22]

DISTRO_DESKTOPS = {
    "ubuntu": ["xfce4", "lxde", "mate", "gnome"],
    "debian": ["xfce4", "lxde", "mate", "gnome"],
    "kali": ["xfce4", "lxde", "mate", "gnome"],
    "fedora": ["xfce4", "lxde", "mate", "gnome"],
    "opensuse": ["xfce4", "lxde", "mate", "gnome"],
    "archlinux": ["xfce4", "lxde", "mate", "gnome"],
    "void": ["xfce4", "lxde", "mate"],
    "alpine": ["xfce4", "mate"],
}

# Android 8+ can run Termux:X11. Older devices use VNC only.
MODERN_BACKENDS = ["x11", "vnc", "both"]
LEGACY_BACKENDS = ["vnc"]


@dataclass(frozen=True)
class Scenario:
    name: str
    api: str
    arch: str
    target: str
    distro: str
    desktop: str
    backend: str
    scenario: str = "install"

    def key(self) -> tuple[str, ...]:
        return (self.api, self.distro, self.desktop, self.backend, self.scenario)


def arch_for(api: int) -> str:
    # API 23 is the reliable legacy image; use x86. Modern images are x86_64.
    return "x86" if api <= 23 else "x86_64"


def target_for(api: int) -> str:
    # google_apis (not playstore) is debuggable and has no Play services.
    if api <= 23:
        return "google_apis"
    return "google_apis"


def scenario_name(api: int, distro: str, desktop: str, backend: str, kind: str) -> str:
    return f"api{api}-{distro}-{desktop}-{backend}-{kind}"


def make(api: int, distro: str, desktop: str, backend: str, kind: str = "install") -> Scenario:
    return Scenario(
        name=scenario_name(api, distro, desktop, backend, kind),
        api=str(api),
        arch=arch_for(api),
        target=target_for(api),
        distro=distro,
        desktop=desktop,
        backend=backend,
        scenario=kind,
    )


def smoke() -> list[Scenario]:
    # Keep PR smoke on the reliable modern Termux. API 23 uses archived
    # repositories and lives in the weekly/full matrix instead.
    return [
        make(26, "ubuntu", "xfce4", "x11"),
        make(33, "debian", "xfce4", "vnc"),
        make(36, "ubuntu", "xfce4", "both", "switch"),
        make(24, "debian", "xfce4", "vnc", "legacy"),
        make(33, "alpine", "xfce4", "vnc"),
        make(33, "ubuntu", "xfce4", "vnc", "software"),
    ]


def reduced() -> list[Scenario]:
    out: list[Scenario] = []
    # Every distro, one desktop, one backend.
    for distro in DISTRO_DESKTOPS:
        out.append(make(33, distro, "xfce4", "vnc"))
    # Every desktop on a representative distro.
    for desktop in DISTRO_DESKTOPS["ubuntu"]:
        out.append(make(33, "ubuntu", desktop, "x11"))
    # Android version sweep.
    for api in [LEGACY_API, *BOUNDARY_APIS, *MODERN_APIS]:
        backend = "vnc" if api < 26 else "vnc"
        kind = "legacy" if api < 26 else "install"
        out.append(make(api, "debian", "xfce4", backend, kind))
    # Legacy distro coverage.
    out.append(make(LEGACY_API, "debian", "xfce4", "vnc", "legacy"))
    # Switching and removal.
    out.append(make(33, "ubuntu", "xfce4", "both", "switch"))
    # Software installation and launch probes.
    out.append(make(33, "ubuntu", "xfce4", "vnc", "software"))
    return dedupe(out)


def full(include_best_effort: bool = False) -> list[Scenario]:
    out: list[Scenario] = []
    legacy = [LEGACY_API, *BOUNDARY_APIS]
    if include_best_effort:
        legacy = [*BEST_EFFORT_APIS, *legacy]
    for api in legacy:
        for distro, desktops in DISTRO_DESKTOPS.items():
            for desktop in desktops:
                if api < 24 and distro not in ("alpine", "debian"):
                    # Android 5/6: glibc distros are not reliable.
                    continue
                if api < 26 and desktop == "gnome":
                    # GNOME is hidden below Android 8 by the installer.
                    continue
                out.append(make(api, distro, desktop, "vnc", "legacy"))
    for api in MODERN_APIS:
        for distro, desktops in DISTRO_DESKTOPS.items():
            for desktop in desktops:
                for backend in MODERN_BACKENDS:
                    out.append(make(api, distro, desktop, backend))
    # One switching and one software scenario per modern API.
    for api in MODERN_APIS:
        out.append(make(api, "ubuntu", "xfce4", "both", "switch"))
        out.append(make(api, "ubuntu", "xfce4", "vnc", "software"))
    return dedupe(out)


def dedupe(items: list[Scenario]) -> list[Scenario]:
    seen: set[tuple[str, ...]] = set()
    out: list[Scenario] = []
    for item in items:
        if item.key() in seen:
            continue
        seen.add(item.key())
        out.append(item)
    return out


def shard(items: list[Scenario], index: int, total: int) -> list[Scenario]:
    if total <= 1:
        return items
    return [item for pos, item in enumerate(items) if pos % total == index]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["smoke", "reduced", "full"], default="smoke")
    parser.add_argument("--format", choices=["json", "list"], default="json")
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--total-shards", type=int, default=1)
    parser.add_argument("--include-best-effort", action="store_true",
                        help="include API 21/22 in full mode")
    args = parser.parse_args()

    if args.total_shards < 1:
        parser.error("--total-shards must be at least 1")
    if not (0 <= args.shard < args.total_shards):
        parser.error("--shard must be between 0 and total-shards - 1")

    if args.mode == "smoke":
        items = smoke()
    elif args.mode == "reduced":
        items = reduced()
    else:
        items = full(include_best_effort=args.include_best_effort)

    items = shard(items, args.shard, args.total_shards)

    if args.format == "list":
        for item in items:
            print(item.name)
    else:
        json.dump({"include": [asdict(item) for item in items]}, sys.stdout, indent=None)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
