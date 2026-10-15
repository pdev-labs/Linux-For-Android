/*
 * libuid0 - minimal fakeroot-style UID emulation for proot-on-Android.
 *
 * Used by the ritual-only sudo shim (LD_PRELOAD) so that tools which demand
 * uid 0 (dpkg/apt, pacman, ...) proceed inside a user shell. Real kernel
 * identity never changes (NO_NEW_PRIVS + no CAP_CHOWN make that impossible);
 * instead identity queries are answered as 0 and ownership changes are
 * reported as successful (files really land owned by the Termux uid, which
 * is consistent everywhere in the guest).
 *
 * Deliberately daemon-free (no SysV IPC like classic fakeroot, which is
 * unavailable in --no-sysvipc proot sessions) and ptrace-free (would fight
 * proot itself). Plain leaf functions only: builds with gcc -shared
 * -nostdlib, no libc headers or symbols required, so the same source builds
 * on any guest arch/libc (glibc, musl alike).
 *
 * Build:  gcc -shared -nostdlib -O2 -o libuid0.so uid0.c
 * Use:    LD_PRELOAD=/usr/local/lib/libuid0.so <command>
 */
typedef unsigned int uid_t;
typedef unsigned int gid_t;

uid_t getuid(void) { return 0; }
uid_t geteuid(void) { return 0; }
gid_t getgid(void) { return 0; }
gid_t getegid(void) { return 0; }

int getresuid(uid_t *r, uid_t *e, uid_t *s)
{
	if (r) *r = 0;
	if (e) *e = 0;
	if (s) *s = 0;
	return 0;
}

int getresgid(gid_t *r, gid_t *e, gid_t *s)
{
	if (r) *r = 0;
	if (e) *e = 0;
	if (s) *s = 0;
	return 0;
}

/* Ownership changes cannot take effect without CAP_CHOWN; report success
 * so install scripts proceed. Files keep their real (Termux uid) owner,
 * which is what the rest of the guest already sees. */
int chown(const char *p, uid_t o, gid_t g)
{
	(void)p; (void)o; (void)g;
	return 0;
}

int lchown(const char *p, uid_t o, gid_t g)
{
	(void)p; (void)o; (void)g;
	return 0;
}

int fchown(int f, uid_t o, gid_t g)
{
	(void)f; (void)o; (void)g;
	return 0;
}

int fchownat(int d, const char *p, uid_t o, gid_t g, int fl)
{
	(void)d; (void)p; (void)o; (void)g; (void)fl;
	return 0;
}
