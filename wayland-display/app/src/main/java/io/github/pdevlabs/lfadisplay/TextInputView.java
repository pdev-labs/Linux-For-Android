package io.github.pdevlabs.lfadisplay;

import android.content.Context;
import android.text.InputType;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputConnectionWrapper;
import android.widget.EditText;

/**
 * Invisible text field that owns the IME connection. Committed text is
 * translated into key events: characters with a key mapping become a key
 * press with the right modifiers, everything else falls back to the
 * Ctrl+Shift+U codepoint sequence used by GTK/Qt/IBus applications.
 */
public final class TextInputView extends EditText {
    private final KeyCharacterMap keyMap = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD);

    public TextInputView(Context context) {
        super(context);
        setAlpha(0f);
        setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        setImeOptions(EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN);
        setSingleLine(false);
        setBackground(null);
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
        InputConnection base = super.onCreateInputConnection(outAttrs);
        if (base == null)
            return null;

        return new InputConnectionWrapper(base, false) {
            @Override
            public boolean commitText(CharSequence text, int newCursorPosition) {
                sendText(text.toString());
                return true;
            }

            @Override
            public boolean sendKeyEvent(KeyEvent event) {
                DisplayView.sendKey(event.getKeyCode(), event);
                return true;
            }

            @Override
            public boolean deleteSurroundingText(int beforeLength, int afterLength) {
                for (int i = 0; i < beforeLength; i++)
                    tapKey(KeyEvent.KEYCODE_DEL);
                return true;
            }
        };
    }

    private static void tapKey(int keyCode) {
        long now = android.os.SystemClock.uptimeMillis();
        WaylandBridge.nativeOnKeyEvent(keyCode, 0, true, now);
        WaylandBridge.nativeOnKeyEvent(keyCode, 0, false, now + 8);
    }

    private static void modifier(int keyCode, boolean down) {
        long now = android.os.SystemClock.uptimeMillis();
        WaylandBridge.nativeOnKeyEvent(keyCode, 0, down, now);
    }

    public void sendText(String text) {
        for (int i = 0; i < text.length(); ) {
            int cp = text.codePointAt(i);
            i += Character.charCount(cp);

            KeyEvent[] events = keyMap.getEvents(new char[]{(char) cp});
            if (events == null || events.length == 0) {
                unicodeFallback(cp);
                continue;
            }

            boolean shift = false, ctrl = false, alt = false, meta = false;
            for (KeyEvent e : events) {
                int m = e.getMetaState();
                shift |= (m & KeyEvent.META_SHIFT_ON) != 0;
                ctrl |= (m & KeyEvent.META_CTRL_ON) != 0;
                alt |= (m & KeyEvent.META_ALT_ON) != 0;
                meta |= (m & KeyEvent.META_META_ON) != 0;
            }

            if (shift) modifier(KeyEvent.KEYCODE_SHIFT_LEFT, true);
            if (ctrl) modifier(KeyEvent.KEYCODE_CTRL_LEFT, true);
            if (alt) modifier(KeyEvent.KEYCODE_ALT_LEFT, true);
            if (meta) modifier(KeyEvent.KEYCODE_META_LEFT, true);

            for (KeyEvent e : events) {
                WaylandBridge.nativeOnKeyEvent(e.getKeyCode(), e.getMetaState(),
                        e.getAction() == KeyEvent.ACTION_DOWN, e.getEventTime());
            }

            if (meta) modifier(KeyEvent.KEYCODE_META_LEFT, false);
            if (alt) modifier(KeyEvent.KEYCODE_ALT_LEFT, false);
            if (ctrl) modifier(KeyEvent.KEYCODE_CTRL_LEFT, false);
            if (shift) modifier(KeyEvent.KEYCODE_SHIFT_LEFT, false);
        }
    }

    /** Ctrl+Shift+U, hex codepoint, Enter — the IBus/GTK input convention. */
    private void unicodeFallback(int codepoint) {
        modifier(KeyEvent.KEYCODE_CTRL_LEFT, true);
        modifier(KeyEvent.KEYCODE_SHIFT_LEFT, true);
        tapKey(KeyEvent.KEYCODE_U);
        modifier(KeyEvent.KEYCODE_SHIFT_LEFT, false);
        modifier(KeyEvent.KEYCODE_CTRL_LEFT, false);

        for (char c : Integer.toHexString(codepoint).toCharArray()) {
            if (c >= '0' && c <= '9')
                tapKey(KeyEvent.KEYCODE_0 + (c - '0'));
            else if (c >= 'a' && c <= 'f')
                tapKey(KeyEvent.KEYCODE_A + (c - 'a'));
        }
        tapKey(KeyEvent.KEYCODE_ENTER);
    }
}
