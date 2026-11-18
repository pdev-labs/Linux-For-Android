/*
 * lfa-usb-node.c - USB session preload for Linux-for-Android guests.
 *
 * Android hands Termux one real usbfs file descriptor per USB device, but a
 * proot guest cannot create /dev/bus/usb/BBB/DDD nodes (no mknod) and its
 * /sys belongs to Android.  This object, preloaded for a session, makes the
 * guest look like a normal Linux box:
 *
 *   open("/dev/bus/usb/001/002")   returns a duplicate of the real
 *                                  descriptor from LFA_USB_MAP
 *   open("/dev/ttyUSB0")           returns a duplicate of the pty slave
 *                                  from LFA_USB_TTY_FD
 *   statfs()/fstatfs() on /sys     reports SYSFS_MAGIC, so libudev accepts
 *                                  the synthetic /sys/bus/usb/devices tree
 *   udev_monitor_*()               returns an idle monitor: there is no
 *                                  udev daemon in an Android proot guest
 *   ioctl(TIOCMBIS/BIC/MSET)       forwards DTR/RTS changes on the pty to
 *                                  the tty bridge (for esptool reset)
 *
 * Built with -nostdlib: it has no DT_NEEDED entries and only uses symbols
 * that glibc, musl and bionic all export, so one build per CPU architecture
 * works in every distribution.  Everything is inert unless the LFA_USB_*
 * environment of a session is present.
 *
 * Environment:
 *   LFA_USB_MAP="001/002=7;001/003=8"   usbfs node -> inherited descriptor
 *   LFA_USB_TTY="/dev/ttyUSB0"          serial node name
 *   LFA_USB_TTY_FD=9                    inherited pty slave descriptor
 *   LFA_USB_TTY_CTL=10                  pipe for DTR/RTS reports
 */

typedef unsigned long lfa_size_t;

extern char **environ;
extern long syscall(long number, ...);
extern int *__errno_location(void);

#define LFA_AT_FDCWD (-100)
#define LFA_O_CREAT 0100
#define LFA_O_CLOEXEC 02000000
#define LFA_EBADF 9
#define LFA_SYSFS_MAGIC 0x62656572L
#define LFA_MAX_DEV 16
#define LFA_PATH_MAX 64

#define LFA_TIOCMBIS 0x5416
#define LFA_TIOCMBIC 0x5417
#define LFA_TIOCMSET 0x5418
#define LFA_TIOCMGET 0x5415

#if defined(__x86_64__)
# define LFA_NR_openat 257
# define LFA_NR_dup 32
# define LFA_NR_dup3 292
# define LFA_NR_fcntl 72
# define LFA_NR_ioctl 16
# define LFA_NR_pipe2 293
# define LFA_NR_write 1
# define LFA_NR_close 3
# define LFA_NR_readlinkat 267
# define LFA_NR_fstatfs 138
# define LFA_NR_fstatfs64 138
# define LFA_NR_statfs 137
# define LFA_NR_statfs64 137
#else
# if defined(__aarch64__)
#  define LFA_NR_openat 56
#  define LFA_NR_dup 23
#  define LFA_NR_dup3 24
#  define LFA_NR_fcntl 25
#  define LFA_NR_ioctl 29
#  define LFA_NR_pipe2 59
#  define LFA_NR_write 64
#  define LFA_NR_close 57
#  define LFA_NR_readlinkat 78
#  define LFA_NR_fstatfs 44
#  define LFA_NR_fstatfs64 44
#  define LFA_NR_statfs 43
#  define LFA_NR_statfs64 43
# else
#  if defined(__arm__)
#   define LFA_NR_openat 322
#   define LFA_NR_dup 41
#   define LFA_NR_dup3 358
#   define LFA_NR_fcntl 55
#   define LFA_NR_ioctl 54
#   define LFA_NR_pipe2 359
#   define LFA_NR_write 4
#   define LFA_NR_close 6
#   define LFA_NR_readlinkat 332
#   define LFA_NR_fstatfs 100
#   define LFA_NR_fstatfs64 267
#   define LFA_NR_statfs 99
#   define LFA_NR_statfs64 266
#  else
#   if defined(__i386__)
#    define LFA_NR_openat 295
#    define LFA_NR_dup 41
#    define LFA_NR_dup3 330
#    define LFA_NR_fcntl 55
#    define LFA_NR_ioctl 54
#    define LFA_NR_pipe2 331
#    define LFA_NR_write 4
#    define LFA_NR_close 6
#    define LFA_NR_readlinkat 305
#    define LFA_NR_fstatfs 100
#    define LFA_NR_fstatfs64 269
#    define LFA_NR_statfs 99
#    define LFA_NR_statfs64 268
#   else
#    error "lfa-usb-node: unsupported architecture"
#   endif
#  endif
# endif
#endif

