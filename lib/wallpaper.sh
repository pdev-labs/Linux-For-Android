#!/bin/sh
# Distro default wallpaper setup for Linux-for-Android.
#
# Runs on the Android/Termux host (NOT inside the guest) and writes into a
# proot rootfs:
#   1. the bundled wallpaper for the selected distribution ->
#        /usr/share/backgrounds/lfa-default.jpg
#   2. /usr/local/bin/lfa-set-wallpaper, which applies it in the running
#      XFCE / LXDE / MATE session (and rewrites the DE config for next login)
#   3. an XDG autostart entry for the desktop user, so the first desktop
#      login already shows the distro wallpaper
#   4. static LXDE pcmanfm config (works even without autostart)
#
# Environment:
#   LFA_ROOT       rootfs path (required)
#   LFA_USER       desktop user name (default: user)
#   LFA_DISTRO     distro/base alias (ubuntu, debian, kali, fedora, ...)
#   LFA_DE         xfce4 | lxde | mate | none
#   LFA_MODE       light | dark (desktop wallpaper variant, default light)
#   LFA_ASSET_DIR  directory containing the bundled .jpg files
#                  (default: <repo>/assets/wallpapers)
#
# CLI-only installs must not call this script (the installer gates on DE).
set -u

ROOT="${LFA_ROOT:-}"
USER_NAME="${LFA_USER:-user}"
DISTRO="${LFA_DISTRO:-}"
DE="${LFA_DE:-none}"
MODE="${LFA_MODE:-light}"
ASSET_DIR="${LFA_ASSET_DIR:-}"

case "$MODE" in
    light|dark) ;;
    *) MODE="light" ;;
esac

if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    echo "[!] wallpaper: rootfs not found: ${ROOT:-<unset>}" >&2
    exit 1
fi
if [ "$DE" = "none" ] || [ -z "$DE" ]; then
    echo "[*] wallpaper: CLI-only install, skipped."
    exit 0
fi
if ! echo "$USER_NAME" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then
    echo "[!] wallpaper: invalid user name '$USER_NAME'" >&2
    exit 1
fi

# Repo layout fallback (lib/ -> .. -> assets/wallpapers).
if [ -z "$ASSET_DIR" ]; then
    ASSET_DIR="$(cd "$(dirname "$0")/.." && pwd)/assets/wallpapers"
fi

# Map aliases/custom instance names to the bundled image family.
case "$DISTRO" in
    ubuntu*)                    ASSET_BASE="ubuntu" ;;
    debian*|bullseye*)          ASSET_BASE="debian" ;;
    kali*)                      ASSET_BASE="kali" ;;
    fedora*)                    ASSET_BASE="fedora" ;;
    opensuse*|suse*)            ASSET_BASE="opensuse" ;;
    archlinux*|arch*|alarm*)    ASSET_BASE="archlinux" ;;
    void*)                      ASSET_BASE="void" ;;
    alpine*)                    ASSET_BASE="alpine" ;;
    *)                          ASSET_BASE="ubuntu" ;;
esac
ASSET="$ASSET_BASE.jpg"
if [ "$MODE" = "dark" ] && [ -s "$ASSET_DIR/$ASSET_BASE-dark.jpg" ]; then
    ASSET="$ASSET_BASE-dark.jpg"
fi
SRC="$ASSET_DIR/$ASSET"
if [ ! -s "$SRC" ]; then
    echo "[!] wallpaper: bundled image missing: $SRC" >&2
    exit 1
fi

WALL_DIR="$ROOT/usr/share/backgrounds"
WALL="$WALL_DIR/lfa-default.jpg"
mkdir -p "$WALL_DIR" || exit 1
cp -f "$SRC" "$WALL" || exit 1
chmod 644 "$WALL" 2>/dev/null || true
mkdir -p "$ROOT/etc" 2>/dev/null || true
printf '%s\n' "$MODE" > "$ROOT/etc/lfa-wallpaper-mode" 2>/dev/null || true
echo "[*] Wallpaper: $MODE / $ASSET -> /usr/share/backgrounds/lfa-default.jpg"

# ---------------------------------------------------------------------------
# Guest-side applier. Kept dependency-free and idempotent: it is safe to run
# on every login, and silently does nothing when no matching DE is installed.
# ---------------------------------------------------------------------------
BIN_DIR="$ROOT/usr/local/bin"
mkdir -p "$BIN_DIR" || exit 1
cat > "$BIN_DIR/lfa-set-wallpaper" <<'LFA_WALL_EOF'
#!/bin/sh
# Apply the Linux-for-Android distro wallpaper in the current session.
# Installed by the Linux-for-Android manager; re-run safely at any time.
[ "${1:-}" = "--autostart" ] && sleep 2

WALL="${LFA_WALLPAPER:-/usr/share/backgrounds/lfa-default.jpg}"
[ -r "$WALL" ] || exit 0

# xfconf-query: create the property when missing, otherwise update it.
set_xfconf() { # channel property type value
    if xfconf-query -c "$1" -p "$2" >/dev/null 2>&1; then
        xfconf-query -c "$1" -p "$2" -s "$4" >/dev/null 2>&1 || true
    else
        xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" >/dev/null 2>&1 || true
    fi
}

