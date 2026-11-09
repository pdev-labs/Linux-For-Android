package io.github.pdevlabs.lfadisplay;

import android.os.ParcelFileDescriptor;
import android.os.RemoteException;

import java.util.ArrayDeque;

/**
 * Binder handed from the Termux-side bridge process to the app.
 *
 * SELinux does not let the app accept connections on a socket created by
 * Termux's domain, so the bridge accepts them and queues the connected fds.
 * The app drains the queue and attaches each fd to its Wayland display with
 * wl_client_create().
 */
public final class BridgeBinder extends IWaylandBridge.Stub {
    private static final int MAX_PENDING = 8;

    private final ArrayDeque<ParcelFileDescriptor> pending = new ArrayDeque<>();

    public synchronized void add(ParcelFileDescriptor fd) {
        while (pending.size() >= MAX_PENDING) {
            ParcelFileDescriptor old = pending.poll();
            if (old != null) {
                try {
                    old.close();
                } catch (Exception ignored) {
                }
            }
        }
        pending.add(fd);
    }

    @Override
    public synchronized ParcelFileDescriptor getSocket() throws RemoteException {
        ParcelFileDescriptor p = pending.poll();
        if (p == null)
            return null;
        try {
            return ParcelFileDescriptor.dup(p.getFileDescriptor());
        } catch (Exception e) {
            throw new RemoteException("cannot duplicate client socket: " + e);
        } finally {
            try {
                p.close();
            } catch (Exception ignored) {
            }
        }
    }
}
