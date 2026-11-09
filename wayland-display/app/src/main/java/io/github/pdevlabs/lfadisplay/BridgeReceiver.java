package io.github.pdevlabs.lfadisplay;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.IBinder;
import android.os.ParcelFileDescriptor;
import android.util.Log;

/** Receives the listening socket from the Termux-side bridge. */
public final class BridgeReceiver extends BroadcastReceiver {
    private static final String TAG = "LfaWdBridge";

    public interface Listener {
        void onSocket(int fd);
    }

    private static Listener listener;

    public static void setListener(Listener l) {
        listener = l;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!BridgeMain.ACTION.equals(intent.getAction()))
            return;

        Bundle bundle = intent.getBundleExtra(BridgeMain.EXTRA_BUNDLE);
        IBinder binder = bundle == null ? null : bundle.getBinder(BridgeMain.EXTRA_BINDER);
        if (binder == null)
            return;

        Listener l = listener;
        if (l == null) {
            Log.w(TAG, "bridge broadcast with no listener");
            return;
        }

        try {
            ParcelFileDescriptor pfd = IWaylandBridge.Stub.asInterface(binder).getSocket();
            if (pfd == null)
                return;
            l.onSocket(pfd.detachFd());
        } catch (Exception e) {
            Log.e(TAG, "failed to obtain the bridge socket", e);
        }
    }
}
