package io.github.pdevlabs.lfadisplay;

import android.os.ParcelFileDescriptor;

interface IWaylandBridge {
    ParcelFileDescriptor getSocket();
}