struct lfa_map {
    char path[LFA_PATH_MAX];
    int fd;
};

static struct lfa_map lfa_maps[LFA_MAX_DEV];
static int lfa_map_count = -1;
static int lfa_tty_fd = -1;
static int lfa_tty_ctl = -1;
static char lfa_tty_path[LFA_PATH_MAX];
static int lfa_tty_parsed;
static int lfa_tty_dups[64];
static int lfa_tty_dup_count;
static int lfa_lines = 0x6;   /* DTR | RTS, until the client changes it */

static lfa_size_t lfa_strlen(const char *s)
{
    lfa_size_t n = 0;
    while (s && s[n]) n++;
    return n;
}

static int lfa_streq(const char *a, const char *b)
{
    lfa_size_t i = 0;
    if (!a || !b) return 0;
    while (a[i] && b[i]) {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static char *lfa_getenv(const char *name)
{
    lfa_size_t n = lfa_strlen(name);
    char **e;
    if (!environ) return 0;
    for (e = environ; *e; e++) {
        lfa_size_t i = 0;
        while (i < n && (*e)[i] == name[i]) i++;
        if (i == n && (*e)[n] == '=') return *e + n + 1;
    }
    return 0;
}

static int lfa_atoi(const char *s, int *out)
{
    int value = 0, digits = 0;
    if (!s) return 0;
    while (*s >= '0' && *s <= '9') {
        value = value * 10 + (*s - '0');
        s++;
        digits = 1;
    }
    if (!digits || *s) return 0;
    *out = value;
    return 1;
}

static void lfa_parse_map(void)
{
    const char *p = lfa_getenv("LFA_USB_MAP");
    lfa_map_count = 0;
    if (!p) return;

    while (*p && lfa_map_count < LFA_MAX_DEV) {
        lfa_size_t plen = 0;
        int fd;
        const char *q;
        while (p[plen] && p[plen] != '=' && p[plen] != ';') plen++;
        if (plen < 5 || p[plen] != '=') break;

        q = p + plen + 1;
        if (!lfa_atoi(q, &fd)) {
            while (*q && *q != ';') q++;
            p = (*q == ';') ? q + 1 : q;
            continue;
        }

        {
            struct lfa_map *m = &lfa_maps[lfa_map_count];
            const char *pre = "/dev/bus/usb/";
            lfa_size_t i = 0, j = 0;
            while (pre[i] && i < LFA_PATH_MAX - 2) m->path[i] = pre[i], i++;
            while (j < plen && i < LFA_PATH_MAX - 1) m->path[i++] = p[j++];
            m->path[i] = 0;
            m->fd = fd;
            lfa_map_count++;
        }
        while (*q && *q != ';') q++;
        p = (*q == ';') ? q + 1 : q;
    }
}

static void lfa_parse_tty(void)
{
    const char *path;
    lfa_tty_parsed = 1;
    lfa_tty_fd = -1;
    lfa_tty_ctl = -1;
    lfa_tty_path[0] = 0;

    path = lfa_getenv("LFA_USB_TTY");
    if (!path || path[0] != '/') return;
    {
        lfa_size_t i = 0;
        while (path[i] && i < LFA_PATH_MAX - 1) {
            lfa_tty_path[i] = path[i];
            i++;
        }
        lfa_tty_path[i] = 0;
    }
    if (!lfa_atoi(lfa_getenv("LFA_USB_TTY_FD"), &lfa_tty_fd)) lfa_tty_fd = -1;
    if (!lfa_atoi(lfa_getenv("LFA_USB_TTY_CTL"), &lfa_tty_ctl)) lfa_tty_ctl = -1;
}

static int lfa_find(const char *path)
{
    int i;
    if (!path || path[0] != '/') return -1;
    if (!lfa_tty_parsed) lfa_parse_tty();
    if (lfa_tty_fd >= 0 && lfa_streq(path, lfa_tty_path)) return lfa_tty_fd;
    if (path[1] != 'd' || path[2] != 'e' || path[3] != 'v') return -1;
    if (lfa_map_count < 0) lfa_parse_map();
    for (i = 0; i < lfa_map_count; i++)
        if (lfa_streq(path, lfa_maps[i].path)) return lfa_maps[i].fd;
    return -1;
}

static void lfa_tty_remember(int fd)
{
    int i, keep = 0;
    if (lfa_tty_dup_count >= 64) {
        /* Drop descriptors the client has closed so long sessions do not
         * run out of tracking slots. */
        for (i = 0; i < lfa_tty_dup_count; i++) {
            int candidate = lfa_tty_dups[i];
            if (syscall(LFA_NR_fcntl, candidate, 1 /* F_GETFD */, 0) >= 0)
                lfa_tty_dups[keep++] = candidate;
        }
        lfa_tty_dup_count = keep;
        if (keep >= 64) return;
    }
    lfa_tty_dups[lfa_tty_dup_count++] = fd;
}

static int lfa_dup(int fd, int cloexec)
{
    long r;
    if (!lfa_tty_parsed) lfa_parse_tty();
    r = syscall(LFA_NR_dup, fd);
    if (r < 0) {
        *__errno_location() = LFA_EBADF;
        return -1;
    }
    if (cloexec)
        syscall(LFA_NR_fcntl, r, 2 /* F_SETFD */, 1 /* FD_CLOEXEC */);
    if (fd >= 0 && fd == lfa_tty_fd)
        lfa_tty_remember((int)r);
    return (int)r;
}

static int lfa_is_tty_fd(int fd)
{
    int i;
    if (!lfa_tty_parsed) lfa_parse_tty();
    if (lfa_tty_fd >= 0 && fd == lfa_tty_fd) return 1;
    for (i = 0; i < lfa_tty_dup_count; i++)
        if (lfa_tty_dups[i] == fd) return 1;
    return 0;
}

static int lfa_is_sys(const char *path)
{
    return path && path[0] == '/' && path[1] == 's' && path[2] == 'y' &&
           path[3] == 's';
}

static int lfa_is_sys_fd(int fd)
{
    char link[LFA_PATH_MAX];
    char proc[32];
    long n;
    int i = 0, value = fd, digits = 0;

    /* /proc/self/fd/N without snprintf. */
    {
        const char *pre = "/proc/self/fd/";
        while (pre[i]) { proc[i] = pre[i]; i++; }
    }
    if (fd == 0) { proc[i++] = '0'; digits = 1; }
    else {
        char tmp[12];
        int j = 0;
        while (value > 0) { tmp[j++] = (char)('0' + value % 10); value /= 10; }
        while (j > 0) { proc[i++] = tmp[--j]; digits = 1; }
    }
    if (!digits) return 0;
    proc[i] = 0;

    n = syscall(LFA_NR_readlinkat, LFA_AT_FDCWD, proc, link, sizeof(link) - 1);
    if (n <= 0) return 0;
    link[n] = 0;
    return lfa_is_sys(link);
}

/* ------------------------------------------------------------------ */
/* open() interception                                                 */
/* ------------------------------------------------------------------ */

static int lfa_open_common(int dirfd, const char *path, int flags, int mode)
{
    int fd = lfa_find(path);
    if (fd >= 0) return lfa_dup(fd, flags & LFA_O_CLOEXEC);
    return (int)syscall(LFA_NR_openat, dirfd, path, flags, mode);
}

int open(const char *path, int flags, ...)
{
    int mode = 0;
    if (flags & LFA_O_CREAT) {
        __builtin_va_list ap;
        __builtin_va_start(ap, flags);
        mode = __builtin_va_arg(ap, int);
        __builtin_va_end(ap);
    }
    return lfa_open_common(LFA_AT_FDCWD, path, flags, mode);
}

int open64(const char *path, int flags, ...)
{
    int mode = 0;
    if (flags & LFA_O_CREAT) {
        __builtin_va_list ap;
        __builtin_va_start(ap, flags);
        mode = __builtin_va_arg(ap, int);
        __builtin_va_end(ap);
    }
    return lfa_open_common(LFA_AT_FDCWD, path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...)
{
    int mode = 0;
    if (flags & LFA_O_CREAT) {
        __builtin_va_list ap;
        __builtin_va_start(ap, flags);
        mode = __builtin_va_arg(ap, int);
        __builtin_va_end(ap);
    }
    return lfa_open_common(dirfd, path, flags, mode);
}

int openat64(int dirfd, const char *path, int flags, ...)
{
    int mode = 0;
    if (flags & LFA_O_CREAT) {
        __builtin_va_list ap;
        __builtin_va_start(ap, flags);
        mode = __builtin_va_arg(ap, int);
        __builtin_va_end(ap);
    }
    return lfa_open_common(dirfd, path, flags, mode);
}

int __open_2(const char *path, int flags)
{
    return lfa_open_common(LFA_AT_FDCWD, path, flags, 0);
}

int __open64_2(const char *path, int flags)
{
    return lfa_open_common(LFA_AT_FDCWD, path, flags, 0);
}

int __openat_2(int dirfd, const char *path, int flags)
{
    return lfa_open_common(dirfd, path, flags, 0);
}

/* ------------------------------------------------------------------ */
/* sysfs magic: libudev refuses syspaths that are not on sysfs          */
/* ------------------------------------------------------------------ */

static int lfa_usb_session(void)
{
    if (lfa_map_count < 0) lfa_parse_map();
    if (!lfa_tty_parsed) lfa_parse_tty();
    return lfa_map_count > 0 || lfa_tty_fd >= 0;
}

int fstatfs64(int fd, void *buf)
{
    long r = syscall(LFA_NR_fstatfs64, fd, buf);
    if (r == 0 && buf && lfa_usb_session() && lfa_is_sys_fd(fd))
        *(long *)buf = LFA_SYSFS_MAGIC;
    return (int)r;
}

int fstatfs(int fd, void *buf)
{
    long r = syscall(LFA_NR_fstatfs, fd, buf);
    if (r == 0 && buf && lfa_usb_session() && lfa_is_sys_fd(fd))
        *(long *)buf = LFA_SYSFS_MAGIC;
    return (int)r;
}

int statfs64(const char *path, void *buf)
{
    long r = syscall(LFA_NR_statfs64, path, buf);
    if (r == 0 && buf && lfa_usb_session() && lfa_is_sys(path))
        *(long *)buf = LFA_SYSFS_MAGIC;
    return (int)r;
}

int statfs(const char *path, void *buf)
{
    long r = syscall(LFA_NR_statfs, path, buf);
    if (r == 0 && buf && lfa_usb_session() && lfa_is_sys(path))
        *(long *)buf = LFA_SYSFS_MAGIC;
    return (int)r;
}

/* ------------------------------------------------------------------ */
/* udev monitor: idle stand-in (no udev daemon inside an Android guest) */
/* ------------------------------------------------------------------ */

static int lfa_monitor_fd = -1;
static char lfa_monitor_dummy[8];

static void lfa_ensure_monitor_pipe(void)
{
    int fds[2];
    if (lfa_monitor_fd >= 0) return;
    if (syscall(LFA_NR_pipe2, fds, LFA_O_CLOEXEC) == 0)
        lfa_monitor_fd = fds[0];
}

void *udev_monitor_new_from_netlink(void *udev, const char *name)
{
    (void)udev; (void)name;
    lfa_ensure_monitor_pipe();
    return lfa_monitor_fd >= 0 ? (void *)lfa_monitor_dummy : 0;
}

int udev_monitor_filter_add_match_subsystem_devtype(void *mon,
        const char *subsystem, const char *devtype)
{
    (void)mon; (void)subsystem; (void)devtype;
    return 0;
}

int udev_monitor_enable_receiving(void *mon) { (void)mon; return 0; }

int udev_monitor_get_fd(void *mon)
{
    (void)mon;
    lfa_ensure_monitor_pipe();
    return lfa_monitor_fd;
}

void *udev_monitor_receive_device(void *mon) { (void)mon; return 0; }
void *udev_monitor_ref(void *mon) { return mon; }
void *udev_monitor_unref(void *mon) { (void)mon; return 0; }

/* ------------------------------------------------------------------ */
/* ioctl: forward everything, report DTR/RTS changes on the tty         */
/* ------------------------------------------------------------------ */

static void lfa_report_lines(int op, int bits)
{
    char msg[5];
    if (lfa_tty_ctl < 0) return;
    msg[0] = (char)op;
    msg[1] = (char)(bits & 0xFF);
    msg[2] = (char)((bits >> 8) & 0xFF);
    msg[3] = (char)((bits >> 16) & 0xFF);
    msg[4] = (char)((bits >> 24) & 0xFF);
    syscall(LFA_NR_write, lfa_tty_ctl, msg, sizeof(msg));
}

int ioctl(int fd, unsigned long request, ...)
{
    void *arg;
    __builtin_va_list ap;
    __builtin_va_start(ap, request);
    arg = __builtin_va_arg(ap, void *);
    __builtin_va_end(ap);

    if (lfa_is_tty_fd(fd) && arg) {
        int bits = *(int *)arg;
        if (request == LFA_TIOCMBIS) {
            lfa_lines |= bits;
            lfa_report_lines('s', bits);
            return 0;
        }
        if (request == LFA_TIOCMBIC) {
            lfa_lines &= ~bits;
            lfa_report_lines('c', bits);
            return 0;
        }
        if (request == LFA_TIOCMSET) {
            lfa_lines = bits & 0x6;   /* TIOCMSET sets the outputs */
            lfa_report_lines('m', bits);
            return 0;
        }
        if (request == LFA_TIOCMGET) {
            *(int *)arg = lfa_lines | 0x30;   /* CTS | DSR asserted */
            return 0;
        }
    }
    return (int)syscall(LFA_NR_ioctl, fd, request, arg);
}
