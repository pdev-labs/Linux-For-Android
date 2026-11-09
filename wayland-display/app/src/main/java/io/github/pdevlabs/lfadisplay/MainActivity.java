package io.github.pdevlabs.lfadisplay;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.File;
import java.util.HashSet;
import java.util.Set;

/**
 * Full-screen Wayland display.
 *
 * The app runs a shm Wayland compositor and shows the guest desktop on a
 * Surface. The listening socket is either created directly (shared-UID build,
 * inside Termux's tmp directory) or inherited from the Termux-side bridge
 * (regular build), so the guest can connect without matching signatures.
 */
public final class MainActivity extends Activity implements BridgeReceiver.Listener, DisplayView.Callback {
    private static final String TAG = "LfaWd";

    /** Termux tmp directory, only writable by the shared-UID build. */
    private static final String TERMUX_TMP = "/data/data/com.termux/files/usr/tmp/lfa-wayland";
    private static final String SOCKET_NAME = "wayland-0";

    private DisplayView displayView;
    private TextInputView textInput;
    private LinearLayout keyBar;

    private BroadcastReceiver bridgeReceiver;
    private Surface pendingSurface;
    private boolean serverReady;
    private boolean rendererStarted;
    private int surfaceWidth, surfaceHeight;

    private final Set<Integer> heldModifiers = new HashSet<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        hideSystemBars();

        String runtimeDir = new File(getFilesDir(), "wayland").getAbsolutePath();
        new File(runtimeDir).mkdirs();

        buildUi();

        BridgeReceiver.setListener(this);
        bridgeReceiver = new BridgeReceiver();
        IntentFilter filter = new IntentFilter(BridgeMain.ACTION);
        if (Build.VERSION.SDK_INT >= 33)
            registerReceiver(bridgeReceiver, filter, Context.RECEIVER_EXPORTED);
        else
            registerReceiver(bridgeReceiver, filter);

