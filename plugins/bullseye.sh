# Debian bullseye (oldstable, glibc 2.31) plug-in for pre-4.x kernels.
#
# Modern Debian bookworm (glibc 2.36) cannot execute on Android 5/6
# (3.10 kernel): its ld.so dies with EINVAL at the first guest command
# (verified live on Oppo A37fw-class hardware). Bullseye's glibc 2.31
# (min kernel 3.2) runs fine there.
#
# Rootfs: Docker Hub library/debian:bullseye-slim layers (single layer,
# no whiteouts), re-hosted at pdev-labs/Linux-For-Android release
# 'legacy-rootfs-v1' so the URL cannot rot. SHA256 verified against the
# registry digest at packaging time (see release notes).
# NOTE: docker-slim rootfs has no 'locales' package, so there is no
# distro_setup here; install_linux.sh installs what it needs via apt.
DISTRO_NAME="Debian (bullseye)"
DISTRO_COMMENT="Oldstable (bullseye) for Android 5/6. glibc 2.31 runs on 3.10 kernels."

TARBALL_URL['aarch64']="https://github.com/pdev-labs/Linux-For-Android/releases/download/legacy-rootfs-v1/debian-bullseye-aarch64.tar.gz"
TARBALL_SHA256['aarch64']="104799d4ff5b18bad31a13cbbc383730eebef29a1cac161b7905792a8dbe5bd3"
TARBALL_URL['arm']="https://github.com/pdev-labs/Linux-For-Android/releases/download/legacy-rootfs-v1/debian-bullseye-arm.tar.gz"
TARBALL_SHA256['arm']="5ea592ba871a5245db3c645624a50a3dbc8e59a8ce6f42c9c0425e533dbfdf8f"

# Docker layer tarballs have NO top-level directory (members are
# ./, bin/, etc/...), so nothing may be stripped (default is 1).
TARBALL_STRIP_OPT=0
