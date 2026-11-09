package io.github.pdevlabs.lfadisplay;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/**
 * Termux-side entry point, run with app_process under the Termux UID:
 *
 *   app_process -Djava.class.path=<apk> /system/bin \
 *       io.github.pdevlabs.lfadisplay.BridgeMain <socket-path> <package> <lib-dir>
 *
 * It binds a Unix socket at a path the guest can reach, accepts each client,
 * and publishes a Binder that hands the connected fds to the display app.
 * SELinux forbids the app from accepting on a socket created by Termux's
 * domain, but read/write on an fd passed over Binder is allowed.
 */
public final class BridgeMain {
    public static final String ACTION = "io.github.pdevlabs.lfadisplay.BRIDGE";
    public static final String EXTRA_BUNDLE = "bridge";
    public static final String EXTRA_BINDER = "binder";

    private static final String TAG = "LfaWdBridge";

    private final Context context;
    private final String pkg;
    private final BridgeBinder binder = new BridgeBinder();
    private final Handler handler;
    private int listenFd = -1;

    private BridgeMain(Context context, String pkg) {
        this.context = context;
        this.pkg = pkg;
        this.handler = new Handler(Looper.getMainLooper());
    }

    private static native int nativeBindSocket(String path);

    private static native int nativeAccept(int listenFd);

    public static void main(String[] args) {
        if (Looper.getMainLooper() == null)
            Looper.prepareMainLooper();

        if (args.length < 3) {
            System.err.println("usage: BridgeMain SOCKET_PATH PACKAGE LIB_DIR");
            System.exit(2);
        }

        String path = args[0];
        String pkg = args[1];
        String libDir = args[2];

        try {
            System.load(libDir + "/liblfabridge.so");

            Context context = createContext();
            if (context == null)
                throw new IOException("could not create an Android system context");

            int fd = nativeBindSocket(path);
            if (fd < 0)
                throw new IOException("cannot bind " + path);

            new BridgeMain(context, pkg).run(fd);
        } catch (Exception e) {
            Log.e(TAG, "bridge failed", e);
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private void run(int fd) {
        listenFd = fd;
        Log.i(TAG, "listening on fd " + fd + " for " + pkg);

        Thread acceptor = new Thread(new Runnable() {
            @Override
            public void run() {
                for (;;) {
                    int client = nativeAccept(listenFd);
                    if (client < 0)
                        break;
                    binder.add(ParcelFileDescriptor.adoptFd(client));
                    handler.post(BridgeMain.this::broadcast);
                }
            }
        }, "lfa-wd-accept");
        acceptor.setDaemon(true);
        acceptor.start();

        handler.post(new Runnable() {
            @Override
            public void run() {
                broadcast();
                handler.postDelayed(this, 1000L);
            }
        });
        Looper.loop();
    }

    private void broadcast() {
        Bundle bundle = new Bundle();
        bundle.putBinder(EXTRA_BINDER, binder);

        Intent intent = new Intent(ACTION);
        intent.setPackage(pkg);
        intent.putExtra(EXTRA_BUNDLE, bundle);
        try {
            context.sendBroadcast(intent);
        } catch (RuntimeException e) {
            Log.e(TAG, "broadcast failed", e);
        }
    }

    private static Context createContext() {
        try {
            Class<?> activityThreadClass = Class.forName("android.app.ActivityThread");
            Class<?> unsafeClass = Class.forName("sun.misc.Unsafe");
            Field unsafeField = unsafeClass.getDeclaredField("theUnsafe");
            unsafeField.setAccessible(true);
            Object unsafe = unsafeField.get(null);
            Method allocateInstance = unsafeClass.getMethod("allocateInstance", Class.class);
            Object activityThread = allocateInstance.invoke(unsafe, activityThreadClass);
            Method getSystemContext = activityThreadClass.getDeclaredMethod("getSystemContext");
            getSystemContext.setAccessible(true);
            return (Context) getSystemContext.invoke(activityThread);
        } catch (Exception e) {
            Log.e(TAG, "failed to create Android system context", e);
            return null;
        }
    }
}