        if (BuildConfig.DIRECT_SOCKET) {
            new File(TERMUX_TMP).mkdirs();
            long id = WaylandBridge.nativeCreateServer(TERMUX_TMP, SOCKET_NAME);
            Log.i(TAG, "direct socket " + TERMUX_TMP + "/" + SOCKET_NAME + " id=" + id);
            if (id != 0)
                serverReady = true;
        }
    }

    // ---------------------------------------------------------------- UI

    private void buildUi() {
        FrameLayout root = new FrameLayout(this);

        displayView = new DisplayView(this, this);
        root.addView(displayView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        textInput = new TextInputView(this);
        FrameLayout.LayoutParams textParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(1), Gravity.BOTTOM);
        root.addView(textInput, textParams);

        keyBar = new LinearLayout(this);
        keyBar.setOrientation(LinearLayout.HORIZONTAL);
        keyBar.setBackgroundColor(0xCC111318);
        keyBar.setPadding(dp(4), dp(4), dp(4), dp(4));

        addTapKey("esc", KeyEvent.KEYCODE_ESCAPE);
        addTapKey("tab", KeyEvent.KEYCODE_TAB);
        addModifierKey("ctrl", KeyEvent.KEYCODE_CTRL_LEFT);
        addModifierKey("alt", KeyEvent.KEYCODE_ALT_LEFT);
        addModifierKey("shift", KeyEvent.KEYCODE_SHIFT_LEFT);
        addTapKey("←", KeyEvent.KEYCODE_DPAD_LEFT);
        addTapKey("↑", KeyEvent.KEYCODE_DPAD_UP);
        addTapKey("↓", KeyEvent.KEYCODE_DPAD_DOWN);
        addTapKey("→", KeyEvent.KEYCODE_DPAD_RIGHT);
        addTapKey("enter", KeyEvent.KEYCODE_ENTER);
        addTapKey("⌫", KeyEvent.KEYCODE_DEL);
        addTapKey("\\", KeyEvent.KEYCODE_BACKSLASH);

        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        scroll.addView(keyBar);

        FrameLayout.LayoutParams barParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM);
        root.addView(scroll, barParams);

        LinearLayout toggles = new LinearLayout(this);
        toggles.setOrientation(LinearLayout.HORIZONTAL);

        TextView keyboard = chip("⌨");
        keyboard.setOnClickListener(v -> toggleKeyboard());
        toggles.addView(keyboard);

        TextView bar = chip("≡");
        bar.setOnClickListener(v -> keyBar.setVisibility(
                keyBar.getVisibility() == View.VISIBLE ? View.GONE : View.VISIBLE));
        toggles.addView(bar);

        FrameLayout.LayoutParams toggleParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.END);
        toggleParams.setMargins(0, dp(8), dp(8), 0);
        root.addView(toggles, toggleParams);

        setContentView(root);
    }

    private TextView chip(String label) {
        TextView v = new TextView(this);
        v.setText(label);
        v.setTextColor(Color.WHITE);
        v.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        v.setGravity(Gravity.CENTER);
        v.setPadding(dp(12), dp(6), dp(12), dp(6));
        v.setBackgroundColor(0xAA111318);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(dp(4), 0, 0, 0);
        v.setLayoutParams(lp);
        return v;
    }

    private void addTapKey(String label, int keyCode) {
        TextView v = chip(label);
        v.setOnClickListener(view -> {
            if (!serverReady)
                return;
            long now = SystemClock.uptimeMillis();
            WaylandBridge.nativeOnKeyEvent(keyCode, 0, true, now);
            WaylandBridge.nativeOnKeyEvent(keyCode, 0, false, now + 8);
        });
        keyBar.addView(v);
    }

    private void addModifierKey(String label, int keyCode) {
        TextView v = chip(label);
        v.setOnClickListener(view -> {
            if (!serverReady)
                return;
            boolean down = heldModifiers.add(keyCode);
            WaylandBridge.nativeOnKeyEvent(keyCode, 0, down, SystemClock.uptimeMillis());
            v.setBackgroundColor(down ? 0xFF3D6FD4 : 0xAA111318);
        });
        keyBar.addView(v);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void toggleKeyboard() {
        InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
        if (textInput.hasFocus()) {
            imm.hideSoftInputFromWindow(textInput.getWindowToken(), 0);
            textInput.clearFocus();
        } else {
            textInput.requestFocus();
            textInput.setText("");
            imm.showSoftInput(textInput, InputMethodManager.SHOW_IMPLICIT);
        }
    }

    private void hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        }
    }

    // ------------------------------------------------------- surface callbacks

    @Override
    public void onSurfaceReady(Surface surface) {
        pendingSurface = surface;
        maybeStartRenderer();
    }

    @Override
    public void onSurfaceGone() {
        pendingSurface = null;
        if (rendererStarted) {
            WaylandBridge.nativeSurfaceDestroyed();
            rendererStarted = false;
        }
    }

    @Override
    public void onSurfaceSize(int width, int height) {
        surfaceWidth = width;
        surfaceHeight = height;
        if (rendererStarted)
            WaylandBridge.nativeOutputSizeChanged(width, height, 100, 100);
    }

    private void maybeStartRenderer() {
        if (!serverReady || pendingSurface == null || rendererStarted)
            return;

        String runtimeDir = new File(getFilesDir(), "wayland").getAbsolutePath();
        WaylandBridge.nativeSurfaceCreated(pendingSurface, runtimeDir, 100, 100, false);
        rendererStarted = true;

        if (surfaceWidth > 0 && surfaceHeight > 0)
            WaylandBridge.nativeOutputSizeChanged(surfaceWidth, surfaceHeight, 100, 100);

        WaylandBridge.nativeSetCursorVisible(true);
        Log.i(TAG, "renderer started on " + surfaceWidth + "x" + surfaceHeight);
    }

    // -------------------------------------------------------- bridge socket

    @Override
    public void onSocket(int fd) {
        if (serverReady)
            return;

        String runtimeDir = new File(getFilesDir(), "wayland").getAbsolutePath();
        long id = WaylandBridge.nativeCreateServerFd(runtimeDir, fd);
        Log.i(TAG, "adopted bridge socket fd=" + fd + " id=" + id);
        if (id != 0) {
            serverReady = true;
            maybeStartRenderer();
        }
    }

    // ------------------------------------------------------------ key events

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (serverReady && event.getKeyCode() != KeyEvent.KEYCODE_BACK)
            return DisplayView.sendKey(event.getKeyCode(), event);
        return super.dispatchKeyEvent(event);
    }

    @Override
    protected void onDestroy() {
        if (rendererStarted)
            WaylandBridge.nativeSurfaceDestroyed();
        rendererStarted = false;

        BridgeReceiver.setListener(null);
        if (bridgeReceiver != null)
            unregisterReceiver(bridgeReceiver);
        bridgeReceiver = null;
        super.onDestroy();
    }
}
