#!/bin/sh
# Linux-for-Android: proot-safe dpkg-statoverride.
#
# Why this exists:
#   * Old proot fails dpkg's atomic rename with EPERM, which leaves packages
#     such as dbus half-configured ("dbus-daemon-launch-helper" registration).
#   * A statoverride row naming a user/group that does not exist makes every
#     later dpkg invocation abort with:
#       "unknown system group '...' in statoverride file"
#     which bricks apt until the row is removed by hand.
#
# This shim validates users/groups before recording a row and rewrites the
# file in place (no rename), so neither failure can happen.
REAL=${LFA_DPKG_STATOVERRIDE:-/usr/sbin/dpkg-statoverride}
[ -x "$REAL" ] || REAL=/usr/bin/dpkg-statoverride
DB=${LFA_STATOVERRIDE_DB:-/var/lib/dpkg/statoverride}
TMP="$DB.lfa.tmp"

uok() { getent passwd "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/passwd; }
gok() { getent group "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/group; }

sanitize() {
    [ -f "$DB" ] || return 0
    : > "$TMP"
    while read -r u g m p; do
        [ -n "$u" ] || continue
        [ -n "$p" ] || continue
        uok "$u" || continue
        gok "$g" || continue
        printf '%s %s %s %s\n' "$u" "$g" "$m" "$p" >> "$TMP"
    done < "$DB"
    cat "$TMP" > "$DB"
    rm -f "$TMP"
}

case " $* " in
    *" --list "*) sanitize; exec "$REAL" "$@" ;;
    *" --add "*|*" --update "*) op=add ;;
    *" --remove "*) op=remove ;;
    *) exec "$REAL" "$@" ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --add|--update|--remove|--force|--force-all|--quiet) shift ;;
        *) break ;;
    esac
done

if [ "$op" = "add" ]; then
    [ $# -ge 4 ] || { echo "dpkg-statoverride: bad usage" >&2; exit 2; }
    uok "$1" || { echo "dpkg-statoverride: unknown user '$1'; not recording $4" >&2; exit 0; }
    gok "$2" || { echo "dpkg-statoverride: unknown group '$2'; not recording $4" >&2; exit 0; }
    sanitize
    grep -v " $4\$" "$DB" 2>/dev/null > "$TMP" || true
    printf '%s %s %s %s\n' "$1" "$2" "$3" "$4" >> "$TMP"
else
    [ $# -ge 1 ] || { echo "dpkg-statoverride: bad usage" >&2; exit 2; }
    sanitize
    grep -v " $1\$" "$DB" 2>/dev/null > "$TMP" || true
fi
cat "$TMP" > "$DB"
rm -f "$TMP"
exit 0
