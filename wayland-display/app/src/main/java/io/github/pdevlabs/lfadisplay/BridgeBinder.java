package io.github.pdevlabs.lfadisplay;

import android.os.ParcelFileDescriptor;
import android.os.RemoteException;

/**
 * Binder handed from the Termux-side bridge process to the app.
 *
 * The bridge (running under the Termux UID via app_process) owns the listening
 * Unix socket at a path Termux and the guest can reach. The app cannot create
 * that socket itself: the app's private directory is not writable by Termux and
 * the Termux directory is not writable by the app. Passing the listening fd
 * across Binder solves both directions with one handoff.
 */
public final class BridgeBinder extends IWaylandBridge.Stub {
    private final ParcelFileDescriptor socket;

    public BridgeBinder(ParcelFileDescriptor socket) {
        this.socket = socket;
    }

    @Override
    public ParcelFileDescriptor getSocket() throws RemoteException {
        try {
            return ParcelFileDescriptor.dup(socket.getFileDescriptor());
        } catch (Exception e) {
            throw new RemoteException("cannot duplicate bridge socket: " + e);
        }
    }
}
