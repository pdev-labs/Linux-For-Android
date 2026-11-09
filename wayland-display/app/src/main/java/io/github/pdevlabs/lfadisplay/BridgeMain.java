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
 *       io.github.pdevlabs.lfadisplay.BridgeMain <socket-path> <package>
 *
 * It binds a Unix socket at a path the guest can reach (normally
 * $PREFIX/tmp/lfa-wayland/wayland-0), keeps it open, and publishes a Binder
 * that lets the display app duplicate the listening fd. Re-publishing once a
 * second lets an activity recreated later adopt the same socket.
 */
public final class BridgeMain {
    public static final String ACTION = "io.github.pdevlabs.lfadisplay.BRIDGE";
    public static final String EXTRA_BUNDLE = "bridge";
    public static final String EXTRA_BINDER = "binder";

    private static final String TAG = "LfaWdBridge";

    private final Context context;
    private final BridgeBinder binder;

    private BridgeMain(Context context, ParcelFileDescriptor socket) {
        this.context = context;
        this.binder = new BridgeBinder(socket);
    }

    private static native int nativeBindSocket(String path);

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

        System.load(libDir + "/liblfabridge.so");

        try {
            Context context = createContext();
            if (context == null)
                throw new IOException("could not create an Android system context");

            // Filesystem-namespace Unix socket at a path the guest can reach.
            int fd = nativeBindSocket(path);
            if (fd < 0)
                throw new IOException("cannot bind " + path);
            ParcelFileDescriptor socket = ParcelFileDescriptor.adoptFd(fd);
            Log.i(TAG, "listening on " + path + " for " + pkg);

            new BridgeMain(context, socket).run(pkg);
        } catch (Exception e) {
            Log.e(TAG, "bridge failed", e);
            e.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private void run(final String pkg) {
        Handler handler = new Handler(Looper.getMainLooper());
        handler.post(new Runnable() {
            @Override
            public void run() {
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
                handler.postDelayed(this, 1000L);
            }
        });
        Looper.loop();
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
