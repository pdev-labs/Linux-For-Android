#!/bin/sh
# Linux-for-Android: make the guest shell feel like a normal Linux install.
#
# Runs inside the guest during install, or against a rootfs during migration.
#   LFA_USER      account to polish           (default: user)
#   LFA_HOSTNAME  hostname shown in the prompt (default: /etc/hostname)
#   LFA_PSTYLE    minimal | informative        (default: minimal)
#   LFA_ROOT      optional rootfs prefix       (migration / tests)

R="${LFA_ROOT%/}"
HOST="${LFA_HOSTNAME:-}"
[ -n "$HOST" ] || HOST="$(cat "$R/etc/hostname" 2>/dev/null)"
[ -n "$HOST" ] || HOST="$(/bin/hostname 2>/dev/null)"
[ -n "$HOST" ] || HOST="localhost"
USER_NAME="${LFA_USER:-user}"
PSTYLE="${LFA_PSTYLE:-minimal}"

mkdir -p "$R/etc/profile.d" "$R/usr/local/bin" "$R/etc/skel" \
         "$R/root" "$R/home/$USER_NAME" 2>/dev/null || true

# Keep /etc/hostname (and the local hosts entry) in sync with the chosen name
# so `hostname`, the banner and apps all agree.
printf '%s\n' "$HOST" > "$R/etc/hostname" 2>/dev/null || true
if [ -f "$R/etc/hosts" ] && ! grep -q "[[:space:]]$HOST\$" "$R/etc/hosts" 2>/dev/null; then
    printf '127.0.1.1 %s\n' "$HOST" >> "$R/etc/hosts" 2>/dev/null || true
fi

# ---------------- login banner (once per session) ----------------
cat > "$R/etc/profile.d/00-lfa-welcome.sh" <<'WELCOME'
#!/bin/sh
# Realistic login banner, printed once per interactive session.
[ -n "${LFA_WELCOME_SHOWN:-}" ] && return 0 2>/dev/null
[ -t 1 ] || return 0 2>/dev/null
LFA_WELCOME_SHOWN=1; export LFA_WELCOME_SHOWN
[ -r /etc/os-release ] && . /etc/os-release
printf '\nWelcome to %s\n\n' "${PRETTY_NAME:-Linux}"
printf ' * Hostname : %s\n' "$(cat /etc/hostname 2>/dev/null || echo "${HOSTNAME:-localhost}")"
printf ' * Kernel   : %s\n' "$(uname -r)"
_mem="$(free -h 2>/dev/null | awk '/^Mem:/{print $3" / "$2}')"
[ -n "$_mem" ] && printf ' * Memory   : %s\n' "$_mem"
unset _mem
printf '\n'
WELCOME

# ---------------- hide Termux/Android host variables ----------------
cat > "$R/etc/profile.d/zz-lfa-env.sh" <<'CLEAN'
#!/bin/sh
# Make `env` look like a normal Linux box.
for _v in $(env 2>/dev/null | sed -n 's/^\(TERMUX[^=]*\|ANDROID[^=]*\|EXTERNAL_STORAGE\|PREFIX\|LD_PRELOAD\|TMPDIR\)=.*/\1/p'); do
    unset "$_v" 2>/dev/null || true
