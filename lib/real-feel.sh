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
cat > "$R/etc/profile.d/01-lfa-env.sh" <<'CLEAN'
#!/bin/sh
# Make `env` look like a normal Linux box.
for _v in $(env 2>/dev/null | sed -n 's/^\(TERMUX[^=]*\|ANDROID[^=]*\|EXTERNAL_STORAGE\|PREFIX\|LD_PRELOAD\|TMPDIR\)=.*/\1/p'); do
    unset "$_v" 2>/dev/null || true
done
unset _v
case "${SHELL:-}" in /data/data/*) SHELL=/bin/bash; export SHELL ;; esac
case "${TERM:-}" in xterm-ghostty|xterm-kitty|alacritty) TERM=xterm-256color; export TERM ;; esac
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
        printf '%s\n' '[ -f /etc/profile.d/01-lfa-env.sh ] && . /etc/profile.d/01-lfa-env.sh'
        printf '%s\n' '[ -f /etc/profile.d/00-lfa-welcome.sh ] && . /etc/profile.d/00-lfa-welcome.sh'
        printf '%s\n' '# <<< linux-for-android prompt <<<'
    } >> "$_rc"
}

write_prompt "$R/root/.bashrc" '#' '01;31'
write_prompt "$R/home/$USER_NAME/.bashrc" '$' '01;32'
write_prompt "$R/etc/skel/.bashrc" '$' '01;32'

exit 0
