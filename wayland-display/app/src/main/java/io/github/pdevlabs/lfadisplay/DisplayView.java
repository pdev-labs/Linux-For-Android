package io.github.pdevlabs.lfadisplay;

import android.content.Context;
import android.os.SystemClock;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;

/**
 * The composited desktop surface. Touch becomes wl_pointer motion/button
 * events, two-finger drags become axis events, long press is a right click.
 */
public final class DisplayView extends SurfaceView implements SurfaceHolder.Callback, View.OnTouchListener {
    public interface Callback {
        void onSurfaceReady(android.view.Surface surface);

        void onSurfaceGone();

        void onSurfaceSize(int width, int height);
    }

    private static final long LONG_PRESS_MS = 550;

    private final Callback callback;

    private float lastX, lastY;
    private float downX, downY;
    private long downTime;
    private boolean longPressSent;
    private boolean scrolling;
    private float scrollX, scrollY;

    public DisplayView(Context context, Callback callback) {
        super(context);
        this.callback = callback;
        getHolder().addCallback(this);
        setOnTouchListener(this);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        callback.onSurfaceReady(holder.getSurface());
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        callback.onSurfaceSize(width, height);
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        callback.onSurfaceGone();
    }

    @Override
    public boolean onTouch(View v, MotionEvent event) {
        final int now = (int) SystemClock.uptimeMillis();

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downX = lastX = event.getX();
                downY = lastY = event.getY();
                downTime = now;
                longPressSent = false;
                scrolling = false;
                WaylandBridge.nativeOnPointerEvent(lastX, lastY, WaylandBridge.POINTER_ACTION_DOWN, now);
                return true;

            case MotionEvent.ACTION_POINTER_DOWN:
                scrolling = true;
                scrollX = event.getX(0);
                scrollY = event.getY(0);
                // release the primary button so the guest sees a scroll, not a drag
                WaylandBridge.nativeOnPointerEvent(lastX, lastY, WaylandBridge.POINTER_ACTION_UP, now);
                return true;

            case MotionEvent.ACTION_MOVE:
                if (scrolling && event.getPointerCount() >= 2) {
                    float x = event.getX(0), y = event.getY(0);
                    float dx = x - scrollX, dy = y - scrollY;
                    scrollX = x;
                    scrollY = y;
                    if (dx != 0 || dy != 0)
                        WaylandBridge.nativeOnPointerAxis(dx, dy, now, WaylandBridge.AXIS_SOURCE_FINGER);
                    return true;
                }

                lastX = event.getX();
                lastY = event.getY();

                if (!longPressSent && now - downTime > LONG_PRESS_MS) {
                    longPressSent = true;
                    WaylandBridge.nativeOnPointerRightClick(lastX, lastY, now);
                    return true;
                }

                WaylandBridge.nativeOnPointerEvent(lastX, lastY, WaylandBridge.POINTER_ACTION_MOVE, now);
                return true;

            case MotionEvent.ACTION_POINTER_UP:
                scrolling = false;
                return true;

            case MotionEvent.ACTION_UP:
                if (!longPressSent) {
                    WaylandBridge.nativeOnPointerEvent(event.getX(), event.getY(), WaylandBridge.POINTER_ACTION_UP, now);
                }
                return true;

            case MotionEvent.ACTION_CANCEL:
                WaylandBridge.nativeOnPointerEvent(lastX, lastY, WaylandBridge.POINTER_ACTION_UP, now);
                return true;

            default:
                return false;
        }
    }

    /** Feed a hardware or injected key event to the guest. */
    public static boolean sendKey(int keyCode, KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN)
            WaylandBridge.nativeOnKeyEvent(keyCode, event.getMetaState(), true, event.getEventTime());
        else if (event.getAction() == KeyEvent.ACTION_UP)
            WaylandBridge.nativeOnKeyEvent(keyCode, event.getMetaState(), false, event.getEventTime());
        return true;
    }
}