# ---- XFCE ---------------------------------------------------------------
if command -v xfconf-query >/dev/null 2>&1; then
    props="$(xfconf-query -c xfce4-desktop -l 2>/dev/null \
        | grep -E '/backdrop/.*/(last-image|last-single-image)$' || true)"
    if [ -n "$props" ]; then
        printf '%s\n' "$props" | while IFS= read -r p; do
            set_xfconf xfce4-desktop "$p" string "$WALL"
            base="${p%/last-image}"
            base="${base%/last-single-image}"
            set_xfconf xfce4-desktop "$base/image-style" int 5
        done
    fi
    # First login: xfdesktop may not have created backdrop keys yet. The
    # monitor name differs between Termux:X11 and TigerVNC, so seed the
    # common ones; autostart runs again after xfdesktop starts.
    for mon in monitor0 monitor1 monitorVirtual-1 monitorVNC-0; do
        base="/backdrop/screen0/$mon"
        set_xfconf xfce4-desktop "$base/last-image" string "$WALL"
        set_xfconf xfce4-desktop "$base/image-style" int 5
    done
fi

# ---- LXDE ---------------------------------------------------------------
if command -v pcmanfm >/dev/null 2>&1; then
    [ -n "${DISPLAY:-}" ] && pcmanfm --set-wallpaper="$WALL" >/dev/null 2>&1 || true
fi

# ---- MATE / GNOME -------------------------------------------------------
if command -v gsettings >/dev/null 2>&1; then
    if gsettings list-schemas 2>/dev/null | grep -qx 'org.mate.background'; then
        gsettings set org.mate.background picture-filename "$WALL" >/dev/null 2>&1 || true
        gsettings set org.mate.background picture-options 'zoom' >/dev/null 2>&1 || true
    fi
    if gsettings list-schemas 2>/dev/null | grep -qx 'org.gnome.desktop.background'; then
        gsettings set org.gnome.desktop.background picture-uri "file://$WALL" >/dev/null 2>&1 || true
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALL" >/dev/null 2>&1 || true
        gsettings set org.gnome.desktop.background picture-options 'zoom' >/dev/null 2>&1 || true
    fi
fi

# ---- X11 fallback (feh, hsetroot, xwallpaper) ----------------------------
if [ -n "${DISPLAY:-}" ]; then
    for tool in feh hsetroot xwallpaper; do
        if command -v "$tool" >/dev/null 2>&1; then
            case "$tool" in
                feh)        feh --bg-fill "$WALL" >/dev/null 2>&1 && break ;;
                hsetroot)   hsetroot -fill "$WALL" >/dev/null 2>&1 && break ;;
                xwallpaper) xwallpaper --zoom "$WALL" >/dev/null 2>&1 && break ;;
            esac
        fi
    done
fi

exit 0
LFA_WALL_EOF
chmod 755 "$BIN_DIR/lfa-set-wallpaper" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Desktop user config (autostart + static LXDE wallpaper).
# ---------------------------------------------------------------------------
HOME_DIR="$ROOT/home/$USER_NAME"
mkdir -p "$HOME_DIR/.config/autostart" || exit 1

cat > "$HOME_DIR/.config/autostart/lfa-wallpaper.desktop" <<'LFA_AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=Linux for Android Wallpaper
Comment=Apply the distribution default wallpaper
Exec=/usr/local/bin/lfa-set-wallpaper --autostart
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
LFA_AUTOSTART_EOF
chmod 644 "$HOME_DIR/.config/autostart/lfa-wallpaper.desktop" 2>/dev/null || true

# LXDE reads pcmanfm's own config before XDG autostart runs, so seed it too.
if [ "$DE" = "lxde" ]; then
    PCDIR="$HOME_DIR/.config/pcmanfm/LXDE"
    mkdir -p "$PCDIR" || exit 1
    for PCONF in "$PCDIR/pcmanfm.conf" "$PCDIR/desktop-items-0.conf"; do
        if [ -f "$PCONF" ]; then
            if grep -q '^wallpaper=' "$PCONF"; then
                sed -i "s|^wallpaper=.*|wallpaper=/usr/share/backgrounds/lfa-default.jpg|" "$PCONF"
            else
                echo "wallpaper=/usr/share/backgrounds/lfa-default.jpg" >> "$PCONF"
            fi
            if grep -q '^wallpaper_mode=' "$PCONF"; then
                sed -i 's/^wallpaper_mode=.*/wallpaper_mode=5/' "$PCONF"
            else
                echo 'wallpaper_mode=5' >> "$PCONF"
            fi
        else
            if [ "$(basename "$PCONF")" = "pcmanfm.conf" ]; then
                printf '[desktop]\nwallpaper_mode=5\nwallpaper=/usr/share/backgrounds/lfa-default.jpg\n' > "$PCONF"
            else
                printf '[*]\nwallpaper_mode=5\nwallpaper=/usr/share/backgrounds/lfa-default.jpg\nwallpaper_common=1\n' > "$PCONF"
            fi
        fi
        chmod 644 "$PCONF" 2>/dev/null || true
    done
    echo "[*] Wallpaper: LXDE pcmanfm config seeded."
fi

echo "[*] Wallpaper: $DE autostart entry installed for '$USER_NAME'."
exit 0