done
unset _v
case "${SHELL:-}" in /data/data/*) SHELL=/bin/bash; export SHELL ;; esac
case "${TERM:-}" in xterm-ghostty|xterm-kitty|alacritty) TERM=xterm-256color; export TERM ;; esac
# Do not let an uninstalled guest command fall through to a Termux binary
# (e.g. `apt-get` on Fedora picking up Termux's apt-get). Keep only paths
# that belong to the Linux guest.
_clean_path=""; _ifs="$IFS"; IFS=:
for _p in $PATH; do
    case "$_p" in
        /data/data/*|/data/user/*|/system/bin|/system/xbin|/vendor/bin|/product/bin) ;;
        *) [ -n "$_p" ] && _clean_path="${_clean_path:+$_clean_path:}$_p" ;;
    esac
done
IFS="$_ifs"
[ -n "$_clean_path" ] && PATH="$_clean_path" && export PATH
unset _clean_path _p _ifs
CLEAN

# ---------------- name host-mapped gids ----------------
# PRoot injects Android group ids (aid_inet, aid_everybody, app cache,
# etc.) into the guest. Some have no /etc/group entry, so every login
# prints "groups: cannot find name for group ID N" from bash.bashrc.
# Give the unmapped ones neutral names. Only meaningful inside the guest:
# host-side migration (LFA_ROOT) cannot see the proot-mapped ids.
if [ -z "$R" ] && [ -r /etc/group ]; then
    _gids="$(awk '/^Groups:/{for(i=2;i<=NF;i++) print $i}' /proc/self/status 2>/dev/null)"
    for _u in root "$USER_NAME"; do
        _gids="$_gids $(id -G "$_u" 2>/dev/null)"
    done
    for _g in $_gids; do
        if command -v getent >/dev/null 2>&1; then
            getent group "$_g" >/dev/null 2>&1 && continue
        else
            grep -q "^[^:]*:[^:]*:$_g:" /etc/group 2>/dev/null && continue
        fi
        printf 'lfa_gid_%s:x:%s:\n' "$_g" "$_g" >> /etc/group 2>/dev/null || true
        [ -f /etc/gshadow ] && printf 'lfa_gid_%s:!::\n' "$_g" >> /etc/gshadow 2>/dev/null || true
    done
    unset _u _g _gids
fi

# ---------------- hostname reports the chosen name ----------------
cat > "$R/usr/local/bin/hostname" <<'HOSTNAME'
#!/bin/sh
H="$(cat /etc/hostname 2>/dev/null)"
[ -n "$H" ] || H="${HOSTNAME:-localhost}"
case "${1:-}" in
    ""|-s|--short)     echo "${H%%.*}" ;;
    -f|--fqdn|--long)  echo "$H" ;;
    *) exec /bin/hostname "$@" 2>/dev/null || exec /usr/bin/hostname "$@" ;;
esac
HOSTNAME
chmod 755 "$R/usr/local/bin/hostname" 2>/dev/null || true

# ---------------- Ubuntu-style prompt + aliases ----------------
write_prompt() {
    _rc="$1"; _term="$2"; _color="$3"
    [ -f "$_rc" ] || : > "$_rc"
    sed -i '/# >>> linux-for-android prompt >>>/,/# <<< linux-for-android prompt <<</d' "$_rc" 2>/dev/null || true
    if [ "$PSTYLE" = "informative" ]; then
        _ps1="\\[\\033[${_color}m\\]\\u@${HOST}\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\] \\[\\033[00;33m\\][\\A]\\[\\033[00m\\]${_term} "
    else
        _ps1="\\[\\033[${_color}m\\]\\u@${HOST}\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]${_term} "
    fi
    {
        printf '%s\n' '# >>> linux-for-android prompt >>>'
        printf "export HOSTNAME='%s'\n" "$HOST"
        printf '%s\n' 'force_color_prompt=yes'
        printf "PS1='%s'\n" "$_ps1"
        printf '%s\n' "alias ls='ls --color=auto'"
        printf '%s\n' "alias ll='ls -alF'"
        printf '%s\n' "alias la='ls -A'"
        printf '%s\n' "alias l='ls -CF'"
        printf '%s\n' "alias grep='grep --color=auto'"
        printf '%s\n' 'HISTCONTROL=ignoreboth'
        printf '%s\n' '[ -f /etc/profile.d/zz-lfa-env.sh ] && . /etc/profile.d/zz-lfa-env.sh'
        printf '%s\n' '[ -f /etc/profile.d/00-lfa-welcome.sh ] && . /etc/profile.d/00-lfa-welcome.sh'
        printf '%s\n' '# <<< linux-for-android prompt <<<'
    } >> "$_rc"
}

write_prompt "$R/root/.bashrc" '#' '01;31'
write_prompt "$R/home/$USER_NAME/.bashrc" '$' '01;32'
write_prompt "$R/etc/skel/.bashrc" '$' '01;32'

# Login shells read /etc/profile + ~/.profile, not ~/.bashrc. Make the
# profile pull in .bashrc so the prompt, PATH cleanup and aliases apply even
# when the login shell is forced to bash for consistency.
write_profile() {
    _pf="$1"
    [ -f "$_pf" ] || : > "$_pf"
    sed -i '/# >>> linux-for-android profile >>>/,/# <<< linux-for-android profile <<</d' "$_pf" 2>/dev/null || true
    {
        printf '%s\n' '# >>> linux-for-android profile >>>'
        printf '%s\n' '[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
        printf '%s\n' '# <<< linux-for-android profile <<<'
    } >> "$_pf"
}
write_profile "$R/root/.profile"
write_profile "$R/home/$USER_NAME/.profile"
write_profile "$R/etc/skel/.profile"

# Remove the old early env script: termux-profile.sh runs after 01-* and
# would re-add the Termux PATH. The zz-* script runs last and wins.
rm -f "$R/etc/profile.d/01-lfa-env.sh" 2>/dev/null || true

# Profile snippets must be readable by the unprivileged desktop user.
chmod 644 "$R/etc/profile.d/00-lfa-welcome.sh" \
           "$R/etc/profile.d/zz-lfa-env.sh" 2>/dev/null || true
chmod 644 "$R/root/.profile" "$R/home/$USER_NAME/.profile" \
           "$R/root/.bashrc" "$R/home/$USER_NAME/.bashrc" 2>/dev/null || true

# ---------------- D-Bus machine id ----------------------------------
# Some container images ship an empty /etc/machine-id. D-Bus refuses to
# start without one, so XFCE cannot reach xfconfd and shows "Unable to
# contact settings server" on a black desktop. Generate it once per rootfs.
if [ ! -s "$R/etc/machine-id" ]; then
    _mid="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [ -n "$_mid" ] || _mid="0123456789abcdef0123456789abcdef"
    # Images may ship the file read-only and empty; recreate it.
    rm -f "$R/etc/machine-id" 2>/dev/null || true
    printf '%s\n' "$_mid" > "$R/etc/machine-id" 2>/dev/null || true
    chmod 444 "$R/etc/machine-id" 2>/dev/null || true
fi
mkdir -p "$R/var/lib/dbus" 2>/dev/null || true
[ -e "$R/var/lib/dbus/machine-id" ] || \
    ln -s /etc/machine-id "$R/var/lib/dbus/machine-id" 2>/dev/null || true

# ---------------- GNOME Shell (experimental) ------------------------
# gnome-session cannot run under proot (no systemd user session, no logind),
# so GNOME is started by launching gnome-shell on X11 directly. This wrapper
# also applies the wallpaper, because XDG autostart entries are only processed
# by gnome-session, which we deliberately do not run.
if [ "${LFA_DE:-}" = "gnome" ] || [ -x "$R/usr/bin/gnome-shell" ] || \
   [ -x "$R/usr/local/bin/gnome-shell" ]; then
    cat > "$R/usr/local/bin/start-gnome-session" <<'LFA_GNOME'
#!/bin/sh
# Linux for Android: experimental GNOME Shell session (proot).
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_DESKTOP=gnome
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
# proot starts us with an empty LANG, which glib reports as
# ANSI_X3.4-1968. GTK/GNOME apps then refuse to start with
# "Non UTF-8 locale (ANSI_X3.4-1968) is not supported!" (gnome-terminal
# exits with status 8). C.UTF-8 ships with glibc, so it always exists.
case "${LC_ALL:-}${LANG:-}" in
    *UTF-8*|*utf8*|*UTF8*) ;;
    *) LANG=C.UTF-8; export LANG ;;
esac

# gnome-session normally publishes its environment to the session bus so that
# bus-activated apps inherit LANG/DISPLAY. Without that, org.gnome.Terminal
# starts with an empty locale and dies with "exited with status 8".
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --all >/dev/null 2>&1 || true
fi

[ -n "$HOME" ] && cd "$HOME" 2>/dev/null || true

# gnome-session is not running, so nothing else applies the wallpaper.
if [ -x /usr/local/bin/lfa-set-wallpaper ]; then
    /usr/local/bin/lfa-set-wallpaper --autostart >/dev/null 2>&1 || true
fi

# proot has a session bus but no *system* bus. GNOME Shell asks logind over the
# system bus for suspend/lock state while building the background, so
# Gio.DBus.system throws "A connection to the bus can't be made" and the shell
# dies before the first frame. Pointing DBUS_SYSTEM_BUS_ADDRESS at a private
# daemon that simply has no logind service makes the lookup fail softly.
if [ -z "${DBUS_SYSTEM_BUS_ADDRESS:-}" ] && command -v dbus-daemon >/dev/null 2>&1; then
    _lfa_bus=/tmp/lfa-gnome-system-bus
    mkdir -p "$_lfa_bus" 2>/dev/null || true
    rm -f "$_lfa_bus/socket" 2>/dev/null || true
    dbus-daemon --session --fork --nopidfile \
        --address="unix:path=$_lfa_bus/socket" >/dev/null 2>&1 || true
    if [ -S "$_lfa_bus/socket" ]; then
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$_lfa_bus/socket"
        export DBUS_SYSTEM_BUS_ADDRESS
    fi
fi

# GNOME 49+ removed the X11 session; without it GNOME cannot run in proot.
if gnome-shell --help 2>&1 | grep -q -- '--x11'; then
    exec gnome-shell --x11
fi
echo "This GNOME release no longer supports an X11 session (--x11)." >&2
echo "GNOME cannot run inside proot without X11. Use XFCE/MATE instead, or" >&2
echo "pin a distribution release that ships GNOME 48 or older." >&2
exit 1
LFA_GNOME
    chmod 755 "$R/usr/local/bin/start-gnome-session" 2>/dev/null || true
fi

# ---------------- init-less guest helpers ---------------------------
# There is no init/PID 1 in a proot container, so reboot/shutdown fail with
# "System has not been booted with systemd" and "Failed to talk to init
# daemon". Replace them with a message that points at the commands that do
# work, instead of a confusing error.
for _cmd in reboot poweroff halt shutdown; do
    cat > "$R/usr/local/bin/$_cmd" <<'LFA_INIT'
#!/bin/sh
cat <<'MSG'
Linux for Android: this is a proot container, not a virtual machine.
There is no init/systemd (PID 1), so reboot and shutdown cannot work here.

  restart the desktop : open Termux and run  start-linux
  stop everything     : open Termux and run  stop-linux
  leave this shell    : exit

MSG
exit 1
LFA_INIT
    chmod 755 "$R/usr/local/bin/$_cmd" 2>/dev/null || true
done

# ---------------- glycin (gdk-pixbuf >= 2.42.11) --------------------
# New GTK stacks decode PNG/JPEG through glycin, which sandboxes its loader
# with bubblewrap. proot cannot create user namespaces, so bwrap always fails
# and gdk-pixbuf aborts the whole application (Kali 2026, Fedora 44, ...).
# Report the exact failure glycin's availability probe recognises, so it
# falls back to in-process decoding instead of killing the desktop.
if [ -d "$R/usr/libexec/glycin-loaders" ] || \
   [ -d "$R/usr/lib/glycin-loaders" ] || \
   ls "$R"/usr/lib*/libglycin-*.so* "$R"/usr/lib/*/libglycin-*.so* >/dev/null 2>&1; then
    cat > "$R/usr/local/bin/bwrap" <<'LFA_BWRAP'
#!/bin/sh
# Linux-for-Android: bubblewrap cannot create namespaces inside proot.
# glycin (gdk-pixbuf image loading) treats this message as "sandbox
# unavailable" and decodes images in-process instead of aborting GTK.
echo "bwrap: No permissions to create a new namespace" >&2
exit 1
LFA_BWRAP
    chmod 755 "$R/usr/local/bin/bwrap" 2>/dev/null || true
fi

exit 0
