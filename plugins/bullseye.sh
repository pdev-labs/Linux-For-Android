# Debian bullseye (oldstable, glibc 2.31) plug-in for pre-4.x kernels.
#
# Modern Debian bookworm (glibc 2.36) cannot execute on Android 5/6
# (3.10 kernel): its ld.so dies with EINVAL at the first guest command
# (verified live on Oppo A37fw-class hardware). Bullseye's glibc 2.31
# (min kernel 3.2) runs fine there.
#
# Rootfs pinned to proot-distro v3.18.1 release assets; SHA256 taken from
# upstream commit 6c1ae10 ("debian: update plug-in", present in v4.0.0+).
# Deployed by install_linux.sh on legacy devices only (see
# deploy_legacy_plugins); never shipped upstream, so no update conflicts.
DISTRO_NAME="Debian (bullseye)"
DISTRO_COMMENT="Oldstable (bullseye) for Android 5/6. glibc 2.31 runs on 3.10 kernels."

TARBALL_URL['aarch64']="https://github.com/termux/proot-distro/releases/download/v3.18.1/debian-aarch64-pd-v3.18.1.tar.xz"
TARBALL_SHA256['aarch64']="044b3f7036f853b1fa61f2161862a3b35dbc604a33c81276e97e0dc44010e2ec"
TARBALL_URL['arm']="https://github.com/termux/proot-distro/releases/download/v3.18.1/debian-arm-pd-v3.18.1.tar.xz"
TARBALL_SHA256['arm']="10f1715790b9daccd763d9ce6e5557b970abd69fd84382c093200b76deed44da"

distro_setup() {
	# Configure en_US.UTF-8 locale.
	run_proot_cmd sed -i -E 's/# (en_US.UTF-8)/\1/g' /etc/locale.gen
	run_proot_cmd DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales
}
