#define _GNU_SOURCE
/*
 * Minimal helper for the Termux-side bridge: create, bind and listen on a
 * filesystem Unix socket. Java's LocalServerSocket only exposes the abstract
 * namespace, and android.system.UnixSocketAddress is a hidden API, so the
 * bridge loads this tiny library with app_process and asks it for the fd.
 */
#include <jni.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>

JNIEXPORT jint JNICALL
Java_io_github_pdevlabs_lfadisplay_BridgeMain_nativeBindSocket(JNIEnv *env, jclass clazz, jstring path) {
    (void)clazz;
    if (!path)
        return -1;

    const char *name = (*env)->GetStringUTFChars(env, path, NULL);
    if (!name)
        return -1;

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        (*env)->ReleaseStringUTFChars(env, path, name);
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    if (strlen(name) >= sizeof(addr.sun_path)) {
        close(fd);
        (*env)->ReleaseStringUTFChars(env, path, name);
        return -1;
    }
    strncpy(addr.sun_path, name, sizeof(addr.sun_path) - 1);

    /* Replace a stale socket from a previous run. */
    unlink(name);

    if (bind(fd, (struct sockaddr *) &addr, sizeof(addr)) < 0 || listen(fd, 8) < 0) {
        close(fd);
        (*env)->ReleaseStringUTFChars(env, path, name);
        return -1;
    }

    chmod(name, 0666);

    (*env)->ReleaseStringUTFChars(env, path, name);
    return fd;
}

/*
 * Blocking accept on the bridge's listening socket. The accepted fd is passed
 * to the app over Binder; the app then owns it.
 */
JNIEXPORT jint JNICALL
Java_io_github_pdevlabs_lfadisplay_BridgeMain_nativeAccept(JNIEnv *env, jclass clazz, jint listen_fd) {
    (void)env;
    (void)clazz;

    for (;;) {
        int fd = accept4(listen_fd, NULL, NULL, SOCK_CLOEXEC);
        if (fd >= 0)
            return fd;
        if (errno == EINTR)
            continue;
        return -1;
    }
}
