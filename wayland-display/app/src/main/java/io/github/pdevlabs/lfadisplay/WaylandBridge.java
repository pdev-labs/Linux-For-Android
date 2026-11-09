package io.github.pdevlabs.lfadisplay;

import android.view.Surface;

/**
 * JNI bridge to libwayland-compositor.so.
 *
 * The compositor is the Wayland server; the guest desktop (Hyprland, Sway,
 * anything xdg-shell) connects to it as a client and draws into wl_shm
 * buffers, which the compositor composites onto the Android Surface.
 */
public final class WaylandBridge {
    public static final int POINTER_ACTION_DOWN = 0;
    public static final int POINTER_ACTION_MOVE = 1;
    public static final int POINTER_ACTION_UP = 2;
    public static final int POINTER_ACTION_POINTER_MOVE = 6;

    public static final int AXIS_SOURCE_FINGER = 1;

    static {
        System.loadLibrary("wayland-compositor");
    }

    private WaylandBridge() {}

    /** Create a server that binds its own socket under {@code runtimeDir}. */
    public static native long nativeCreateServer(String runtimeDir, String socketName);

    /**
     * Create a server on a listening Unix socket inherited from the Termux-side
     * bridge. The compositor owns {@code fd} afterwards.
     */
    public static native long nativeCreateServerFd(String runtimeDir, int fd);

    public static native void nativeSurfaceCreated(
            Surface surface, String runtimeDir, int resolutionPercent, int scalePercent, boolean skipEglWaylandBind);

    public static native void nativeSurfaceDestroyed();

    public static native void nativeOutputSizeChanged(
            int width, int height, int resolutionPercent, int scalePercent);

    public static native void nativeOnPointerEvent(float x, float y, int action, int timeMs);

    public static native void nativeOnPointerAxis(float deltaX, float deltaY, int timeMs, int axisSource);

    public static native void nativeOnPointerRightClick(float x, float y, int timeMs);

    public static native void nativeOnKeyEvent(int keyCode, int metaState, boolean isDown, long timeMs);

    public static native void nativeSetCursorVisible(boolean visible);

    public static native boolean nativeHasActiveClients();
}
