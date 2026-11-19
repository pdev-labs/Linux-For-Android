#!/bin/bash

# Exit immediately if a command exits with a non-zero status, and let a
# failure anywhere in a pipeline fail the whole pipeline.
set -e
set -o pipefail

# --help / --version must work anywhere (docs, packaging, CI); everything
# else needs a Termux environment.
if [ -z "$PREFIX" ]; then
    case "${1:-}" in
        -h|--help|-V|--version) ;;
        *)
            echo "Error: This script must be run inside Termux."
            exit 1
            ;;
    esac
fi

# Directory containing this script (lib/ lives next to it).
LFA_DIR="$(cd "$(dirname "$0")" && pwd)"
LFA_VERSION="1.7.1"
LFA_RUNTIME="$PREFIX/lib/linux-for-android"
LFA_PREFS="$HOME/.config/linux-for-android/preferences.conf"
LFA_CLI_MODE="${LFA_CLI_MODE:-0}"
LFA_ASSUME_YES="${LFA_ASSUME_YES:-0}"
CLI_INSTANCE="${CLI_INSTANCE:-}"

# ------------------------------------------------------------
# Interrupt safety and temporary artifacts.
# The guest setup script carries the install passwords (obfuscated) and is
# staged in $PREFIX/tmp, which every distro shares as /tmp. Track everything
# written there and remove it on every exit path, including Ctrl-C and a
# failed install (a stray copy used to survive forever).
# ------------------------------------------------------------
LFA_TMP_ARTIFACTS=()
lfa_track_tmp() { LFA_TMP_ARTIFACTS+=("$1"); }
lfa_cleanup() {
    [ "${LFA_KEEP_SETUP_SCRIPT:-0}" = "1" ] && return 0
    local _f
    for _f in ${LFA_TMP_ARTIFACTS[@]+"${LFA_TMP_ARTIFACTS[@]}"}; do
        rm -f "$_f" 2>/dev/null || true
    done
}
trap lfa_cleanup EXIT INT TERM

# ============================================================
# Interactive UI (npm-style)
# Arrow keys / Enter / space work on a real terminal. When
# stdin is piped (CI, `curl | bash`, tests) the installer falls back to
# plain numbered prompts so automation keeps working.
# ============================================================
UI_TTY=0
if [ -t 0 ] && [ -t 1 ]; then UI_TTY=1; fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
    C_WHITE=$'\033[97m'; C_GRAY=$'\033[90m'
    C_BGREEN=$'\033[1;32m'; C_BCYAN=$'\033[1;36m'; C_BRED=$'\033[1;31m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""
    C_CYAN=""; C_WHITE=""; C_GRAY=""; C_BGREEN=""; C_BCYAN=""; C_BRED=""
fi
export C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA \
       C_CYAN C_WHITE C_GRAY C_BGREEN C_BCYAN C_BRED

ui_clear() {
    if [ "$UI_TTY" = "1" ]; then printf '\033[2J\033[H'; fi
}

ui_rule() {
    printf '%s──────────────────────────────────────────────%s\n' "$C_GRAY" "$C_RESET"
}

ui_banner() {
    printf '\n  %sLinux for Android%s  %s· installer · v%s%s\n' \
        "$C_BCYAN" "$C_RESET" "$C_DIM" "$LFA_VERSION" "$C_RESET"
    ui_rule
}

ui_ok()   { printf '  %s✓%s %s\n' "$C_BGREEN" "$C_RESET" "$*"; }
ui_warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
ui_err()  { printf '  %s✗%s %s\n' "$C_BRED" "$C_RESET" "$*"; }

# ui_select <title> <default-key> <key|label|description>...
# Result: UI_SELECTED (the key). Returns 1 on 'q' (back/abort).
ui_select() {
    local _title="$1" _def="$2"; shift 2
    local -a _items=("$@")
    local _n=$# _i=0 _sel=0 _picked=0 _k _l _d _ans _key _typed=""
    local _note="${UI_NOTE:-}"
    UI_NOTE=""
    for _i in "${!_items[@]}"; do
        [ "${_items[$_i]%%|*}" = "$_def" ] && _sel=$_i
    done

    if [ "$UI_TTY" != "1" ]; then
        ui_banner
        printf '\n  %s%s%s\n' "$C_BOLD" "$_title" "$C_RESET"
        [ -n "$_note" ] && printf '  %s%s%s\n' "$C_GRAY" "$_note" "$C_RESET"
        printf '\n'
        for _i in "${!_items[@]}"; do
            IFS='|' read -r _k _l _d <<< "${_items[$_i]}"
            printf '  %s) %s' "$_k" "$_l"
            [ -n "$_d" ] && printf '  (%s)' "$_d"
            printf '\n'
        done
        while :; do
            printf 'Select (default %s): ' "$_def"
            if ! IFS= read -r _ans; then
                printf '\n'
                return 1
            fi
            [ -z "$_ans" ] && _ans="$_def"
            for _i in "${!_items[@]}"; do
                IFS='|' read -r _k _l _d <<< "${_items[$_i]}"
                if [ "$_k" = "$_ans" ]; then UI_SELECTED="$_k"; return 0; fi
            done
            echo "Invalid choice"
        done
    fi

    while :; do
        ui_clear
        ui_banner
        printf '\n  %s%s%s\n' "$C_BOLD$C_WHITE" "$_title" "$C_RESET"
        [ -n "$_note" ] && printf '  %s%s%s\n' "$C_GRAY" "$_note" "$C_RESET"
        printf '\n'
        for _i in "${!_items[@]}"; do
            IFS='|' read -r _k _l _d <<< "${_items[$_i]}"
            if [ "$_i" -eq "$_sel" ]; then
                printf '  %s❯ %s)%s %s%s%s\n' "$C_BCYAN" "$_k" "$C_RESET" "$C_BOLD" "$_l" "$C_RESET"
                [ -n "$_d" ] && printf '      %s%s%s\n' "$C_GRAY" "$_d" "$C_RESET"
            else
                printf '    %s%s)%s %s%s%s\n' "$C_GRAY" "$_k" "$C_RESET" "$C_DIM" "$_l" "$C_RESET"
                [ -n "$_d" ] && printf '      %s%s%s\n' "$C_GRAY" "$_d" "$C_RESET"
            fi
        done
        printf '\n  %s↑/↓ move  ·  Enter select  ·  q back%s' "$C_DIM" "$C_RESET"
        [ -n "$_typed" ] && printf '  %s[%s]%s' "$C_CYAN" "$_typed" "$C_RESET"
        printf '\n'
        IFS= read -rsn1 _key || true
        case "$_key" in
            "") break ;;
            q|Q) return 1 ;;
            $'\033')
                _typed=""
                IFS= read -rsn2 -t 0.05 _key || true
                case "$_key" in
                    '[A'|'OA') _sel=$((_sel-1)) ;;
                    '[B'|'OB') _sel=$((_sel+1)) ;;
                esac
                [ "$_sel" -lt 0 ] && _sel=$((_n-1))
                [ "$_sel" -ge "$_n" ] && _sel=0
                ;;
            [0-9])
                # Type "10" and press Enter. A single digit only moves the
                # highlight (no surprise selection before Enter).
                _typed="${_typed}${_key}"
                _picked=0
                for _i in "${!_items[@]}"; do
                    if [ "${_items[$_i]%%|*}" = "$_typed" ]; then _sel=$_i; _picked=1; break; fi
                done
                if [ "$_picked" != "1" ] && [ "${#_typed}" -gt 1 ]; then
                    _typed="$_key"
                    for _i in "${!_items[@]}"; do
                        if [ "${_items[$_i]%%|*}" = "$_typed" ]; then _sel=$_i; break; fi
                    done
                fi
                ;;
        esac
    done
    IFS='|' read -r _k _l _d <<< "${_items[$_sel]}"
    UI_SELECTED="$_k"
    return 0
}

# ui_confirm <question> <y|n default>. Returns 0 for yes, 1 for no.
ui_confirm() {
    local _q="$1" _def="$2" _ans _sel _i _key
    local _keep="${UI_NO_CLEAR:-0}"
    UI_NO_CLEAR=0
    if [ "$LFA_ASSUME_YES" = "1" ]; then
        printf '%s [yes]\n' "$_q"
        return 0
    fi
    if [ "$UI_TTY" != "1" ]; then
        local _hint='y/N'
        [ "$_def" = "y" ] && _hint='Y/n'
        while :; do
            printf '%s [%s]: ' "$_q" "$_hint"
            if ! IFS= read -r _ans; then
                printf '\n'
                return 1
            fi
            _ans="${_ans:-$_def}"
            case "$_ans" in
                [Yy]|1|yes|YES) return 0 ;;
                [Nn]|2|no|NO)  return 1 ;;
                *) echo "Invalid choice" ;;
            esac
        done
    fi

    _sel=0
    [ "$_def" = "n" ] && _sel=1
    while :; do
        if [ "$_keep" != "1" ]; then
            ui_clear
            ui_banner
        fi
        printf '\n  %s%s%s\n\n' "$C_BOLD$C_WHITE" "$_q" "$C_RESET"
        for _i in 0 1; do
            if [ "$_i" -eq "$_sel" ]; then
                [ "$_i" = 0 ] && printf '  %s❯ Yes%s\n' "$C_BCYAN" "$C_RESET" || printf '  %s❯ No%s\n' "$C_BCYAN" "$C_RESET"
            else
                [ "$_i" = 0 ] && printf '    %sYes%s\n' "$C_DIM" "$C_RESET" || printf '    %sNo%s\n' "$C_DIM" "$C_RESET"
            fi
        done
        printf '\n  %s←/→ or ↑/↓ choose · Enter confirm · y/n shortcut%s\n' "$C_DIM" "$C_RESET"
        IFS= read -rsn1 _key || true
        case "$_key" in
            "") break ;;
            y|Y) _sel=0; break ;;
            n|N) _sel=1; break ;;
            $'\033')
                IFS= read -rsn2 -t 0.05 _key || true
                case "$_key" in
                    '[A'|'OA'|'[D'|'OD') _sel=0 ;;
                    '[B'|'OB'|'[C'|'OC') _sel=1 ;;
                esac
                ;;
        esac
    done
    [ "$_sel" = "0" ]
}

# ui_multi <title> <key|label|description>...
# Result: UI_MULTI (space-separated selected keys; empty = none).
ui_multi() {
    local _title="$1"; shift
    local -a _items=("$@") _chosen=()
    local _n=$# _i=0 _sel=0 _k _l _d _ans _bad _key _mark _c _picked

    if [ "$UI_TTY" != "1" ]; then
        printf '\n%s\n' "$_title"
        for _i in "${!_items[@]}"; do
            IFS='|' read -r _k _l _d <<< "${_items[$_i]}"
            printf '  %s) %s' "$_k" "$_l"
            [ -n "$_d" ] && printf '  (%s)' "$_d"
            printf '\n'
        done
        while :; do
            printf 'Selection (numbers separated by spaces, Enter to skip): '
            if ! IFS= read -r _ans; then
                printf '\n'
                return 1
            fi
            _ans="$(echo "${_ans:-}" | xargs)"
            if [ -z "$_ans" ]; then UI_MULTI=""; return 0; fi
            if echo "$_ans" | grep -Eq '^[0-9 ]+$'; then
                _bad=""
                for _c in $_ans; do
                    if ! { [ "$_c" -ge 1 ] 2>/dev/null && [ "$_c" -le 14 ] 2>/dev/null; }; then
                        _bad="$_bad $_c"
                    fi
                done
                if [ -z "$_bad" ]; then UI_MULTI="$_ans"; return 0; fi
                echo "Invalid numbers:$_bad — use 1-14 separated by spaces."
            else
                echo "Use numbers 1-14 separated by spaces (or Enter to skip)."
            fi
        done
    fi

    while :; do
        ui_clear
        ui_banner
        printf '\n  %s%s%s\n\n' "$C_BOLD$C_WHITE" "$_title" "$C_RESET"
        for _i in "${!_items[@]}"; do
            IFS='|' read -r _k _l _d <<< "${_items[$_i]}"
            _mark=" "
            case " ${_chosen[*]} " in *" $_k "*) _mark="x" ;; esac
            if [ "$_i" -eq "$_sel" ]; then
                printf '  %s❯ [%s] %s) %s%s%s\n' "$C_BCYAN" "$_mark" "$_k" "$C_BOLD" "$_l" "$C_RESET"
                [ -n "$_d" ] && printf '          %s%s%s\n' "$C_GRAY" "$_d" "$C_RESET"
            else
                printf '    %s[%s]%s %s%s)%s %s%s%s\n' "$C_GREEN" "$_mark" "$C_RESET" "$C_GRAY" "$_k" "$C_RESET" "$C_DIM" "$_l" "$C_RESET"
            fi
        done
        printf '\n  %s↑/↓ move · space toggle · a all · n none · Enter done%s\n' "$C_DIM" "$C_RESET"
        _picked=0
        IFS= read -rsn1 _key || true
        case "$_key" in
            "") break ;;
            q|Q) return 1 ;;
            ' ')
                IFS='|' read -r _k _l _d <<< "${_items[$_sel]}"
                case " ${_chosen[*]} " in
                    *" $_k "*)
                        local -a _next=()
                        for _c in "${_chosen[@]}"; do [ "$_c" != "$_k" ] && _next+=("$_c"); done
                        _chosen=("${_next[@]}")
                        ;;
                    *) _chosen+=("$_k") ;;
                esac
                ;;
            a|A)
                _chosen=()
                for _i in "${!_items[@]}"; do _chosen+=("${_items[$_i]%%|*}"); done
                ;;
            n|N) _chosen=() ;;
            $'\033')
                IFS= read -rsn2 -t 0.05 _key || true
                case "$_key" in
                    '[A'|'OA') _sel=$((_sel-1)) ;;
                    '[B'|'OB') _sel=$((_sel+1)) ;;
                esac
                [ "$_sel" -lt 0 ] && _sel=$((_n-1))
                [ "$_sel" -ge "$_n" ] && _sel=0
                ;;
        esac
    done
    UI_MULTI="${_chosen[*]}"
    return 0
}

LFA_NONINTERACTIVE="${LFA_NONINTERACTIVE:-0}"

ui_pause() {
    [ "$LFA_NONINTERACTIVE" = "1" ] && return 0
    printf '\n  %sPress Enter to continue...%s' "$C_DIM" "$C_RESET"
    IFS= read -r _ || true
}

# ============================================================
# Universal Android compatibility layer (Android 5 -> 15)
# Oppo A37fw (Android 5.1.1, SDK 22, 32-bit ARM) has a frozen
# Termux repo where 'proot-distro' / 'virglrenderer-android'
# do not exist as packages. Detect legacy devices and fall
# back gracefully instead of aborting (set -e).
# ============================================================
detect_environment() {
    ANDROID_SDK=0
    if command -v getprop >/dev/null 2>&1; then
        ANDROID_SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo 0)
    fi
    # Strip anything non-numeric (some ROMs return extra text)
    ANDROID_SDK=$(echo "$ANDROID_SDK" | tr -cd '0-9')
    if [ -z "$ANDROID_SDK" ]; then ANDROID_SDK=0; fi

    ARCH=$(uname -m 2>/dev/null || echo unknown)

    IS_LEGACY=0
    # Termux current builds require Android 7+ (SDK 24).
    # Anything below that uses archived repos with missing packages.
    if [ "$ANDROID_SDK" -gt 0 ] && [ "$ANDROID_SDK" -lt 24 ]; then
        IS_LEGACY=1
    fi
    # Termux:X11 and GNOME need Android 8 (SDK 26). That is a different
    # cutoff from the legacy Termux repo cutoff above: Android 7.0/7.1
    # (SDK 24/25) use modern Termux packages but still cannot run X11.
    X11_SUPPORTED=0
    if [ "$ANDROID_SDK" = "0" ] || [ "$ANDROID_SDK" -ge 26 ]; then
        X11_SUPPORTED=1
    fi
    # Non-Android shells (PC debugging) report SDK 0 -> treat as modern
    # so script syntax can still be tested, but say so instead of silently
    # behaving differently.
    if [ "$ANDROID_SDK" = "0" ] && [ "${LFA_SDK_WARNED:-0}" != "1" ]; then
        echo "[!] Could not read the Android version (getprop unavailable)."
        echo "    Legacy-device handling is disabled for this run."
        LFA_SDK_WARNED=1
    fi

    IS_32BIT_ARM=0
    case "$ARCH" in
        armv7*|armv6*|armhf|arm)
            IS_32BIT_ARM=1
            ;;
    esac
}

print_device_info() {
    detect_environment
    echo "[*] Device detected: arch=$ARCH | android_sdk=$ANDROID_SDK | legacy=$IS_LEGACY"
    if [ "$IS_LEGACY" = "1" ]; then
        echo "----------------------------------------------------------------"
        echo " LEGACY MODE: Android 5/6 detected (SDK $ANDROID_SDK)."
        echo " - Termux:X11 and VirGL GPU acceleration are NOT available."
        echo "   VNC (software rendering) will be used automatically."
        echo " - 'proot-distro' package may be missing. The script will"
        echo "   try to install it from source (pure bash + proot)."
        echo " - STRONGLY recommended: Alpine Linux (musl, option 8)."
        echo "   glibc distros (Ubuntu/Debian/Fedora/...) fail on the"
        echo "   3.10 kernel at the first guest command (verified)."
        echo "   32-bit ARM note: Alpine/Ubuntu/Debian/Kali have arm builds;"
        echo "   Fedora / openSUSE / Void / Arch may lack 32-bit images."
        echo "----------------------------------------------------------------"
    elif [ "$X11_SUPPORTED" != "1" ]; then
        echo "----------------------------------------------------------------"
        echo " X11 UNAVAILABLE: Android 7.0/7.1 detected (SDK $ANDROID_SDK)."
        echo " - Termux packages are modern, so the normal install path is used."
        echo " - Termux:X11 and GNOME require Android 8 (SDK 26) or newer."
        echo "   VNC (software rendering) will be used automatically."
        echo "----------------------------------------------------------------"
    fi
}

# Install proot-distro from GitHub when 'pkg install proot-distro'
# fails (typical on Android 5.1.1 archived repos).
# Install proot-distro v4.2.0 from source — the LAST shell-based release.
# Upstream HEAD (v5+) is a Python rewrite needing modern Python/pip plus
# Docker-registry installs, unsuitable for Android 5/6. v4.2.0 is pure
# bash + proot, supports --override-alias and all classic rootfs tarballs.
# Its install.sh also performs the @TERMUX_PREFIX@ substitution that a
# naive 'cp proot-distro.sh' would skip (which yields a broken install
# whose 'list' is empty and every install fails with "unknown distribution").
PD_LEGACY_TAG="v4.2.0"
install_proot_distro_from_source() {
    echo "[*] Installing proot-distro $PD_LEGACY_TAG from source (legacy fallback)..."
    # set +e: every step here is best-effort, checked manually
    set +e
    pkg install -y proot wget tar 2>/dev/null || true
    if ! command -v proot >/dev/null 2>&1; then
        echo "ERROR: 'proot' itself could not be installed."
        echo "Your Termux repo seems unreachable. Try:"
        echo "  1) Use F-Droid Termux 0.118 (last build with Android 5 support)"
        echo "  2) Run 'termux-change-repo' and pick a working mirror"
        echo "  3) Then re-run this script."
        set -e
        return 1
    fi
    mkdir -p "$PREFIX/tmp"
    SRC_DIR="$PREFIX/tmp/proot-distro-4.2.0-src"
    rm -rf "$SRC_DIR"
    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 --branch "$PD_LEGACY_TAG" https://github.com/termux/proot-distro "$SRC_DIR" 2>/dev/null || rm -rf "$SRC_DIR"
    fi
    # Fallback if git missing/failed: fetch the pinned tag tarball via wget
    if [ ! -f "$SRC_DIR/install.sh" ]; then
        rm -rf "$SRC_DIR"
        mkdir -p "$SRC_DIR"
        if wget -qO "$PREFIX/tmp/pd-4.2.0.tar.gz" "https://github.com/termux/proot-distro/archive/refs/tags/${PD_LEGACY_TAG}.tar.gz" 2>/dev/null; then
            tar -xzf "$PREFIX/tmp/pd-4.2.0.tar.gz" -C "$PREFIX/tmp" 2>/dev/null || true
            cp -r "$PREFIX/tmp"/proot-distro-4.2.0/* "$SRC_DIR"/ 2>/dev/null || true
        fi
    fi
    # No published checksum exists for GitHub tag archives (they are not
    # byte-stable), so validate the tree instead of trusting the download.
    if [ -f "$SRC_DIR/proot-distro.sh" ] && ! grep -q "$PD_LEGACY_TAG\|4\.2\.0" "$SRC_DIR/proot-distro.sh" 2>/dev/null; then
        echo "[!] proot-distro source does not look like $PD_LEGACY_TAG; refusing to install it."
        rm -rf "$SRC_DIR"
    fi
    if [ -f "$SRC_DIR/install.sh" ]; then
        # install.sh respects TERMUX_PREFIX/TERMUX_ANDROID_HOME from env,
        # so this also works on Termux forks with non-standard paths.
        ( cd "$SRC_DIR" && TERMUX_PREFIX="$PREFIX" TERMUX_ANDROID_HOME="$HOME" bash install.sh ) 2>/dev/null || \
        ( cd "$SRC_DIR" && TERMUX_PREFIX="$PREFIX" TERMUX_ANDROID_HOME="$HOME" bash install.sh )
        mkdir -p "$PREFIX/var/lib/proot-distro/installed-rootfs" "$PREFIX/var/lib/proot-distro/dl-cache"
        hash -r 2>/dev/null || true
        if command -v proot-distro >/dev/null 2>&1; then
            echo "[*] proot-distro $PD_LEGACY_TAG installed to $PREFIX/bin/proot-distro"
            set -e
            return 0
        fi
    fi
    echo "ERROR: Could not fetch proot-distro $PD_LEGACY_TAG sources (no network?)."
    set -e
    return 1
}

# `producer | grep -q` is unsafe with `set -o pipefail`: grep exits at the
# first match, the producer dies with SIGPIPE (141), and the pipeline is
# reported as failed even though the match succeeded. This helper keeps the
# text in a variable and uses bash's own regex engine instead.
lfa_match() { # $1 text, $2 extended regex (case-insensitive)
    local _t="$1" _p="$2" _rc
    shopt -s nocasematch
    [[ "$_t" =~ $_p ]]; _rc=$?
    shopt -u nocasematch
    return $_rc
}

# Verify the installed proot-distro actually knows distro $1.
# Frozen Android 5 repos ship a pre---override-alias proot-distro build
# whose plugin dir can be empty -> every install fails with
# "unknown distribution 'debian'". Repair from pinned sources then.
# On modern devices the pkg build is authoritative: never overwrite it,
# just show 'proot-distro list' and stop.
verify_proot_distro_plugin() {
    WANT="$1"
    # proot-distro v5+ installs OCI images directly. Its `list` command only
    # shows created containers, not available distro plugins, so checking it
    # would reject every not-yet-installed image (e.g. alpine:latest).
    if command -v proot-distro >/dev/null 2>&1 && \
       lfa_match "$(proot-distro install --help 2>&1)" '(IMAGE:TAG|Docker image|registry)'; then
        return 0
    fi
    # NOTE: proot-distro prints EVERYTHING (including 'list' results)
    # to stderr via msg(), so capture 2>&1 here, not 2>/dev/null.
    set +e
    if command -v proot-distro >/dev/null 2>&1 && \
       lfa_match "$(proot-distro list 2>&1)" "(^|[^[:alnum:]_])$WANT([^[:alnum:]_]|$)"; then
        set -e
        return 0
    fi
    if [ "$IS_LEGACY" != "1" ]; then
        echo "ERROR: your proot-distro knows no '$WANT' distribution."
        echo "Available distributions:"
        proot-distro list 2>&1 || true
        set -e
        return 1
    fi
    echo "[!] proot-distro has no '$WANT' plugin (stale pre-$PD_LEGACY_TAG pkg build?). Repairing from $PD_LEGACY_TAG sources..."
    install_proot_distro_from_source || { set -e; return 1; }
    if lfa_match "$(proot-distro list 2>&1)" "(^|[^[:alnum:]_])$WANT([^[:alnum:]_]|$)"; then
        set -e
        return 0
    fi
    echo "ERROR: '$WANT' still unknown after repair. Supported names:"
    proot-distro list 2>&1 || true
    set -e
    return 1
}

# Resilient dependency installer. Never aborts the whole script
# on one missing optional package (old behavior with 'set -e' did).
ensure_dependencies() {
    NEED_X11="$1"  # "1" if user chose Termux:X11, else "0"
    set +e  # do NOT exit on single pkg failure here
    echo "[*] Updating Termux packages (best effort)..."
    pkg update -y 2>/dev/null || true
    # NOTE: 'pkg upgrade' on EOL Android 5 repos can break things;
    # run it but never abort on failure.
    pkg upgrade -y 2>/dev/null || true

    echo "[*] Installing core dependencies (proot, wget, curl, pulseaudio)..."
    # NOTE: v4.2.0 proot-distro downloads rootfs with 'curl' (not wget)
    # and needs coreutils/findutils/gawk tools, so install them explicitly:
    # a bare Termux bootstrap on old Android may miss some.
    pkg install -y proot wget curl pulseaudio 2>/dev/null || true
    pkg install -y coreutils findutils gawk 2>/dev/null || true
    # 'proot-distro' may not exist on SDK 22 repos -> source fallback
    if ! command -v proot-distro >/dev/null 2>&1; then
        pkg install -y proot-distro 2>/dev/null || true
    fi
    if ! command -v proot-distro >/dev/null 2>&1; then
        install_proot_distro_from_source || {
            echo "FATAL: proot-distro unavailable. Cannot continue."
            set -e
            exit 1
        }
    fi

    # virglrenderer-android = optional GPU accel, Android 7+ only.
    # Missing on Android 5 -> silently skip, VNC will be used.
    # NEED_VIRGL (from guided setup) can disable it on modern devices too.
    if [ "$IS_LEGACY" = "1" ]; then
        echo "[*] Skipping virglrenderer-android (not available on Android 5/6)."
    elif [ "${NEED_VIRGL:-1}" = "1" ]; then
        echo "[*] Installing VirGL (optional, for GPU acceleration)..."
        pkg install -y virglrenderer-android 2>/dev/null || echo "[!] virglrenderer-android unavailable, continuing without GPU acceleration."
    else
        echo "[*] VirGL disabled by setup choice."
    fi

    if [ "$NEED_X11" = "1" ]; then
        if ! x11_supported; then
            echo "[!] Termux:X11 requires Android 8+ (SDK 26). Cannot install on this device."
        else
            echo "[*] Installing Termux:X11 backend..."
            pkg install -y x11-repo 2>/dev/null || true
            pkg install -y termux-x11-nightly 2>/dev/null || echo "[!] termux-x11-nightly install failed. Use VNC instead."
        fi
    fi
    set -e
}

# login flags for proot-distro: v4 login passes --sysvipc by default,
# but the frozen Android 5 proot (5.1.x) has no such option, so EVERY
# login dies with "unknown option '--sysvipc'". Opt out when needed.
# Detection is file-based (no execution), safe on modern builds too:
# v5+ pkg builds keep working untouched.
pd_login_flags() {
    if command -v proot >/dev/null 2>&1 && ! lfa_match "$(proot --help 2>&1)" 'sysvipc'; then
        if [ -f "$PREFIX/bin/proot-distro" ] && grep -q "no-sysvipc" "$PREFIX/bin/proot-distro" 2>/dev/null; then
            echo "--no-sysvipc"
        fi
    fi
}

# v4 shell builds (legacy fallback) vs v5 Python builds have different
# backup/restore CLI: v4 'restore' takes a tarball PATH and restores the
# embedded instance name; only v5 understands '--input <file>' + rename.
pd_is_v4() {
    # v4.2 source builds keep the legacy plugin layout; v5+ installs OCI
    # images and restores from a single archive argument (`restore FILE`).
    [ -f "$PREFIX/bin/proot-distro" ] || return 1
    grep -q "DISTRO_PLUGINS_DIR" "$PREFIX/bin/proot-distro" 2>/dev/null && return 0
    lfa_match "$(proot-distro restore --help 2>&1)" 'BACKUP_FILE' 
}

# Legacy devices need the bullseye plug-in (shipped in ./plugins), which
# neither the frozen pkg build nor a clean v4.2.0 source install provides.
deploy_legacy_plugins() {
    [ "$IS_LEGACY" = "1" ] || return 0
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$SCRIPT_DIR/plugins/bullseye.sh" ]; then
        mkdir -p "$PREFIX/etc/proot-distro"
        cp "$SCRIPT_DIR/plugins/bullseye.sh" "$PREFIX/etc/proot-distro/bullseye.sh"
        chmod 600 "$PREFIX/etc/proot-distro/bullseye.sh" 2>/dev/null || true
    else
        echo "[!] Warning: plugins/bullseye.sh not found next to the script;"
        echo "    legacy Debian installs will fail. Re-clone the repository."
    fi
}

# ============================================================
# Desktop / display-server questions.
# Guided setup and the install wizard used to carry two copies of these
# menus; adding GNOME meant editing both. One implementation now.
# ============================================================
ask_desktop_environment() {   # $1 = suggestion label, $2 = default index
    local _suggest="${1:-XFCE4}" _def="${2:-1}"
    local -a _items=(
        "1|XFCE4|light, familiar, great on phones"
        "2|LXDE|ultra light, minimal"
        "3|MATE|classic GNOME 2 feel"
        "4|None (CLI only)|terminal only - lightest and fastest"
    )
    gnome_available && _items+=("5|GNOME (experimental)|BETA - may crash; read the warning")
    ui_select "Choose Desktop Environment (suggested: $_suggest)" "$_def" "${_items[@]}" || return 1
    case "$UI_SELECTED" in
        1) DE="xfce4" ;;
        2) DE="lxde" ;;
        3) DE="mate" ;;
        4) DE="none" ;;
        5) DE="gnome" ;;
    esac
    if [ "$DE" = "gnome" ] && ! gnome_experimental_warning; then
        echo "[*] Falling back to XFCE4."
        DE="xfce4"
    fi
    return 0
}

ask_display_server() {        # $1 = default index (1=x11, 2=vnc)
    local _def="${1:-1}"
    ui_select "Choose Display Server" "$_def" \
        "1|Termux:X11|hardware acceleration, faster, smoother" \
        "2|VNC|software rendering, works everywhere, slower" \
        "3|Both|install both; choose one each time you start" || return 1
    case "$UI_SELECTED" in
        1) SERVER="x11" ;;
        2) SERVER="vnc" ;;
        3) SERVER="both" ;;
    esac
    if [ "$DE" = "gnome" ] && { [ "$SERVER" = "x11" ] || [ "$SERVER" = "both" ]; }; then
        echo "[!] GNOME over Termux:X11 is known to crash the app often."
        echo "    VNC is more stable for GNOME - Both keeps VNC available too."
    fi
    return 0
}

# Termux:X11 requires Android 8 (SDK 26). Keep this separate from
# IS_LEGACY, which describes the Termux package/repo cutoff (SDK 24).
x11_supported() {
    [ "${X11_SUPPORTED:-0}" = "1" ]
}

# Both backends share one config value. These helpers keep the package,
# password, launcher and verification paths from drifting when "both" is set.
server_has_x11() {
    case "${SERVER:-none}" in x11|both) return 0 ;; esac
    return 1
}
server_has_vnc() {
    case "${SERVER:-none}" in vnc|both) return 0 ;; esac
    return 1
}

# Guest binaries are often absolute symlinks (vncserver -> /etc/alternatives/
# vncserver). Checking them from the host follows the link into the host's
# /etc and reports a false "missing package"; accept the link itself.
guest_has_path() {
    [ -e "$1" ] || [ -L "$1" ]
}

# ============================================================
# Guided setup questionnaire (integrated first screen).
# Asks everything up front, saves answers to setup.conf for unattended
# re-runs, then hands off to install_linux() with SETUP_ANSWERED=1 so no
# question is asked twice. Passwords are base64-encoded (obfuscation, not
# encryption) in a mode-0600 file; treat that file as a secret.
# ============================================================
SETUP_CONF="$HOME/.config/linux-for-android/setup.conf"
# Wallpaper mode: light (default) or dark. Guided setup asks for GUI
# installs; CLI-only installs keep the default and skip wallpaper setup.
COLOR_MODE="light"
# Which backend Termux:Boot should start when "both" is installed. Empty
# means "not chosen yet"; the installer fills it before writing the script.
AUTOSTART_SERVER=""

b64enc() {
    printf '%s' "$1" | base64 2>/dev/null | tr -d '\n'
}

setup_read_secret() {
    # $1 = var name to fill, $2 = prompt, $3 = default (used on empty)
    local __prompt="$2" __dflt="$3" __val=""
    if [ -t 0 ]; then
        printf '%s' "$__prompt" >&2
        IFS= read -rs __val || true
        printf '\n' >&2
    else
        IFS= read -r __val || true
    fi
    [ -z "$__val" ] && __val="$__dflt"
    printf -v "$1" '%s' "$__val"
}

setup_confirm_secret() {
    # Like setup_read_secret, but asks twice on a real terminal. There is no
    # password-reset path inside the guest, so a typo is unrecoverable.
    # When stdin is piped (tests/CI) it asks once, as before.
    local __var="$1" __prompt="$2" __dflt="$3" __a="" __b=""
    if [ ! -t 0 ]; then
        setup_read_secret "$__var" "$__prompt" "$__dflt"
        return 0
    fi
    while true; do
        setup_read_secret __a "$__prompt" "$__dflt"
        setup_read_secret __b "  Repeat to confirm: " "$__a"
        [ "$__a" = "$__b" ] && break
        echo "[!] Passwords do not match, try again."
    done
    printf -v "$__var" '%s' "$__a"
}

setup_guess_timezone() {
    local _tz=""
    _tz=$(getprop persist.sys.timezone 2>/dev/null || true)
    case "$_tz" in
        ""|*[!A-Za-z0-9_+./-]*|*..*|/*|*/) _tz="UTC" ;;
    esac
    printf '%s' "${_tz:-UTC}"
}

# Rough free-space requirement (MB) for an install of this shape.
setup_required_mb() {
    if [ "${DE:-none}" = "gnome" ]; then
        printf '3500'
    elif [ "${DE:-none}" != "none" ]; then
        printf '2500'
    else
        printf '900'
    fi
}

# shellcheck disable=SC2120  # $1 is optional (defaults to $PREFIX)
lfa_free_mb() {
    local _path="${1:-$PREFIX}" _kb _blocks _bsize _human _val
    # GNU/BusyBox df: 1024-byte blocks in column 4.
    _kb=$(df -Pk "$_path" 2>/dev/null | awk 'NR==2 {print $4}')
    case "$_kb" in ''|*[!0-9]*) _kb="" ;; esac
    if [ -n "$_kb" ]; then printf '%s' $((_kb / 1024)); return 0; fi
    # Android 5 toybox df ignores -Pk and prints human units (3.6G). Prefer
    # stat -f, which gives exact blocks, then fall back to the human value.
    _blocks=$(stat -f "$_path" 2>/dev/null | awk '/Available:/ {print $2}')
    _bsize=$(stat -f "$_path" 2>/dev/null | sed -n 's/.*Fundamental block size:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    case "${_blocks}${_bsize}" in
        ''|*[!0-9]*) ;;
        *) printf '%s' $((_blocks * _bsize / 1024 / 1024)); return 0 ;;
    esac
    _human=$(df "$_path" 2>/dev/null | awk 'NR==2 {print $4}')
    _val="${_human%[GgMmTt]}"
    case "$_human" in
        *[Gg]) printf '%s' "$(awk -v v="$_val" 'BEGIN {printf "%d", v * 1024}')" ;;
        *[Mm]) printf '%s' "$(awk -v v="$_val" 'BEGIN {printf "%d", v}')" ;;
        *[Tt]) printf '%s' "$(awk -v v="$_val" 'BEGIN {printf "%d", v * 1024 * 1024}')" ;;
        *) printf '%s' "$_human" ;;
    esac
}

# Refuse to start a multi-gigabyte install on a nearly full device: it would
# die halfway through apt and leave a half-configured rootfs behind.
lfa_check_disk_space() {
    local _need _have
    _need="$(setup_required_mb)"
    _have="$(lfa_free_mb)"
    case "$_have" in ''|*[!0-9]*) return 0 ;; esac
    if [ "$_have" -lt "$_need" ]; then
        echo ""
        echo "[!] Not enough free space: this install needs about ${_need} MB,"
        echo "    and only ${_have} MB is free on the Termux filesystem."
        echo "    Remove another distro or clear Downloads, then re-run."
        return 1
    fi
    echo "[*] Free space check: ${_have} MB available, ${_need} MB needed."
    return 0
}

setup_ram_mb() {
    local _m=""
    _m=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
    case "$_m" in
        ''|*[!0-9]*) _m=2048 ;;
    esac
    printf '%s' "$_m"
}

# ============================================================
# GNOME (experimental / beta)
# ============================================================
# gnome-session cannot work under proot: there is no systemd user session and
# no logind seat, so it hands gnome-shell an "Oh no! Something has gone
# wrong" screen. The community workaround is to skip gnome-session entirely
# and run `gnome-shell --x11` directly inside a D-Bus session. That produces a
# real GNOME Shell desktop, but the session services normally started by
# gnome-session never run, so parts of the desktop are missing or unstable.
gnome_distro_supported() {
    case "${DISTRO:-}" in
        ubuntu|debian|kali|archlinux|fedora|opensuse) return 0 ;;
        *) return 1 ;;
    esac
}

gnome_available() {
    x11_supported || return 1
    gnome_distro_supported
}

gnome_experimental_warning() {
    echo ""
    echo "${C_YELLOW}${C_BOLD}================================================================${C_RESET}"
    echo "${C_YELLOW}${C_BOLD}  GNOME  -  EXPERIMENTAL / BETA  -  READ THIS FIRST${C_RESET}"
    echo "${C_YELLOW}${C_BOLD}================================================================${C_RESET}"
    echo ""
    echo "  This is a real GNOME Shell (40+), not GNOME Flashback. It is NOT a"
    echo "  supported desktop and it will misbehave. Install it only to try it."
    echo ""
    echo "${C_BOLD}  How it works${C_RESET}"
    echo "  A normal GNOME session starts gnome-session, which needs systemd and"
    echo "  logind. Neither exists inside proot. So this option skips"
    echo "  gnome-session completely and launches 'gnome-shell --x11' directly"
    echo "  in a D-Bus session."
    echo ""
    echo "${C_BOLD}  What will be missing or broken${C_RESET}"
    echo "   - Login/logout menu, session saving and session restore"
    echo "   - Screen locking, idle blanking, suspend/inhibit"
    echo "   - Some panel/dock entries and the app grid at first login"
    echo "   - GNOME Settings (gnome-control-center) may crash, especially the"
    echo "     Sound panel. The usual 'fix' wipes ~/.cache ~/.config ~/.local,"
    echo "     which also wipes your settings."
    echo "   - Portals, auto-mount, polkit prompts, UPower/brightness, and"
    echo "     notifications are partial or absent"
    echo "   - Extensions that need root or Android files do not work"
    echo "   - Touch input often only works in mouse mode"
    echo "   - Video playback is roughly 1-7 FPS (software rendering)"
    echo "   - Termux:X11 crashes the session often; VNC is more stable, so"
    echo "     VNC is pre-selected here"
    echo "   - A package upgrade that updates systemd/gdm can break the session."
    echo "     If that happens, run menu 0 (Doctor) and start it again."
    echo ""
    echo "${C_BOLD}  Requirements${C_RESET}"
    echo "   - Android 8+ (no Android 5/6, no Alpine, no Void)"
    echo "   - 3 GB RAM minimum, 4 GB+ recommended (it is heavy)"
    echo "   - about 2.5-3 GB of free storage"
    echo ""
    echo "${C_YELLOW}  Bug reports for this desktop are accepted as experimental only.${C_RESET}"
    echo ""
    if ! ui_confirm "I understand this is experimental and may crash - continue with GNOME?" n; then
        echo ""
        echo "[*] GNOME cancelled."
        return 1
    fi
    echo ""
    echo "[*] GNOME selected (experimental). VNC is recommended; you can still"
    echo "    choose Termux:X11 in the next step, but it is less stable."
    return 0
}

setup_save() {
    mkdir -p "$(dirname "$SETUP_CONF")"
    cat > "$SETUP_CONF" <<EOF
# Linux-for-Android setup answers (reused on re-install, chmod 600).
# Passwords are base64-encoded (reversible) - the file mode is what protects
# them, so keep it 0600 and never copy it around.
DISTRO="$DISTRO"
DE="$DE"
SERVER="$SERVER"
RESOLUTION="$RESOLUTION"
COLOR_MODE="$COLOR_MODE"
APP_CHOICES="$APP_CHOICES"
INSTANCE_NAME="$INSTANCE_NAME"
SETUP_USER="$SETUP_USER"
SETUP_USER_B64="$SETUP_USER_B64"
SETUP_ROOT_B64="$SETUP_ROOT_B64"
TIMEZONE="$TIMEZONE"
HOSTNAME="$HOSTNAME"
PSTYLE="$PSTYLE"
NEED_VIRGL="$NEED_VIRGL"
AUTOSTART_SERVER="$AUTOSTART_SERVER"
DO_AUTOSTART="$DO_AUTOSTART"
DO_STORAGE="$DO_STORAGE"
DO_SSH="$DO_SSH"
DO_WIDGET="$DO_WIDGET"
EOF
    chmod 600 "$SETUP_CONF" 2>/dev/null || true
    echo "[*] Answers saved to $SETUP_CONF (reused automatically next time)."
}

setup_summary() {
    printf '\n  %sSetup Summary%s\n' "$C_BOLD$C_WHITE" "$C_RESET"
    ui_rule
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Distribution" "$C_RESET" "$DISTRO"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Desktop" "$C_RESET" "$DE"
    [ "$DE" != "none" ] && printf '  %s%-13s%s %s\n' "$C_GRAY" "Wallpaper" "$C_RESET" "$COLOR_MODE"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Server" "$C_RESET" "$SERVER"
    server_has_vnc && printf '  %s%-13s%s %s\n' "$C_GRAY" "Resolution" "$C_RESET" "$RESOLUTION"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Software" "$C_RESET" "${APP_CHOICES:-none}"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Instance" "$C_RESET" "${INSTANCE_NAME:-(auto)}"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Username" "$C_RESET" "$SETUP_USER"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Password" "$C_RESET" "****"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Root passwd" "$C_RESET" "****"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Timezone" "$C_RESET" "$TIMEZONE"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Hostname" "$C_RESET" "$HOSTNAME"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "HW accel" "$C_RESET" "$([ "$NEED_VIRGL" = "1" ] && echo on || echo off)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Prompt style" "$C_RESET" "$PSTYLE"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Autostart" "$C_RESET" "$([ "$DO_AUTOSTART" = "1" ] && echo "yes (${AUTOSTART_SERVER:-$SERVER})" || echo no)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Storage perm" "$C_RESET" "$([ "$DO_STORAGE" = "1" ] && echo yes || echo no)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "SSH server" "$C_RESET" "$([ "$DO_SSH" = "1" ] && echo yes || echo no)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Widget hint" "$C_RESET" "$([ "$DO_WIDGET" = "1" ] && echo yes || echo no)"
    ui_rule
}

setup_quick() {
    echo "[*] Quick setup: taking every default."
    if [ "$IS_LEGACY" = "1" ]; then DISTRO="alpine"; else DISTRO="debian"; fi
    if [ "$IS_LEGACY" = "1" ] || [ "$(setup_ram_mb)" -le 2048 ]; then DE="none"; else DE="xfce4"; fi
    if [ "$DE" = "none" ]; then SERVER="none"; elif ! x11_supported; then SERVER="vnc"; else SERVER="x11"; fi
    RESOLUTION="1280x720"
    COLOR_MODE="light"
    APP_CHOICES=""
    INSTANCE_NAME=""
    SETUP_USER="user"
    SETUP_USER_B64="$(b64enc root)"
    SETUP_ROOT_B64="$(b64enc root)"
    TIMEZONE="$(setup_guess_timezone)"
    HOSTNAME="localhost"
    PSTYLE="minimal"
    if [ "$IS_LEGACY" = "1" ]; then NEED_VIRGL=0; else NEED_VIRGL=1; fi
    AUTOSTART_SERVER="$SERVER"
    DO_AUTOSTART=0
    DO_STORAGE=1
    DO_SSH=0
    DO_WIDGET=0
    SETUP_ANSWERED=1
    setup_summary
    setup_save
    install_linux
}

setup_guided() {
    echo ""
    echo "========================================="
    echo "   Guided Setup (Enter = default)        "
    echo "========================================="
    # 1. Distro
    local _dd _ddef
    if [ "$IS_LEGACY" = "1" ]; then _dd="Alpine"; _ddef=8; else _dd="Debian"; _ddef=2; fi
    while true; do
        if ! ui_select "Choose Linux Distribution (recommended here: $_dd)" "$_ddef" \
            "1|Ubuntu|24.04 LTS · APT · widest app support" \
            "2|Debian|stable · APT · rock solid" \
            "3|Kali Linux|APT · security tools" \
            "4|Fedora|DNF · bleeding edge" \
            "5|OpenSUSE|Zypper · enterprise" \
            "6|Void Linux|XBPS · lightweight, rolling" \
            "7|Arch Linux|Pacman · rolling (may be unstable on ARM64)" \
            "8|Alpine Linux|APK · musl · best for Android 5/6 + low RAM"; then
            show_menu
            return
        fi
        case "$UI_SELECTED" in
            1) DISTRO="ubuntu"; break ;;
            2) DISTRO="debian"; break ;;
            3) if [ "$IS_LEGACY" = "1" ]; then
                   ui_err "Kali has no legacy plugin (Android 5/6). Pick Debian (bullseye) or Alpine."
                   continue
               else DISTRO="kali"; break; fi ;;
            4) DISTRO="fedora"; break ;;
            5) DISTRO="opensuse"; break ;;
            6) DISTRO="void"; break ;;
            7) DISTRO="archlinux"; break ;;
            8) DISTRO="alpine"; break ;;
        esac
    done
    # 2. Desktop
    local _de _dedef
    if [ "$IS_LEGACY" = "1" ] || [ "$(setup_ram_mb)" -le 2048 ]; then _de="None (CLI only)"; _dedef=4; else _de="XFCE4"; _dedef=1; fi
    if ! ask_desktop_environment "$_de" "$_dedef"; then
        show_menu
        return
    fi
    if [ "$DISTRO" = "alpine" ] && [ "$DE" = "lxde" ]; then
        echo "[*] LXDE is not packaged for Alpine -> using XFCE4 instead."
        DE="xfce4"
    fi
    # 2b. Desktop wallpaper mode (GUI only; CLI installs skip wallpaper).
    COLOR_MODE="light"
    if [ "$DE" != "none" ]; then
        if ! ui_select "Default desktop mode (wallpaper)" "1" \
            "1|Light|bright default wallpaper" \
            "2|Dark|dark default wallpaper"; then
            show_menu
            return
        fi
        case "$UI_SELECTED" in
            2) COLOR_MODE="dark" ;;
            *) COLOR_MODE="light" ;;
        esac
    fi
    # 3. Display server + resolution + HW accel (GUI only)
    SERVER="none"
    RESOLUTION="1280x720"
    NEED_VIRGL=0
    AUTOSTART_SERVER=""
    if [ "$DE" != "none" ]; then
        if [ "$IS_LEGACY" = "1" ]; then
            echo "[*] Legacy Android: display server auto-set to VNC, HW acceleration off."
            SERVER="vnc"
        else
            local _srvdef=1
            [ "$DE" = "gnome" ] && _srvdef=2
            if ! ask_display_server "$_srvdef"; then
                show_menu
                return
            fi
            if ! ui_select "Hardware acceleration (VirGL GPU passthrough)?" "1" \
                "1|On|recommended for X11" \
                "2|Off|use if the screen is black or glitchy"; then
                show_menu
                return
            fi
            case "$UI_SELECTED" in
                1) NEED_VIRGL=1 ;;
                2) NEED_VIRGL=0 ;;
            esac
        fi
        if server_has_vnc; then
            if ! ui_select "Choose Display Resolution" "1" \
                "1|Auto / 720p|recommended, works on most phones" \
                "2|1080p|sharper, needs more RAM" \
                "3|Tablet (1440x1080)|large screen / tablet layout"; then
                show_menu
                return
            fi
            case "$UI_SELECTED" in
                1) RESOLUTION="1280x720" ;;
                2) RESOLUTION="1920x1080" ;;
                3) RESOLUTION="1440x1080" ;;
            esac
        fi
    fi
    # 4. Software
    if ! ui_multi "Extra software (space toggles, Enter when done)" \
        "1|Python|python3 + pip" \
        "2|Git|version control" \
        "3|Node.js|npm and JS tooling" \
        "4|curl|HTTP client" \
        "5|wget|download tool" \
        "6|Antigravity IDE|AI-first editor" \
        "7|Firefox|web browser" \
        "8|Chromium|web browser" \
        "9|LibreOffice|office suite" \
        "10|VLC|media player" \
        "11|GIMP|image editor" \
        "12|htop|process monitor" \
        "13|neofetch|system info" \
        "14|VS Code|Microsoft editor"; then
        show_menu
        return
    fi
    APP_CHOICES="$UI_MULTI"
    # 5. Instance name
    echo ""
    while true; do
        read -p "Instance name (blank = auto): " INSTANCE_NAME || true
        INSTANCE_NAME="$(echo "${INSTANCE_NAME:-}" | xargs)"
        if [ -z "$INSTANCE_NAME" ]; then break; fi
        if echo "$INSTANCE_NAME" | grep -Eq '^[A-Za-z0-9_.-]+$'; then break; fi
        echo "Use letters, digits, dot, underscore or dash."
    done
    # 6-8. Username + passwords
    echo ""
    while true; do
        read -p "Username [default: user]: " SETUP_USER || true
        SETUP_USER="${SETUP_USER:-user}"
        if echo "$SETUP_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$' && [ "${#SETUP_USER}" -le 32 ]; then break; fi
        echo "Lowercase letters, digits, _ or -, must start with a letter or _."
    done
    _pw=""
    setup_confirm_secret _pw "Password for $SETUP_USER [default: root]: " "root"
    [ "$_pw" = "root" ] && echo "[!] Using the default password 'root' - anyone with the phone can log in."
    SETUP_USER_B64="$(b64enc "$_pw")"
    _pw=""
    setup_confirm_secret _pw "Root password [default: root]: " "root"
    [ "$_pw" = "root" ] && echo "[!] Using the default root password 'root'."
    SETUP_ROOT_B64="$(b64enc "$_pw")"
    # VNC authentication only uses the first 8 characters of the password.
    if server_has_vnc && [ "${#_pw}" -gt 8 ]; then
        echo "[!] This password is ${#_pw} characters, but VNC only uses the first 8"
        echo "    ('${_pw:0:8}'). Type that shorter version in your VNC client."
    fi
    _pw=""
    echo "[*] This password doubles as the VNC and sudo-ritual password."
    # 9-10. Timezone + hostname
    echo ""
    _tzdef="$(setup_guess_timezone)"
    while true; do
        read -p "Timezone [default: $_tzdef]: " TIMEZONE || true
        TIMEZONE="${TIMEZONE:-$_tzdef}"
        # Real zones are Area/City (contain /); UTC is the only bare word.
        if [ "$TIMEZONE" = "UTC" ] || echo "$TIMEZONE" | grep -Eq '^[A-Za-z0-9_+.-]+/[A-Za-z0-9_+./-]+$'; then break; fi
        echo "Format like Area/City (e.g. Asia/Kathmandu) or UTC."
    done
    while true; do
        read -p "Hostname [default: localhost]: " HOSTNAME || true
        HOSTNAME="${HOSTNAME:-localhost}"
        if echo "$HOSTNAME" | grep -Eq '^[A-Za-z0-9-]+$' && [ "${#HOSTNAME}" -le 63 ]; then break; fi
        echo "Letters, digits and dashes only."
    done
    # 11. Prompt style
    if ! ui_select "Shell prompt style" "1" \
        "1|Minimal|clean colored user@host prompt (recommended)" \
        "2|Informative|adds time and last exit status"; then
        show_menu
        return
    fi
    case "$UI_SELECTED" in
        1) PSTYLE="minimal" ;;
        2) PSTYLE="informative" ;;
    esac
    # 12-14. Autostart / storage / SSH / widget
    if ui_confirm "Autostart at boot via Termux:Boot? (needs the Termux:Boot app)" n; then
        DO_AUTOSTART=1
        if [ "$SERVER" = "both" ]; then
            if ! ui_select "Autostart backend" "1" \
                "1|VNC|starts unattended; recommended" \
                "2|Termux:X11|starts the server and desktop; open the app later" \
                "3|None|do not start a desktop at boot"; then
                show_menu
                return
            fi
            case "$UI_SELECTED" in
                1) AUTOSTART_SERVER="vnc" ;;
                2) AUTOSTART_SERVER="x11" ;;
                3) AUTOSTART_SERVER="none" ;;
            esac
        else
            AUTOSTART_SERVER="$SERVER"
        fi
    else
        DO_AUTOSTART=0
        AUTOSTART_SERVER="none"
    fi
    if ui_confirm "Request Android storage access now? (Downloads/Documents)" y; then DO_STORAGE=1; else DO_STORAGE=0; fi
    if ui_confirm "Start an SSH server after install? (port 8022)" n; then DO_SSH=1; else DO_SSH=0; fi
    if ui_confirm "Show Termux:Widget shortcut instructions?" n; then DO_WIDGET=1; else DO_WIDGET=0; fi
    # Summary + save + go
    setup_summary
    UI_NO_CLEAR=1
    if ! ui_confirm "Proceed with installation?" y; then
        echo "Setup cancelled."
        show_menu
        return
    fi
    SETUP_ANSWERED=1
    setup_save
    install_linux
}

setup_load_saved() {
    # shellcheck disable=SC1090
    # Guarded: a corrupt file must fall back to guided setup, not abort
    # the whole script under set -e.
    source "$SETUP_CONF" 2>/dev/null || true
    if [ -z "${DISTRO:-}" ] || [ -z "${DE:-}" ]; then
        echo "[!] Saved config is incomplete, starting guided setup instead."
        setup_guided
        return
    fi
    : "${SERVER:=none}" "${RESOLUTION:=1280x720}" "${APP_CHOICES:=}"
    : "${COLOR_MODE:=light}"
    : "${INSTANCE_NAME:=}" "${SETUP_USER:=user}"
    : "${SETUP_USER_B64:=cm9vdA==}" "${SETUP_ROOT_B64:=cm9vdA==}"
    : "${TIMEZONE:=UTC}" "${HOSTNAME:=localhost}" "${PSTYLE:=minimal}"
    : "${NEED_VIRGL:=1}" "${DO_AUTOSTART:=0}" "${DO_STORAGE:=1}"
    : "${DO_SSH:=0}" "${DO_WIDGET:=0}"
    : "${AUTOSTART_SERVER:=}"
    if [ -z "$AUTOSTART_SERVER" ]; then
        case "$SERVER" in
            both) AUTOSTART_SERVER="vnc" ;;
            x11|vnc|none) AUTOSTART_SERVER="$SERVER" ;;
            *) AUTOSTART_SERVER="none" ;;
        esac
    fi
    SETUP_ANSWERED=1
    echo "[*] Loaded saved answers from $SETUP_CONF"
    setup_summary
    install_linux
}

# ------------------------------------------------------------
# Non-interactive entry points. Everything interactive stays available,
# but the script can now be introspected and scripted:
#   --help / --version / --list / --doctor / --yes (quick setup) / --debug
# ------------------------------------------------------------
# --debug keeps the generated guest script *and* tees an execution trace to a
# file, so a failure can be read afterwards instead of scrolled past.
lfa_enable_debug_log() {
    local log="$HOME/.config/linux-for-android/debug.log"
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 0
    exec 19>>"$log" 2>/dev/null || return 0
    export BASH_XTRACEFD=19
    PS4='+ \${BASH_SOURCE##*/}:\$LINENO: '
    set -x
    echo "[debug] $(date -Is) LFA_VERSION=$LFA_VERSION" >&19
}

lfa_usage() {
    cat <<HELP
Linux for Android Manager ${LFA_VERSION}

Usage: ./install_linux.sh [options]

  -h, --help       show this help and exit
  -V, --version    print the version and exit
      --list       list installed distributions and exit
      --doctor     repair the selected distribution and exit
      --yes        run quick setup (all defaults) without menus
      --debug      keep the guest setup script and write a debug log
      --diagnostics  write a redacted support bundle to $HOME and exit
HELP
}

# One cheap, cached check against the GitHub API. Never blocks: 3s timeout,
# result cached for a day, silent on any failure, disabled in tests/CI and
# by LFA_NO_UPDATE_CHECK=1.
lfa_check_update() {
    [ "${LFA_NO_UPDATE_CHECK:-0}" = "1" ] && return 0
    [ "${UI_TTY:-0}" = "1" ] || return 0
    local cache="$HOME/.config/linux-for-android/update-check" latest=""
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    if [ -s "$cache" ] && [ -n "$(find "$cache" -mtime -1 2>/dev/null)" ]; then
        latest="$(cat "$cache" 2>/dev/null)" || latest=""
    elif command -v curl >/dev/null 2>&1; then
        # The check is advisory: a timeout (curl 28), DNS failure, or a
        # missing release must not abort the installer through `set -e`.
        latest="$(curl -fsSL --max-time 3 \
            https://api.github.com/repos/pdev-labs/Linux-For-Android/releases/latest 2>/dev/null \
            | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)" || latest=""
        case "$latest" in ''|*[!0-9.]*) latest="" ;; esac
        if [ -n "$latest" ]; then
            printf '%s' "$latest" > "$cache" 2>/dev/null || true
        fi
    fi
    if [ -n "$latest" ] && [ "$latest" != "$LFA_VERSION" ]; then
        echo ""
        echo "[*] A newer release is available: v$latest (you are on v$LFA_VERSION)."
        echo "    Update with: git -C \"$LFA_DIR\" pull --ff-only"
    fi
    return 0
}

# A single file to attach to a bug report instead of "here is my terminal
# scrollback" (#50). Secrets are stripped; everything else is the state that
# actually matters when a desktop does not start.
lfa_diagnostics() {
    local out stage inst conf f
    out="$HOME/lfa-diagnostics-$(date +%Y%m%d-%H%M%S).tar.gz"
    stage="$(mktemp -d "$PREFIX/tmp/lfa-diag.XXXXXX")" || {
        echo "Could not create a temporary directory." >&2
        return 1
    }
    mkdir -p "$stage/logs" "$stage/launchers" "$stage/configs"

    {
        echo "Linux for Android diagnostics"
        echo "generated:   $(date -Is)"
        echo "version:     $LFA_VERSION"
        echo "device:      $(getprop ro.product.model 2>/dev/null || echo unknown)"
        echo "sdk:         $(getprop ro.build.version.sdk 2>/dev/null || echo unknown)"
        echo "arch:        $(uname -m)"
        echo "kernel:      $(uname -r)"
        echo "termux:      ${TERMUX_VERSION:-unknown}"
        echo "prefix:      $PREFIX"
        echo "report tail: $(tail -c 200 "$HOME/.config/linux-for-android/debug.log" 2>/dev/null | tr '\n' ' ')"
        echo ""
        echo "--- free space ---"
        df -Pk "$PREFIX" 2>/dev/null || echo unavailable
        echo ""
        echo "--- memory ---"
        free -m 2>/dev/null | head -3 || echo unavailable
        echo ""
        echo "--- installed distributions ---"
        pd_instances 2>/dev/null || echo none
        echo ""
        echo "--- running display processes ---"
        pgrep -af 'termux-x11|Xvnc|gnome-shell|xfce4-session|mate-session|lxsession' 2>/dev/null || echo none
        echo ""
        echo "--- display sockets ---"
        ls -l "$PREFIX/tmp/.X11-unix" 2>/dev/null || echo none
    } > "$stage/report.txt" 2>&1

    # Manager config, with anything secret removed before it is written.
    while IFS= read -r inst; do
        [ -n "$inst" ] || continue
        conf="$(pd_conf "$inst" 2>/dev/null)"
        if [ -f "$conf" ]; then
            sed -E 's/^([A-Z_]*(PASS|PASSWD|SECRET|TOKEN|KEY)[A-Z_]*)="?.*"?$/\1="REDACTED"/' \
                "$conf" > "$stage/configs/$inst.conf" 2>/dev/null || true
        fi
    done < <(pd_instances 2>/dev/null)

    for f in start-linux stop-linux terminal-linux lfa-lib.sh lfa linux switch-linux autostart-linux; do
        [ -f "$PREFIX/bin/$f" ] && cp "$PREFIX/bin/$f" "$stage/launchers/" 2>/dev/null || true
    done

    for f in "$HOME"/start-linux-session.log "$HOME"/.vnc/*.log "$PREFIX"/tmp/lfa-*.log; do
        [ -f "$f" ] && cp "$f" "$stage/logs/" 2>/dev/null || true
    done

    if tar -czf "$out" -C "$stage" . 2>/dev/null; then
        rm -rf "$stage" 2>/dev/null || true
        chmod 600 "$out" 2>/dev/null || true
        echo "Diagnostics written to: $out"
        echo "Passwords and tokens are already removed; attach this file to a bug report."
        return 0
    fi
    rm -rf "$stage" 2>/dev/null || true
    echo "Could not create $out" >&2
    return 1
}

lfa_cli_usage() {
    cat <<'HELP'
Linux for Android - command line

Usage: lfa <command> [options]

  install       install a distro without menus
  list          list installed distributions
  status        show backend and autostart state
  start         start the desktop
  shell         open a terminal
  stop          stop the desktop
  switch        change backend and optionally remove old packages
  autostart     set the boot backend
  update        update a distro
  fix           apply latest fixes to an existing distro
  doctor        repair a distro
  backup        create a backup
  restore       restore a backup
  remove        delete a distro
  compat        inspect or enable compatibility shims
  android       inspect or enable the Termux:API bridge
  usb           real USB devices: list, scan, attach, tty, flash
  storage       Android shared storage: status, repair, run helpers
  appimage      extract and run an AppImage (alias: app)
  run           run an AppImage once without installing it
  diagnostics   write a support bundle
  notice        show, hide, or query the start-linux notice
  version       print the version
  help          show this help

Global short option:
  -i, --instance NAME

Install options:
  -d, --distro NAME       ubuntu, debian, kali, fedora, opensuse,
                          void, archlinux, alpine
      --desktop NAME      xfce4, lxde, mate, gnome, none
  -b, --backend NAME      x11, vnc, both, none
      --autostart NAME    x11, vnc, none
      --user NAME         desktop username
      --hostname NAME     guest hostname
      --timezone AREA/CITY
      --software LIST     comma-separated apps (python,git,node,curl,wget,
                          antigravity,firefox,chromium,libreoffice,vlc,gimp,
                          htop,neofetch,vscode)

Switch options:
      --remove-old        remove the packages of the backend being left
      --keep-packages     keep them (default)
      --force             remove shared Termux:X11 despite another distro

Compatibility options:
  lfa compat list|status|explain ID|enable ID|disable ID
  lfa android status|install|permissions|test|refresh|
              enable CAP|disable CAP|bridge CAP|pump

Examples:
  lfa install --distro ubuntu --desktop xfce4 --backend both -i ubuntu
  lfa start -i ubuntu --vnc
  lfa shell -i ubuntu --user
  lfa switch x11 -i ubuntu --remove-old
  lfa autostart vnc -i ubuntu
  lfa compat list
  lfa compat enable upower -i ubuntu
  lfa android test
  lfa usb status
  lfa usb scan
  lfa usb exec 001/002 -- lfa-usb desc
  lfa appimage add ~/Foo.AppImage
  lfa appimage list
  lfa appimage run Foo
  lfa run ~/Foo.AppImage
  lfa notice off
HELP
}

lfa_cli_notice_write() {  # $1 = on|off
    local _val="${1:-on}"
    case "$_val" in on) _val=1 ;; off) _val=0 ;; *) echo "Usage: lfa notice on|off|status" >&2; return 2 ;; esac
    mkdir -p "$(dirname "$LFA_PREFS")" 2>/dev/null || true
    if grep -q '^START_NOTICE=' "$LFA_PREFS" 2>/dev/null; then
        sed -i "s|^START_NOTICE=.*|START_NOTICE=\"$_val\"|" "$LFA_PREFS"
    else
        printf 'START_NOTICE="%s"\n' "$_val" >> "$LFA_PREFS"
    fi
}

# ------------------------------------------------------------
# Compatibility layer (Linux software that expects missing services)
# and Android data provider (Termux:API).
#
# These are deliberately separate:
#   lfa compat  shims Linux-side components (systemctl, logind, ...)
#   lfa android exposes real Android data (battery, location, ...)
#
# Neither one can create kernel facilities. Anything that needs the kernel
# (Docker, KVM, TUN/TAP, CUDA, modules) is reported as unsupported instead
# of being faked.
# ------------------------------------------------------------
LFA_COMPAT_CONF="$HOME/.config/linux-for-android/compat.conf"
LFA_ANDROID_CONF="$HOME/.config/linux-for-android/android.conf"

lfa_list_manifest() {
    cat <<'EOF'
systemctl|systemctl|supervisor|partial|medium|Map units to a tiny LFA supervisor
logind|loginctl|builtin|partial|Low|CLI session queries; no real D-Bus logind
upower|upower|android+builtin|real-data when Termux:API is installed|Low|Battery and AC state
snap|snap|apt/tarball map|partial|medium|Map known snaps to distro packages
bwrap|bwrap|builtin|partial|medium|Run sandboxed commands unsandboxed
vulkan|Vulkan|lavapipe|software-only|Low|CPU Vulkan fallback
opencl|OpenCL|pocl|software-only|Low|CPU OpenCL fallback
docker|Docker|none|unsupported|high|Needs namespaces, cgroups and a daemon
podman|Podman|none|unsupported|high|Needs namespaces and cgroups
flatpak|Flatpak|none|unsupported|high|Needs user namespaces and bubblewrap
tun|TUN/TAP VPN|none|unsupported|high|Android does not expose /dev/net/tun
iptables|iptables/nftables|none|unsupported|high|No netfilter control in Termux
cuda|CUDA|none|unsupported|high|No CUDA runtime or GPU device for proot
rocm|ROCm|none|unsupported|high|No ROCm runtime on Android
kvm|KVM/emulators|none|unsupported|high|No /dev/kvm access
modules|Kernel modules|none|unsupported|high|Termux cannot load modules
EOF
}

lfa_manifest_field() {  # $1 = id, $2 = field number (1-based)
    local _id="$1" _n="$2" _i _a _b _c _d _e _f
    # Use a read loop, not `manifest | awk`: under `set -o pipefail`,
    # grep -q or an early awk exit turns a successful lookup into SIGPIPE.
    while IFS='|' read -r _i _a _b _c _d _e _f; do
        [ "$_i" = "$_id" ] || continue
        case "$_n" in
            1) printf '%s\n' "$_i" ;;
            2) printf '%s\n' "$_a" ;;
            3) printf '%s\n' "$_b" ;;
            4) printf '%s\n' "$_c" ;;
            5) printf '%s\n' "$_d" ;;
            6) printf '%s\n' "$_e" ;;
            7) printf '%s\n' "$_f" ;;
            *) return 1 ;;
        esac
        return 0
    done < <(lfa_list_manifest)
    return 1
}

lfa_compat_is_shimmable() {
    case "$1" in systemctl|logind|upower|snap|bwrap|vulkan|opencl) return 0 ;; esac
    return 1
}

lfa_compat_state_get() {  # $1 = id
    [ -r "$LFA_COMPAT_CONF" ] || return 1
    sed -n "s/^$1=\"\\{0,1\\}\\([01]\\)\"\\{0,1\\}$/\\1/p" "$LFA_COMPAT_CONF" 2>/dev/null | tail -n1
}

lfa_compat_state_set() {  # $1 = id, $2 = 0|1
    local _id="$1" _v="$2"
    mkdir -p "$(dirname "$LFA_COMPAT_CONF")" 2>/dev/null || true
    if grep -q "^$_id=" "$LFA_COMPAT_CONF" 2>/dev/null; then
        sed -i "s|^$_id=.*|$_id=\"$_v\"|" "$LFA_COMPAT_CONF"
    else
        printf '%s="%s"\n' "$_id" "$_v" >> "$LFA_COMPAT_CONF"
    fi
}

lfa_android_state_get() {  # $1 = capability
    [ -r "$LFA_ANDROID_CONF" ] || return 1
    sed -n "s/^$1=\"\\{0,1\\}\\([01]\\)\"\\{0,1\\}$/\\1/p" "$LFA_ANDROID_CONF" 2>/dev/null | tail -n1
}

lfa_android_state_set() {  # $1 = capability, $2 = 0|1
    local _id="$1" _v="$2"
    mkdir -p "$(dirname "$LFA_ANDROID_CONF")" 2>/dev/null || true
    if grep -q "^$_id=" "$LFA_ANDROID_CONF" 2>/dev/null; then
        sed -i "s|^$_id=.*|$_id=\"$_v\"|" "$LFA_ANDROID_CONF"
    else
        printf '%s="%s"\n' "$_id" "$_v" >> "$LFA_ANDROID_CONF"
    fi
}

# Return the rootfs to apply shims into. An explicit -i wins; otherwise a
# single installed distro is used. With none or several, only the manager
# state is written and the user is told how to apply it later.
lfa_shim_rootfs() {
    local _inst="${CLI_INSTANCE:-}" _n=0 _one="" _d
    if [ -z "$_inst" ]; then
        while IFS= read -r _d; do
            [ -n "$_d" ] || continue
            _n=$((_n + 1)); _one="$_d"
        done < <(pd_instances 2>/dev/null)
        [ "$_n" = "1" ] && _inst="$_one"
    fi
    if [ -n "$_inst" ]; then
        pd_instance_exists "$_inst" || return 1
        printf '%s\n' "$(pd_rootfs "$_inst")"
    fi
}

lfa_shim_write() {  # $1 = rootfs, $2 = relative path, rest via stdin
    local _root="$1" _rel="$2" _dest
    _dest="$_root/$_rel"
    mkdir -p "$(dirname "$_dest")" 2>/dev/null || return 1
    cat > "$_dest" || return 1
    chmod 755 "$_dest" 2>/dev/null || true
}

lfa_compat_apply_shims() {  # $1 = id
    local _id="$1" _root="" _inst="${CLI_INSTANCE:-}"
    _root="$(lfa_shim_rootfs 2>/dev/null)" || _root=""
    if [ -z "$_root" ]; then
        echo "[i] Saved the preference. Install or choose a distro, then run:"
        echo "      lfa compat enable $_id -i NAME"
        return 0
    fi
    case "$_id" in
        systemctl)
            lfa_shim_write "$_root" "usr/local/bin/systemctl" <<'SHIM'
#!/bin/sh
# LFA compatibility shim: a tiny supervisor, NOT systemd.
# Units are mapped in /etc/lfa/systemd-map.conf as NAME=/path/to/command.
MAP=/etc/lfa/systemd-map.conf
STATE=/run/lfa-systemctl
case "$1" in
  daemon-reload|daemon-reexec) exit 0 ;;
  is-system-running) echo "degraded"; exit 0 ;;
  list-units|list-unit-files)
    [ -f "$MAP" ] || { echo "No units are mapped by LFA."; exit 0; }
    while IFS='=' read -r _u _c; do
      case "$_u" in ''|\#*) continue ;; esac
      if [ -f "$STATE/$_u.pid" ] && kill -0 "$(cat "$STATE/$_u.pid" 2>/dev/null)" 2>/dev/null; then
        echo "$_u.service loaded active running $_c"
      else
        echo "$_u.service loaded inactive dead $_c"
      fi
    done < "$MAP"
    exit 0 ;;
esac
ACTION="$1"; UNIT="$2"
case "$UNIT" in *.*) UNIT="${UNIT%.service}" ;; esac
CMD=""
[ -f "$MAP" ] && CMD="$(awk -F= -v u="$UNIT" '$1==u {print substr($0, index($0,"=")+1); exit}' "$MAP" 2>/dev/null)"
have_unit() { [ -n "$CMD" ]; }
mkdir -p "$STATE" 2>/dev/null || true
case "$ACTION" in
  start|restart)
    have_unit || { echo "Unit $UNIT is not provided by the LFA compatibility layer." >&2; echo "Add it to $MAP first." >&2; exit 5; }
    [ "$ACTION" = restart ] && 'systemctl' stop "$UNIT" >/dev/null 2>&1 || true
    if [ -f "$STATE/$UNIT.pid" ] && kill -0 "$(cat "$STATE/$UNIT.pid" 2>/dev/null)" 2>/dev/null; then
      echo "Unit $UNIT is already running."; exit 0
    fi
    setsid sh -c "$CMD" >"/var/log/lfa-$UNIT.log" 2>&1 &
    echo $! > "$STATE/$UNIT.pid"
    echo "Started $UNIT (LFA supervisor, pid $(cat "$STATE/$UNIT.pid"))."
    ;;
  stop)
    have_unit || { echo "Unit $UNIT is not provided by the LFA compatibility layer." >&2; exit 5; }
    if [ -f "$STATE/$UNIT.pid" ]; then kill "$(cat "$STATE/$UNIT.pid" 2>/dev/null)" 2>/dev/null || true; rm -f "$STATE/$UNIT.pid"; fi
    echo "Stopped $UNIT."
    ;;
  is-active)
    have_unit || { echo "inactive"; exit 3; }
    if [ -f "$STATE/$UNIT.pid" ] && kill -0 "$(cat "$STATE/$UNIT.pid" 2>/dev/null)" 2>/dev/null; then echo active; exit 0; fi
    echo inactive; exit 3 ;;
  status)
    have_unit || { echo "Unit $UNIT is not provided by the LFA compatibility layer." >&2; exit 4; }
    if [ -f "$STATE/$UNIT.pid" ] && kill -0 "$(cat "$STATE/$UNIT.pid" 2>/dev/null)" 2>/dev/null; then
      echo "$UNIT.service - LFA mapped service"; echo "   Active: active (running)"; echo "   Command: $CMD"
    else
      echo "$UNIT.service - LFA mapped service"; echo "   Active: inactive (dead)"; echo "   Command: $CMD"
    fi ;;
  enable|disable)
    have_unit || { echo "Unit $UNIT is not provided by the LFA compatibility layer." >&2; exit 5; }
    echo "$ACTION is recorded by the map; LFA does not create boot symlinks." ;;
  *)
    echo "systemctl (LFA shim): unsupported action '$ACTION'." >&2
    echo "Supported: start stop restart status is-active list-units daemon-reload enable disable" >&2
    exit 2 ;;
esac
SHIM
            mkdir -p "$_root/etc/lfa"
            if [ ! -f "$_root/etc/lfa/systemd-map.conf" ]; then
                cat > "$_root/etc/lfa/systemd-map.conf" <<'MAP'
# LFA systemctl compatibility map.
# One NAME=COMMAND per line. Only units listed here exist.
# Examples:
# dbus=/usr/bin/dbus-daemon --system --nofork
# ssh=/usr/sbin/sshd -D
MAP
            fi
            ;;
        logind)
            lfa_shim_write "$_root" "usr/local/bin/loginctl" <<'SHIM'
#!/bin/sh
# LFA compatibility shim: loginctl CLI only (no D-Bus logind).
case "$1" in
  list-sessions) echo " 1 ${USER:-user} seat0 tty1" ;;
  show-session)
    echo "Id=1"; echo "User=${USER:-user}"; echo "Name=${USER:-user}"
    echo "State=active"; echo "Type=x11"; echo "Remote=no"; echo "Seat=seat0" ;;
  list-seats) echo "seat0" ;;
  show-seat) echo "Id=seat0"; echo "ActiveSession=1" ;;
  lock-session|terminate-session|kill-session)
    echo "loginctl (LFA shim): $1 is not supported without systemd/logind." >&2; exit 1 ;;
  *) echo "loginctl (LFA shim): unsupported action '$1'." >&2; exit 2 ;;
esac
SHIM
            ;;
        upower)
            lfa_shim_write "$_root" "usr/local/bin/upower" <<'SHIM'
#!/bin/sh
# LFA compatibility shim. Reads the Termux:API battery bridge when present.
ENVF=/tmp/lfa-android-battery.env
_show() {
  echo "  native-path:          /sys/class/power_supply/battery"
  echo "  power supply:         yes"
  echo "  updated:              $(date -u '+%a %d %b %Y %H:%M:%S UTC')"
  if [ -r "$ENVF" ]; then
    # shellcheck disable=SC1090
    . "$ENVF"
    echo "  present:              yes"
    echo "  state:                ${BATTERY_STATE:-unknown}"
    echo "  percentage:           ${BATTERY_PERCENT:-unknown}%"
    echo "  time to empty:        ${BATTERY_TIME_EMPTY:-unknown}"
    echo "  time to full:         ${BATTERY_TIME_FULL:-unknown}"
    echo "  source:               Termux:API"
  else
    echo "  present:              unknown"
    echo "  state:                unknown"
    echo "  percentage:           unknown"
    echo "  source:               no Termux:API bridge"
  fi
}
case "$1" in
  -e|--enumerate) echo "/org/freedesktop/UPower/devices/battery_BAT0" ;;
  -d|--dump) echo "Device: /org/freedesktop/UPower/devices/battery_BAT0"; _show ;;
  -i|--show-info) _show ;;
  -v|--version) echo "UPower client version 1.90.8 (LFA shim)" ;;
  *) _show ;;
esac
SHIM
            ;;
        snap)
            lfa_shim_write "$_root" "usr/local/bin/snap" <<'SHIM'
#!/bin/sh
# LFA compatibility shim: map a few known snaps to distro packages.
# This is not snapd and does not provide confinement.
PKG=""
case "$2" in
  firefox) PKG="firefox" ;;
  chromium) PKG="chromium" ;;
  code|code-insiders) PKG="code" ;;
  vlc) PKG="vlc" ;;
  gimp) PKG="gimp" ;;
  libreoffice) PKG="libreoffice" ;;
esac
case "$1" in
  list)
    echo "Name       Version  Publisher  Notes"
    echo "firefox    mapped   lfa        apt/tarball fallback"
    echo "chromium   mapped   lfa        apt/tarball fallback"
    echo "vlc        mapped   lfa        apt/tarball fallback"
    echo "gimp       mapped   lfa        apt/tarball fallback"
    ;;
  install)
    [ -n "$PKG" ] || { echo "snap (LFA shim): no fallback mapping for '${2:-}'." >&2; echo "Use your distro package manager instead." >&2; exit 1; }
    if command -v apt-get >/dev/null 2>&1; then exec apt-get install -y "$PKG"
    elif command -v dnf >/dev/null 2>&1; then exec dnf install -y "$PKG"
    elif command -v pacman >/dev/null 2>&1; then exec pacman -S --noconfirm "$PKG"
    elif command -v zypper >/dev/null 2>&1; then exec zypper install -y "$PKG"
    elif command -v apk >/dev/null 2>&1; then exec apk add "$PKG"
    else echo "snap (LFA shim): no supported package manager." >&2; exit 1; fi
    ;;
  remove) echo "snap (LFA shim): use your distro package manager to remove $PKG." ;;
  version) echo "snap 0 (LFA compatibility shim, not snapd)" ;;
  *) echo "snap (LFA shim): supported: list, install NAME, remove NAME, version" >&2; exit 2 ;;
esac
SHIM
            ;;
        bwrap)
            lfa_shim_write "$_root" "usr/local/bin/bwrap" <<'SHIM'
#!/bin/sh
# LFA compatibility shim: run the command after the last '--' without a
# sandbox. Used only where an application has an unsandboxed fallback.
args=""
seen=0
for a in "$@"; do
  if [ "$seen" = "1" ]; then args="$args $(printf '%s' "$a" | sed "s/'/'\\\\''/g")"; fi
  [ "$a" = "--" ] && seen=1
done
if [ "$seen" != "1" ]; then echo "bwrap (LFA shim): no command after --." >&2; exit 2; fi
echo "bwrap (LFA shim): running without a sandbox." >&2
eval "exec $args"
SHIM
            ;;
        vulkan|opencl)
            lfa_compat_install_pkgs "$_id" || true
            ;;
    esac
    echo "[*] Enabled LFA compatibility shim '$_id' for $(basename "$(dirname "$_root")")."
}

lfa_compat_install_pkgs() {  # $1 = vulkan|opencl
    local _kind="$1" _conf _distro="" _root _inst="" _n=0 _one="" _d
    _root="$(lfa_shim_rootfs 2>/dev/null)" || _root=""
    [ -n "$_root" ] || { echo "[i] No distro selected; install the packages inside it later."; return 0; }
    if [ -n "${CLI_INSTANCE:-}" ]; then
        _inst="$CLI_INSTANCE"
    else
        while IFS= read -r _d; do
            [ -n "$_d" ] || continue
            _n=$((_n + 1)); _one="$_d"
        done < <(pd_instances 2>/dev/null)
        [ "$_n" = "1" ] && _inst="$_one"
    fi
    [ -n "$_inst" ] || { echo "[i] No distro instance selected; nothing to install into."; return 0; }
    _conf="$(pd_conf "$_inst" 2>/dev/null)"
    # shellcheck disable=SC1090
    [ -f "$_conf" ] && . "$_conf" 2>/dev/null || true
    INSTANCE_NAME="$_inst"
    _distro="${DISTRO:-}"
    case "$_distro" in
        ubuntu|debian|kali)
            if [ "$_kind" = "vulkan" ]; then
                guest_install_pkgs mesa-vulkan-drivers vulkan-tools || return 1
            else
                guest_install_pkgs pocl-opencl-icd clinfo || return 1
            fi ;;
        fedora)
            if [ "$_kind" = "vulkan" ]; then guest_install_pkgs mesa-vulkan-drivers vulkan-tools || return 1
            else guest_install_pkgs pocl clinfo || return 1; fi ;;
        archlinux)
            if [ "$_kind" = "vulkan" ]; then guest_install_pkgs vulkan-swrast vulkan-tools || return 1
            else guest_install_pkgs pocl clinfo || return 1; fi ;;
        alpine)
            if [ "$_kind" = "vulkan" ]; then
                guest_install_pkgs mesa-vulkan-swrast vulkan-loader vulkan-tools || return 1
            else
                echo "[i] Alpine has no POCL package for this architecture." >&2
                echo "    Install an OpenCL ICD manually, or use the CPU Vulkan path (lavapipe)." >&2
                return 2
            fi ;;
        *)
            echo "[i] Install the software $([ "$_kind" = vulkan ] && echo 'Vulkan (lavapipe)' || echo 'OpenCL (POCL)') packages with your distro package manager." >&2
            return 2 ;;
    esac
}

lfa_compat_remove_shims() {  # $1 = id
    local _id="$1" _root _f _rel
    _root="$(lfa_shim_rootfs 2>/dev/null)" || _root=""
    [ -n "$_root" ] || return 0
    case "$_id" in
        systemctl) _rel="usr/local/bin/systemctl" ;;
        logind) _rel="usr/local/bin/loginctl" ;;
        upower) _rel="usr/local/bin/upower" ;;
        snap) _rel="usr/local/bin/snap" ;;
        bwrap) _rel="usr/local/bin/bwrap" ;;
        *) return 0 ;;
    esac
    _f="$_root/$_rel"
    if [ -f "$_f" ] && grep -q 'LFA compatibility shim' "$_f" 2>/dev/null; then
        rm -f "$_f"
        echo "[*] Removed $_rel from $(basename "$(dirname "$_root")")."
    fi
}

lfa_cli_compat() {
    local _sub="${1:-list}"; [ $# -gt 0 ] && shift || true
    local _inst="" _id="" _v
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            -h|--help) _sub="help"; shift ;;
            *) _id="$1"; shift ;;
        esac
    done
    CLI_INSTANCE="$_inst"
    case "$_sub" in
        list|help)
            echo "LFA compatibility layer"
            echo ""
            printf '  %-10s %-18s %-24s %-12s %s\n' "ID" "SOURCE" "QUALITY" "RISK" "DESCRIPTION"
            lfa_list_manifest | while IFS='|' read -r _i _n _s _q _r _d; do
                printf '  %-10s %-18s %-24s %-12s %s\n' "$_i" "$_s" "$_q" "$_r" "$_d"
            done
            echo ""
            echo "Enable a shim with: lfa compat enable ID [-i NAME]"
            echo "Explain one with:   lfa compat explain ID"
            ;;
        status)
            local _root
            _root="$(lfa_shim_rootfs 2>/dev/null || true)"
            echo "Compatibility state${_root:+ (target: $(basename "$(dirname "$_root")"))}"
            printf '  %-12s %-8s %s\n' "ID" "STATE" "QUALITY"
            lfa_list_manifest | while IFS='|' read -r _i _n _s _q _r _d; do
                [ "$_i" = "systemctl" ] || [ "$_i" = "logind" ] || [ "$_i" = "upower" ] || \
                [ "$_i" = "snap" ] || [ "$_i" = "bwrap" ] || [ "$_i" = "vulkan" ] || \
                [ "$_i" = "opencl" ] || continue
                _v="$(lfa_compat_state_get "$_i" 2>/dev/null || echo 0)"
                [ "$_v" = "1" ] && _v="enabled" || _v="disabled"
                printf '  %-12s %-8s %s\n' "$_i" "$_v" "$_q"
            done
            echo ""
            echo "Unsupported by design: docker, podman, flatpak, tun, iptables, cuda, rocm, kvm, modules."
            echo "These need kernel features Termux cannot provide, so LFA does not fake them."
            ;;
        explain)
            [ -n "$_id" ] || { echo "Usage: lfa compat explain ID" >&2; return 2; }
            local _name _src _q _r _d
            _name="$(lfa_manifest_field "$_id" 2)"; _src="$(lfa_manifest_field "$_id" 3)"
            _q="$(lfa_manifest_field "$_id" 4)"; _r="$(lfa_manifest_field "$_id" 5)"; _d="$(lfa_manifest_field "$_id" 6)"
            [ -n "$_name" ] || { echo "No compatibility entry named '$_id'." >&2; return 1; }
            echo "$_id - $_name"
            echo "  source:  $_src"
            echo "  quality: $_q"
            echo "  risk:    $_r"
            echo "  summary: $_d"
            case "$_id" in
                systemctl) echo "  limit:   no PID 1, cgroups, sockets, timers or dependency graph." ;;
                logind) echo "  limit:   CLI answers only; applications that talk to org.freedesktop.login1 over D-Bus still fail." ;;
                upower) echo "  limit:   real battery data only when Termux:API is installed and 'lfa android enable battery' has run." ;;
                snap) echo "  limit:   only the mapped names work; unknown snaps fail clearly. No confinement." ;;
                bwrap) echo "  limit:   removes the sandbox. Use only for apps with an unsandboxed fallback." ;;
                vulkan) echo "  limit:   CPU rendering through Mesa lavapipe, not the phone GPU." ;;
                opencl) echo "  limit:   CPU execution through POCL, not the phone GPU." ;;
                docker|podman) echo "  limit:   no namespaces, cgroups or daemon; use a proot container instead." ;;
                flatpak) echo "  limit:   no user namespaces or bubblewrap sandbox." ;;
                tun) echo "  limit:   /dev/net/tun is not exposed to Termux; userspace proxies only." ;;
                iptables) echo "  limit:   no CAP_NET_ADMIN/netfilter; rules would be a dangerous no-op." ;;
                cuda|rocm) echo "  limit:   no runtime or GPU device passthrough; CPU fallbacks only." ;;
                kvm) echo "  limit:   /dev/kvm is not available to apps." ;;
                modules) echo "  limit:   loading kernel modules requires root and a matching kernel." ;;
            esac
            if lfa_compat_is_shimmable "$_id"; then
                echo ""
                echo "Enable with: lfa compat enable $_id"
            else
                echo ""
                echo "This capability is not shimmable. LFA will not pretend it works."
            fi
            ;;
        enable)
            [ -n "$_id" ] || { echo "Usage: lfa compat enable ID [-i NAME]" >&2; return 2; }
            lfa_compat_is_shimmable "$_id" || {
                echo "[!] '$_id' cannot be shimmed safely." >&2
                echo "    It needs a kernel or security boundary that Termux does not have." >&2
                return 1
            }
            local _entry_name
            _entry_name="$(lfa_manifest_field "$_id" 2)"
            [ -n "$_entry_name" ] || { echo "No compatibility entry named '$_id'." >&2; return 1; }
            if [ "$_id" = "vulkan" ] || [ "$_id" = "opencl" ]; then
                if ! lfa_compat_install_pkgs "$_id"; then
                    lfa_compat_state_set "$_id" 0
                    echo "[!] '$_id' was not enabled: the software packages could not be installed." >&2
                    return 1
                fi
                lfa_compat_state_set "$_id" 1
                echo "[*] Enabled LFA compatibility shim '$_id'."
            else
                lfa_compat_state_set "$_id" 1
                lfa_compat_apply_shims "$_id"
            fi
            ;;
        disable)
            [ -n "$_id" ] || { echo "Usage: lfa compat disable ID [-i NAME]" >&2; return 2; }
            lfa_compat_state_set "$_id" 0
            lfa_compat_remove_shims "$_id"
            echo "[*] Disabled LFA compatibility shim '$_id'."
            ;;
        *) echo "Unknown compat command: $_sub" >&2; echo "Usage: lfa compat list|status|explain ID|enable ID|disable ID" >&2; return 2 ;;
    esac
}

lfa_android_pm_has() {  # $1 = package name
    local _pkgs=""
    command -v pm >/dev/null 2>&1 || return 1
    if command -v timeout >/dev/null 2>&1; then
        _pkgs="$(timeout 5 pm list packages 2>/dev/null || true)"
    else
        _pkgs="$(pm list packages 2>/dev/null || true)"
    fi
    case "$_pkgs" in *"$1"*) return 0 ;; esac
    return 1
}

# A Termux:API helper can block forever when the app was killed or a
# permission dialog is waiting. Never let a bridge probe hang the CLI.
lfa_android_timeout() {  # $1 = seconds, rest = command
    local _secs="$1"
    shift
    # 0 means "no limit". Do not wrap it in timeout: GNU timeout puts the
    # child in its own process group, so an interactive guest shell would
    # become a background job and lose the terminal (reads stop with
    # SIGTTIN, or fail with EIO).
    if [ "$_secs" = "0" ]; then
        "$@"
        return $?
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout "$_secs" "$@"
    else
        "$@"
    fi
}

# The Termux:API app can be asleep when the first broadcast arrives. One
# short probe plus one longer retry separates "waking up" from "unavailable"
# without letting a dead app hang the CLI.
lfa_android_battery_json() {
    local _out
    _out="$(lfa_android_timeout 8 termux-battery-status 2>/dev/null || true)"
    if [ -z "$_out" ]; then
        sleep 1
        _out="$(lfa_android_timeout 12 termux-battery-status 2>/dev/null || true)"
    fi
    printf '%s' "$_out"
}

lfa_android_cmd() {
    local _sub="${1:-status}" _what="" _inst=""
    [ $# -gt 0 ] && shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            -h|--help) _sub="help"; shift ;;
            *) _what="$1"; shift ;;
        esac
    done
    CLI_INSTANCE="$_inst"
    local _bridge="$PREFIX/tmp"
    case "$_sub" in
        help)
            cat <<'HELP'
Usage: lfa android COMMAND

  status                 show Termux:API and bridge state
  install                install the termux-api client package
  permissions            list the Android permissions to grant
  test                   run read-only probes (battery, location, clipboard)
  refresh                write fresh bridge files into $PREFIX/tmp
  enable CAP             enable battery, location, clipboard or notifications
  disable CAP            disable a capability
  bridge CAP             enable CAP and refresh its data now
  pump                   deliver queued guest notifications

The guest sees bridge files under /tmp because proot uses --shared-tmp.
HELP
            ;;
        status)
            local _pkg=0 _app=0 _cap _v
            command -v termux-battery-status >/dev/null 2>&1 && _pkg=1
            lfa_android_pm_has 'com.termux.api' && _app=1
            echo "Android bridge"
            echo "  termux-api package: $([ "$_pkg" = 1 ] && echo installed || echo missing)"
            echo "  Termux:API app:     $([ "$_app" = 1 ] && echo installed || echo not detected)"
            echo "  bridge directory:   $_bridge"
            echo ""
            printf '  %-16s %-8s %s\n' "CAPABILITY" "STATE" "SOURCE"
            for _cap in battery location clipboard notifications; do
                _v="$(lfa_android_state_get "$_cap" 2>/dev/null || echo 0)"
                [ "$_v" = "1" ] && _v="enabled" || _v="disabled"
                printf '  %-16s %-8s %s\n' "$_cap" "$_v" "Termux:API"
            done
            echo ""
            echo "Kernel/device passthrough (Docker, TUN/TAP, CUDA, /dev nodes) is not"
            echo "provided by Termux:API. See docs/INCOMPATIBLE.md."
            ;;
        install)
            if ! command -v pkg >/dev/null 2>&1; then
                echo "[!] pkg not found; run this inside Termux." >&2
                return 1
            fi
            pkg install -y termux-api || return 1
            echo ""
            echo "Now install the Termux:API app from F-Droid, then run:"
            echo "  lfa android permissions"
            ;;
        permissions)
            cat <<'HELP'
Grant these in Android Settings > Apps > Termux:API > Permissions:
  - Location (for lfa android enable location)
  - Notifications (for lfa android enable notifications)
  - Camera / Microphone only if you use those bridges
Termux itself also needs the matching Android permissions.
HELP
            ;;
        refresh)
            command -v termux-battery-status >/dev/null 2>&1 || {
                echo "[!] termux-api is not installed. Run: lfa android install" >&2
                return 1
            }
            mkdir -p "$_bridge" 2>/dev/null || true
            local _json _pct _state
            _json="$(lfa_android_battery_json)"
            if [ -n "$_json" ]; then
                printf '%s\n' "$_json" > "$_bridge/lfa-android-battery.json"
                _pct="$(printf '%s' "$_json" | sed -n 's/.*"percentage"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
                _state="$(printf '%s' "$_json" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
                {
                    printf 'BATTERY_PERCENT=%s\n' "${_pct:-unknown}"
                    printf 'BATTERY_STATE=%s\n' "${_state:-unknown}"
                    printf 'BATTERY_TIME_EMPTY=unknown\nBATTERY_TIME_FULL=unknown\n'
                } > "$_bridge/lfa-android-battery.env"
                echo "[*] battery: ${_pct:-unknown}% ${_state:-unknown}"
            else
                echo "[!] Battery probe returned nothing (permission, app missing, or timed out)." >&2
            fi
            # Only probe capabilities the user turned on. Location and
            # clipboard can each wait on a permission prompt.
            if [ "$(lfa_android_state_get location 2>/dev/null || echo 0)" = "1" ] && \
               command -v termux-location >/dev/null 2>&1; then
                lfa_android_timeout 12 termux-location -p network \
                    > "$_bridge/lfa-android-location.json" 2>/dev/null || true
                if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
                    lfa_android_timeout 5 termux-wifi-connectioninfo \
                        > "$_bridge/lfa-android-wifi.json" 2>/dev/null || true
                fi
            fi
            if [ "$(lfa_android_state_get clipboard 2>/dev/null || echo 0)" = "1" ] && \
               command -v termux-clipboard-get >/dev/null 2>&1; then
                lfa_android_timeout 5 termux-clipboard-get \
                    > "$_bridge/lfa-android-clipboard.txt" 2>/dev/null || true
            fi
            lfa_android_pump
            ;;
        test)
            local _rc=0
            echo "Running read-only Android probes..."
            if ! command -v termux-battery-status >/dev/null 2>&1; then
                echo "FAIL: termux-api is not installed (run: lfa android install)." >&2
                return 1
            fi
            local _b
            _b="$(lfa_android_battery_json)"
            if printf '%s' "$_b" | grep -q '"percentage"'; then
                echo "PASS: battery -> $(printf '%s' "$_b" | tr -d '\n' | cut -c1-120)"
            else
                echo "FAIL: battery probe returned no data." >&2; _rc=1
            fi
            for _probe in termux-location termux-clipboard-get termux-wifi-connectioninfo; do
                if command -v "$_probe" >/dev/null 2>&1; then
                    echo "PASS: $_probe is present"
                else
                    echo "SKIP: $_probe is not available"
                fi
            done
            return $_rc ;;
        enable|disable)
            case "$_what" in battery|location|clipboard|notifications) ;; *)
                echo "Usage: lfa android $_sub battery|location|clipboard|notifications" >&2; return 2 ;; esac
            local _val=1; [ "$_sub" = "disable" ] && _val=0
            lfa_android_state_set "$_what" "$_val"
            if [ "$_val" = "1" ]; then
                lfa_android_apply_wrappers "$_what"
                [ "$_what" = "battery" ] && lfa_android_cmd refresh || true
                echo "[*] Android $_what bridge enabled."
            else
                lfa_android_remove_wrapper "$_what"
                echo "[*] Android $_what bridge disabled."
            fi ;;
        bridge)
            [ -n "$_what" ] || { echo "Usage: lfa android bridge battery|location|clipboard|notifications" >&2; return 2; }
            if [ -n "$_inst" ]; then
                lfa_android_cmd enable "$_what" -i "$_inst"
            else
                lfa_android_cmd enable "$_what"
            fi
            lfa_android_cmd refresh
            ;;
        pump)
            lfa_android_pump ;;
        *) echo "Unknown android command: $_sub" >&2; lfa_android_cmd help >&2; return 2 ;;
    esac
}

lfa_android_apply_wrappers() {  # $1 = capability
    local _root _rel _file="" _hint=""
    _root="$(lfa_shim_rootfs 2>/dev/null)" || _root=""
    [ -n "$_root" ] || { echo "[i] No distro selected; wrappers will be installed on the next enable -i NAME."; return 0; }
    case "$1" in
        battery) _rel="usr/local/bin/lfa-android-battery"; _file="/tmp/lfa-android-battery.env"; _hint="battery" ;;
        location) _rel="usr/local/bin/lfa-android-location"; _file="/tmp/lfa-android-location.json"; _hint="location" ;;
        clipboard) _rel="usr/local/bin/lfa-android-clipboard"; _file="/tmp/lfa-android-clipboard.txt"; _hint="clipboard" ;;
        notifications) _rel="usr/local/bin/lfa-android-notify" ;;
        *) return 0 ;;
    esac
    if [ "$1" = "notifications" ]; then
        lfa_shim_write "$_root" "$_rel" <<'SHIM'
#!/bin/sh
# LFA Android notification bridge. Queues a request for `lfa android pump`.
mkdir -p /tmp/lfa-android-outbox 2>/dev/null || true
_id="$(date +%s)-$$"
printf '%s\n' "$*" > "/tmp/lfa-android-outbox/$_id.title"
cat > "/tmp/lfa-android-outbox/$_id.body" 2>/dev/null || true
echo "lfa-android-notify: queued (run 'lfa android pump' on the Termux side)." >&2
SHIM
        return 0
    fi
    lfa_shim_write "$_root" "$_rel" <<SHIM
#!/bin/sh
# LFA Android bridge (reads the shared /tmp file written by Termux:API).
cat "$_file" 2>/dev/null || { echo "$_hint bridge has no data; run 'lfa android refresh'." >&2; exit 1; }
SHIM
}

lfa_android_remove_wrapper() {  # $1 = capability
    local _root _f
    _root="$(lfa_shim_rootfs 2>/dev/null)" || _root=""
    [ -n "$_root" ] || return 0
    case "$1" in
        battery) _f="$_root/usr/local/bin/lfa-android-battery" ;;
        location) _f="$_root/usr/local/bin/lfa-android-location" ;;
        clipboard) _f="$_root/usr/local/bin/lfa-android-clipboard" ;;
        notifications) _f="$_root/usr/local/bin/lfa-android-notify" ;;
        *) return 0 ;;
    esac
    [ -f "$_f" ] && grep -q 'LFA Android' "$_f" 2>/dev/null && rm -f "$_f"
    return 0
}

lfa_android_pump() {
    local _dir="$PREFIX/tmp/lfa-android-outbox" _f
    [ -d "$_dir" ] || return 0
    command -v termux-notification >/dev/null 2>&1 || return 0
    for _f in "$_dir"/*.title; do
        [ -f "$_f" ] || continue
        local _base="${_f%.title}" _title _body
        _title="$(cat "$_f" 2>/dev/null || true)"
        _body="$(cat "$_base.body" 2>/dev/null || true)"
        lfa_android_timeout 8 termux-notification --title "$_title" --content "$_body" >/dev/null 2>&1 || true
        rm -f "$_f" "$_base.body"
    done
}

# ------------------------------------------------------------
# USB bridge: real Android USB devices in the guest.
#
# Termux:API is the only supported way to see USB hardware from Termux. It
# returns usbdevfs paths (`termux-usb -l`) and can hand a process the real
# file descriptor for one device (`termux-usb -E -e`). LFA does two things:
#
#   * publishes the live device list and its descriptors into $PREFIX/tmp,
#     which every guest sees as /tmp, so `lsusb` shows real devices;
#   * forwards the real descriptor into the guest for `lfa usb exec`.
#
# It never invents a /dev/bus/usb node: proot cannot create device nodes,
# and a fake node would break programs in a more confusing way than an
# honest "use lfa usb exec" message.
# ------------------------------------------------------------
LFA_USB_BRIDGE="$PREFIX/tmp/lfa-usb"
LFA_USB_CACHE="$HOME/.cache/linux-for-android/usb"
LFA_USB_CONF="$HOME/.config/linux-for-android/usb.conf"
LFA_USB_CALLBACK="$PREFIX/bin/lfa-usb-callback"
LFA_USB_SYSFS="${LFA_USB_SYSFS:-/sys/bus/usb/devices}"

lfa_usb_pad3() {
    case "${1:-}" in
        ''|*[!0-9]*) printf '%s' "${1:-}" ;;
        *) printf '%03d' "$((10#${1:-0}))" ;;
    esac
}

lfa_usb_clean() {
    printf '%s' "${1:-}" | tr '\t\r\n' '   '
}

lfa_usb_json_escape() {
    printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\t\r\n' '   '
}

lfa_usb_bus_dev() {  # $1 = /dev/bus/usb/001/002 -> "001 002"
    printf '%s\n' "${1:-}" | sed -n 's#.*/\([0-9][0-9]*\)/\([0-9][0-9]*\)$#\1 \2#p'
}

lfa_usb_api_ok() {
    command -v termux-usb >/dev/null 2>&1
}

lfa_usb_host_feature() {
    local _features
    if ! command -v pm >/dev/null 2>&1; then
        echo unknown
        return 0
    fi
    _features="$(lfa_android_timeout 5 pm list features 2>/dev/null || true)"
    case "$_features" in
        *android.hardware.usb.host*) echo yes ;;
        '') echo unknown ;;
        *) echo "not advertised" ;;
    esac
}

lfa_usb_raw_json() {
    lfa_android_timeout 12 termux-usb -l 2>/dev/null || true
}

# `-E` (descriptor as TERMUX_USB_FD) arrived in termux-api-package 0.57.
# Without it there is no safe way to hand the real device to the guest.
lfa_usb_export_ok() {
    local _help
    lfa_usb_api_ok || return 1
    _help="$(lfa_android_timeout 5 termux-usb -h 2>&1 || true)"
    case "$_help" in *-E*) return 0 ;; esac
    return 1
}

lfa_usb_names_from_json() {
    tr -d '\r' \
        | tr '\n' ' ' \
        | sed -e 's/^[[:space:]]*\[//' -e 's/\][[:space:]]*$//' \
              -e 's/"//g' -e 's/,/\n/g' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep '^/' || true
}

lfa_usb_live_names() {
    lfa_usb_raw_json | lfa_usb_names_from_json
}

lfa_usb_cache_file() {  # $1 bus, $2 dev
    printf '%s/dev-%s-%s.tsv' "$LFA_USB_CACHE" "$1" "$2"
}

lfa_usb_cache_row() {  # $1 bus, $2 dev
    local _f
    _f="$(lfa_usb_cache_file "$1" "$2")"
    [ -s "$_f" ] || return 1
    head -n1 "$_f"
}

lfa_usb_cache_put() {  # $1 bus, $2 dev, $3 row
    local _f
    mkdir -p "$LFA_USB_CACHE" 2>/dev/null || return 1
    _f="$(lfa_usb_cache_file "$1" "$2")"
    printf '%s\n' "$3" > "$_f"
}

lfa_usb_ifaces_from_sysfs() {  # $1 = /sys/bus/usb/devices/X-Y
    local _dir="$1" _if _num _cls _sub _proto _eps=0 _out="" _sep=""
    for _if in "$_dir":*.*; do
        [ -d "$_if" ] || continue
        _num="$(cat "$_if/bInterfaceNumber" 2>/dev/null || true)"
        [ -n "$_num" ] || _num="${_if##*:}"
        _num="${_num%%.*}"
        case "$_num" in
            ''|*[!0-9a-fA-F]*) ;;
            *) _num=$((16#$_num)) ;;
        esac
        _cls="$(cat "$_if/bInterfaceClass" 2>/dev/null || true)"
        _sub="$(cat "$_if/bInterfaceSubClass" 2>/dev/null || true)"
        _proto="$(cat "$_if/bInterfaceProtocol" 2>/dev/null || true)"
        _eps=0
        for _ep in "$_if"/ep_*; do
            [ -e "$_ep" ] && _eps=$((_eps + 1))
        done
        _out="${_out}${_sep}${_num}:${_cls}:${_sub}:${_proto}:${_eps}"
        _sep=";"
    done
    printf '%s' "$_out"
}

lfa_usb_sysfs_row() {  # $1 bus, $2 dev, $3 path
    local _bus="$1" _dev="$2" _path="$3" _dir _b _n _vid _pid _ver _cls _sub _proto
    local _man _prod _ser _ifaces
    for _dir in "$LFA_USB_SYSFS"/*; do
        [ -r "$_dir/busnum" ] || continue
        _b="$(cat "$_dir/busnum" 2>/dev/null || true)"
        _n="$(cat "$_dir/devnum" 2>/dev/null || true)"
        [ "$(lfa_usb_pad3 "$_b")" = "$_bus" ] || continue
        [ "$(lfa_usb_pad3 "$_n")" = "$_dev" ] || continue
        _vid="$(cat "$_dir/idVendor" 2>/dev/null || true)"
        _pid="$(cat "$_dir/idProduct" 2>/dev/null || true)"
        _ver="$(tr -d '[:space:]' < "$_dir/version" 2>/dev/null || true)"
        _cls="$(cat "$_dir/bDeviceClass" 2>/dev/null || true)"
        _sub="$(cat "$_dir/bDeviceSubClass" 2>/dev/null || true)"
        _proto="$(cat "$_dir/bDeviceProtocol" 2>/dev/null || true)"
        _man="$(cat "$_dir/manufacturer" 2>/dev/null || true)"
        _prod="$(cat "$_dir/product" 2>/dev/null || true)"
        _ser="$(cat "$_dir/serial" 2>/dev/null || true)"
        _ifaces="$(lfa_usb_ifaces_from_sysfs "$_dir")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tsysfs\n' \
            "$_bus" "$_dev" "$_path" "$_vid" "$_pid" "$_ver" "$_cls" "$_sub" \
            "$_proto" "$(lfa_usb_clean "$_man")" "$(lfa_usb_clean "$_prod")" \
            "$(lfa_usb_clean "$_ser")" "$_ifaces"
        return 0
    done
    return 1
}

lfa_usb_publish() {  # $1 = visible device count
    local _count="${1:-0}" _row _bus _dev _dir _vid _pid _ver _cls _sub _proto
    local _man _prod _ser _ifaces _n
    rm -rf "$LFA_USB_BRIDGE/sys" 2>/dev/null || true
    mkdir -p "$LFA_USB_BRIDGE/sys" 2>/dev/null || true
    while IFS= read -r _row; do
        case "$_row" in ''|'#'*) continue ;; esac
        _bus="$(printf '%s' "$_row" | cut -f1)"
        _dev="$(printf '%s' "$_row" | cut -f2)"
        [ -n "$_bus" ] && [ -n "$_dev" ] || continue
        _vid="$(printf '%s' "$_row" | cut -f4)"
        _pid="$(printf '%s' "$_row" | cut -f5)"
        _ver="$(printf '%s' "$_row" | cut -f6)"
        _cls="$(printf '%s' "$_row" | cut -f7)"
        _sub="$(printf '%s' "$_row" | cut -f8)"
        _proto="$(printf '%s' "$_row" | cut -f9)"
        _man="$(printf '%s' "$_row" | cut -f10)"
        _prod="$(printf '%s' "$_row" | cut -f11)"
        _ser="$(printf '%s' "$_row" | cut -f12)"
        _ifaces="$(printf '%s' "$_row" | cut -f13)"
        _dir="$LFA_USB_BRIDGE/sys/${_bus}-${_dev}"
        mkdir -p "$_dir" 2>/dev/null || continue
        printf '%s\n' "$_bus" > "$_dir/busnum"
        printf '%s\n' "$_dev" > "$_dir/devnum"
        printf '%s\n' "$_vid" > "$_dir/idVendor"
        printf '%s\n' "$_pid" > "$_dir/idProduct"
        printf '%s\n' "$_ver" > "$_dir/version"
        printf '%s\n' "$_cls" > "$_dir/bDeviceClass"
        printf '%s\n' "$_sub" > "$_dir/bDeviceSubClass"
        printf '%s\n' "$_proto" > "$_dir/bDeviceProtocol"
        printf '%s\n' "$_man" > "$_dir/manufacturer"
        printf '%s\n' "$_prod" > "$_dir/product"
        printf '%s\n' "$_ser" > "$_dir/serial"
        _n=0
        if [ -n "$_ifaces" ]; then
            _n="$(printf '%s' "$_ifaces" | tr ';' '\n' | grep -c . || true)"
        fi
        printf '%s\n' "$_n" > "$_dir/bNumInterfaces"
    done < "$LFA_USB_BRIDGE/devices.tsv"
    {
        printf 'USB_COUNT=%s\n' "$_count"
        printf 'USB_UPDATED=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"
        printf 'USB_SOURCE=termux-api\n'
    } > "$LFA_USB_BRIDGE/state.env"
    cat > "$LFA_USB_BRIDGE/README" <<'USBREADME'
LFA USB bridge
==============

Written by `lfa usb refresh` in Termux. Every LFA guest sees this directory
as /tmp/lfa-usb because proot uses --shared-tmp.

devices.tsv   live devices from `termux-usb -l`, one tab-separated row each:
              bus, dev, android path, idVendor, idProduct, USB version,
              class, subclass, protocol, manufacturer, product, serial,
              interfaces, source
devices.json  raw output of `termux-usb -l`
sys/BUS-DEV/  the same values as small files, shaped like sysfs
scan-*.json   full descriptors read by `lfa usb scan` (permission required)
scan-*.tsv    the one-line form of the same descriptors
state.env     USB_COUNT, USB_UPDATED, USB_SOURCE

Sessions get a real port without mknod. From Termux:

    lfa usb attach DEV -- COMMAND   /dev/bus/usb/BBB/DDD + sysfs
    lfa usb tty DEV -- COMMAND      /dev/ttyUSB0 serial bridge
    lfa usb exec DEV -- COMMAND     raw descriptor in TERMUX_USB_FD

`attach` duplicates the descriptor Termux:API opened with a preload, and
fills a sysfs tree from the real descriptors. proot cannot create device
nodes, so the name is virtual even though the descriptor and every ioctl
are real. `lfa-usb fd` prints the raw descriptor number.
USBREADME
    chmod 644 "$LFA_USB_BRIDGE"/devices.tsv "$LFA_USB_BRIDGE"/devices.json \
        "$LFA_USB_BRIDGE"/README "$LFA_USB_BRIDGE"/state.env 2>/dev/null || true
    chmod 755 "$LFA_USB_BRIDGE" 2>/dev/null || true
}

lfa_usb_refresh() {
    local _json _names _path _bd _bus _dev _row _tmp _count=0
    if ! lfa_usb_api_ok; then
        echo "[!] termux-usb is not installed. Install the client first:" >&2
        echo "      lfa android install" >&2
        return 1
    fi
    _json="$(lfa_usb_raw_json)"
    if [ -z "$_json" ]; then
        echo "[!] termux-usb returned nothing. Open Termux:API once, then retry." >&2
        return 1
    fi
    case "$(printf '%s' "$_json" | tr -d '[:space:]')" in
        \[*) ;;
        *)
            echo "[!] termux-usb did not return a device list:" >&2
            printf '    %s\n' "$(printf '%s' "$_json" | head -n1)" >&2
            echo "    Check Termux:API, then run: lfa android test" >&2
            return 1 ;;
    esac
    mkdir -p "$LFA_USB_BRIDGE" "$LFA_USB_CACHE" 2>/dev/null || return 1
    printf '%s\n' "$_json" > "$LFA_USB_BRIDGE/devices.json"
    _names="$(printf '%s' "$_json" | lfa_usb_names_from_json)"
    _tmp="$LFA_USB_BRIDGE/.devices.tmp.$$"
    {
        printf '# LFA USB bridge v1 - generated by lfa usb refresh\n'
        printf '# bus\tdev\tpath\tvid\tpid\tusbver\tclass\tsubclass\tprotocol\tmanufacturer\tproduct\tserial\tinterfaces\tsource\n'
    } > "$_tmp" || return 1
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        _bd="$(lfa_usb_bus_dev "$_path")"
        [ -n "$_bd" ] || continue
        _bus="$(lfa_usb_pad3 "${_bd%% *}")"
        _dev="$(lfa_usb_pad3 "${_bd##* }")"
        [ -n "$_bus" ] && [ -n "$_dev" ] || continue
        _row="$(lfa_usb_sysfs_row "$_bus" "$_dev" "$_path" 2>/dev/null || true)"
        if [ -z "$_row" ]; then
            _row="$(lfa_usb_cache_row "$_bus" "$_dev" 2>/dev/null || true)"
        fi
        if [ -z "$_row" ]; then
            _row="$(printf '%s\t%s\t%s\t\t\t\t\t\t\t\t\t\t\tenum' \
                "$_bus" "$_dev" "$_path")"
        else
            _row="$(printf '%s\t%s\t%s\t%s' "$_bus" "$_dev" "$_path" \
                "$(printf '%s' "$_row" | cut -f4-)")"
        fi
        printf '%s\n' "$_row" >> "$_tmp"
        _count=$((_count + 1))
    done <<< "$_names"
    mv -f "$_tmp" "$LFA_USB_BRIDGE/devices.tsv" || {
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    }
    lfa_usb_publish "$_count"
    printf '%s\n' "$_count"
}

lfa_usb_count() {
    [ -f "$LFA_USB_BRIDGE/devices.tsv" ] || { echo 0; return 0; }
    awk -F '\t' '!/^#/ && NF >= 3 {n++} END {print n + 0}' \
        "$LFA_USB_BRIDGE/devices.tsv"
}

lfa_usb_described_count() {
    [ -f "$LFA_USB_BRIDGE/devices.tsv" ] || { echo 0; return 0; }
    awk -F '\t' '!/^#/ && NF >= 5 && $4 != "" && $5 != "" {n++} END {print n + 0}' \
        "$LFA_USB_BRIDGE/devices.tsv"
}

lfa_usb_conf_instance() {
    [ -r "$LFA_USB_CONF" ] || return 0
    sed -n 's/^USB_INSTANCE="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' \
        "$LFA_USB_CONF" 2>/dev/null | tail -n1
}

lfa_usb_conf_get() {  # $1 = key (USB_INSTANCE|USB_SHIMS)
    [ -r "$LFA_USB_CONF" ] || return 0
    sed -n "s/^$1=\"\\{0,1\\}\\([^\"]*\\)\"\\{0,1\\}$/\\1/p" \
        "$LFA_USB_CONF" 2>/dev/null | tail -n1
}

lfa_usb_conf_set() {  # $1 = key, $2 = value
    local _key="$1" _val="$2"
    mkdir -p "$(dirname "$LFA_USB_CONF")" 2>/dev/null || return 1
    if grep -q "^$_key=" "$LFA_USB_CONF" 2>/dev/null; then
        sed -i "s|^$_key=.*|$_key=\"$_val\"|" "$LFA_USB_CONF"
    else
        printf '%s="%s"\n' "$_key" "$_val" >> "$LFA_USB_CONF"
    fi
}

lfa_usb_write_callback() {
    if ! mkdir -p "$PREFIX/bin" 2>/dev/null; then
        echo "[!] Could not create $PREFIX/bin." >&2
        return 1
    fi
    if ! cat > "$LFA_USB_CALLBACK" <<'USBCALLBACK'
#!/bin/bash
# LFA USB bridge callback. Started by `termux-usb -E -e`, which puts the
# real usbdevfs descriptor in TERMUX_USB_FD. Forward it into the guest.
set -u
FD="${TERMUX_USB_FD:-}"
if [ -z "$FD" ]; then
    echo "lfa-usb: Termux:API did not pass a file descriptor." >&2
    exit 1
fi
PD="${LFA_USB_PD:-}"
if [ -z "$PD" ]; then
    PD="$(command -v proot-distro 2>/dev/null || true)"
fi
if [ -z "$PD" ]; then
    echo "lfa-usb: proot-distro not found on the Termux side." >&2
    exit 1
fi
INST="${LFA_USB_INSTANCE:-}"
if [ -z "$INST" ]; then
    echo "lfa-usb: no instance was selected." >&2
    exit 1
fi
USER_NAME="${LFA_USB_USER:-user}"
FLAGS="${LFA_USB_PD_FLAGS:-}"
MODE="${LFA_USB_MODE:-exec}"
# `termux-usb` runs this callback inside `OUTPUT="$(...)"`, so the guest's
# stdout would be swallowed by a command substitution and only printed when
# the session ends. When stdout is a pipe but stderr is still the terminal,
# point stdout at the terminal so output is live and the guest sees a tty.
# `cmd > file 2>&1` still redirects both and captures everything.
if [ ! -t 1 ] && [ -t 2 ]; then
    exec >&2
fi
# shellcheck disable=SC2086  # flags are a word list such as --no-sysvipc
run_guest() {
    local _bind=() _oldifs _d
    [ -n "${LFA_USB_BIND:-}" ] && _bind=(--bind "$LFA_USB_BIND")
    # proot-distro binds the host /dev over the guest /dev, which hides any
    # node stored in the rootfs. The host tree passed here restores the
    # device path so `ls` and stat() see it as well as open().
    if [ -n "${LFA_USB_DEVBIND:-}" ]; then
        _oldifs="$IFS"; IFS=';'
        # shellcheck disable=SC2086  # ';' separates the specs, not spaces
        for _d in $LFA_USB_DEVBIND; do
            [ -n "$_d" ] && _bind+=(--bind "$_d")
        done
        IFS="$_oldifs"
    fi
    exec "$PD" login $FLAGS "${_bind[@]}" "$INST" --user "$USER_NAME" \
        --shared-tmp -- "$@"
}
# The node path is derived from the descriptor number the kernel gave
# Termux:API, so the map must be built here, not before `termux-usb` runs.
USB_MAP=""
if [ -n "${LFA_USB_BUS:-}" ] && [ -n "${LFA_USB_DEV:-}" ]; then
    USB_MAP="${LFA_USB_BUS}/${LFA_USB_DEV}=${FD}"
fi
case "$MODE" in
    exec)
        SCRIPT="${LFA_USB_RUN_SCRIPT:-}"
        if [ -z "$SCRIPT" ]; then
            echo "lfa-usb: no command was staged for the guest." >&2
            exit 1
        fi
        run_guest /bin/sh -c '
            export TERMUX_USB_FD="$1"
            LFA_USB_PATH="$4"; export LFA_USB_PATH
            if [ -n "$5" ]; then LFA_USB_MAP="$5"; export LFA_USB_MAP; fi
            if [ -n "$6" ]; then LD_PRELOAD="$6"; export LD_PRELOAD; fi
            cd "$2" 2>/dev/null || cd /
            exec bash "$3"
        ' sh "$FD" "${LFA_USB_CWD:-/}" "$SCRIPT" "${LFA_USB_PATH:-}" \
           "$USB_MAP" "${LFA_USB_PRELOAD:-}"
        ;;
    prep)
        OUT="${LFA_USB_OUT:-}"
        TSV="${LFA_USB_TSV:-}"
        BLOB="${LFA_USB_BLOB:-}"
        SYSFS="${LFA_USB_SYSFS_OUT:-}"
        if [ -z "$OUT" ]; then
            echo "lfa-usb: no descriptor output path was set." >&2
            exit 1
        fi
        run_guest env "TERMUX_USB_FD=$FD" \
            "LFA_USB_PATH=${LFA_USB_PATH:-}" \
            python3 /usr/local/libexec/lfa-usb-desc.py \
            --json --out "$OUT" --tsv "$TSV" --blob "$BLOB" --sysfs "$SYSFS" \
            --speed "${LFA_USB_SPEED:-480}" \
            --bus "${LFA_USB_BUS:-}" --dev "${LFA_USB_DEV:-}" \
            --path "${LFA_USB_PATH:-}"
        ;;
    scan)
        OUT="${LFA_USB_OUT:-}"
        TSV="${LFA_USB_TSV:-}"
        if [ -z "$OUT" ]; then
            echo "lfa-usb: no scan output path was set." >&2
            exit 1
        fi
        if [ -n "$TSV" ]; then
            run_guest env "TERMUX_USB_FD=$FD" \
                "LFA_USB_PATH=${LFA_USB_PATH:-}" \
                python3 /usr/local/libexec/lfa-usb-desc.py \
                --json --out "$OUT" --tsv "$TSV" \
                --bus "${LFA_USB_BUS:-}" --dev "${LFA_USB_DEV:-}" \
                --path "${LFA_USB_PATH:-}"
        else
            run_guest env "TERMUX_USB_FD=$FD" \
                "LFA_USB_PATH=${LFA_USB_PATH:-}" \
                python3 /usr/local/libexec/lfa-usb-desc.py \
                --json --out "$OUT" \
                --bus "${LFA_USB_BUS:-}" --dev "${LFA_USB_DEV:-}" \
                --path "${LFA_USB_PATH:-}"
        fi
        ;;
    *)
        echo "lfa-usb: unknown callback mode '$MODE'." >&2
        exit 1
        ;;
esac
USBCALLBACK
    then
        echo "[!] Could not write $LFA_USB_CALLBACK." >&2
        return 1
    fi
    chmod 755 "$LFA_USB_CALLBACK" 2>/dev/null || true
}

lfa_usb_stage_desc() {  # $1 = guest rootfs
    local _src="$LFA_DIR/lib/usb-desc.py"
    local _dst="$1/usr/local/libexec/lfa-usb-desc.py"
    if [ ! -f "$_src" ]; then
        echo "[!] lib/usb-desc.py is missing; run menu 12 or reinstall." >&2
        return 1
    fi
    if ! mkdir -p "$(dirname "$_dst")" 2>/dev/null; then
        echo "[!] Could not create $(dirname "$_dst") in the guest rootfs." >&2
        return 1
    fi
    if ! cp -f "$_src" "$_dst" 2>/dev/null; then
        echo "[!] Could not copy lib/usb-desc.py to $_dst." >&2
        return 1
    fi
    chmod 755 "$_dst" 2>/dev/null || true
}

lfa_usb_guest_python_ok() {  # $1 = instance
    local _inst="$1" _user _flags
    _user="$(lfa_appimage_user "$_inst")"
    _flags="$(pd_login_flags)"
    # shellcheck disable=SC2086  # flags are a word list
    proot-distro login $_flags "$_inst" --user "$_user" --shared-tmp -- \
        /bin/sh -c 'command -v python3 >/dev/null 2>&1 && python3 -c "import ctypes" >/dev/null 2>&1' \
        >/dev/null 2>&1
}

lfa_usb_pick_instance() {  # $1 = optional instance name; sets INSTANCE_NAME
    local _want="${1:-}" _root _name _saved=""
    if [ -n "$_want" ]; then
        CLI_INSTANCE="$_want"
    elif [ -z "${CLI_INSTANCE:-}" ]; then
        # Fall back to the instance `lfa usb enable` remembered, so plain
        # `lfa usb scan` keeps working when more than one distro is installed.
        _saved="$(lfa_usb_conf_instance)"
        [ -n "$_saved" ] && CLI_INSTANCE="$_saved"
    fi
    _root="$(lfa_shim_rootfs 2>/dev/null)" || _root=""
    if [ -z "$_root" ]; then
        if [ -n "$_want" ]; then
            echo "No installed distribution named '$_want'." >&2
        elif [ -n "$_saved" ]; then
            echo "[!] The saved USB instance '$_saved' is not installed." >&2
            echo "    Pick another with: lfa usb <command> -i NAME" >&2
        else
            echo "[!] Choose a distribution: lfa usb <command> -i NAME" >&2
            echo "    Installed: $(pd_instances 2>/dev/null | tr '\n' ' ')" >&2
        fi
        return 1
    fi
    INSTANCE_NAME=""
    while IFS= read -r _name; do
        [ -n "$_name" ] || continue
        if [ "$(pd_rootfs "$_name")" = "$_root" ]; then
            INSTANCE_NAME="$_name"
            break
        fi
    done < <(pd_instances)
    if [ -z "$INSTANCE_NAME" ]; then
        echo "[!] Could not match the rootfs to an installed instance." >&2
        echo "    Pass -i NAME (see: proot-distro list)." >&2
        return 1
    fi
    CONF_FILE="$(pd_conf "$INSTANCE_NAME")"
    if [ -f "$CONF_FILE" ]; then
        # shellcheck disable=SC1090  # instance config path is computed at runtime
        . "$CONF_FILE"
    fi
    return 0
}

lfa_usb_line_for() {  # $1 bus, $2 dev -> lsusb-style line
    awk -F '\t' -v b="$1" -v d="$2" '
        /^#/ || NF < 3 { next }
        $1 == b && $2 == d {
            name = $10
            if (name != "" && $11 != "") name = name " " $11
            else if (name == "") name = $11
            if (name == "") name = "Unknown device"
            id = ($4 != "" && $5 != "") ? $4 ":" $5 : "----:----"
            printf "Bus %s Device %s: ID %s %s\n", $1, $2, id, name
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$LFA_USB_BRIDGE/devices.tsv" 2>/dev/null
}

lfa_usb_normalize_dev() {  # 001/002 or 001:002 or a full path -> full path
    local _v="${1:-}"
    case "$_v" in
        /dev/bus/usb/*) printf '%s' "$_v" ;;
        */*)
            printf '/dev/bus/usb/%s/%s' \
                "$(lfa_usb_pad3 "${_v%%/*}")" "$(lfa_usb_pad3 "${_v##*/}")" ;;
        *:*)
            printf '/dev/bus/usb/%s/%s' \
                "$(lfa_usb_pad3 "${_v%%:*}")" "$(lfa_usb_pad3 "${_v##*:}")" ;;
        *) printf '%s' "$_v" ;;
    esac
}

lfa_usb_usage() {
    cat <<'USBHELP'
Usage: lfa usb <command> [options]

  status                   show Termux:API, USB host, bridge, and shim state
  list [--json]            list real devices visible through Termux:API
  refresh                  re-read `termux-usb -l` and rebuild the guest view
  scan [DEV...]            request permission and read real descriptors
  watch [--interval N] [--count N]
                           poll for hotplug and print add/remove events
  enable [-i NAME]         install the guest helpers, libusb preload, tty bridge
  disable [-i NAME]        remove those guest helpers
  attach [DEV] [-- CMD...] open a guest session with /dev/bus/usb/BBB/DDD
  tty [DEV] [-- CMD...]    open a session with /dev/ttyUSB0 (serial bridge)
  exec DEV -- COMMAND...   run COMMAND with the raw USB fd (no preload)
  flash [--install] ARGS   flash ESP32/ESP8266 with esptool in the guest
  help                     show this help

DEV is /dev/bus/usb/001/002, 001/002, or 001:002. The device path is exactly
what `termux-usb -l` reports. With one device attached, DEV may be omitted.

Examples:
  lfa usb status
  lfa usb refresh
  lfa usb scan
  lfa usb enable -i ubuntu
  lfa usb attach                  # shell with a real /dev/bus/usb + sysfs
  lfa usb attach 001/002 -- lsusb -v
  lfa usb tty                     # shell with /dev/ttyUSB0
  lfa usb tty 001/002 -- picocom -b 115200 /dev/ttyUSB0
  lfa usb flash --install
  lfa usb flash --baud 460800 write 0x0 /sdcard/firmware.bin
  lfa usb exec 001/002 -- lfa-usb desc

How it works: Termux:API owns USB access on Android and can hand one process
the real usbfs descriptor (`termux-usb -E`). `lfa usb attach` forwards that
descriptor into the guest, publishes the device's real descriptors as a small
sysfs tree, and preloads liblfa-usb-node.so. open() on /dev/bus/usb/BBB/DDD
then returns the real descriptor, so lsusb, pyusb, dfu-util and other libusb
tools work unchanged, with real ioctls and transfers. `lfa usb tty` bridges
the bulk endpoints to a pty so esptool and other serial tools see
/dev/ttyUSB0. Nothing is simulated: proot still cannot create device nodes,
which is why the node comes from the preload instead of mknod.

Options:
  -i, --instance NAME      distribution to use (enable/disable/scan/attach/tty)
      --user NAME          guest account for attach/tty/exec
      --root               run the command as root in the guest
      --cwd DIR            guest working directory (default: user's home)
      --device DEV         device for tty/flash (same forms as DEV)
      --no-permission      do not show the Android permission dialog
      --no-sysfs           attach without the synthetic /sys/bus/usb tree
      --baud N             serial baud rate for tty/flash (default 115200)
      --json               machine-readable output of list/scan
USBHELP
}

lfa_usb_list() {
    local _json=0 _unknown=0 _shown=0 _row _b _d
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) _json=1; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    if ! lfa_usb_api_ok; then
        echo "[!] termux-usb is not installed. Run: lfa android install" >&2
        return 1
    fi
    if ! lfa_usb_refresh >/dev/null; then
        return 1
    fi
    if [ ! -s "$LFA_USB_BRIDGE/devices.tsv" ]; then
        echo "No USB devices are visible to Termux:API." >&2
        return 1
    fi
    if [ "$_json" = "1" ]; then
        local _first=1 _path _vid _pid _ver _cls _sub _proto _man _prod _ser _ifaces _src
        printf '['
        while IFS= read -r _row; do
            case "$_row" in ''|'#'*) continue ;; esac
            _b="$(printf '%s' "$_row" | cut -f1)"
            _d="$(printf '%s' "$_row" | cut -f2)"
            [ -n "$_b" ] && [ -n "$_d" ] || continue
            _path="$(printf '%s' "$_row" | cut -f3)"
            _vid="$(printf '%s' "$_row" | cut -f4)"
            _pid="$(printf '%s' "$_row" | cut -f5)"
            _ver="$(printf '%s' "$_row" | cut -f6)"
            _cls="$(printf '%s' "$_row" | cut -f7)"
            _sub="$(printf '%s' "$_row" | cut -f8)"
            _proto="$(printf '%s' "$_row" | cut -f9)"
            _man="$(printf '%s' "$_row" | cut -f10)"
            _prod="$(printf '%s' "$_row" | cut -f11)"
            _ser="$(printf '%s' "$_row" | cut -f12)"
            _ifaces="$(printf '%s' "$_row" | cut -f13)"
            _src="$(printf '%s' "$_row" | cut -f14)"
            [ "$_first" = "1" ] || printf ','
            _first=0
            printf '{"bus":"%s","dev":"%s","path":"%s","vid":"%s","pid":"%s","usb_version":"%s","class":"%s","subclass":"%s","protocol":"%s","manufacturer":"%s","product":"%s","serial":"%s","interfaces":"%s","source":"%s"}' \
                "$(lfa_usb_json_escape "$_b")" "$(lfa_usb_json_escape "$_d")" \
                "$(lfa_usb_json_escape "$_path")" "$(lfa_usb_json_escape "$_vid")" \
                "$(lfa_usb_json_escape "$_pid")" "$(lfa_usb_json_escape "$_ver")" \
                "$(lfa_usb_json_escape "$_cls")" "$(lfa_usb_json_escape "$_sub")" \
                "$(lfa_usb_json_escape "$_proto")" "$(lfa_usb_json_escape "$_man")" \
                "$(lfa_usb_json_escape "$_prod")" "$(lfa_usb_json_escape "$_ser")" \
                "$(lfa_usb_json_escape "$_ifaces")" "$(lfa_usb_json_escape "$_src")"
        done < "$LFA_USB_BRIDGE/devices.tsv"
        printf ']\n'
        return 0
    fi
    while IFS= read -r _row; do
        case "$_row" in ''|'#'*) continue ;; esac
        _b="$(printf '%s' "$_row" | cut -f1)"
        _d="$(printf '%s' "$_row" | cut -f2)"
        [ -n "$_b" ] && [ -n "$_d" ] || continue
        lfa_usb_line_for "$_b" "$_d" || true
        _shown=$((_shown + 1))
        [ -n "$(printf '%s' "$_row" | cut -f4)" ] || _unknown=$((_unknown + 1))
    done < "$LFA_USB_BRIDGE/devices.tsv"
    if [ "$_shown" -eq 0 ]; then
        echo "No USB devices are visible to Termux:API." >&2
        return 1
    fi
    if [ "$_unknown" -gt 0 ] 2>/dev/null; then
        echo "" >&2
        echo "[i] $_unknown device(s) have no descriptors yet. Run: lfa usb scan" >&2
        echo "    Android shows one permission dialog per device." >&2
    fi
}

lfa_usb_status() {
    local _api="missing" _app="not detected" _host _count=0 _described=0
    local _inst _shims="not enabled" _last="never" _fd_now="no" _root=""
    local _export="no" _refresh="no" _preload="not installed" _arch="unknown"
    lfa_usb_api_ok && _api="installed"
    lfa_android_pm_has 'com.termux.api' && _app="installed"
    lfa_usb_export_ok && _export="yes"
    _host="$(lfa_usb_host_feature)"
    if lfa_usb_api_ok; then
        lfa_usb_refresh >/dev/null 2>&1 && _refresh="yes"
    fi
    # `pm list packages` cannot see other apps on some Android 11+ builds, so
    # a working `termux-usb -l` is the better proof that the app is present.
    if [ "$_app" = "not detected" ] && [ "$_refresh" = "yes" ]; then
        _app="installed (pm cannot list it)"
    fi
    _count="$(lfa_usb_count)"
    _described="$(lfa_usb_described_count)"
    _inst="$(lfa_usb_conf_instance)"
    if [ "$(lfa_usb_conf_get USB_SHIMS)" = "1" ] && [ -n "$_inst" ]; then
        _root="$(pd_rootfs "$_inst" 2>/dev/null || true)"
        if [ -n "$_root" ] && [ -f "$_root/usr/local/bin/lsusb" ]; then
            _shims="enabled for $_inst"
            if [ -f "$_root/usr/local/lib/lfa-usb-node.so" ]; then
                _arch="$(lfa_usb_elf_arch "$_root")"
                _preload="yes (${_arch} preload)"
            fi
        else
            _shims="configured for $_inst (helpers missing; run lfa usb enable)"
        fi
    fi
    if ls "$LFA_USB_BRIDGE"/scan-*.json >/dev/null 2>&1; then
        _last="$(basename "$(ls -t "$LFA_USB_BRIDGE"/scan-*.json 2>/dev/null | head -n1)")"
    fi
    [ -n "${TERMUX_USB_FD:-}" ] && _fd_now="yes (fd $TERMUX_USB_FD)"
    echo "USB bridge"
    echo "  termux-api package: $_api"
    echo "  Termux:API app:     $_app"
    echo "  descriptor export:  $_export (-E)"
    echo "  USB host feature:   $_host"
    echo "  devices visible:    $_count"
    echo "  with descriptors:   $_described (run: lfa usb scan)"
    echo "  live refresh:       $_refresh"
    echo "  bridge directory:   $LFA_USB_BRIDGE"
    echo "  guest helpers:      $_shims"
    echo "  libusb preload:     $_preload"
    echo "  last scan:          $_last"
    echo "  USB fd in this shell: $_fd_now"
    echo ""
    echo "Sessions with a real device view:"
    echo "  lfa usb attach 001/002          /dev/bus/usb/001/002 + real sysfs"
    echo "  lfa usb tty 001/002             /dev/ttyUSB0 serial bridge"
    echo "  lfa usb flash write 0x0 FILE    esptool inside the guest"
    echo ""
    echo "proot cannot create device nodes, so the node is provided by a"
    echo "preload that duplicates the descriptor Termux:API opened."
    if [ "$_api" = "missing" ]; then
        echo ""
        echo "[!] Install the client: lfa android install"
    fi
    if [ "$_api" = "installed" ] && [ "$_refresh" = "no" ]; then
        echo ""
        echo "[!] The live device list could not be read; this is a cached view."
        echo "    Open Termux:API once, then run: lfa usb refresh"
    fi
    if [ "$_app" = "not detected" ]; then
        echo ""
        echo "[!] Install the Termux:API app from F-Droid, then run lfa usb status."
    fi
    if [ "$_api" = "installed" ] && [ "$_export" = "no" ]; then
        echo ""
        echo "[!] This termux-api cannot export a descriptor (-E)."
        echo "    Update it: pkg upgrade termux-api"
    fi
    if [ "$_host" = "not advertised" ]; then
        echo ""
        echo "[!] Android does not advertise USB host support in its feature list."
        echo "    Many phones still work with an OTG adapter; powered hubs help."
    fi
}

lfa_usb_scan_one() {  # $1 instance, $2 user, $3 flags, $4 path, $5 quiet
    local _inst="$1" _user="$2" _flags="$3" _path="$4" _quiet="${5:-0}"
    local _bd _bus _dev _out _tsv _log _rc _row
    _bd="$(lfa_usb_bus_dev "$_path")"
    if [ -z "$_bd" ]; then
        echo "[!] $_path is not a usbdevfs path; skipping." >&2
        return 2
    fi
    _bus="$(lfa_usb_pad3 "${_bd%% *}")"
    _dev="$(lfa_usb_pad3 "${_bd##* }")"
    _out="/tmp/lfa-usb/scan-${_bus}-${_dev}.json"
    _tsv="/tmp/lfa-usb/scan-${_bus}-${_dev}.tsv"
    _log="$LFA_USB_BRIDGE/last-scan.log"
    rm -f "$LFA_USB_BRIDGE/scan-${_bus}-${_dev}.json" \
          "$LFA_USB_BRIDGE/scan-${_bus}-${_dev}.tsv" "$_log" 2>/dev/null || true
    (
        export LFA_USB_MODE=scan
        export LFA_USB_INSTANCE="$_inst"
        export LFA_USB_USER="$_user"
        export LFA_USB_PD_FLAGS="$_flags"
        export LFA_USB_OUT="$_out"
        export LFA_USB_TSV="$_tsv"
        export LFA_USB_BUS="$_bus"
        export LFA_USB_DEV="$_dev"
        export LFA_USB_PATH="$_path"
        lfa_android_timeout 90 termux-usb -r -E -e "$LFA_USB_CALLBACK" "$_path"
    ) > "$_log" 2>&1
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "[!] Bus $_bus Device $_dev: permission or read failed." >&2
        [ -s "$_log" ] && sed 's/^/    /' "$_log" >&2
        return "$_rc"
    fi
    if [ ! -s "$LFA_USB_BRIDGE/scan-${_bus}-${_dev}.tsv" ]; then
        echo "[!] Bus $_bus Device $_dev: no descriptor row was produced." >&2
        if [ -s "$LFA_USB_BRIDGE/scan-${_bus}-${_dev}.json" ]; then
            sed -n 's/.*"error": *"\([^"]*\)".*/    descriptor error: \1/p' \
                "$LFA_USB_BRIDGE/scan-${_bus}-${_dev}.json" >&2
        fi
        if [ -s "$_log" ]; then
            sed 's/^/    /' "$_log" >&2
        else
            echo "    Is python3 (with ctypes) installed in $_inst?" >&2
        fi
        return 1
    fi
    _row="$(head -n1 "$LFA_USB_BRIDGE/scan-${_bus}-${_dev}.tsv")"
    lfa_usb_cache_put "$_bus" "$_dev" "$_row" || return 1
    local _vid _pid _man _prod _name
    _vid="$(printf '%s' "$_row" | cut -f4)"
    _pid="$(printf '%s' "$_row" | cut -f5)"
    [ -n "$_vid" ] || _vid="----"
    [ -n "$_pid" ] || _pid="----"
    _man="$(printf '%s' "$_row" | cut -f10)"
    _prod="$(printf '%s' "$_row" | cut -f11)"
    _name="$_man"
    if [ -n "$_man" ] && [ -n "$_prod" ]; then _name="$_man $_prod"
    elif [ -z "$_man" ]; then _name="$_prod"; fi
    [ -n "$_name" ] || _name="Unknown device"
    if [ "$_quiet" = "0" ]; then
        printf 'Bus %s Device %s: ID %s:%s %s\n' "$_bus" "$_dev" \
            "$_vid" "$_pid" "$_name"
    fi
    return 0
}

lfa_usb_scan() {
    local _inst="" _user="" _json=0 _flags _root _id _ok=0 _bad=0 _dev
    local -a _devs=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --json) _json=1; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            --) shift; while [ $# -gt 0 ]; do _devs+=("$1"); shift; done ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) _devs+=("$1"); shift ;;
        esac
    done
    lfa_usb_api_ok || {
        echo "[!] termux-usb is not installed. Run: lfa android install" >&2
        return 1
    }
    if ! lfa_usb_export_ok; then
        echo "[!] This termux-api cannot export a USB descriptor (-E)." >&2
        echo "    Update it first: pkg upgrade termux-api" >&2
        return 1
    fi
    lfa_usb_pick_instance "$_inst" || return 1
    _id="$INSTANCE_NAME"
    _root="$(pd_rootfs "$_id")"
    [ -d "$_root" ] || { echo "[!] Rootfs missing for $_id." >&2; return 1; }
    command -v proot-distro >/dev/null 2>&1 || {
        echo "[!] proot-distro is required to enter the guest." >&2
        return 1
    }
    [ -n "$_user" ] || _user="$(lfa_appimage_user "$_id")"
    _flags="$(pd_login_flags)"
    lfa_usb_stage_desc "$_root" || return 1
    lfa_usb_write_callback || return 1
    if ! lfa_usb_guest_python_ok "$_id"; then
        echo "[!] $_id needs python3 with ctypes to read descriptors." >&2
        echo "    Install it in the guest, then retry:" >&2
        echo "      lfa shell -i $_id --root" >&2
        echo "      apt-get install -y python3    # or the distro equivalent" >&2
        return 1
    fi
    if [ ${#_devs[@]} -eq 0 ]; then
        mapfile -t _devs < <(lfa_usb_live_names)
    fi
    if [ ${#_devs[@]} -eq 0 ]; then
        echo "[!] No USB devices are visible. Connect one with an OTG adapter." >&2
        return 1
    fi
    mkdir -p "$LFA_USB_BRIDGE" 2>/dev/null || true
    local _quiet=0
    [ "$_json" = "1" ] && _quiet=1
    [ "$_quiet" = "1" ] || echo "Reading real descriptors through Termux:API..."
    for _dev in "${_devs[@]}"; do
        _dev="$(lfa_usb_normalize_dev "$_dev")"
        lfa_usb_scan_one "$_id" "$_user" "$_flags" "$_dev" "$_quiet" \
            && _ok=$((_ok + 1)) || _bad=$((_bad + 1))
    done
    lfa_usb_refresh >/dev/null 2>&1 || true
    if [ "$_json" = "1" ]; then
        local _f _first=1 _bd _bus _devn
        printf '['
        for _dev in "${_devs[@]}"; do
            _bd="$(lfa_usb_bus_dev "$(lfa_usb_normalize_dev "$_dev")")"
            [ -n "$_bd" ] || continue
            _bus="$(lfa_usb_pad3 "${_bd%% *}")"
            _devn="$(lfa_usb_pad3 "${_bd##* }")"
            _f="$LFA_USB_BRIDGE/scan-${_bus}-${_devn}.json"
            [ -f "$_f" ] || continue
            [ "$_first" = "1" ] || printf ','
            _first=0
            cat "$_f"
        done
        printf ']\n'
    else
        echo ""
        echo "Scanned: $_ok succeeded, $_bad failed."
        echo "Cache:   $LFA_USB_CACHE"
    fi
    [ "$_bad" -eq 0 ]
}

lfa_usb_shim_safe() {  # $1 = destination; refuse to overwrite a foreign file
    local _dest="$1"
    if [ ! -e "$_dest" ] && [ ! -L "$_dest" ]; then
        return 0
    fi
    if head -n3 "$_dest" 2>/dev/null | grep -q 'LFA USB bridge'; then
        return 0
    fi
    echo "[!] $_dest already exists and was not created by LFA." >&2
    echo "    Move it aside, then run: lfa usb enable -i NAME" >&2
    return 1
}

lfa_usb_enable() {
    local _inst="" _root="" _id _shim
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    if ! lfa_usb_pick_instance "$_inst"; then
        if [ -n "$_inst" ]; then
            lfa_usb_conf_set USB_INSTANCE "$_inst"
            echo "[i] Saved $_inst as the USB instance. Install it, then run:"
            echo "      lfa usb enable -i $_inst"
            return 0
        fi
        return 1
    fi
    _id="$INSTANCE_NAME"
    _root="$(pd_rootfs "$_id")"
    if [ ! -d "$_root" ]; then
        echo "[!] Rootfs missing for $_id." >&2
        return 1
    fi
    mkdir -p "$_root/usr/local/bin" "$_root/usr/local/libexec" 2>/dev/null || true
    lfa_usb_shim_safe "$_root/usr/local/bin/lsusb" || return 1
    lfa_usb_shim_safe "$_root/usr/local/bin/lfa-usb" || return 1
    lfa_shim_write "$_root" "usr/local/bin/lsusb" <<'LSUSB'
#!/bin/sh
# LFA USB bridge: lsusb over the real Termux:API device list.
# The list is written by `lfa usb refresh`; descriptors by `lfa usb scan`.
#
# A session started by `lfa usb attach`/`tty` exports LFA_USB_MAP and a real
# (preloaded) /dev/bus/usb node.  There the distro's usbutils lsusb is the
# better program, so hand over to it and only fall back to the bridge view.
if [ -n "${LFA_USB_MAP:-}" ]; then
    for _real in /usr/bin/lsusb /bin/lsusb; do
        [ -x "$_real" ] && exec "$_real" "$@"
    done
fi
# An explicit LFA_USB_BRIDGE always wins; the /tmp fallback is only for a
# guest where the session did not export one (proot shares /tmp).
if [ -n "${LFA_USB_BRIDGE:-}" ]; then
    BR="$LFA_USB_BRIDGE"
else
    BR=/tmp/lfa-usb
fi
DB="$BR/devices.tsv"
VERSION="1.0"

usage() {
    cat <<'HELP'
Usage: lsusb [options]
  -d VENDOR:PRODUCT   show only matching devices
  -s [[BUS]:][DEV]    show only matching bus/device
  -t                  show a simple device tree
  -v                  show cached descriptor fields
  -V, --version       print the LFA bridge version
  -h, --help          show this help

This lsusb reads the real devices enumerated by Termux:API. It is not the
usbutils binary: full descriptors come from `lfa usb scan` in Termux.
HELP
}

vid=""; sel=""; tree=0; verbose=0
while [ $# -gt 0 ]; do
    case "$1" in
        -d) vid="${2:-}"; shift 2 ;;
        -s) sel="${2:-}"; shift 2 ;;
        -t) tree=1; shift ;;
        -v) verbose=1; shift ;;
        -V|--version) echo "lsusb (LFA USB bridge) $VERSION"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "lsusb (LFA): unsupported option '$1'" >&2; exit 2 ;;
    esac
done

if [ ! -s "$DB" ]; then
    echo "lsusb (LFA): the USB bridge has no data." >&2
    echo "Run this in Termux: lfa usb refresh" >&2
    exit 1
fi

sel_bus=""; sel_dev=""
case "$sel" in
    '') ;;
    *:*) sel_bus="${sel%%:*}"; sel_dev="${sel##*:}" ;;
    *) sel_dev="$sel" ;;
esac

awk -F '\t' -v want="$vid" -v sb="$sel_bus" -v sd="$sel_dev" \
    -v tree="$tree" -v verbose="$verbose" '
function pad(value) {
    if (value ~ /^[0-9]+$/) return sprintf("%03d", value + 0)
    return value
}
function cname(code) {
    if (code == "01") return "Audio"
    if (code == "02") return "Communications"
    if (code == "03") return "Human Interface Device"
    if (code == "05") return "Physical"
    if (code == "06") return "Imaging"
    if (code == "07") return "Printer"
    if (code == "08") return "Mass Storage"
    if (code == "09") return "Hub"
    if (code == "0a") return "CDC Data"
    if (code == "0b") return "Smart Card"
    if (code == "0d") return "Content Security"
    if (code == "0e") return "Video"
    if (code == "dc") return "Diagnostic"
    if (code == "e0") return "Wireless"
    if (code == "ef") return "Miscellaneous"
    if (code == "fe") return "Application Specific"
    if (code == "ff") return "Vendor Specific"
    return "Class " code
}
BEGIN { FS = "\t"; found = 0 }
/^#/ || NF < 3 { next }
{
    b = $1; d = $2
    if (want != "" && tolower($4 ":" $5) != tolower(want)) next
    if (sb != "" && b != pad(sb)) next
    if (sd != "" && d != pad(sd)) next
    id = ($4 != "" && $5 != "") ? $4 ":" $5 : "----:----"
    name = $10
    if (name != "" && $11 != "") name = name " " $11
    else if (name == "") name = $11
    if (name == "") name = "Unknown device"
    if (tree) {
        printf "/:  Bus %s Device %s: ID %s %s\n", b, d, id, name
        n = split($13, ifs, ";")
        for (i = 1; i <= n; i++) {
            split(ifs[i], f, ":")
            printf "    |__ Interface %s, Class=%s (%s/%s/%s), %s endpoint(s)\n",
                f[1], cname(f[2]), f[2], f[3], f[4], f[5]
        }
        found = 1
        next
    }
    printf "Bus %s Device %s: ID %s %s\n", b, d, id, name
    if (verbose) {
        printf "  bcdUSB        %s\n", $6
        printf "  idVendor      0x%s\n", $4
        printf "  idProduct     0x%s\n", $5
        printf "  bDeviceClass  %s (%s)\n", $7, cname($7)
        printf "  iManufacturer %s\n", $10
        printf "  iProduct      %s\n", $11
        printf "  iSerial       %s\n", $12
        n = split($13, ifs, ";")
        for (i = 1; i <= n; i++) {
            split(ifs[i], f, ":")
            printf "  Interface %s: class %s (%s), subclass %s, protocol %s, %s endpoint(s)\n",
                f[1], f[2], cname(f[2]), f[3], f[4], f[5]
        }
        if ($14 != "scan")
            printf "  (descriptor not cached; run \"lfa usb scan\" in Termux)\n"
        printf "\n"
    }
    found = 1
}
END {
    if (!found) {
        if (want != "" || sb != "" || sd != "") exit 1
        print "No USB devices are visible to Termux:API."
        print "Run \"lfa usb refresh\" in Termux after connecting a device."
        exit 1
    }
}
' "$DB"
rc=$?
if [ "$rc" -ne 0 ]; then
    exit "$rc"
fi
if [ "$tree" = "0" ] && [ "$verbose" = "0" ]; then
    _unknown="$(awk -F '\t' '!/^#/ && NF >= 3 && $4 == "" {n++} END {print n + 0}' "$DB")"
    if [ "${_unknown:-0}" -gt 0 ] 2>/dev/null; then
        echo "" >&2
        echo "[i] $_unknown device(s) have no descriptors yet: run \"lfa usb scan\" in Termux." >&2
    fi
fi
exit 0
LSUSB
    cat <<'LFAUSB' | lfa_shim_write "$_root" "usr/local/bin/lfa-usb"
#!/bin/sh
# LFA USB bridge helper inside the guest.
# An explicit LFA_USB_BRIDGE always wins; the /tmp fallback is only for a
# guest where the session did not export one (proot shares /tmp).
if [ -n "${LFA_USB_BRIDGE:-}" ]; then
    BR="$LFA_USB_BRIDGE"
else
    BR=/tmp/lfa-usb
fi

usage() {
    cat <<'HELP'
Usage: lfa-usb COMMAND [args]

  list [lsusb options]   list real devices (same as lsusb)
  info BUS DEV           show cached descriptor fields for one device
  status                 bridge directory, device count, inherited fd
  path BUS DEV           print the Android device path
  fd                     print the inherited USB file descriptor
  run COMMAND [args]     run COMMAND with TERMUX_USB_FD (set by lfa usb exec)
  desc [FD]              read descriptors from FD (default: TERMUX_USB_FD)
  help                   show this help

Start an fd session from Termux:
  lfa usb exec 001/002 -- lfa-usb info 001 002
  lfa usb exec 001/002 -- lfa-usb desc
HELP
}

pad3() {
    _v="$1"
    case "$_v" in
        ''|*[!0-9]*) printf '%s' "$_v"; return 0 ;;
    esac
    while [ "${#_v}" -gt 1 ] && [ "${_v#0}" != "$_v" ]; do
        _v="${_v#0}"
    done
    printf '%03d' "$_v"
}

case "${1:-help}" in
    help|-h|--help) usage ;;
    list|ls)
        shift
        if command -v lsusb >/dev/null 2>&1; then
            exec lsusb "$@"
        fi
        if [ -x /usr/local/bin/lsusb ]; then
            exec /usr/local/bin/lsusb "$@"
        fi
        echo "lfa-usb: lsusb helper is missing; run 'lfa usb enable' in Termux." >&2
        exit 1
        ;;
    status)
        [ -r "$BR/state.env" ] && . "$BR/state.env"
        echo "LFA USB bridge"
        echo "  bridge directory: $BR"
        echo "  devices:          ${USB_COUNT:-0}"
        echo "  updated:          ${USB_UPDATED:-unknown}"
        echo "  source:           ${USB_SOURCE:-unknown}"
        if [ -n "${TERMUX_USB_FD:-}" ]; then
            echo "  USB fd:           $TERMUX_USB_FD"
            echo "  device path:      ${LFA_USB_PATH:-unknown}"
        else
            echo "  USB fd:           none in this shell"
        fi
        echo ""
        echo "Run in Termux: lfa usb attach DEV -- COMMAND"
        echo "for /dev/bus/usb/BBB/DDD, or lfa usb tty for /dev/ttyUSB0."
        echo "The node is a preload over the real Termux:API descriptor."
        ;;
    fd)
        if [ -z "${TERMUX_USB_FD:-}" ]; then
            echo "lfa-usb: no USB fd. Start with: lfa usb exec DEV -- COMMAND" >&2
            exit 1
        fi
        printf '%s\n' "$TERMUX_USB_FD"
        ;;
    run)
        shift
        [ $# -gt 0 ] || { usage >&2; exit 2; }
        if [ -z "${TERMUX_USB_FD:-}" ]; then
            echo "lfa-usb: warning: TERMUX_USB_FD is not set; start via 'lfa usb exec'." >&2
        fi
        exec "$@"
        ;;
    desc)
        shift
        _desc="${LFA_USB_DESC:-/usr/local/libexec/lfa-usb-desc.py}"
        if [ ! -f "$_desc" ]; then
            echo "lfa-usb: descriptor reader missing: $_desc" >&2
            exit 1
        fi
        if ! command -v python3 >/dev/null 2>&1; then
            echo "lfa-usb: python3 is required for descriptor reads." >&2
            exit 1
        fi
        exec python3 "$_desc" "$@"
        ;;
    path)
        shift
        _bus="$(pad3 "${1:-}")"
        _dev="$(pad3 "${2:-}")"
        if [ -z "$_bus" ] || [ -z "$_dev" ]; then
            echo "Usage: lfa-usb path BUS DEV" >&2
            exit 2
        fi
        printf '/dev/bus/usb/%s/%s\n' "$_bus" "$_dev"
        ;;
    info)
        shift
        _bus="$(pad3 "${1:-}")"
        _dev="${2:-}"
        if [ -z "$_dev" ]; then
            case "$_bus" in
                */*) _dev="$(pad3 "${_bus##*/}")"; _bus="$(pad3 "${_bus%%/*}")" ;;
                *:*) _dev="$(pad3 "${_bus##*:}")"; _bus="$(pad3 "${_bus%%:*}")" ;;
            esac
        else
            _dev="$(pad3 "$_dev")"
        fi
        if [ -z "$_bus" ] || [ -z "$_dev" ]; then
            echo "Usage: lfa-usb info BUS DEV" >&2
            exit 2
        fi
        _line="$(awk -F '\t' -v b="$_bus" -v d="$_dev" \
            '!/^#/ && $1 == b && $2 == d { print; exit }' "$BR/devices.tsv" 2>/dev/null)"
        if [ -z "$_line" ]; then
            echo "lfa-usb: no cached device Bus $_bus Device $_dev." >&2
            echo "Run 'lfa usb refresh' in Termux first." >&2
            exit 1
        fi
        _d() { printf '%s' "$_line" | cut -f"$1"; }
        echo "Bus $_bus Device $_dev"
        echo "  path:          $(_d 3)"
        echo "  idVendor:      0x$(_d 4)"
        echo "  idProduct:     0x$(_d 5)"
        echo "  USB version:   $(_d 6)"
        echo "  class:         $(_d 7) ($(_d 8)/$(_d 9))"
        echo "  manufacturer:  $(_d 10)"
        echo "  product:       $(_d 11)"
        echo "  serial:        $(_d 12)"
        echo "  interfaces:    $(_d 13)"
        _json="$BR/scan-$_bus-$_dev.json"
        if [ -f "$_json" ]; then
            echo ""
            echo "Full descriptor: $_json"
            if command -v python3 >/dev/null 2>&1; then
                python3 -m json.tool "$_json" 2>/dev/null || cat "$_json"
            else
                cat "$_json"
            fi
        else
            echo ""
            echo "No full descriptor cached. Run 'lfa usb scan' in Termux."
        fi
        ;;
    *)
        echo "lfa-usb: unknown command '$1'" >&2
        usage >&2
        exit 2
        ;;
esac
LFAUSB
    lfa_usb_stage_desc "$_root" || return 1
    if [ -d "$_root/run" ] || mkdir -p "$_root/run" 2>/dev/null; then
        if [ ! -e "$_root/run/lfa-usb" ] || [ -L "$_root/run/lfa-usb" ]; then
            ln -sfn /tmp/lfa-usb "$_root/run/lfa-usb" 2>/dev/null || true
        fi
    fi
    lfa_usb_stage_tty "$_root" 2>/dev/null || true
    _shim="$(lfa_usb_build_shim "$_root" 2>/dev/null || true)"
    if [ -n "$_shim" ] && lfa_usb_stage_shim "$_root" "$_shim"; then
        echo "[*] libusb preload installed for $(lfa_usb_elf_arch "$_root"): $LFA_USB_SHIM_GUEST"
    else
        echo "[!] The libusb preload could not be built for this rootfs."
        echo "    Install clang in Termux (pkg install clang) to enable /dev/bus/usb."
    fi
    lfa_usb_write_callback || true
    lfa_usb_conf_set USB_INSTANCE "$_id"
    lfa_usb_conf_set USB_SHIMS 1
    lfa_usb_refresh >/dev/null 2>&1 || true
    echo "[*] USB helpers installed in $_id: /usr/local/bin/lsusb, /usr/local/bin/lfa-usb"
    echo "    View:    lfa usb list"
    echo "    Scan:    lfa usb scan"
    echo "    Device:  lfa usb attach          (real /dev/bus/usb + sysfs)"
    echo "    Serial:  lfa usb tty             (real /dev/ttyUSB0)"
    echo "    Flash:   lfa usb flash --install"
    echo "    Raw fd:  lfa usb exec 001/002 -- lfa-usb desc"
}

lfa_usb_disable() {
    local _inst="" _root _id _f _manifest
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    if ! lfa_usb_pick_instance "$_inst"; then
        echo "[!] Choose a distribution with -i NAME." >&2
        return 1
    fi
    _id="$INSTANCE_NAME"
    _root="$(pd_rootfs "$_id")"
    for _f in "usr/local/bin/lsusb" "usr/local/bin/lfa-usb"; do
        if [ -f "$_root/$_f" ] && grep -q 'LFA USB bridge' "$_root/$_f" 2>/dev/null; then
            rm -f "$_root/$_f"
        fi
    done
    for _f in "usr/local/libexec/lfa-usb-desc.py" "usr/local/libexec/lfa-usb-tty.py" \
              "usr/local/lib/lfa-usb-node.so"; do
        [ -e "$_root/$_f" ] && rm -f "$_root/$_f"
    done
    _manifest="$_root/var/lib/lfa-usb/nodes"
    if [ -f "$_manifest" ]; then
        while IFS= read -r _f; do
            case "$_f" in /dev/*) rm -f "$_root$_f" 2>/dev/null || true ;; esac
        done < "$_manifest"
        rm -f "$_manifest" 2>/dev/null || true
    fi
    if [ -L "$_root/run/lfa-usb" ]; then
        rm -f "$_root/run/lfa-usb"
    fi
    lfa_usb_conf_set USB_SHIMS 0
    echo "[*] USB helpers removed from $_id."
    echo "    The published bridge in $LFA_USB_BRIDGE is unchanged."
}

lfa_usb_exec() {
    local _inst="" _user="" _root _id _dev _cwd="" _perm=1
    local -a _cmd=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --root) _user="root"; shift ;;
            --cwd) _cwd="${2:-}"; shift 2 ;;
            --no-permission) _perm=0; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            --) shift; break ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) break ;;
        esac
    done
    [ $# -gt 0 ] || { echo "Usage: lfa usb exec DEV -- COMMAND..." >&2; return 2; }
    _dev="$(lfa_usb_normalize_dev "$1")"
    shift
    # Options may follow DEV, as long as they come before `--` or the command.
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --root) _user="root"; shift ;;
            --cwd) _cwd="${2:-}"; shift 2 ;;
            --no-permission) _perm=0; shift ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    _cmd=("$@")
    [ ${#_cmd[@]} -gt 0 ] || {
        echo "Usage: lfa usb exec DEV -- COMMAND..." >&2
        return 2
    }
    lfa_usb_api_ok || {
        echo "[!] termux-usb is not installed. Run: lfa android install" >&2
        return 1
    }
    if ! lfa_usb_export_ok; then
        echo "[!] This termux-api cannot export a USB descriptor (-E)." >&2
        echo "    Update it first: pkg upgrade termux-api" >&2
        return 1
    fi
    lfa_usb_pick_instance "$_inst" || return 1
    _id="$INSTANCE_NAME"
    _root="$(pd_rootfs "$_id")"
    command -v proot-distro >/dev/null 2>&1 || {
        echo "[!] proot-distro is required to enter the guest." >&2
        return 1
    }
    [ -n "$_user" ] || _user="$(lfa_appimage_user "$_id")"
    lfa_usb_stage_desc "$_root" 2>/dev/null || true
    if [ -z "$_cwd" ]; then
        _cwd="/home/$_user"
        [ -d "$_root$_cwd" ] || _cwd="/"
    fi
    lfa_usb_write_callback || return 1
    mkdir -p "$LFA_USB_BRIDGE" 2>/dev/null || true
    local _run_host="$LFA_USB_BRIDGE/run-$$.sh"
    local _run_guest="/tmp/lfa-usb/run-$$.sh"
    {
        printf '#!/bin/bash\n'
        printf '# Generated by lfa usb exec; removed when this command exits.\n'
        printf 'exec'
        printf ' %q' "${_cmd[@]}"
        printf '\n'
    } > "$_run_host" || return 1
    chmod 700 "$_run_host" 2>/dev/null || true
    local _perm_flag="-r"
    [ "$_perm" = "1" ] || _perm_flag=""
    local _rc=0
    if [ -n "$_perm_flag" ]; then
        LFA_USB_MODE=exec \
        LFA_USB_INSTANCE="$_id" \
        LFA_USB_USER="$_user" \
        LFA_USB_PD_FLAGS="$(pd_login_flags)" \
        LFA_USB_RUN_SCRIPT="$_run_guest" \
        LFA_USB_CWD="$_cwd" \
        LFA_USB_PATH="$_dev" \
            termux-usb -r -E -e "$LFA_USB_CALLBACK" "$_dev" || _rc=$?
    else
        LFA_USB_MODE=exec \
        LFA_USB_INSTANCE="$_id" \
        LFA_USB_USER="$_user" \
        LFA_USB_PD_FLAGS="$(pd_login_flags)" \
        LFA_USB_RUN_SCRIPT="$_run_guest" \
        LFA_USB_CWD="$_cwd" \
        LFA_USB_PATH="$_dev" \
            termux-usb -E -e "$LFA_USB_CALLBACK" "$_dev" || _rc=$?
    fi
    rm -f "$_run_host" 2>/dev/null || true
    return "$_rc"
}

lfa_usb_print_changes() {  # $1 old list, $2 new list
    local _old="$1" _new="$2" _path _bd _bus _dev _line
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        grep -Fxq -- "$_path" <<< "$_old" 2>/dev/null && continue
        _bd="$(lfa_usb_bus_dev "$_path")"
        _bus="$(lfa_usb_pad3 "${_bd%% *}")"
        _dev="$(lfa_usb_pad3 "${_bd##* }")"
        _line="$(lfa_usb_line_for "$_bus" "$_dev" 2>/dev/null || true)"
        [ -n "$_line" ] || _line="$_path"
        echo "[+] $_line"
        printf '%s added %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$_path" \
            >> "$LFA_USB_BRIDGE/events.log" 2>/dev/null || true
    done <<< "$_new"
    while IFS= read -r _path; do
        [ -n "$_path" ] || continue
        grep -Fxq -- "$_path" <<< "$_new" 2>/dev/null && continue
        echo "[-] removed $_path"
        printf '%s removed %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$_path" \
            >> "$LFA_USB_BRIDGE/events.log" 2>/dev/null || true
    done <<< "$_old"
}

lfa_usb_watch() {
    local _interval=3 _count=0 _i=0 _prev _cur
    while [ $# -gt 0 ]; do
        case "$1" in
            --interval|-n) _interval="${2:-3}"; shift 2 ;;
            --count) _count="${2:-0}"; shift 2 ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    case "$_interval" in ''|*[!0-9]*) _interval=3 ;; esac
    case "$_count" in ''|*[!0-9]*) _count=0 ;; esac
    lfa_usb_api_ok || {
        echo "[!] termux-usb is not installed. Run: lfa android install" >&2
        return 1
    }
    mkdir -p "$LFA_USB_BRIDGE" 2>/dev/null || true
    (
        trap 'exit 130' INT TERM
        _prev="$(lfa_usb_live_names)"
        lfa_usb_refresh >/dev/null 2>&1 || true
        echo "Watching USB devices every ${_interval}s (Ctrl-C to stop)..."
        lfa_usb_print_changes "" "$_prev"
        while :; do
            if [ "$_count" -gt 0 ] && [ "$_i" -ge "$_count" ]; then
                break
            fi
            sleep "$_interval"
            _cur="$(lfa_usb_live_names)"
            if [ "$_cur" != "$_prev" ]; then
                lfa_usb_refresh >/dev/null 2>&1 || true
                lfa_usb_print_changes "$_prev" "$_cur"
                _prev="$_cur"
            fi
            _i=$((_i + 1))
        done
    )
}

# ------------------------------------------------------------
# USB session: a real usbfs view inside the guest.
#
# proot cannot create device nodes, but it does inherit descriptors.
# Termux:API hands the callback the real usbfs descriptor; this session
# duplicates it as /dev/bus/usb/BBB/DDD with a small preload, writes a
# sysfs-shaped tree from the real descriptors and binds it over
# /sys/bus/usb/devices, so unmodified libusb tools work:
#
#   * open() on the node returns the inherited usbfs descriptor, and every
#     ioctl/read/write then talks to the real kernel driver;
#   * statfs() on /sys reports SYSFS_MAGIC, because libudev refuses
#     syspaths on other filesystems;
#   * the udev hotplug monitor becomes an idle pipe, because Android has
#     no udev daemon to talk to.
#
# Nothing is simulated at the transfer level: descriptors and endpoints
# are read from the device, and data goes through the real descriptor.
# ------------------------------------------------------------
LFA_USB_SHIM_SRC="$LFA_DIR/lib/lfa-usb-node.c"
LFA_USB_TTY_SRC="$LFA_DIR/lib/lfa-usb-tty.py"
LFA_USB_BUILD="$LFA_USB_CACHE/build"
LFA_USB_SHIM_GUEST="/usr/local/lib/lfa-usb-node.so"
LFA_USB_TTY_GUEST="/usr/local/libexec/lfa-usb-tty.py"

lfa_usb_elf_arch() {  # $1 = rootfs; prints aarch64, arm, x86_64, i386, unknown
    local _root="$1" _elf _class _lo _hi _mach
    local -a _bytes=()
    _elf="$_root/bin/sh"
    [ -r "$_elf" ] || _elf="$_root/usr/bin/sh"
    [ -r "$_elf" ] || { echo unknown; return 0; }
    mapfile -t _bytes < <(od -An -tu1 -N20 "$_elf" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' || true)
    if [ "${#_bytes[@]}" -lt 20 ]; then
        echo unknown
        return 0
    fi
    _class="${_bytes[4]}"
    _lo="${_bytes[18]}"
    _hi="${_bytes[19]}"
    _mach=$((_lo + _hi * 256))
    case "$_class:$_mach" in
        2:183) echo aarch64 ;;
        1:40) echo arm ;;
        2:62) echo x86_64 ;;
        1:3) echo i386 ;;
        *) echo unknown ;;
    esac
}

lfa_usb_build_shim() {  # $1 = rootfs; prints the built .so path
    local _root="$1" _arch _out _cc="" _target="" _host
    _arch="$(lfa_usb_elf_arch "$_root")"
    [ "$_arch" != unknown ] || return 1
    [ -f "$LFA_USB_SHIM_SRC" ] || return 1
    mkdir -p "$LFA_USB_BUILD" 2>/dev/null || return 1
    _out="$LFA_USB_BUILD/lfa-usb-node-$_arch.so"
    if [ -s "$_out" ] && [ "$_out" -nt "$LFA_USB_SHIM_SRC" ]; then
        printf '%s\n' "$_out"
        return 0
    fi
    if command -v clang >/dev/null 2>&1; then
        _cc="clang"
        case "$_arch" in
            aarch64) _target="--target=aarch64-linux-gnu" ;;
            arm) _target="--target=armv7a-linux-gnueabihf" ;;
            x86_64) _target="--target=x86_64-linux-gnu" ;;
            i386) _target="--target=i686-linux-gnu" ;;
        esac
    elif command -v cc >/dev/null 2>&1; then
        _host="$(uname -m)"
        case "$_host" in
            arm64|arm64-v8a) _host=aarch64 ;;
            armv7l|armv8l) _host=arm ;;
        esac
        [ "$_host" = "$_arch" ] && _cc="cc"
    fi
    if [ -n "$_cc" ]; then
        # shellcheck disable=SC2086  # the target flag is optional
        "$_cc" $_target -shared -fPIC -nostdlib -fno-builtin -O2 \
            -fno-stack-protector -Wl,-soname,liblfa-usb-node.so \
            -o "$_out" "$LFA_USB_SHIM_SRC" >/dev/null 2>&1 || rm -f "$_out"
    fi
    if [ ! -s "$_out" ] && [ -s "$LFA_DIR/lib/prebuilt/lfa-usb-node-$_arch.so" ]; then
        cp -f "$LFA_DIR/lib/prebuilt/lfa-usb-node-$_arch.so" "$_out" 2>/dev/null || true
    fi
    [ -s "$_out" ] || return 1
    printf '%s\n' "$_out"
}

lfa_usb_stage_shim() {  # $1 = rootfs, $2 = built .so
    local _root="$1" _so="$2" _dst
    [ -s "$_so" ] || return 1
    _dst="$_root$LFA_USB_SHIM_GUEST"
    mkdir -p "$(dirname "$_dst")" 2>/dev/null || return 1
    cp -f "$_so" "$_dst" 2>/dev/null || return 1
    chmod 644 "$_dst" 2>/dev/null || true
}

lfa_usb_stage_tty() {  # $1 = rootfs
    local _dst="$1$LFA_USB_TTY_GUEST"
    [ -f "$LFA_USB_TTY_SRC" ] || return 1
    mkdir -p "$(dirname "$_dst")" 2>/dev/null || return 1
    cp -f "$LFA_USB_TTY_SRC" "$_dst" 2>/dev/null || return 1
    chmod 755 "$_dst" 2>/dev/null || true
}

lfa_usb_prepare_nodes() {  # $1 rootfs, $2 bus, $3 dev, $4 tty(0/1)
    local _root="$1" _bus="$2" _dev="$3" _tty="${4:-0}"
    local _manifest _old _dir _node _ttynode
    [ -d "$_root/dev" ] || return 0
    _manifest="$_root/var/lib/lfa-usb/nodes"
    mkdir -p "$(dirname "$_manifest")" 2>/dev/null || true
    if [ -f "$_manifest" ]; then
        while IFS= read -r _old; do
            [ -n "$_old" ] || continue
            case "$_old" in /dev/*) rm -f "$_root$_old" 2>/dev/null || true ;; esac
        done < "$_manifest"
    fi
    : > "$_manifest" 2>/dev/null || true
    _dir="$_root/dev/bus/usb/$_bus"
    mkdir -p "$_dir" 2>/dev/null || true
    _node="$_dir/$_dev"
    if [ ! -e "$_node" ]; then
        if : > "$_node" 2>/dev/null; then
            chmod 666 "$_node" 2>/dev/null || true
            printf '/dev/bus/usb/%s/%s\n' "$_bus" "$_dev" >> "$_manifest" 2>/dev/null || true
        fi
    fi
    # proot-distro v5+ binds the host /dev over the guest /dev, hiding the
    # placeholder above. Keep the same node in a Termux-side shadow tree and
    # bind `<shadow>/bus/usb` over /dev/bus/usb, which wins over that bind.
    _shadow="$LFA_USB_BRIDGE/dev/bus/usb/$_bus"
    if mkdir -p "$_shadow" 2>/dev/null && : > "$_shadow/$_dev" 2>/dev/null; then
        chmod 666 "$_shadow/$_dev" 2>/dev/null || true
    fi
    if [ "$_tty" = 1 ]; then
        _ttynode="$_root/dev/ttyUSB0"
        if [ ! -e "$_ttynode" ] && [ ! -L "$_ttynode" ]; then
            if : > "$_ttynode" 2>/dev/null; then
                chmod 666 "$_ttynode" 2>/dev/null || true
                printf '/dev/ttyUSB0\n' >> "$_manifest" 2>/dev/null || true
            fi
        fi
    fi
    return 0
}

lfa_usb_write_script() {  # $1 = host path, $2 = preload (may be empty), rest = command
    local _dst="$1" _preload="${2:-}"
    shift 2
    [ $# -gt 0 ] || return 1
    {
        printf '#!/bin/bash\n'
        printf '# Generated by lfa usb; deleted when the session ends.\n'
        # Set the preload here, inside the guest. proot-distro v5 removes
        # LD_PRELOAD from the environment it passes to proot, so setting it
        # only in the callback's /bin/sh would lose it.
        if [ -n "$_preload" ]; then
            printf 'export LD_PRELOAD=%q\n' "$_preload"
        fi
        printf 'exec'
        printf ' %q' "$@"
        printf '\n'
    } > "$_dst" 2>/dev/null || return 1
    chmod 700 "$_dst" 2>/dev/null || true
}

lfa_usb_default_dev() {
    local _path=""
    [ -s "$LFA_USB_BRIDGE/devices.tsv" ] || lfa_usb_refresh >/dev/null 2>&1 || true
    _path="$(awk -F '\t' '!/^#/ && NF >= 3 { print $3; exit }' \
        "$LFA_USB_BRIDGE/devices.tsv" 2>/dev/null || true)"
    printf '%s' "$_path"
}

lfa_usb_install_esptool() {  # $1 = optional instance
    local _id _user _root _rc=0
    lfa_usb_pick_instance "${1:-}" || return 1
    _id="$INSTANCE_NAME"
    _user="$(lfa_appimage_user "$_id")"
    _root="$(pd_rootfs "$_id")"
    echo "[*] Installing esptool in $_id (pip)..."
    # shellcheck disable=SC2046,SC2086  # pd_login_flags is a word list
    proot-distro login $(pd_login_flags) "$_id" --user "$_user" --shared-tmp -- \
        /bin/sh -c '
            if command -v esptool.py >/dev/null 2>&1 || command -v esptool >/dev/null 2>&1; then
                echo "esptool is already installed."
                exit 0
            fi
            command -v python3 >/dev/null 2>&1 || {
                echo "python3 is missing in this distribution." >&2
                exit 1
            }
            python3 -m pip install --upgrade esptool 2>/dev/null ||
                python3 -m pip install --break-system-packages --upgrade esptool
        ' || _rc=$?
    if [ "$_rc" -ne 0 ]; then
        echo "[!] esptool install failed in $_id." >&2
        echo "    Install python3 and pip first, or run inside the guest:" >&2
        echo "      python3 -m pip install esptool" >&2
        return "$_rc"
    fi
    echo "[*] esptool is ready in $_id."
    return 0
}

lfa_usb_attach() {
    local _inst="" _user="" _root _id _dev="" _cwd="" _perm=1 _sysfs=1 _rc=0
    local _devbind=""
    local _bd _bus _devn _speed _shim _preload="" _bind="" _prep_rc=0
    local _script_host _script_guest
    local -a _cmd=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --root) _user="root"; shift ;;
            --cwd) _cwd="${2:-}"; shift 2 ;;
            --device) _dev="${2:-}"; shift 2 ;;
            --no-permission) _perm=0; shift ;;
            --no-sysfs) _sysfs=0; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            --) shift; break ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) break ;;
        esac
    done
    if [ -z "$_dev" ] && [ $# -gt 0 ]; then
        case "$1" in
            /dev/bus/usb/*|[0-9]*/*|[0-9]*:*|[0-9]*-[0-9]*) _dev="$1"; shift ;;
        esac
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --root) _user="root"; shift ;;
            --cwd) _cwd="${2:-}"; shift 2 ;;
            --device) _dev="${2:-}"; shift 2 ;;
            --no-permission) _perm=0; shift ;;
            --no-sysfs) _sysfs=0; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            --) shift; break ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) break ;;
        esac
    done
    _cmd=("$@")
    if [ -z "$_dev" ]; then
        _dev="$(lfa_usb_default_dev)"
        [ -n "$_dev" ] || {
            echo "[!] No USB device is visible. Connect one and run: lfa usb refresh" >&2
            return 1
        }
        echo "[*] Using $_dev (the only visible device)."
    fi
    _dev="$(lfa_usb_normalize_dev "$_dev")"
    _bd="$(lfa_usb_bus_dev "$_dev")"
    if [ -z "$_bd" ]; then
        echo "[!] '$_dev' is not a usbdevfs device path." >&2
        return 2
    fi
    _bus="$(lfa_usb_pad3 "${_bd%% *}")"
    _devn="$(lfa_usb_pad3 "${_bd##* }")"
    lfa_usb_api_ok || {
        echo "[!] termux-usb is not installed. Run: lfa android install" >&2
        return 1
    }
    if ! lfa_usb_export_ok; then
        echo "[!] This termux-api cannot export a USB descriptor (-E)." >&2
        echo "    Update it first: pkg upgrade termux-api" >&2
        return 1
    fi
    lfa_usb_pick_instance "$_inst" || return 1
    _id="$INSTANCE_NAME"
    _root="$(pd_rootfs "$_id")"
    [ -d "$_root" ] || { echo "[!] Rootfs missing for $_id." >&2; return 1; }
    command -v proot-distro >/dev/null 2>&1 || {
        echo "[!] proot-distro is required to enter the guest." >&2
        return 1
    }
    [ -n "$_user" ] || _user="$(lfa_appimage_user "$_id")"
    if [ -z "$_cwd" ]; then
        _cwd="/home/$_user"
        [ -d "$_root$_cwd" ] || _cwd="/"
    fi

    lfa_usb_stage_desc "$_root" || return 1
    lfa_usb_stage_tty "$_root" 2>/dev/null || true
    _shim="$(lfa_usb_build_shim "$_root" 2>/dev/null || true)"
    if [ -n "$_shim" ] && lfa_usb_stage_shim "$_root" "$_shim"; then
        _preload="$LFA_USB_SHIM_GUEST"
    else
        echo "[!] The usbfs preload could not be built for $_id." >&2
        echo "    Install clang in Termux (pkg install clang), or use the raw" >&2
        echo "    descriptor mode: lfa usb exec $_bus/$_devn -- lfa-usb desc" >&2
    fi
    lfa_usb_write_callback || return 1
    mkdir -p "$LFA_USB_BRIDGE" 2>/dev/null || true
    lfa_usb_prepare_nodes "$_root" "$_bus" "$_devn" 0
    [ -f "$LFA_USB_BRIDGE/dev/bus/usb/$_bus/$_devn" ] && \
        _devbind="$LFA_USB_BRIDGE/dev/bus/usb:/dev/bus/usb"

    _speed="$(cat "$LFA_USB_BRIDGE/sys/${_bus}-${_devn}/speed" 2>/dev/null || true)"
    case "$_speed" in ''|*[!0-9]*) _speed=480 ;; esac

    if [ "$_sysfs" = 1 ] && [ -n "$_preload" ]; then
        rm -rf "$LFA_USB_BRIDGE/session-sys" 2>/dev/null || true
        rm -f "$LFA_USB_BRIDGE/prep-$_bus-$_devn.json" \
              "$LFA_USB_BRIDGE/prep-$_bus-$_devn.tsv" \
              "$LFA_USB_BRIDGE/prep-$_bus-$_devn.bin" 2>/dev/null || true
        (
            export LFA_USB_MODE=prep
            export LFA_USB_INSTANCE="$_id"
            export LFA_USB_USER="$_user"
            LFA_USB_PD_FLAGS="$(pd_login_flags)"
            export LFA_USB_PD_FLAGS
            export LFA_USB_OUT="/tmp/lfa-usb/prep-$_bus-$_devn.json"
            export LFA_USB_TSV="/tmp/lfa-usb/prep-$_bus-$_devn.tsv"
            export LFA_USB_BLOB="/tmp/lfa-usb/prep-$_bus-$_devn.bin"
            export LFA_USB_SYSFS_OUT="/tmp/lfa-usb/session-sys"
            export LFA_USB_BUS="$_bus"
            export LFA_USB_DEV="$_devn"
            export LFA_USB_PATH="$_dev"
            export LFA_USB_SPEED="$_speed"
            lfa_android_timeout 120 termux-usb -r -E -e "$LFA_USB_CALLBACK" "$_dev"
        ) > "$LFA_USB_BRIDGE/prep.log" 2>&1 || _prep_rc=$?
        if [ -d "$LFA_USB_BRIDGE/session-sys" ] && \
           [ -n "$(ls -A "$LFA_USB_BRIDGE/session-sys" 2>/dev/null)" ]; then
            _bind="$LFA_USB_BRIDGE/session-sys:/sys/bus/usb/devices"
        else
            echo "[!] Descriptors could not be read; libusb will not see the device." >&2
            if [ -s "$LFA_USB_BRIDGE/prep.log" ]; then
                sed 's/^/    /' "$LFA_USB_BRIDGE/prep.log" >&2
            fi
        fi
    fi

    if [ ${#_cmd[@]} -eq 0 ]; then
        _cmd=(/bin/bash -l)
    fi
    _script_host="$LFA_USB_BRIDGE/run-$$.sh"
    _script_guest="/tmp/lfa-usb/run-$$.sh"
    lfa_usb_write_script "$_script_host" "$_preload" "${_cmd[@]}" || return 1

    echo "[*] USB session for $_id"
    echo "    node:    /dev/bus/usb/$_bus/$_devn"
    if [ -n "$_bind" ]; then
        echo "    sysfs:   /sys/bus/usb/devices (real descriptors)"
    else
        echo "    sysfs:   not available in this session"
    fi
    if [ -n "$_preload" ]; then
        echo "    preload: $LFA_USB_SHIM_GUEST"
    fi
    echo "    Try:     lsusb; lsusb -v -d \$(lsusb | awk '{print \$6}')"
    echo ""

    (
        export LFA_USB_MODE=exec
        export LFA_USB_INSTANCE="$_id"
        export LFA_USB_USER="$_user"
        LFA_USB_PD_FLAGS="$(pd_login_flags)"
        export LFA_USB_PD_FLAGS
        export LFA_USB_RUN_SCRIPT="$_script_guest"
        export LFA_USB_CWD="$_cwd"
        export LFA_USB_PATH="$_dev"
        export LFA_USB_BUS="$_bus"
        export LFA_USB_DEV="$_devn"
        export LFA_USB_PRELOAD="$_preload"
        export LFA_USB_BIND="$_bind"
        export LFA_USB_DEVBIND="$_devbind"
        if [ "$_perm" = "1" ] && { [ -z "$_bind" ] || [ "$_prep_rc" -ne 0 ]; }; then
            lfa_android_timeout 0 termux-usb -r -E -e "$LFA_USB_CALLBACK" "$_dev"
        else
            lfa_android_timeout 0 termux-usb -E -e "$LFA_USB_CALLBACK" "$_dev"
        fi
    ) || _rc=$?
    rm -f "$_script_host" 2>/dev/null || true
    return "$_rc"
}

lfa_usb_tty() {
    local _inst="" _user="" _root _id _dev="" _cwd="" _perm=1 _baud=115200 _rc=0
    local _devbind=""
    local _bd _bus _devn _shim _preload="" _script_host _script_guest
    local -a _cmd=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --root) _user="root"; shift ;;
            --cwd) _cwd="${2:-}"; shift 2 ;;
            --device) _dev="${2:-}"; shift 2 ;;
            --baud) _baud="${2:-}"; shift 2 ;;
            --no-permission) _perm=0; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            --) shift; break ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) break ;;
        esac
    done
    if [ -z "$_dev" ] && [ $# -gt 0 ]; then
        case "$1" in
            /dev/bus/usb/*|[0-9]*/*|[0-9]*:*|[0-9]*-[0-9]*) _dev="$1"; shift ;;
        esac
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --root) _user="root"; shift ;;
            --cwd) _cwd="${2:-}"; shift 2 ;;
            --device) _dev="${2:-}"; shift 2 ;;
            --baud) _baud="${2:-}"; shift 2 ;;
            --no-permission) _perm=0; shift ;;
            -h|--help) lfa_usb_usage; return 0 ;;
            --) shift; break ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) break ;;
        esac
    done
    _cmd=("$@")
    case "$_baud" in ''|*[!0-9]*) echo "[!] --baud must be a number." >&2; return 2 ;; esac
    if [ -z "$_dev" ]; then
        _dev="$(lfa_usb_default_dev)"
        [ -n "$_dev" ] || {
            echo "[!] No USB device is visible. Connect one and run: lfa usb refresh" >&2
            return 1
        }
        echo "[*] Using $_dev (the only visible device)."
    fi
    _dev="$(lfa_usb_normalize_dev "$_dev")"
    _bd="$(lfa_usb_bus_dev "$_dev")"
    if [ -z "$_bd" ]; then
        echo "[!] '$_dev' is not a usbdevfs device path." >&2
        return 2
    fi
    _bus="$(lfa_usb_pad3 "${_bd%% *}")"
    _devn="$(lfa_usb_pad3 "${_bd##* }")"
    lfa_usb_api_ok || {
        echo "[!] termux-usb is not installed. Run: lfa android install" >&2
        return 1
    }
    if ! lfa_usb_export_ok; then
        echo "[!] This termux-api cannot export a USB descriptor (-E)." >&2
        echo "    Update it first: pkg upgrade termux-api" >&2
        return 1
    fi
    lfa_usb_pick_instance "$_inst" || return 1
    _id="$INSTANCE_NAME"
    _root="$(pd_rootfs "$_id")"
    [ -d "$_root" ] || { echo "[!] Rootfs missing for $_id." >&2; return 1; }
    [ -n "$_user" ] || _user="$(lfa_appimage_user "$_id")"
    if [ -z "$_cwd" ]; then
        _cwd="/home/$_user"
        [ -d "$_root$_cwd" ] || _cwd="/"
    fi
    lfa_usb_stage_desc "$_root" || return 1
    lfa_usb_stage_tty "$_root" || {
        echo "[!] lib/lfa-usb-tty.py is missing; reinstall Linux-for-Android." >&2
        return 1
    }
    _shim="$(lfa_usb_build_shim "$_root" 2>/dev/null || true)"
    if [ -n "$_shim" ] && lfa_usb_stage_shim "$_root" "$_shim"; then
        _preload="$LFA_USB_SHIM_GUEST"
    else
        echo "[!] The usbfs preload could not be built; /dev/ttyUSB0 will not" >&2
        echo "    be visible in this session (auto-reset also needs it)." >&2
    fi
    lfa_usb_write_callback || return 1
    mkdir -p "$LFA_USB_BRIDGE" 2>/dev/null || true
    lfa_usb_prepare_nodes "$_root" "$_bus" "$_devn" 1
    [ -f "$LFA_USB_BRIDGE/dev/bus/usb/$_bus/$_devn" ] && \
        _devbind="$LFA_USB_BRIDGE/dev/bus/usb:/dev/bus/usb"

    _script_host="$LFA_USB_BRIDGE/tty-$$.sh"
    _script_guest="/tmp/lfa-usb/tty-$$.sh"
    {
        printf '#!/bin/bash\n'
        printf '# Generated by lfa usb tty; deleted when the session ends.\n'
        # proot-distro v5 drops LD_PRELOAD from the environment; set it in
        # the guest so the tty node map and DTR/RTS forwarding work.
        [ -n "$_preload" ] && printf 'export LD_PRELOAD=%q\n' "$_preload"
        printf 'exec python3 %q --fd "$TERMUX_USB_FD" --node /dev/ttyUSB0 --baud %q --' \
            "$LFA_USB_TTY_GUEST" "$_baud"
        [ ${#_cmd[@]} -gt 0 ] && printf ' %q' "${_cmd[@]}"
        printf '\n'
    } > "$_script_host" 2>/dev/null || return 1
    chmod 700 "$_script_host" 2>/dev/null || true

    echo "[*] USB serial session for $_id"
    echo "    device: $_dev"
    echo "    node:   /dev/ttyUSB0 (pty bridged to the real bulk endpoints)"
    echo "    baud:   $_baud"
    echo ""

    (
        export LFA_USB_MODE=exec
        export LFA_USB_INSTANCE="$_id"
        export LFA_USB_USER="$_user"
        LFA_USB_PD_FLAGS="$(pd_login_flags)"
        export LFA_USB_PD_FLAGS
        export LFA_USB_RUN_SCRIPT="$_script_guest"
        export LFA_USB_CWD="$_cwd"
        export LFA_USB_PATH="$_dev"
        export LFA_USB_BUS="$_bus"
        export LFA_USB_DEV="$_devn"
        export LFA_USB_PRELOAD="$_preload"
        export LFA_USB_DEVBIND="$_devbind"
        if [ "$_perm" = "1" ]; then
            lfa_android_timeout 0 termux-usb -r -E -e "$LFA_USB_CALLBACK" "$_dev"
        else
            lfa_android_timeout 0 termux-usb -E -e "$LFA_USB_CALLBACK" "$_dev"
        fi
    ) || _rc=$?
    rm -f "$_script_host" 2>/dev/null || true
    return "$_rc"
}

lfa_usb_flash() {
    local _install=0 _baud=115200 _inst="" _dev="" _rc=0 _i=0 _a
    local _wrapper_host _wrapper_guest _port_seen=0
    local -a _args=() _tty_args=() _fwd=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --install) _install=1; shift ;;
            --baud) _baud="${2:-}"; shift 2 ;;
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --device) _dev="${2:-}"; shift 2 ;;
            -h|--help) lfa_usb_flash_usage; return 0 ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    _args+=("$@")
    if [ "$_install" = "1" ]; then
        lfa_usb_install_esptool "$_inst" || return 1
        if [ ${#_args[@]} -eq 0 ]; then
            return 0
        fi
    fi
    if [ ${#_args[@]} -eq 0 ]; then
        lfa_usb_flash_usage
        return 1
    fi
    _fwd=()
    _i=0
    while [ "$_i" -lt "${#_args[@]}" ]; do
        _a="${_args[$_i]}"
        case "$_a" in
            --port|-p|--port=*) _port_seen=1; _fwd+=("$_a") ;;
            --baud) _baud="${_args[$((_i + 1))]:-$_baud}"; _i=$((_i + 1)) ;;
            --baud=*) _baud="${_a#--baud=}" ;;
            *) _fwd+=("$_a") ;;
        esac
        _i=$((_i + 1))
    done
    case "$_baud" in ''|*[!0-9]*) echo "[!] --baud must be a number." >&2; return 2 ;; esac
    _args=("${_fwd[@]}")
    if [ ${#_args[@]} -eq 0 ]; then
        lfa_usb_flash_usage
        return 1
    fi
    mkdir -p "$LFA_USB_BRIDGE" 2>/dev/null || true
    _wrapper_host="$LFA_USB_BRIDGE/esptool-$$.sh"
    _wrapper_guest="/tmp/lfa-usb/esptool-$$.sh"
    {
        printf '#!/bin/bash\n'
        printf 'if command -v esptool.py >/dev/null 2>&1; then _esptool=esptool.py\n'
        printf 'elif command -v esptool >/dev/null 2>&1; then _esptool=esptool\n'
        printf 'else\n'
        printf '    echo "lfa: esptool is not installed in the guest." >&2\n'
        printf '    echo "     Run in Termux: lfa usb flash --install" >&2\n'
        printf '    exit 1\n'
        printf 'fi\n'
        printf 'case "$("$_esptool" version 2>/dev/null | head -n1)" in\n'
        printf '    *v5*|*" 5."*) _sep=- ;;\n'
        printf '    *) _sep=_ ;;\n'
        printf 'esac\n'
        printf '_first="${1:-}"\n'
        printf '[ $# -gt 0 ] && shift\n'
        printf 'case "$_first" in\n'
        printf '    probe|id) _first="flash${_sep}id" ;;\n'
        printf '    write) _first="write${_sep}flash" ;;\n'
        printf '    verify) _first="verify${_sep}flash" ;;\n'
        printf '    erase) _first="erase${_sep}flash" ;;\n'
        printf '    read) _first="read${_sep}flash" ;;\n'
        printf 'esac\n'
        printf '[ -n "$_first" ] && set -- "$_first" "$@"\n'
        printf 'exec "$_esptool"'
        if [ "$_port_seen" = 0 ]; then
            printf ' --port /dev/ttyUSB0 --baud %q' "$_baud"
        fi
        printf ' "$@"\n'
    } > "$_wrapper_host" 2>/dev/null || return 1
    chmod 700 "$_wrapper_host" 2>/dev/null || true

    _tty_args=(--baud "$_baud")
    [ -n "$_inst" ] && _tty_args+=(-i "$_inst")
    [ -n "$_dev" ] && _tty_args+=(--device "$_dev")
    lfa_usb_tty "${_tty_args[@]}" -- /bin/bash "$_wrapper_guest" "${_args[@]}" || _rc=$?
    rm -f "$_wrapper_host" 2>/dev/null || true
    return "$_rc"
}

lfa_usb_flash_usage() {
    cat <<'FLASHHELP'
Usage: lfa usb flash [--install] [--device DEV] [--baud N] ARGS...

Flash ESP32/ESP8266 firmware through a real serial port in the guest.
The USB endpoints are bridged to /dev/ttyUSB0, so this runs esptool inside
the distribution, exactly like on a desktop Linux machine.

  --install           install esptool inside the guest with pip
  --device DEV        pick the Android device (default: the only one)
  --baud N            baud rate for the bridge and esptool (default 115200)
  probe               read the chip ID (esptool flash_id)
  write ARGS...       esptool write-flash arguments
  read_mac, erase_flash, ...   any other esptool command

Examples:
  lfa usb flash --install
  lfa usb flash probe
  lfa usb flash write 0x0 /sdcard/firmware.bin
  lfa usb flash write 0x0 /sdcard/boot.bin 0x10000 /sdcard/app.bin
  lfa usb flash --baud 460800 write 0x0 /sdcard/firmware.bin

Firmware paths are guest paths. /sdcard is shared with the guest, so it is
the easiest place to keep a .bin file.

If the board does not reset automatically, hold BOOT while plugging it in;
esptool still synchronises and flashes.
FLASHHELP
}
lfa_cli_usb() {
    local _sub="${1:-status}"
    [ $# -gt 0 ] && shift || true
    case "$_sub" in
        status) lfa_usb_status "$@" ;;
        list|ls) lfa_usb_list "$@" ;;
        refresh)
            local _n
            _n="$(lfa_usb_refresh)" || return $?
            echo "USB bridge updated: $_n device(s) in $LFA_USB_BRIDGE" ;;
        scan) lfa_usb_scan "$@" ;;
        watch|monitor) lfa_usb_watch "$@" ;;
        enable|install) lfa_usb_enable "$@" ;;
        disable|remove) lfa_usb_disable "$@" ;;
        exec|run) lfa_usb_exec "$@" ;;
        attach|shell) lfa_usb_attach "$@" ;;
        tty|serial) lfa_usb_tty "$@" ;;
        flash) lfa_usb_flash "$@" ;;
        help|-h|--help) lfa_usb_usage ;;
        *) echo "Unknown usb command: $_sub" >&2; lfa_usb_usage >&2; return 2 ;;
    esac
}

# The CLI runs from the private runtime copy, not from the generated
# lfa-lib.sh. Keep these two helpers here as well so `lfa status` works on a
# fresh install (they are also written into lfa-lib.sh for the launchers).
lfa_pid_matches() {   # $1 = pid, rest = patterns that must appear in cmdline
    local _pid="$1" _cmd _pat
    shift
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)" || return 1
    [ -n "$_cmd" ] || return 1
    for _pat in "$@"; do
        case "$_cmd" in *"$_pat"*) return 0 ;; esac
    done
    return 1
}

# Termux:X11 is global, but a desktop belongs to one instance. A running
# X server must not make every installed distro look like it is running.
lfa_instance_session_running() {  # $1 = instance
    local _inst="$1" _c _cmd
    [ -n "$_inst" ] || return 1
    for _c in /proc/[0-9]*/cmdline; do
        [ -r "$_c" ] || continue
        _cmd="$(tr '\0' ' ' < "$_c" 2>/dev/null)" || continue
        case "$_cmd" in
            *"/containers/$_inst/"*|*"/installed-rootfs/$_inst/"*)
                # A terminal login also contains the instance path. Only
                # count a real desktop session for the X11 running state.
                case "$_cmd" in
                    *startxfce4*|*startlxde*|*mate-session*|*gnome-shell*|*start-gnome-session*) return 0 ;;
                esac ;;
        esac
    done
    return 1
}

lfa_cli_status_one() {  # $1 = instance, $2 = json
    local _inst="$1" _json="${2:-0}" _conf _d _de _srv _auto _pid _run="none"
    _conf="$(pd_conf "$_inst" 2>/dev/null)"
    _d=""; _de=""; _srv="none"; _auto="none"
    if [ -f "$_conf" ]; then
        # shellcheck disable=SC1090
        { IFS= read -r _d; IFS= read -r _de; IFS= read -r _srv; IFS= read -r _auto; } < <(
            . "$_conf" 2>/dev/null
            printf '%s\n%s\n%s\n%s\n' "${DISTRO:-}" "${DE:-none}" "${SERVER:-none}" "${AUTOSTART_SERVER:-none}"
        )
    fi
    if [ -f "$PREFIX/tmp/lfa-vnc-$_inst.pid" ]; then
        _pid="$(cat "$PREFIX/tmp/lfa-vnc-$_inst.pid" 2>/dev/null || true)"
        if lfa_pid_matches "$_pid" "proot" "Xvnc"; then _run="vnc"; fi
    fi
    if [ "$_run" = "none" ] && \
       pgrep -f '^termux-x11 .* :1( |$)' >/dev/null 2>&1 && \
       lfa_instance_session_running "$_inst"; then
        _run="x11"
    fi
    if [ "$_json" = "1" ]; then
        printf '{"instance":"%s","distro":"%s","desktop":"%s","backend":"%s","autostart":"%s","running":"%s"}\n' \
            "$_inst" "$_d" "$_de" "$_srv" "$_auto" "$_run"
    else
        echo "instance:  $_inst"
        echo "distro:    ${_d:-unknown}"
        echo "desktop:   ${_de:-none}"
        echo "backend:   ${_srv:-none}"
        echo "autostart: ${_auto:-none}"
        echo "running:   $_run"
    fi
}

# ------------------------------------------------------------
# AppImage support
#
# A type-2 AppImage self-mounts through FUSE. proot does not expose
# /dev/fuse, so running one directly fails with
#     fuse: failed to open /dev/fuse: Permission denied
# The AppImage runtime can extract instead. lib/real-feel.sh exports
# APPIMAGE_EXTRACT_AND_RUN=1 in the guest session, so a direct run, a
# file-manager double-click and a menu entry all work. `lfa appimage add`
# extracts once and writes a menu entry, which avoids re-extracting a large
# AppImage on every launch.
# ------------------------------------------------------------
LFA_APPIMAGE_DIR=".local/opt/appimages"

lfa_appimage_user() {  # $1 = instance; print the desktop user
    local _conf _u=""
    _conf="$(pd_conf "$1" 2>/dev/null)"
    if [ -f "$_conf" ]; then
        # shellcheck disable=SC1090  # instance config path is computed at runtime
        _u="$( . "$_conf" 2>/dev/null; printf '%s' "${USER_NAME:-${SETUP_USER:-}}" )"
    fi
    [ -n "$_u" ] || _u="user"
    printf '%s' "$_u"
}

lfa_appimage_ensure_env() {  # $1 = instance
    local _rf _f
    _rf="$(pd_rootfs "$1")"
    [ -d "$_rf/etc" ] || return 0
    _f="$_rf/etc/profile.d/zz-lfa-env.sh"
    mkdir -p "$(dirname "$_f")" 2>/dev/null || true
    if [ ! -f "$_f" ]; then
        printf '#!/bin/sh\n' > "$_f" 2>/dev/null || return 1
    fi
    if ! grep -q 'APPIMAGE_EXTRACT_AND_RUN' "$_f" 2>/dev/null; then
        {
            printf '\n# proot cannot mount AppImages (no /dev/fuse); extract instead.\n'
            printf 'APPIMAGE_EXTRACT_AND_RUN=1; export APPIMAGE_EXTRACT_AND_RUN\n'
        } >> "$_f" 2>/dev/null || return 1
    fi
    chmod 644 "$_f" 2>/dev/null || true
    return 0
}

lfa_is_appimage() {  # $1 = file; ELF magic plus the 'AI' marker at byte 8
    [ -f "$1" ] && [ -r "$1" ] || return 1
    [ "$(dd if="$1" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || return 1
    [ "$(dd if="$1" bs=1 skip=8 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "4149" ] || return 1
}

lfa_appimage_default_name() {  # $1 = file
    local _b
    _b="$(basename -- "$1")"
    _b="${_b%.AppImage}"; _b="${_b%.appimage}"
    _b="$(printf '%s' "$_b" | tr -c 'A-Za-z0-9._-' '-')"
    _b="${_b#-}"; _b="${_b%-}"
    [ -n "$_b" ] || _b="appimage"
    printf '%s' "$_b"
}

lfa_appimage_display_ready() {  # $1 = instance
    local _p
    if [ -f "$PREFIX/tmp/lfa-vnc-$1.pid" ]; then
        _p="$(cat "$PREFIX/tmp/lfa-vnc-$1.pid" 2>/dev/null || true)"
        lfa_pid_matches "$_p" "proot" "Xvnc" && return 0
    fi
    if pgrep -f '^termux-x11 .* :1( |$)' >/dev/null 2>&1 && \
       lfa_instance_session_running "$1"; then
        return 0
    fi
    return 1
}

# The extraction runs inside the guest: the AppImage runtime is a glibc
# binary and cannot run on Android's bionic libc directly.
lfa_appimage_write_add_script() {  # $1 = path
    cat > "$1" <<'LFA_APPIMAGE_ADD'
#!/bin/bash
# Runs inside the guest as the desktop user.
# $1 = staged AppImage, $2 = install dir, $3 = name, $4 = sha256, $5 = source
set -u
src="$1"; dest="$2"; name="$3"; sha="$4"; source_label="${5:-}"
[ -n "${HOME:-}" ] || { echo "lfa-appimage: HOME is not set" >&2; exit 1; }
[ -f "$src" ] || { echo "lfa-appimage: staged file is missing" >&2; exit 1; }
chmod +x "$src" 2>/dev/null || true
work="$(mktemp -d "${TMPDIR:-/tmp}/lfa-appimage.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1
# --appimage-extract does not need FUSE and works for type 1 and type 2.
if ! "$src" --appimage-extract >/dev/null 2>&1; then
    echo "lfa-appimage: extraction failed; is this a valid AppImage?" >&2
    exit 1
fi
[ -d squashfs-root ] || { echo "lfa-appimage: no squashfs-root was produced" >&2; exit 1; }
[ -f squashfs-root/AppRun ] || { echo "lfa-appimage: the AppImage has no AppRun" >&2; exit 1; }
chmod -R u+rwX squashfs-root 2>/dev/null || true
chmod +x squashfs-root/AppRun 2>/dev/null || true
mkdir -p "$(dirname "$dest")" || exit 1
rm -rf "$dest"
mv squashfs-root "$dest" || exit 1

display_name="$name"
icon="application-x-executable"
for d in "$dest"/*.desktop; do
    [ -f "$d" ] || continue
    n="$(sed -n 's/^Name=//p' "$d" | head -n1)"
    [ -n "$n" ] && display_name="$n"
    i="$(sed -n 's/^Icon=//p' "$d" | head -n1)"
    if [ -n "$i" ]; then
        case "$i" in
            /*) [ -f "$i" ] && icon="$i" ;;
            *)
                for c in "$dest/$i" "$dest/.DirIcon" "$dest"/*."$i" \
                         "$dest"/usr/share/icons/hicolor/*/apps/"$i".* \
                         "$dest"/usr/share/pixmaps/"$i".*; do
                    [ -f "$c" ] && { icon="$c"; break; }
                done ;;
        esac
    fi
    break
done

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" || exit 1
cat > "$HOME/.local/bin/$name" <<WRAPPER
#!/bin/sh
# Linux for Android: extracted AppImage launcher.
exec "$dest/AppRun" "\$@"
WRAPPER
chmod 755 "$HOME/.local/bin/$name" || exit 1

cat > "$HOME/.local/share/applications/$name.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$display_name
Comment=AppImage installed by Linux for Android
Exec=$HOME/.local/bin/$name %U
Icon=$icon
Terminal=false
Categories=Utility;
DESKTOP
chmod 644 "$HOME/.local/share/applications/$name.desktop" 2>/dev/null || true

{
    printf 'NAME=%s\n' "$name"
    printf 'SOURCE=%s\n' "$source_label"
    printf 'SHA256=%s\n' "$sha"
    printf 'INSTALLED=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    printf 'DISPLAY_NAME=%s\n' "$display_name"
} > "$dest/.lfa-appimage" 2>/dev/null || true

printf 'LFA_APPIMAGE_DEST=%s\n' "$dest"
LFA_APPIMAGE_ADD
    chmod 644 "$1" 2>/dev/null || true
}

lfa_appimage_usage() {
    cat <<'APPHELP'
Usage: lfa appimage <command> [options]   (alias: lfa app)

  add FILE [--name NAME]   extract an AppImage once and add a menu entry
  list                     show installed AppImages
  run NAME|FILE            launch an installed AppImage, or run a file once
  remove NAME [-y]         delete an installed AppImage
  help                     show this help

Options:
  -i, --instance NAME      distribution to use
  --name NAME              launcher name (default: the file name)

AppImages cannot self-mount under proot because /dev/fuse is not exposed.
LFA runs them by extracting instead; the guest session already exports
APPIMAGE_EXTRACT_AND_RUN=1, so a direct `./App.AppImage` also works.

Examples:
  lfa appimage add ~/Foo.AppImage
  lfa appimage add ~/Foo.AppImage --name foo
  lfa appimage list
  lfa appimage run Foo
  lfa run ~/Foo.AppImage
APPHELP
}

lfa_appimage_add() {
    local _file="" _name=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;;
            -n|--name) _name="${2:-}"; shift 2 ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) _file="$1"; shift ;;
        esac
    done
    [ -n "$_file" ] || { echo "Usage: lfa appimage add FILE [--name NAME] [-i INSTANCE]" >&2; return 2; }
    require_proot_distro || return 1
    select_installed_instance || return 1
    local _inst="$INSTANCE_NAME" _rf _user _home _src _stage _guest_src _dest _sha _out _rc
    _rf="$(pd_rootfs "$_inst")"
    _user="$(lfa_appimage_user "$_inst")"
    _home="/home/$_user"

    if [ -f "$_file" ]; then
        _src="$_file"
    elif [ -f "$_rf$_file" ]; then
        _src="$_rf$_file"
    else
        echo "No such file: $_file" >&2
        echo "Pass a file from Termux (e.g. ~/foo.AppImage) or a path inside $_inst." >&2
        return 1
    fi
    if ! lfa_is_appimage "$_src"; then
        echo "Not an AppImage: $_file" >&2
        echo "An AppImage is an ELF file with the 'AI' marker at byte 8." >&2
        return 1
    fi
    _name="${_name:-$(lfa_appimage_default_name "$_file")}"
    case "$_name" in
        ""|.|..|*[!A-Za-z0-9._-]*) echo "Invalid AppImage name: $_name" >&2; return 2 ;;
    esac
    _dest="$_home/$LFA_APPIMAGE_DIR/$_name"
    _sha="$(sha256sum "$_src" 2>/dev/null | awk '{print $1}')" || _sha=""
    _stage="$PREFIX/tmp/lfa-appimage-$_name.AppImage"
    if [ ! "$_src" -ef "$_stage" ]; then
        cp -f "$_src" "$_stage" 2>/dev/null || { echo "Could not stage $_file" >&2; return 1; }
    fi
    chmod 755 "$_stage" 2>/dev/null || true
    _guest_src="/tmp/lfa-appimage-$_name.AppImage"

    lfa_appimage_ensure_env "$_inst" || true
    lfa_appimage_write_add_script "$PREFIX/tmp/lfa-appimage-add.sh"
    echo "[*] Extracting $_name (large AppImages take a minute)..."
    _rc=0
    # shellcheck disable=SC2046  # flag list, not one argument
    _out="$(proot-distro login $(pd_login_flags) "$_inst" --user "$_user" --shared-tmp -- \
        bash /tmp/lfa-appimage-add.sh "$_guest_src" "$_dest" "$_name" "${_sha:-unknown}" "$_file" 2>&1)" || _rc=$?
    rm -f "$_stage" 2>/dev/null || true
    if [ "$_rc" -ne 0 ]; then
        echo "$_out" >&2
        echo "Could not install $_name." >&2
        return 1
    fi
    echo "[*] Installed $_name"
    echo "    launcher:   $_home/.local/bin/$_name"
    echo "    menu entry: $_home/.local/share/applications/$_name.desktop"
    echo "    run now:    lfa appimage run $_name -i $_inst"
}

lfa_appimage_list() {
    local _inst=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    local -a _insts=()
    if [ -n "$_inst" ]; then
        pd_instances 2>/dev/null | grep -Fxq -- "$_inst" || {
            echo "No installed distribution named '$_inst'." >&2; return 1; }
        _insts=("$_inst")
    else
        mapfile -t _insts < <(pd_instances)
    fi
    local _found=0 _i _rf _u _dir _n _meta _disp _sha _date
    for _i in "${_insts[@]}"; do
        [ -n "$_i" ] || continue
        _rf="$(pd_rootfs "$_i")"
        _u="$(lfa_appimage_user "$_i")"
        _dir="$_rf/home/$_u/$LFA_APPIMAGE_DIR"
        [ -d "$_dir" ] || continue
        for _n in "$_dir"/*; do
            [ -d "$_n" ] || continue
            if [ "$_found" = "0" ]; then
                printf '%-12s %-24s %-24s %s\n' "INSTANCE" "NAME" "APP" "INSTALLED"
                _found=1
            fi
            _disp="$(basename "$_n")"; _sha=""; _date=""
            _meta="$_n/.lfa-appimage"
            if [ -f "$_meta" ]; then
                _disp="$(sed -n 's/^DISPLAY_NAME=//p' "$_meta" | tail -n1)"
                [ -n "$_disp" ] || _disp="$(basename "$_n")"
                _sha="$(sed -n 's/^SHA256=//p' "$_meta" | tail -n1)"
                _date="$(sed -n 's/^INSTALLED=//p' "$_meta" | tail -n1)"
            fi
            printf '%-12s %-24s %-24s %s\n' "$_i" "$(basename "$_n")" "$_disp" "${_date:-unknown}"
            if [ -n "$_sha" ]; then
                printf '%-12s %-24s %s\n' "" "" "sha256 ${_sha:0:16}..."
            fi
        done
    done
    if [ "$_found" = "0" ]; then
        echo "No AppImages installed."
        echo "Add one with: lfa appimage add FILE"
    fi
}

lfa_appimage_remove() {
    local _name="${1:-}" _yes=0 _inst=""
    [ $# -gt 0 ] && shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            -y|--yes) _yes=1; shift ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    [ -n "$_name" ] || { echo "Usage: lfa appimage remove NAME [-y] [-i INSTANCE]" >&2; return 2; }
    case "$_name" in
        .|..|*[!A-Za-z0-9._-]*) echo "Invalid AppImage name: $_name" >&2; return 2 ;;
    esac
    require_proot_distro || return 1
    [ -n "$_inst" ] && CLI_INSTANCE="$_inst"
    select_installed_instance || return 1
    local _id="$INSTANCE_NAME" _rf _user _home _dest
    _rf="$(pd_rootfs "$_id")"
    _user="$(lfa_appimage_user "$_id")"
    _home="/home/$_user"
    _dest="$_rf$_home/$LFA_APPIMAGE_DIR/$_name"
    if [ ! -d "$_dest" ]; then
        echo "No AppImage named '$_name' for $_id." >&2
        echo "List them with: lfa appimage list -i $_id" >&2
        return 1
    fi
    if [ "$_yes" != "1" ]; then
        if [ -t 0 ]; then
            local _a=""
            read -rp "Remove $_name from $_id? [y/N] " _a || true
            case "$_a" in y|Y|yes|YES) ;; *) echo "Cancelled."; return 0 ;; esac
        else
            echo "Refusing to remove without -y." >&2
            return 2
        fi
    fi
    rm -rf "$_dest"
    rm -f "$_rf$_home/.local/bin/$_name" \
          "$_rf$_home/.local/share/applications/$_name.desktop" 2>/dev/null || true
    echo "[*] Removed $_name from $_id."
}

lfa_appimage_run() {
    local _target="${1:-}" _nocheck=0 _inst=""
    [ $# -gt 0 ] && shift || true
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --no-display-check) _nocheck=1; shift ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    [ -n "$_target" ] || { echo "Usage: lfa appimage run NAME|FILE [-i INSTANCE]" >&2; return 2; }
    require_proot_distro || return 1
    [ -n "$_inst" ] && CLI_INSTANCE="$_inst"
    select_installed_instance || return 1
    local _id="$INSTANCE_NAME" _rf _user _home _file _stage
    _rf="$(pd_rootfs "$_id")"
    _user="$(lfa_appimage_user "$_id")"
    _home="/home/$_user"

    if [ -f "$_target" ] || [ -f "$_rf$_target" ]; then
        _file="$_target"
        [ -f "$_file" ] || _file="$_rf$_target"
        if ! lfa_is_appimage "$_file"; then
            echo "Not an AppImage: $_target" >&2
            return 1
        fi
        if [ "$_nocheck" != "1" ] && ! lfa_appimage_display_ready "$_id"; then
            echo "[!] No desktop is running for $_id." >&2
            echo "    Start it first: lfa start -i $_id" >&2
            echo "    Override with: lfa appimage run $_target --no-display-check" >&2
            return 1
        fi
        _stage="$PREFIX/tmp/lfa-appimage-run-$$.AppImage"
        cp -f "$_file" "$_stage" 2>/dev/null || { echo "Could not stage $_target" >&2; return 1; }
        chmod 755 "$_stage" 2>/dev/null || true
        lfa_appimage_ensure_env "$_id" || true
        echo "[*] Extracting and running $_target (install it to avoid this each time)..."
        local _rc=0
        # shellcheck disable=SC2046  # flag list, not one argument
        proot-distro login $(pd_login_flags) "$_id" --user "$_user" --shared-tmp -- \
            bash -lc 'export APPIMAGE_EXTRACT_AND_RUN=1; export DISPLAY="${DISPLAY:-:1}"; exec "$1"' \
            _ "/tmp/$(basename "$_stage")" || _rc=$?
        rm -f "$_stage" 2>/dev/null || true
        return $_rc
    fi

    local _dest="$_home/$LFA_APPIMAGE_DIR/$_target"
    if [ ! -x "$_rf$_dest/AppRun" ]; then
        echo "No AppImage named '$_target' for $_id." >&2
        echo "List them with: lfa appimage list -i $_id" >&2
        return 1
    fi
    if [ "$_nocheck" != "1" ] && ! lfa_appimage_display_ready "$_id"; then
        echo "[!] No desktop is running for $_id." >&2
        echo "    Start it first: lfa start -i $_id" >&2
        return 1
    fi
    # shellcheck disable=SC2046  # flag list, not one argument
    proot-distro login $(pd_login_flags) "$_id" --user "$_user" --shared-tmp -- \
        bash -lc 'export DISPLAY="${DISPLAY:-:1}"; exec "$1"' _ "$_dest/AppRun" || return $?
}

lfa_storage_usage() {
    cat <<'STOHELP'
Usage: lfa storage <command> [options]

  status                   check Termux permission, guest access, and chmod
  fix                      repair links, bookmarks, and the storage group
  exec FILE [args...]      run a file from shared storage without chmod
  open                     show where shared storage is and how to open it
  data status              check adb access to Android/data and Android/obb
  data list                list packages under Android/data and Android/obb
  data pull PKG [data|obb|both] [--dest DIR]
                           copy an app's folders into shared storage
  help                     show this help

Options:
  -i, --instance NAME      distribution to use
  --interpreter CMD        run with CMD (for example: bash, python3)

Android shared storage is mounted with fixed permissions.
chmod does not work on /storage/emulated/0. `lfa storage exec` copies the
file to a Linux filesystem, sets the mode there, runs it, and removes the copy.

Android/data and Android/obb are blocked for apps, including Termux. The
data commands use adb, which runs as the shell user and can read them.
STOHELP
}

lfa_storage_fix() {
    local _inst=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    require_proot_distro || return 1
    [ -n "$_inst" ] && CLI_INSTANCE="$_inst"
    select_installed_instance || return 1
    local _id="$INSTANCE_NAME" _rf _user _conf _de="" _host="" _pstyle=""
    _rf="$(pd_rootfs "$_id")"
    _user="$(lfa_appimage_user "$_id")"
    _conf="$(pd_conf "$_id")"
    if [ -f "$_conf" ]; then
        # shellcheck disable=SC1090  # instance config path is computed at runtime
        _de="$( . "$_conf" 2>/dev/null; printf '%s' "${DE:-}" )"
        # shellcheck disable=SC1090
        _host="$( . "$_conf" 2>/dev/null; printf '%s' "${HOSTNAME:-}" )"
        # shellcheck disable=SC1090
        _pstyle="$( . "$_conf" 2>/dev/null; printf '%s' "${PSTYLE:-}" )"
    fi
    if [ ! -d "$HOME/storage" ]; then
        echo "[*] Requesting Android storage access..."
        termux-setup-storage || true
    fi
    if [ -f "$LFA_DIR/lib/real-feel.sh" ]; then
        LFA_ROOT="$_rf" LFA_USER="$_user" LFA_DE="${_de:-xfce4}" \
            LFA_HOSTNAME="${_host:-localhost}" LFA_PSTYLE="${_pstyle:-minimal}" \
            LFA_TERMUX_HOME="$HOME" sh "$LFA_DIR/lib/real-feel.sh" || true
    else
        echo "lfa: real-feel.sh is missing; run menu 12 or lfa fix first." >&2
        return 1
    fi
    echo "[*] Storage links, bookmarks, and the desktop shortcut are updated."
    echo "    The desktop user now uses gid 1023 (Android media_rw)."
    echo "    Restart the desktop to apply it: lfa start -i $_id --restart"
    echo "    chmod is not supported on /storage/emulated/0; use: lfa storage exec FILE"
}

lfa_storage_status() {
    local _inst=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    require_proot_distro || return 1
    [ -n "$_inst" ] && CLI_INSTANCE="$_inst"
    select_installed_instance || return 1
    local _id="$INSTANCE_NAME" _user _out
    _user="$(lfa_appimage_user "$_id")"
    echo "instance: $_id"
    if [ -d "$HOME/storage" ]; then
        echo "termux storage: present"
        echo "shared target:  $(readlink -f "$HOME/storage/shared" 2>/dev/null || echo unknown)"
    else
        echo "termux storage: missing (run: lfa storage fix -i $_id)"
    fi
    # shellcheck disable=SC2046  # flag list, not one argument
    _out="$(proot-distro login $(pd_login_flags) "$_id" --user "$_user" --shared-tmp -- bash -c '
        printf "guest gid: %s\n" "$(id -g)"
        printf "storage:   "
        ls -ld /storage/emulated/0 2>&1
        if touch /storage/emulated/0/.lfa-status-$$ 2>/dev/null; then
            printf "write:     ok\n"
            rm -f /storage/emulated/0/.lfa-status-$$
        else
            printf "write:     no\n"
        fi
        echo x > /storage/emulated/0/.lfa-mode-$$ 2>/dev/null || exit 0
        _b="$(stat -c %a /storage/emulated/0/.lfa-mode-$$ 2>/dev/null)"
        chmod 755 /storage/emulated/0/.lfa-mode-$$ 2>/dev/null
        _a="$(stat -c %a /storage/emulated/0/.lfa-mode-$$ 2>/dev/null)"
        printf "chmod:     %s -> %s (unchanged is normal)\n" "$_b" "$_a"
        rm -f /storage/emulated/0/.lfa-mode-$$
    ' 2>&1)" || true
    printf '%s\n' "$_out"
    case "$_out" in
        *"guest gid: 1023"*) ;;
        *) echo "fix:       run: lfa storage fix -i $_id (removes the false X in Thunar)" ;;
    esac
}

lfa_storage_exec() {
    local _inst="" _interp="" _file=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --interpreter) _interp="${2:-}"; shift 2 ;;
            --) shift; _file="${1:-}"; [ $# -gt 0 ] && shift || true; break ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) _file="$1"; shift; break ;;
        esac
    done
    [ -n "$_file" ] || { lfa_storage_usage >&2; return 2; }
    require_proot_distro || return 1
    [ -n "$_inst" ] && CLI_INSTANCE="$_inst"
    select_installed_instance || return 1
    local _id="$INSTANCE_NAME" _rf _user _file_guest="" _stage="" _rc=0
    _rf="$(pd_rootfs "$_id")"
    _user="$(lfa_appimage_user "$_id")"
    if [ -f "$_file" ]; then
        case "$_file" in
            "$HOME"/*|/storage/*|/sdcard/*|/mnt/sdcard/*)
                _file_guest="$_file" ;;
            *)
                _stage="$PREFIX/tmp/lfa-exec-$$-$(basename "$_file")"
                cp -f "$_file" "$_stage" 2>/dev/null || {
                    echo "Could not stage $_file" >&2
                    return 1
                }
                _file_guest="/tmp/$(basename "$_stage")" ;;
        esac
    elif [ -f "$_rf$_file" ]; then
        _file_guest="$_file"
    else
        echo "No such file: $_file" >&2
        return 1
    fi
    # shellcheck disable=SC2046  # flag list, not one argument
    proot-distro login $(pd_login_flags) "$_id" --user "$_user" --shared-tmp -- \
        lfa-run-file --interpreter "$_interp" -- "$_file_guest" "$@" || _rc=$?
    [ -n "$_stage" ] && rm -f "$_stage" 2>/dev/null || true
    if [ "$_rc" = "127" ]; then
        echo "lfa: lfa-run-file is missing in $_id; run: lfa fix -i $_id" >&2
    fi
    return $_rc
}

lfa_storage_open() {
    local _inst=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    require_proot_distro || return 1
    [ -n "$_inst" ] && CLI_INSTANCE="$_inst"
    select_installed_instance || return 1
    local _id="$INSTANCE_NAME"
    echo "Android storage is at /storage/emulated/0 in $_id."
    echo "It is also bookmarked in Thunar as Android, and on the desktop."
    echo "Open it from the file manager, or run: thunar /storage/emulated/0"
}

lfa_storage_data_help() {
    cat <<'DATAHELP'
Usage: lfa storage data <command> [options]

  status                   check adb and Android/data, Android/obb access
  list                     list packages under Android/data and Android/obb
  pull PKG [data|obb|both] copy an app's folders into shared storage
  help                     show this help

Options:
  --dest DIR               destination (default: ~/storage/shared/Android-backup/PKG)

Android blocks /sdcard/Android/data and /sdcard/Android/obb for apps,
including Termux. adb runs as the shell user and can read them. LFA copies
the files into shared storage so the Linux guest can open them.

The copy lands in shared storage, which other apps can read. Delete it when
you are done.

One-time setup from a PC with USB debugging enabled:

  adb tcpip 5555

After a reboot, run that command again, or enable Wireless debugging and
pair Termux's adb once.
DATAHELP
}

lfa_storage_adb_serial() {
    local _d
    command -v adb >/dev/null 2>&1 || return 1
    if adb -s 127.0.0.1:5555 get-state >/dev/null 2>&1; then
        printf '%s\n' "127.0.0.1:5555"
        return 0
    fi
    adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
    sleep 1
    if adb -s 127.0.0.1:5555 get-state >/dev/null 2>&1; then
        printf '%s\n' "127.0.0.1:5555"
        return 0
    fi
    _d="$(adb devices 2>/dev/null | awk '$2=="device" && $1 !~ /^emulator-/ {print $1; exit}')"
    [ -n "$_d" ] || return 1
    printf '%s\n' "$_d"
}

lfa_storage_data_no_device() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb is not installed. Run: pkg install android-tools" >&2
        return 1
    fi
    echo "No adb device is connected." >&2
    echo "From a PC with USB debugging enabled, run:" >&2
    echo "  adb tcpip 5555" >&2
    echo "Then run this command again. The connection lasts until the phone reboots." >&2
    echo "For a no-PC restart, enable Wireless debugging and pair Termux's adb once." >&2
    return 1
}

lfa_storage_data_status() {
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb:       missing (run: pkg install android-tools)"
        return 0
    fi
    echo "adb:       installed"
    local _s
    if ! _s="$(lfa_storage_adb_serial)"; then
        lfa_storage_data_no_device
        return 0
    fi
    echo "device:    $_s"
    if adb -s "$_s" shell ls /sdcard/Android/data >/dev/null 2>&1; then
        echo "data:      readable"
    else
        echo "data:      not readable"
    fi
    if adb -s "$_s" shell ls /sdcard/Android/obb >/dev/null 2>&1; then
        echo "obb:       readable"
    else
        echo "obb:       not readable"
    fi
}

lfa_storage_data_list() {
    local _s
    if ! _s="$(lfa_storage_adb_serial)"; then
        lfa_storage_data_no_device
        return 1
    fi
    echo "Android/data:"
    adb -s "$_s" shell ls /sdcard/Android/data 2>/dev/null | sed 's/^/  /'
    echo "Android/obb:"
    adb -s "$_s" shell ls /sdcard/Android/obb 2>/dev/null | sed 's/^/  /'
}

lfa_storage_data_pull() {
    local _pkg="" _what="both" _dest=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dest) _dest="${2:-}"; shift 2 ;;
            data|obb|both) _what="$1"; shift ;;
            -*) echo "Unknown option: $1" >&2; return 2 ;;
            *) _pkg="$1"; shift ;;
        esac
    done
    [ -n "$_pkg" ] || { lfa_storage_data_help >&2; return 2; }
    local _s
    if ! _s="$(lfa_storage_adb_serial)"; then
        lfa_storage_data_no_device
        return 1
    fi
    [ -n "$_dest" ] || _dest="$HOME/storage/shared/Android-backup/$_pkg"
    mkdir -p "$_dest" || return 1
    local _rc=0
    case "$_what" in
        data|both)
            if adb -s "$_s" shell test -d "/sdcard/Android/data/$_pkg" 2>/dev/null; then
                adb -s "$_s" pull "/sdcard/Android/data/$_pkg" "$_dest/data" || _rc=1
            else
                echo "No Android/data folder for $_pkg" >&2
                [ "$_what" = "data" ] && _rc=1
            fi ;;
    esac
    case "$_what" in
        obb|both)
            if adb -s "$_s" shell test -d "/sdcard/Android/obb/$_pkg" 2>/dev/null; then
                adb -s "$_s" pull "/sdcard/Android/obb/$_pkg" "$_dest/obb" || _rc=1
            else
                echo "No Android/obb folder for $_pkg" >&2
                [ "$_what" = "obb" ] && _rc=1
            fi ;;
    esac
    echo "Saved to $_dest"
    case "$_dest" in
        "$HOME/storage/shared"/*)
            echo "Guest path: /storage/emulated/0/${_dest#"$HOME/storage/shared/"}" ;;
    esac
    return $_rc
}

lfa_storage_data() {
    local _sub="${1:-status}"
    [ $# -gt 0 ] && shift || true
    case "$_sub" in
        status) lfa_storage_data_status ;;
        list|ls) lfa_storage_data_list ;;
        pull|copy) lfa_storage_data_pull "$@" ;;
        help|-h|--help) lfa_storage_data_help ;;
        *) echo "Unknown data command: $_sub" >&2; lfa_storage_data_help >&2; return 2 ;;
    esac
}

lfa_cli_storage() {
    local _sub="${1:-status}"
    [ $# -gt 0 ] && shift || true
    case "$_sub" in
        status) lfa_storage_status "$@" ;;
        fix) lfa_storage_fix "$@" ;;
        exec) lfa_storage_exec "$@" ;;
        open) lfa_storage_open "$@" ;;
        data) lfa_storage_data "$@" ;;
        help|-h|--help) lfa_storage_usage ;;
        *) echo "Unknown storage command: $_sub" >&2; lfa_storage_usage >&2; return 2 ;;
    esac
}

lfa_cli_appimage() {
    local _sub="${1:-help}"
    [ $# -gt 0 ] && shift || true
    case "$_sub" in
        help|-h|--help|"") lfa_appimage_usage ;;
        add|install) lfa_appimage_add "$@" ;;
        list|ls) lfa_appimage_list "$@" ;;
        remove|rm|uninstall) lfa_appimage_remove "$@" ;;
        run|start) lfa_appimage_run "$@" ;;
        *) echo "Unknown appimage command: $_sub" >&2; lfa_appimage_usage >&2; return 2 ;;
    esac
}

lfa_software_choices() {  # $1 = comma-separated names -> space-separated menu numbers
    local _list="$1" _name _out="" _n
    local IFS=','
    for _name in $_list; do
        case "$_name" in
            ''|none) continue ;;
            python|python3) _n=1 ;;
            git) _n=2 ;;
            node|nodejs|npm) _n=3 ;;
            curl) _n=4 ;;
            wget) _n=5 ;;
            antigravity|ide) _n=6 ;;
            firefox) _n=7 ;;
            chromium) _n=8 ;;
            libreoffice|office) _n=9 ;;
            vlc) _n=10 ;;
            gimp) _n=11 ;;
            htop) _n=12 ;;
            neofetch|fastfetch) _n=13 ;;
            vscode|vs-code|code) _n=14 ;;
            *) echo "Unknown software choice: $_name" >&2; return 2 ;;
        esac
        _out="$_out $_n"
    done
    printf '%s' "${_out# }"
}

lfa_cli_install() {
    local _distro="" _de="" _backend="" _inst="" _auto="" _user="user" _tz="" _host="localhost" _software=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --distro|-d) _distro="${2:-}"; shift 2 ;;
            --desktop) _de="${2:-}"; shift 2 ;;
            --backend|-b) _backend="${2:-}"; shift 2 ;;
            -i|--instance) _inst="${2:-}"; shift 2 ;;
            --autostart) _auto="${2:-}"; shift 2 ;;
            --user) _user="${2:-}"; shift 2 ;;
            --timezone) _tz="${2:-}"; shift 2 ;;
            --hostname) _host="${2:-}"; shift 2 ;;
            --software) _software="${2:-}"; shift 2 ;;
            -h|--help) lfa_cli_usage; return 0 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    local _software_choices=""
    if [ -n "$_software" ]; then
        _software_choices="$(lfa_software_choices "$_software")" || return 2
    fi
    if [ -n "$_inst" ] && ! printf '%s' "$_inst" | grep -Eq '^[A-Za-z0-9_.-]+$'; then
        echo "Invalid instance name '$_inst': use letters, digits, dot, underscore or dash." >&2
        return 2
    fi
    if ! printf '%s' "$_user" | grep -Eq '^[a-z_][a-z0-9_-]*$' || [ "${#_user}" -gt 32 ]; then
        echo "Invalid username '$_user': lowercase letters, digits, _ or -, starting with a letter or _." >&2
        return 2
    fi
    if [ -n "$_host" ] && ! printf '%s' "$_host" | grep -Eq '^[A-Za-z0-9.-]+$'; then
        echo "Invalid hostname '$_host'." >&2
        return 2
    fi
    if [ -n "$_tz" ] && ! printf '%s' "$_tz" | grep -Eq '^[A-Za-z0-9_+/-]+$'; then
        echo "Invalid timezone '$_tz'. Use a name such as Europe/London." >&2
        return 2
    fi
    if [ -z "$_distro" ]; then
        [ "$IS_LEGACY" = "1" ] && _distro="alpine" || _distro="debian"
    fi
    case "$_distro" in ubuntu|debian|kali|fedora|opensuse|void|archlinux|alpine) ;; *) echo "Unknown distro: $_distro" >&2; return 2 ;; esac
    if [ -z "$_de" ]; then
        if [ "$IS_LEGACY" = "1" ] || [ "$(setup_ram_mb)" -le 2048 ]; then _de="none"; else _de="xfce4"; fi
    fi
    case "$_de" in xfce|xfce4) _de="xfce4" ;; lxde|mate|gnome|none) ;; *) echo "Unknown desktop: $_de" >&2; return 2 ;; esac
    if [ "$_de" = "none" ] && [ -n "$_backend" ] && [ "$_backend" != "none" ]; then
        echo "[!] --desktop none cannot be combined with --backend $_backend." >&2
        return 1
    fi
    if [ "$_de" = "none" ]; then _backend="none"; fi
    if [ -z "$_backend" ]; then
        if [ "$_de" = "none" ]; then _backend="none"
        elif ! x11_supported; then _backend="vnc"
        else _backend="x11"; fi
    fi
    case "$_backend" in x11|vnc|both|none) ;; *) echo "Unknown backend: $_backend" >&2; return 2 ;; esac
    if ! x11_supported && { [ "$_backend" = "x11" ] || [ "$_backend" = "both" ]; }; then
        echo "[!] Termux:X11 requires Android 8 (SDK 26) or newer; this device reports SDK ${ANDROID_SDK:-unknown}." >&2
        echo "    Use --backend vnc." >&2
        return 1
    fi
    if [ "$_backend" = "none" ] && [ "$_de" != "none" ]; then
        echo "[!] A GUI desktop needs --backend x11, vnc, or both." >&2
        return 1
    fi
    if [ -n "$_auto" ] && [ "$_de" = "none" ]; then
        echo "[!] Autostart needs a desktop." >&2
        return 1
    fi
    _tz="${_tz:-$(setup_guess_timezone)}"
    DISTRO="$_distro"; DE="$_de"; SERVER="$_backend"
    INSTANCE_NAME="$_inst"
    SETUP_USER="$_user"
    SETUP_USER_B64="$(b64enc "${LFA_USER_PASSWORD:-root}")"
    SETUP_ROOT_B64="$(b64enc "${LFA_ROOT_PASSWORD:-root}")"
    TIMEZONE="$_tz"; HOSTNAME="$_host"; PSTYLE="minimal"; COLOR_MODE="light"
    RESOLUTION="${LFA_RESOLUTION:-1280x720}"
    APP_CHOICES="$_software_choices"
    NEED_VIRGL=1; [ "$IS_LEGACY" = "1" ] && NEED_VIRGL=0
    DO_AUTOSTART=0; AUTOSTART_SERVER="none"
    if [ -n "$_auto" ] && [ "$_auto" != "none" ]; then
        case "$_auto" in x11|vnc) ;; *) echo "Unknown autostart backend: $_auto" >&2; return 2 ;; esac
        if [ "$_auto" = "x11" ] && [ "$_backend" != "x11" ] && [ "$_backend" != "both" ]; then
            echo "[!] X11 autostart needs --backend x11 or both." >&2; return 1
        fi
        if [ "$_auto" = "vnc" ] && [ "$_backend" != "vnc" ] && [ "$_backend" != "both" ]; then
            echo "[!] VNC autostart needs --backend vnc or both." >&2; return 1
        fi
        DO_AUTOSTART=1; AUTOSTART_SERVER="$_auto"
    fi
    DO_STORAGE=0; DO_SSH=0; DO_WIDGET=0; SETUP_ANSWERED=1
    setup_save
    LFA_NONINTERACTIVE=1 LFA_ASSUME_YES=1 install_linux
}

lfa_cli() {
    local _cmd="${1:-help}"
    [ $# -gt 0 ] && shift || true
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        lfa_cli_usage
        return 0
    fi
    case "$_cmd" in
        help|-h|--help) lfa_cli_usage ;;
        version|-V|--version) echo "Linux for Android Manager $LFA_VERSION" ;;
        list)
            local _json=0 _n _first _i
            [ "${1:-}" = "--json" ] && _json=1
            _n="$(pd_instances)"
            if [ "$_json" = "1" ]; then
                printf '['
                _first=1
                while IFS= read -r _i; do [ -n "$_i" ] || continue; [ "$_first" = "1" ] || printf ','; printf '"%s"' "$_i"; _first=0; done <<< "$_n"
                printf ']\n'
            elif [ -z "$_n" ]; then
                echo "No distributions installed."
            else
                echo "Installed distributions:"
                echo "$_n" | sed 's/^/  - /'
            fi
            ;;
        status)
            local _json=0 _inst=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --json) _json=1; shift ;;
                    -i|--instance) _inst="${2:-}"; shift 2 ;;
                    *) echo "Unknown option: $1" >&2; return 2 ;;
                esac
            done
            if [ -n "$_inst" ]; then
                if ! pd_instances 2>/dev/null | grep -Fxq -- "$_inst"; then
                    echo "No installed distribution named '$_inst'." >&2
                    return 1
                fi
                lfa_cli_status_one "$_inst" "$_json"
            else
                local _any=0
                while IFS= read -r _i; do
                    [ -z "$_i" ] && continue
                    [ "$_any" = "1" ] && [ "$_json" != "1" ] && echo ""
                    lfa_cli_status_one "$_i" "$_json"
                    _any=1
                done < <(pd_instances)
                if [ "$_any" != "1" ]; then
                    [ "$_json" = "1" ] && echo "[]" || echo "No distributions installed."
                fi
            fi
            ;;
        start)
            local -a _a=(--desktop)
            while [ $# -gt 0 ]; do
                case "$1" in
                    -i|--instance) _a+=(--instance "${2:-}"); shift 2 ;;
                    -b|--backend|--server) _a+=(--server "${2:-}"); shift 2 ;;
                    --x11) _a+=(--server x11); shift ;;
                    --vnc) _a+=(--server vnc); shift ;;
                    --restart) _a+=(--restart); shift ;;
                    --desktop) shift ;;
                    --no-notice) shift ;;
                    *) echo "Unknown option: $1" >&2; return 2 ;;
                esac
            done
            exec "$PREFIX/bin/start-linux" "${_a[@]}" ;;
        shell)
            local _mode="user" _inst=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -i|--instance) _inst="${2:-}"; shift 2 ;;
                    --root) _mode="root"; shift ;;
                    --user) _mode="user"; shift ;;
                    *) echo "Unknown option: $1" >&2; return 2 ;;
                esac
            done
            local -a _a=("--$_mode")
            [ -n "$_inst" ] && _a+=(--instance "$_inst")
            exec "$PREFIX/bin/terminal-linux" "${_a[@]}" ;;
        stop)
            local -a _a=()
            while [ $# -gt 0 ]; do
                case "$1" in
                    -i|--instance) _a+=(--instance "${2:-}"); shift 2 ;;
                    --all) _a+=(--all); shift ;;
                    *) echo "Unknown option: $1" >&2; return 2 ;;
                esac
            done
            exec "$PREFIX/bin/stop-linux" "${_a[@]}" ;;
        switch)
            local _target="${1:-}"; [ $# -gt 0 ] && shift || true
            change_backend "$_target" "$@" ;;
        autostart)
            local _srv="${1:-}"; [ $# -gt 0 ] && shift || true
            set_autostart "$_srv" "$@" ;;
        notice)
            case "${1:-status}" in
                off) lfa_cli_notice_write off; echo "start-linux notice disabled. Re-enable with: lfa notice on" ;;
                on) lfa_cli_notice_write on; echo "start-linux notice enabled." ;;
                status)
                    _v=1
                    # shellcheck disable=SC1090
                    [ -r "$LFA_PREFS" ] && . "$LFA_PREFS" 2>/dev/null || true
                    [ "${START_NOTICE:-1}" = "0" ] && _v=0
                    [ "$_v" = "1" ] && echo "start-linux notice: on" || echo "start-linux notice: off" ;;
                *) echo "Usage: lfa notice on|off|status" >&2; return 2 ;;
            esac ;;
        install) lfa_cli_install "$@" ;;
        compat) lfa_cli_compat "$@" ;;
        android) lfa_android_cmd "$@" ;;
        usb) lfa_cli_usb "$@" ;;
        appimage|app) lfa_cli_appimage "$@" ;;
        storage) lfa_cli_storage "$@" ;;
        run) lfa_appimage_run "$@" ;;
        update)
            while [ $# -gt 0 ]; do case "$1" in -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;; *) echo "Unknown option: $1" >&2; return 2 ;; esac; done
            LFA_NONINTERACTIVE=1 LFA_CLI_MODE=1 update_linux ;;
        fix)
            while [ $# -gt 0 ]; do case "$1" in -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;; *) echo "Unknown option: $1" >&2; return 2 ;; esac; done
            require_proot_distro || return 1
            LFA_NONINTERACTIVE=1 LFA_CLI_MODE=1 upgrade_existing ;;
        doctor)
            while [ $# -gt 0 ]; do case "$1" in -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;; *) echo "Unknown option: $1" >&2; return 2 ;; esac; done
            LFA_NONINTERACTIVE=1 LFA_CLI_MODE=1 repair_linux ;;
        backup)
            local _out=""
            while [ $# -gt 0 ]; do
                case "$1" in -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;; -o|--output) _out="${2:-}"; shift 2 ;; *) echo "Unknown option: $1" >&2; return 2 ;; esac
            done
            require_proot_distro || return 1
            select_installed_instance || return 1
            [ -n "$INSTANCE_NAME" ] || return 1
            _out="${_out:-$HOME/${INSTANCE_NAME}-backup.tar.gz}"
            proot-distro backup "$INSTANCE_NAME" --output "$_out" ;;
        restore)
            local _file="" _inst=""
            while [ $# -gt 0 ]; do
                case "$1" in -i|--instance) _inst="${2:-}"; shift 2 ;; -*) echo "Unknown option: $1" >&2; return 2 ;; *) _file="$1"; shift ;; esac
            done
            [ -n "$_file" ] || { echo "Usage: lfa restore FILE [-i NAME]" >&2; return 2; }
            require_proot_distro || return 1
            if pd_is_v4; then
                proot-distro restore "$_file"
            else
                [ -n "$_inst" ] || { echo "[!] This proot-distro needs -i NAME to restore." >&2; return 1; }
                proot-distro restore "$_inst" --input "$_file"
            fi ;;
        remove)
            local _yes=0
            while [ $# -gt 0 ]; do
                case "$1" in -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;; -y|--yes) _yes=1; shift ;; *) echo "Unknown option: $1" >&2; return 2 ;; esac
            done
            [ "$_yes" = "1" ] && LFA_ASSUME_YES=1
            LFA_NONINTERACTIVE=1 LFA_CLI_MODE=1 uninstall_linux ;;
        diagnostics) lfa_diagnostics ;;
        *) echo "Unknown command: $_cmd" >&2; lfa_cli_usage >&2; return 2 ;;
    esac
}

lfa_run_cli() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    lfa_usage; exit 0 ;;
            -V|--version) echo "Linux for Android Manager $LFA_VERSION"; exit 0 ;;
            --debug)
                LFA_KEEP_SETUP_SCRIPT=1
                export LFA_KEEP_SETUP_SCRIPT
                lfa_enable_debug_log
                shift ;;
            --list)
                detect_environment
                local _n
                _n="$(pd_instances)"
                if [ -z "$_n" ]; then
                    echo "No distributions installed."
                else
                    echo "Installed distributions:"
                    echo "$_n" | sed 's/^/  - /'
                fi
                exit 0 ;;
            --doctor)
                detect_environment
                LFA_NONINTERACTIVE=1
                repair_linux
                exit $? ;;
            --diagnostics)
                detect_environment
                lfa_diagnostics
                exit $? ;;
            --yes|-y)
                detect_environment
                LFA_NONINTERACTIVE=1
                setup_quick
                exit 0 ;;
            *)
                echo "Unknown option: $1" >&2
                lfa_usage >&2
                exit 2 ;;
        esac
    done
}

setup_entry() {
    detect_environment
    lfa_check_update
    if [ "$UI_TTY" = "1" ]; then
        UI_NOTE="$ARCH · Android SDK ${ANDROID_SDK:-0} · legacy=${IS_LEGACY:-0}"
    else
        print_device_info
    fi
    local -a _entry=(
        "1|Quick setup|all defaults, zero questions"
        "2|Guided setup|choose distro, desktop, user, passwords, ..."
        "3|Manager menu|install / update / repair / uninstall"
    )
    [ -f "$SETUP_CONF" ] && _entry+=("4|Re-install with saved answers|uses ~/.config/linux-for-android/setup.conf")

    if ! ui_select "Linux for Android - Setup" "1" "${_entry[@]}"; then
        show_menu
        return
    fi
    case "$UI_SELECTED" in
        1) setup_quick ;;
        2) setup_guided ;;
        3) show_menu ;;
        4) if [ -f "$SETUP_CONF" ]; then setup_load_saved; else echo "No saved setup found."; show_menu; fi ;;
    esac
}

require_proot_distro() {
    if command -v proot-distro >/dev/null 2>&1; then
        return 0
    fi
    echo "[!] proot-distro not found. Attempting legacy source install..."
    if install_proot_distro_from_source; then
        return 0
    fi
    echo "ERROR: proot-distro is required for this operation."
    ui_pause
    show_menu
    return 1
}

show_menu() {
    if [ "$LFA_CLI_MODE" = "1" ]; then
        exit "${1:-1}"
    fi
    local -a _menu=(
        "1|Install / Re-install Linux Distro|pick a distro, desktop and apps"
        "2|Update a Distro|1-click updater, heals apt/dpkg first"
        "3|Start SSH Server|connect from another device, port 8022"
        "4|System Dashboard|RAM, storage and installed distros"
        "5|Audio Debugger / Fixer|PulseAudio checks and repair"
        "6|Backup a Distro|internal TAR archive in your home"
        "7|Restore a Distro|restore an internal backup"
        "8|Export Distro|copy a TAR to Downloads for sharing"
        "9|Import Shared Distro|restore a TAR from Downloads"
        "10|Uninstall a Distro|delete a rootfs permanently"
        "11|Toggle Browser Hardware Acceleration|GPU on/off for Chromium"
        "12|Apply Latest Fixes|migrate an older install in place"
        "14|Change Display Backend|switch X11/VNC/Both and remove packages"
        "0|Repair a Distro (Doctor)|fix broken apt/dpkg, missing users"
        "13|Exit|close the manager"
    )
    if ! ui_select "Linux for Termux Manager" "1" "${_menu[@]}"; then
        printf '  %sBye.%s
' "$C_DIM" "$C_RESET"
        exit 0
    fi
    case "$UI_SELECTED" in
        0) repair_linux ;;
        1) install_linux ;;
        2) update_linux ;;
        3) start_ssh ;;
        4) system_dashboard ;;
        5) audio_fixer ;;
        6) backup_linux ;;
        7) restore_linux ;;
        8) export_distro ;;
        9) import_distro ;;
        10) uninstall_linux ;;
        11) optimize_browser ;;
        12) upgrade_existing ;;
        14) menu_change_backend ;;
        13) exit 0 ;;
    esac
}

select_os_flavor() {
    if ! ui_select "Choose Linux Distribution" "2" \
        "1|Ubuntu|24.04 LTS · APT" \
        "2|Debian|stable · APT" \
        "3|Kali Linux|APT · security tools" \
        "4|Fedora|DNF" \
        "5|OpenSUSE|Zypper" \
        "6|Void Linux|XBPS" \
        "7|Arch Linux|Pacman · may be unstable on ARM64" \
        "8|Alpine Linux|APK · musl · best for Android 5/6"; then
        return 1
    fi
    case "$UI_SELECTED" in
        1) DISTRO="ubuntu" ;;
        2) DISTRO="debian" ;;
        3) DISTRO="kali" ;;
        4) DISTRO="fedora" ;;
        5) DISTRO="opensuse" ;;
        6) DISTRO="void" ;;
        7) DISTRO="archlinux" ;;
        8) DISTRO="alpine" ;;
    esac
}

# proot-distro layout compatibility:
#   v3 and earlier: $PREFIX/var/lib/proot-distro/installed-rootfs/<name>
#   v4 and later:   $PREFIX/var/lib/proot-distro/containers/<name>/rootfs
# Always resolve to the real rootfs; fall back to the legacy path.
pd_rootfs() {
    local inst="$1"
    local base="$PREFIX/var/lib/proot-distro"
    if [ -d "$base/containers/$inst/rootfs" ]; then
        printf '%s' "$base/containers/$inst/rootfs"
    else
        printf '%s' "$base/installed-rootfs/$inst"
    fi
}

pd_conf() {
    local inst="$1"
    local real legacy
    real="$(pd_rootfs "$inst")/etc/termux-linux-manager.conf"
    legacy="$PREFIX/var/lib/proot-distro/installed-rootfs/$inst/etc/termux-linux-manager.conf"
    if [ -f "$real" ]; then
        printf '%s' "$real"
    else
        printf '%s' "$legacy"
    fi
}

pd_instances() {
    local base="$PREFIX/var/lib/proot-distro" d
    {
        if [ -d "$base/containers" ]; then
            for d in "$base/containers"/*; do
                [ -d "$d" ] && basename "$d"
            done
        fi
        # Legacy layout: only count entries that actually contain a rootfs.
        # Old versions of this manager left conf-only stubs there; listing
        # those made uninstall/start show ghost distros.
        for d in "$base/installed-rootfs"/*; do
            [ -d "$d" ] || continue
            { [ -d "$d/var" ] || [ -d "$d/usr" ] || [ -d "$d/bin" ]; } || continue
            basename "$d"
        done
    } | awk '!seen[$0]++'
}

pd_instance_exists() {
    local inst="$1"
    local base="$PREFIX/var/lib/proot-distro"
    [ -d "$base/containers/$inst/rootfs" ] && return 0
    [ -d "$base/installed-rootfs/$inst/var" ] || [ -d "$base/installed-rootfs/$inst/usr" ]
}

select_installed_instance() {
    INSTANCE_NAME=""
    if [ -n "$CLI_INSTANCE" ]; then
        mapfile -t DISTROS < <(pd_instances)
        local _found=0 _d
        for _d in "${DISTROS[@]}"; do [ "$_d" = "$CLI_INSTANCE" ] && _found=1; done
        if [ "$_found" != "1" ]; then
            echo "No installed distribution named '$CLI_INSTANCE'." >&2
            return 1
        fi
        INSTANCE_NAME="$CLI_INSTANCE"
        CONF_FILE="$(pd_conf "$INSTANCE_NAME")"
        if [ -f "$CONF_FILE" ]; then
            # shellcheck source=/dev/null
            source "$CONF_FILE"
        fi
        return 0
    fi
    mapfile -t DISTROS < <(pd_instances)
    if [ ${#DISTROS[@]} -eq 0 ]; then
        echo "No distributions installed."
        ui_pause
        show_menu
    elif [ ${#DISTROS[@]} -eq 1 ]; then
        INSTANCE_NAME=${DISTROS[0]}
    elif [ "$LFA_CLI_MODE" = "1" ]; then
        echo "Multiple distributions found. Choose one with -i NAME:" >&2
        printf '  %s\n' "${DISTROS[@]}" >&2
        return 1
    else
        local -a _inst=()
        for i in "${!DISTROS[@]}"; do
            _inst+=("$((i+1))|${DISTROS[$i]}|$([ -x "$(pd_rootfs "${DISTROS[$i]}")/bin/sh" ] && echo ready || echo incomplete)")
        done
        if ! ui_select "Multiple distributions found - pick one" "1" "${_inst[@]}"; then
            show_menu
            return
        fi
        INSTANCE_NAME="${DISTROS[$((UI_SELECTED-1))]}"
    fi
    if [ -n "$INSTANCE_NAME" ]; then
        CONF_FILE="$(pd_conf "$INSTANCE_NAME")"
        if [ -f "$CONF_FILE" ]; then
            # shellcheck source=/dev/null
            source "$CONF_FILE"
        fi
    fi
}

system_dashboard() {
    clear 2>/dev/null || true
    echo "========================================="
    echo "         SYSTEM DASHBOARD                "
    echo "========================================="
    echo "OS Architecture: $(uname -m)"
    echo "-----------------------------------------"
    echo "Android Memory (RAM) Usage:"
    free -m || echo "Memory stats unavailable."
    echo "-----------------------------------------"
    echo "Termux Storage Usage (Total Size):"
    du -sh "$PREFIX" 2>/dev/null | awk '{print $1}' || true
    echo "-----------------------------------------"
    echo "Available Phone Storage:"
    df -h /data 2>/dev/null | awk 'NR==2 {print $4}' || echo "unavailable"
    echo "========================================="
    ui_pause
    show_menu
}

audio_fixer() {
    if ! command -v pulseaudio >/dev/null 2>&1; then
        echo "[*] pulseaudio not found, trying to install..."
        pkg install -y pulseaudio 2>/dev/null || true
    fi
    if ! command -v pulseaudio >/dev/null 2>&1; then
        echo "ERROR: pulseaudio unavailable on this Termux repo (common on Android 5)."
        echo "Audio inside Linux will be silent, but the desktop itself still works."
        ui_pause
        show_menu
        return
    fi
    echo "[*] Restarting PulseAudio and clearing sockets..."
    pulseaudio -k 2>/dev/null || true
    rm -rf /data/data/com.termux/files/usr/tmp/pulse-* 2>/dev/null || true
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
    echo "Audio server forcefully bound to TCP protocol!"
    ui_pause
    show_menu
}

# Guest-side repair script. Staged into the shared /tmp and executed as root
# inside the distro by run_guest_repair().
write_guest_repair_script() {
    cat > "$PREFIX/tmp/lfa-repair.sh" << 'REPAIR'
#!/bin/bash
# Staged by install_linux.sh. Fixes common proot/apt breakages in place.
# Keep this free of fancy quoting: it runs inside arbitrary old guests.

echo " -> Sanitising dpkg statoverride (missing users/groups are fatal to dpkg)..."
if [ -f /var/lib/dpkg/statoverride ]; then
    : > /var/lib/dpkg/statoverride.lfa
    while read -r u g m p; do
        [ -n "$u" ] || continue
        [ -n "$p" ] || continue
        if ! { getent passwd "$u" >/dev/null 2>&1 || grep -q "^$u:" /etc/passwd; }; then
            echo "    dropped row (missing user $u): $p"
            continue
        fi
        if ! { getent group "$g" >/dev/null 2>&1 || grep -q "^$g:" /etc/group; }; then
            echo "    dropped row (missing group $g): $p"
            continue
        fi
        printf '%s %s %s %s\n' "$u" "$g" "$m" "$p" >> /var/lib/dpkg/statoverride.lfa
    done < /var/lib/dpkg/statoverride
    cat /var/lib/dpkg/statoverride.lfa > /var/lib/dpkg/statoverride
    rm -f /var/lib/dpkg/statoverride.lfa
fi

echo " -> Re-applying proot-friendly apt settings..."
mkdir -p /etc/apt/apt.conf.d
echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99-proot-no-sandbox
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d
rm -f /var/lib/dpkg/statoverride-new /var/lib/dpkg/statoverride-old

# snapd can never work here: its postinst needs CAP_SETFCAP, mount and a
# systemd init, none of which exist inside proot. Left half-configured it
# makes EVERY later apt/dpkg run exit non-zero. Purge it and pin it off so
# apt cannot drag it back in (installing ubuntu-desktop pulls it in).
echo " -> Neutralising snapd (snaps cannot run inside proot)..."
if command -v dpkg-query >/dev/null 2>&1; then
    _snap_state="$(dpkg-query -W -f='${Status}' snapd 2>/dev/null || true)"
    case "$_snap_state" in
        ""|*"install ok installed")
            [ -n "$_snap_state" ] && echo "    snapd is configured; leaving it alone."
            ;;
        *)
            echo "    snapd state: $_snap_state"
            dpkg --purge --force-all snapd >/dev/null 2>&1 || true
            mkdir -p /etc/apt/preferences.d
            printf 'Package: snapd\nPin: release *\nPin-Priority: -1\n' \
                > /etc/apt/preferences.d/99-proot-no-snap
            echo "    purged snapd and pinned it off so apt stays usable."
            ;;
    esac
fi

echo " -> Finishing half-configured packages (dpkg --configure -a)..."
DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true

# Re-register dbus's helper ONLY after dbus's own postinst had a chance to
# create the messagebus group. Seeding it earlier is what used to break apt.
if dpkg -s dbus-system-bus-common >/dev/null 2>&1 || dpkg -s dbus >/dev/null 2>&1; then
    if getent group messagebus >/dev/null 2>&1; then
        /usr/local/bin/dpkg-statoverride --update --add root messagebus 4754 /usr/lib/dbus-1.0/dbus-daemon-launch-helper >/dev/null 2>&1 || true
    fi
fi

echo " -> Package database audit:"
dpkg --audit || true
echo " -> Doctor finished."
REPAIR
    chmod +x "$PREFIX/tmp/lfa-repair.sh"
}

# Install the shim host-side (no proot needed) and run the repair script.
run_guest_repair() {
    local ROOTFS
    ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"

    if [ ! -d "$ROOTFS/var/lib/dpkg" ]; then
        echo "[*] $INSTANCE_NAME is not dpkg-based (Alpine/Fedora/...); nothing to repair."
        return 0
    fi

    if [ -f "$LFA_DIR/lib/dpkg-statoverride.sh" ]; then
        mkdir -p "$ROOTFS/usr/local/bin"
        cp "$LFA_DIR/lib/dpkg-statoverride.sh" "$ROOTFS/usr/local/bin/dpkg-statoverride"
        chmod 755 "$ROOTFS/usr/local/bin/dpkg-statoverride"
    fi

    write_guest_repair_script
    # shellcheck disable=SC2046  # flag list, not one argument
    proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --shared-tmp -- bash /tmp/lfa-repair.sh
}

repair_linux() {
    require_proot_distro || return
    select_installed_instance || return 1
    if [ -z "$INSTANCE_NAME" ]; then return 1; fi
    echo "[*] Running Doctor on $INSTANCE_NAME..."
    echo "========================================="
    local _rc=0
    if run_guest_repair; then
        echo "Repair complete!"
    else
        echo "[!] Doctor hit an error - review the output above."
        _rc=1
    fi
    echo "========================================="
    ui_pause
    show_menu "$_rc"
}

# Menu 12 helpers. Adding a second backend must not depend on the installer's
# distro-specific variables, which are only set on a fresh install.
vnc_pkg_for_distro() {
    case "${DISTRO:-}" in
        ubuntu|debian|kali) echo "tigervnc-standalone-server" ;;
        fedora)             echo "tigervnc-server" ;;
        opensuse|void|archlinux|alpine) echo "tigervnc" ;;
        *)                  echo "tigervnc" ;;
    esac
}

guest_update_pkgs() {
    case "${DISTRO:-}" in
        ubuntu|debian|kali)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- apt-get update -y ;;
        fedora)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- dnf makecache ;;
        opensuse)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- zypper refresh ;;
        archlinux)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- pacman -Sy --noconfirm ;;
        void)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- xbps-install -S ;;
        alpine)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- apk update ;;
        *) return 1 ;;
    esac
}

guest_install_pkgs() {  # $@ = package names
    [ "$#" -gt 0 ] || return 0
    guest_update_pkgs || true
    case "${DISTRO:-}" in
        ubuntu|debian|kali)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- apt-get install -y "$@" ;;
        fedora)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- dnf install -y "$@" ;;
        opensuse)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- zypper install -y "$@" ;;
        archlinux)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- pacman -S --noconfirm "$@" ;;
        void)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- xbps-install -y "$@" ;;
        alpine)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- apk add "$@" ;;
        *)
            echo "[!] Unknown package manager for $DISTRO."
            return 1 ;;
    esac
}

vnc_guest_ready() {  # $1 = rootfs
    [ -x "$1/usr/bin/vncserver" ] || [ -x "$1/usr/bin/Xvnc" ]
}

write_vnc_xstartup() {  # $1 = rootfs, $2 = user, $3 = desktop
    local _rootfs="$1" _user="$2" _de="$3" _ses=""
    case "$_de" in
        xfce4|xfce) _ses="startxfce4" ;;
        lxde)       _ses="startlxde" ;;
        mate)       _ses="mate-session" ;;
        gnome)      _ses="/usr/local/bin/start-gnome-session" ;;
        *) return 0 ;;
    esac
    for _dir in "$_rootfs/home/$_user/.vnc" "$_rootfs/home/$_user/.config/tigervnc"; do
        mkdir -p "$_dir"
        cat > "$_dir/xstartup" <<EOF
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PULSE_SERVER=127.0.0.1
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
export XDG_RUNTIME_DIR="/tmp/xdg-\$(id -un)"
mkdir -p "\$XDG_RUNTIME_DIR"
chmod 700 "\$XDG_RUNTIME_DIR"
if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- $_ses
elif command -v dbus-launch >/dev/null 2>&1; then
    exec dbus-launch --exit-with-session $_ses
else
    exec $_ses
fi
EOF
        chmod 755 "$_dir/xstartup"
    done
}

vnc_set_password() {  # $1 = guest user
    local _user="$1" _b64="" _pw=""
    if [ -n "${LFA_VNC_PASSWORD:-}" ]; then
        _pw="$LFA_VNC_PASSWORD"
    elif [ -f "$SETUP_CONF" ]; then
        _b64="$(sed -n 's/^SETUP_USER_B64="\(.*\)"/\1/p' "$SETUP_CONF" 2>/dev/null | head -n1)"
    fi
    if [ -z "$_pw" ] && [ -n "$_b64" ]; then
        _pw="$(printf '%s' "$_b64" | base64 -d 2>/dev/null || true)"
    fi
    if [ -z "$_pw" ]; then
        if [ "$LFA_CLI_MODE" = "1" ] || [ ! -t 0 ]; then
            _pw="root"
            echo "[!] No saved VNC password; using the default 'root'." >&2
            echo "    Change it with: lfa switch vnc -i $INSTANCE_NAME" >&2
        else
            setup_confirm_secret _pw "VNC password [default: root]: " "root"
        fi
    fi
    # shellcheck disable=SC2046  # flag list, not one argument
    printf '%s\n' "$_pw" | proot-distro login $(pd_login_flags) "$INSTANCE_NAME" \
        --user "$_user" --shared-tmp -- bash -c \
        'mkdir -p "$HOME/.vnc" "$HOME/.config/tigervnc"; vncpasswd -f > "$HOME/.vnc/passwd"; cp -f "$HOME/.vnc/passwd" "$HOME/.config/tigervnc/passwd"; chmod 600 "$HOME/.vnc/passwd" "$HOME/.config/tigervnc/passwd"'
}

enable_vnc_backend() {
    vnc_set_password "$LINUX_USER" || return 1
    write_vnc_xstartup "$ROOTFS" "$LINUX_USER" "$DE" || return 1
    SERVER="both"
}

# ------------------------------------------------------------
# Backend switching and clean package removal.
# ------------------------------------------------------------
lfa_conf_set() {  # $1 = conf file, $2 = key, $3 = value
    local _f="$1" _k="$2" _v="$3"
    [ -f "$_f" ] || return 1
    if grep -q "^${_k}=" "$_f" 2>/dev/null; then
        sed -i "s|^${_k}=.*|${_k}=\"${_v}\"|" "$_f"
    else
        printf '%s="%s"\n' "$_k" "$_v" >> "$_f"
    fi
}

guest_remove_pkgs() {  # $@ = package names
    [ "$#" -gt 0 ] || return 0
    case "${DISTRO:-}" in
        ubuntu|debian|kali)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- apt-get remove -y "$@" ;;
        fedora)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- dnf remove -y "$@" ;;
        opensuse)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- zypper remove -y "$@" ;;
        archlinux)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- pacman -R --noconfirm "$@" ;;
        void)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- xbps-remove -y "$@" ;;
        alpine)
            # shellcheck disable=SC2046
            proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- apk del "$@" ;;
        *)
            echo "[!] Unknown package manager for ${DISTRO:-unknown}." >&2
            return 1 ;;
    esac
}

x11_used_by_another_instance() {  # $1 = instance to exclude
    local _skip="$1" _inst _conf
    while IFS= read -r _inst; do
        [ -n "$_inst" ] || continue
        [ "$_inst" = "$_skip" ] && continue
        _conf="$(pd_conf "$_inst" 2>/dev/null)"
        [ -f "$_conf" ] || continue
        # shellcheck disable=SC1090
        if ( . "$_conf" 2>/dev/null; [ "${SERVER:-none}" = "x11" ] || [ "${SERVER:-none}" = "both" ] ); then
            return 0
        fi
    done < <(pd_instances 2>/dev/null)
    return 1
}

remove_x11_backend() {  # $1 = force (0/1)
    local _force="${1:-0}"
    if x11_used_by_another_instance "$INSTANCE_NAME"; then
        if [ "$_force" != "1" ]; then
            # Termux:X11 is a host package shared by every instance. Keeping
            # it installed does not stop this instance from using VNC, and
            # removing it would break the other distro's desktop.
            echo "[i] Termux:X11 is still used by another installed distro; keeping the host packages."
            echo "    This instance will use VNC only. Use --force to remove them anyway."
            return 0
        fi
        echo "[!] --force: removing Termux:X11 while another distro still uses it."
    fi
    echo "[*] Removing Termux:X11 host packages..."
    if ! pkg uninstall -y termux-x11-nightly 2>/dev/null; then
        pkg uninstall termux-x11-nightly 2>/dev/null || {
            echo "[!] Could not remove termux-x11-nightly." >&2
            return 1
        }
    fi
    echo "[i] To restore X11 later: lfa switch x11 -i $INSTANCE_NAME (or lfa switch both)"
}

remove_vnc_backend() {
    local _rootfs="$1" _user="$2"
    echo "[*] Removing VNC guest packages..."
    guest_remove_pkgs "$(vnc_pkg_for_distro)" || return 1
    rm -rf "$_rootfs/home/$_user/.vnc" "$_rootfs/home/$_user/.config/tigervnc" 2>/dev/null || true
    echo "[i] To restore VNC later: lfa switch vnc -i $INSTANCE_NAME (or lfa switch both)"
}

boot_script_targets() {  # $1 = instance name
    local _f="$HOME/.termux/boot/start-linux-services.sh"
    [ -f "$_f" ] || return 1
    grep -qF -- "--instance \"$1\"" "$_f" 2>/dev/null
}

boot_script_has_ssh() {
    grep -q '^sshd ' "$HOME/.termux/boot/start-linux-services.sh" 2>/dev/null
}

write_boot_script() {  # $1 = instance, $2 = x11|vnc|none, $3 = ssh 0/1
    local _inst="$1" _srv="$2" _ssh="${3:-0}"
    mkdir -p ~/.termux/boot
    {
        echo "#!/bin/bash"
        echo "# Generated by Linux-for-Android: starts services at boot."
        echo "termux-wake-lock 2>/dev/null || true"
        if [ "$_ssh" = "1" ]; then
            echo "sshd 2>/dev/null || true"
        fi
        if [ "$_srv" = "none" ]; then
            echo "# Desktop autostart is disabled for this install."
        else
            echo "sleep 5"
            echo "nohup \"$PREFIX/bin/start-linux\" --instance \"$_inst\" --server \"$_srv\" >/dev/null 2>&1 &"
        fi
    } > ~/.termux/boot/start-linux-services.sh
    chmod +x ~/.termux/boot/start-linux-services.sh
}

change_backend() {  # change_backend TARGET [flags]
    local _target="${1:-}"; shift || true
    local _remove_old=0 _force=0 _no_start=0 _was_running=0
    [ -n "$_target" ] || { echo "Usage: switch x11|vnc|both" >&2; return 2; }
    case "$_target" in x11|vnc|both) ;; *) echo "Unknown backend: $_target" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;;
            --remove-old|--remove-packages) _remove_old=1; shift ;;
            --keep-packages) _remove_old=0; shift ;;
            --force) _force=1; shift ;;
            --no-start) _no_start=1; shift ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    select_installed_instance || return 1
    [ -n "$INSTANCE_NAME" ] || return 1
    [ -f "$CONF_FILE" ] || { echo "[!] Missing config for $INSTANCE_NAME." >&2; return 1; }
    local _old="$SERVER"
    local _rootfs _user
    _rootfs="$(pd_rootfs "$INSTANCE_NAME")"
    _user="${USER_NAME:-${LINUX_USER:-user}}"

    if [ "${DE:-none}" = "none" ]; then
        echo "[!] $INSTANCE_NAME has no desktop installed (CLI-only)." >&2
        echo "    Re-install it with a desktop first, for example:" >&2
        echo "      lfa install --distro ${DISTRO:-debian} --desktop xfce4 --backend $_target -i $INSTANCE_NAME" >&2
        return 1
    fi
    if ! x11_supported && { [ "$_target" = "x11" ] || [ "$_target" = "both" ]; }; then
        echo "[!] Termux:X11 requires Android 8 (SDK 26) or newer." >&2
        echo "    This device (Android SDK ${ANDROID_SDK:-unknown}) can only use VNC." >&2
        echo "    Nothing was changed; the current VNC desktop keeps working." >&2
        echo "    Stay on VNC with: lfa switch vnc -i $INSTANCE_NAME" >&2
        if [ "$_remove_old" = "1" ]; then
            echo "" >&2
            echo "[!] --remove-old was ignored on purpose: deleting the VNC packages" >&2
            echo "    would leave this device with no desktop at all." >&2
            echo "    If VNC is ever removed by hand, restore it with:" >&2
            echo "      lfa switch vnc -i $INSTANCE_NAME" >&2
            echo "    That reinstalls the VNC server, password and xstartup." >&2
        fi
        return 1
    fi
    if [ "$_target" = "$_old" ] && [ "$_remove_old" != "1" ]; then
        echo "[*] $INSTANCE_NAME already uses $_target."
        return 0
    fi

    # Remember whether a desktop was live: the switch stops it below, and a
    # desktop that was in use should come back on the new backend instead of
    # leaving the user with an empty display and the root cross cursor.
    lfa_instance_session_running "$INSTANCE_NAME" && _was_running=1
    if [ -f "$PREFIX/tmp/lfa-vnc-$INSTANCE_NAME.pid" ]; then
        lfa_pid_matches "$(cat "$PREFIX/tmp/lfa-vnc-$INSTANCE_NAME.pid" 2>/dev/null || true)" \
            "proot" "Xvnc" && _was_running=1
    fi

    # Stop the running session before touching packages.
    if [ -x "$PREFIX/bin/stop-linux" ]; then
        "$PREFIX/bin/stop-linux" -i "$INSTANCE_NAME" >/dev/null 2>&1 || true
    fi

    # Install the backend we are entering *before* removing anything. If a
    # download fails, the old backend is still installed and still works.
    case "$_target" in
        x11|both)
            if ! command -v termux-x11 >/dev/null 2>&1; then
                echo "[*] Installing Termux:X11 host packages..."
                { pkg install -y x11-repo && pkg install -y termux-x11-nightly; } || {
                    echo "[!] Termux:X11 packages could not be installed; nothing was removed." >&2
                    return 1
                }
            fi
            ;;
    esac
    case "$_target" in
        vnc|both)
            if ! vnc_guest_ready "$_rootfs"; then
                echo "[*] Installing VNC guest packages..."
                guest_install_pkgs "$(vnc_pkg_for_distro)" || {
                    echo "[!] VNC packages could not be installed; nothing was removed." >&2
                    return 1
                }
            fi
            # Do not overwrite a password the user set inside the guest.
            if [ ! -f "$_rootfs/home/$_user/.vnc/passwd" ]; then
                vnc_set_password "$_user" || { echo "[!] Could not write the VNC password; nothing was removed." >&2; return 1; }
            fi
            write_vnc_xstartup "$_rootfs" "$_user" "$DE" || { echo "[!] Could not write the VNC xstartup; nothing was removed." >&2; return 1; }
            ;;
    esac

    # Remove the backend we are leaving, when asked, now that the new one is
    # in place.
    if [ "$_remove_old" = "1" ]; then
        case "$_old" in
            both)
                if [ "$_target" = "x11" ]; then
                    remove_vnc_backend "$_rootfs" "$_user" || return 1
                elif [ "$_target" = "vnc" ]; then
                    remove_x11_backend "$_force" || return 1
                fi
                ;;
            x11)
                [ "$_target" = "vnc" ] && { remove_x11_backend "$_force" || return 1; }
                ;;
            vnc)
                [ "$_target" = "x11" ] && { remove_vnc_backend "$_rootfs" "$_user" || return 1; }
                ;;
        esac
    fi

    lfa_conf_set "$CONF_FILE" SERVER "$_target"
    # Older configs may not have an autostart backend yet. Pick the new one
    # only when this instance is the boot target; otherwise record "none".
    if [ -z "${AUTOSTART_SERVER:-}" ]; then
        if [ "${DO_AUTOSTART:-0}" = "1" ] || boot_script_targets "$INSTANCE_NAME"; then
            AUTOSTART_SERVER="$_target"
        else
            AUTOSTART_SERVER="none"
        fi
        lfa_conf_set "$CONF_FILE" AUTOSTART_SERVER "$AUTOSTART_SERVER"
    fi
    # Keep autostart pointing at a backend that still exists.
    if [ "${AUTOSTART_SERVER:-none}" = "x11" ] && [ "$_target" = "vnc" ]; then
        AUTOSTART_SERVER="vnc"
    elif [ "${AUTOSTART_SERVER:-none}" = "vnc" ] && [ "$_target" = "x11" ]; then
        AUTOSTART_SERVER="x11"
    elif [ "${AUTOSTART_SERVER:-none}" = "both" ]; then
        AUTOSTART_SERVER="$_target"
    fi
    [ "${AUTOSTART_SERVER:-none}" = "none" ] || lfa_conf_set "$CONF_FILE" AUTOSTART_SERVER "$AUTOSTART_SERVER"
    rm -f "$HOME/.config/linux-for-android/last-server-$INSTANCE_NAME" 2>/dev/null || true
    if [ "${DO_AUTOSTART:-0}" = "1" ] || boot_script_targets "$INSTANCE_NAME"; then
        local _boot_ssh="${DO_SSH:-0}"
        if [ "$_boot_ssh" != "1" ] && boot_script_targets "$INSTANCE_NAME" && boot_script_has_ssh; then
            _boot_ssh=1
        fi
        write_boot_script "$INSTANCE_NAME" "${AUTOSTART_SERVER:-none}" "$_boot_ssh"
    fi
    echo "[*] $INSTANCE_NAME now uses $_target."
    if [ "$_no_start" = "1" ]; then
        return 0
    fi
    if [ "$_was_running" = "1" ] && [ "${DE:-none}" != "none" ]; then
        local _start_backend="$_target"
        if [ "$_start_backend" = "both" ]; then
            case "$_old" in x11|vnc) _start_backend="$_old" ;; *) _start_backend="x11" ;; esac
        fi
        echo "[*] Restarting the desktop on $_start_backend..."
        nohup "$PREFIX/bin/start-linux" -i "$INSTANCE_NAME" \
            --server "$_start_backend" --desktop >/dev/null 2>&1 &
    fi
}

menu_change_backend() {
    CLI_INSTANCE=""
    select_installed_instance
    [ -n "$INSTANCE_NAME" ] || return
    local _cur="${SERVER:-none}" _target _remove=""
    if [ "${DE:-none}" = "none" ]; then
        echo ""
        echo "$INSTANCE_NAME is a CLI-only install (no desktop)."
        echo "Re-install it with a desktop to use display backends."
        ui_pause
        show_menu
        return
    fi
    if ! x11_supported; then
        echo ""
        echo "This device supports VNC only. Termux:X11 needs Android 8 (SDK 26)"
        echo "or newer, so X11 and Both are not offered here."
        echo "Current backend: $_cur (VNC)."
        ui_pause
        show_menu
        return
    fi
    local _def="1"
    case "$_cur" in vnc) _def="2" ;; both) _def="3" ;; esac
    if ! ui_select "Display backend for $INSTANCE_NAME (now: $_cur)" "$_def" \
        "1|Termux:X11|hardware acceleration" \
        "2|VNC|software rendering" \
        "3|Both|install both; choose each start"; then
        show_menu
        return
    fi
    case "$UI_SELECTED" in
        1) _target="x11" ;;
        2) _target="vnc" ;;
        3) _target="both" ;;
    esac
    if [ "$_cur" != "$_target" ] && [ "$_target" != "both" ]; then
        if ui_confirm "Remove the unused backend packages?" y; then
            _remove="--remove-old"
        fi
    fi
    change_backend "$_target" -i "$INSTANCE_NAME" $_remove || true
    ui_pause
    show_menu
}

set_autostart() {  # set_autostart x11|vnc|none [flags]
    local _srv="${1:-}"; shift || true
    case "$_srv" in x11|vnc|none) ;; *) echo "Usage: autostart x11|vnc|none" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            -i|--instance) CLI_INSTANCE="${2:-}"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    select_installed_instance || return 1
    [ -n "$INSTANCE_NAME" ] || return 1
    [ -f "$CONF_FILE" ] || { echo "[!] Missing config for $INSTANCE_NAME." >&2; return 1; }
    if [ "${DE:-none}" = "none" ] && [ "$_srv" != "none" ]; then
        echo "[!] $INSTANCE_NAME has no desktop installed (CLI-only)." >&2
        echo "    Autostart needs a desktop; re-install with one first." >&2
        return 1
    fi
    if [ "$_srv" = "x11" ] && ! x11_supported; then
        echo "[!] Termux:X11 requires Android 8 (SDK 26) or newer; use VNC." >&2
        return 1
    fi
    if [ "$_srv" = "vnc" ] && [ "${SERVER:-none}" != "vnc" ] && [ "${SERVER:-none}" != "both" ]; then
        echo "[!] $INSTANCE_NAME does not have VNC installed." >&2
        echo "    Run: lfa switch both -i $INSTANCE_NAME" >&2
        return 1
    fi
    if [ "$_srv" = "x11" ] && [ "${SERVER:-none}" != "x11" ] && [ "${SERVER:-none}" != "both" ]; then
        echo "[!] $INSTANCE_NAME does not have Termux:X11 enabled." >&2
        echo "    Run: lfa switch both -i $INSTANCE_NAME" >&2
        return 1
    fi
    AUTOSTART_SERVER="$_srv"
    if [ "$_srv" = "none" ]; then
        lfa_conf_set "$CONF_FILE" DO_AUTOSTART 0
    else
        lfa_conf_set "$CONF_FILE" DO_AUTOSTART 1
    fi
    lfa_conf_set "$CONF_FILE" AUTOSTART_SERVER "$_srv"
    local _boot_ssh="${DO_SSH:-0}"
    if [ "$_boot_ssh" != "1" ] && boot_script_targets "$INSTANCE_NAME" && boot_script_has_ssh; then
        _boot_ssh=1
    fi
    write_boot_script "$INSTANCE_NAME" "$_srv" "$_boot_ssh"
    echo "[*] $INSTANCE_NAME autostart: $_srv"
}

# Guest-side migration tweaks for an already-installed distro.
write_guest_upgrade_script() {
    if [ -f "$LFA_DIR/lib/uid0-build.sh" ]; then
        cp "$LFA_DIR/lib/uid0-build.sh" "$PREFIX/tmp/lfa-uid0-build.sh"
    fi
    cat > "$PREFIX/tmp/lfa-upgrade.sh" << 'UPGRADE'
#!/bin/bash
# Staged by install_linux.sh. Applies fixes that older installs miss.

# 1. EOL Debian bullseye: -security moved to archive.debian.org.
if [ -f /etc/apt/sources.list ] && grep -q 'deb.debian.org/debian-security bullseye-security' /etc/apt/sources.list 2>/dev/null; then
    sed -i 's|^deb http://deb.debian.org/debian-security bullseye-security |deb http://archive.debian.org/debian-security bullseye-security/updates |' /etc/apt/sources.list || true
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99-no-check-valid-until
    echo "    repointed EOL bullseye-security at archive.debian.org"
fi

# 2. uid0 emulation library (only when missing; needs a transient gcc).
#    The build itself lives in lib/uid0-build.sh, shared with the installer.
if [ -d /var/lib/dpkg ] && [ ! -s /usr/local/lib/libuid0.so ]; then
    echo " -> Rebuilding uid0 emulation library (one-time)..."
    apt-get update -qq >/dev/null 2>&1 || true
    if [ -f /tmp/lfa-uid0-build.sh ]; then
        sh /tmp/lfa-uid0-build.sh
    fi
    apt-get autoremove -y >/dev/null 2>&1 || true
fi
rm -f /tmp/uid0.c

# 3. Sanity: the sudo shim must still exist for user shells.
if [ -d /var/lib/dpkg ] && [ ! -x /usr/local/bin/sudo ]; then
    echo "    [!] sudo shim missing - reinstall the distro to restore it."
fi
echo " -> Guest tweaks applied."
UPGRADE
    chmod +x "$PREFIX/tmp/lfa-upgrade.sh"
}

# Option 12: bring a distro created by an older Linux-for-Android up to date
# with the current installer's tweaks, without reinstalling it.
upgrade_existing() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi

    local ROOTFS
    ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"
    local CONF
    CONF="$ROOTFS/etc/termux-linux-manager.conf"
    local LEGACY_CONF="$PREFIX/var/lib/proot-distro/installed-rootfs/$INSTANCE_NAME/etc/termux-linux-manager.conf"

    # proot-distro v4 uses containers/<name>/rootfs; older versions of this
    # manager wrote the conf into installed-rootfs. Move it to the real
    # rootfs so the guest and future tooling see the same settings.
    if [ ! -f "$CONF" ] && [ -f "$LEGACY_CONF" ]; then
        mkdir -p "$ROOTFS/etc"
        cp "$LEGACY_CONF" "$CONF"
        echo "[*] Migrated manager config into the real rootfs."
    fi

    # Load what the old install recorded; supply defaults for newer keys.
    USER_NAME="user"; DE="none"; SERVER="none"; RESOLUTION=""; PSTYLE="minimal"
    HOSTNAME="localhost"; TIMEZONE="UTC"; NEED_VIRGL="1"; COLOR_MODE="light"
    AUTOSTART_SERVER=""; DO_AUTOSTART=""; DO_SSH="0"
    if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        # shellcheck source=/dev/null
        source "$CONF" 2>/dev/null || true
    fi
    LINUX_USER="${USER_NAME:-user}"
    if ! echo "$LINUX_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then LINUX_USER="user"; fi
    if [ -z "$AUTOSTART_SERVER" ]; then
        case "$SERVER" in
            both) AUTOSTART_SERVER="vnc" ;;
            x11|vnc) AUTOSTART_SERVER="$SERVER" ;;
            *) AUTOSTART_SERVER="none" ;;
        esac
    fi

    echo "========================================="
    echo " Applying latest fixes to $INSTANCE_NAME"
    echo "========================================="
    echo "  user:     $LINUX_USER"
    echo "  desktop:  $DE ($SERVER)"
    echo "  hostname: ${HOSTNAME:-localhost}"
    echo ""

    # 1. Heal dpkg/apt and refresh the statoverride shim.
    run_guest_repair || true

    # 2. Add settings keys introduced by newer versions.
    if [ -f "$CONF" ]; then
        grep -q '^USER_NAME=' "$CONF" || echo "USER_NAME=\"$LINUX_USER\"" >> "$CONF"
        grep -q '^COLOR_MODE=' "$CONF" || echo 'COLOR_MODE="light"' >> "$CONF"
        grep -q '^TIMEZONE=' "$CONF" || echo 'TIMEZONE="UTC"' >> "$CONF"
        grep -q '^HOSTNAME=' "$CONF" || echo 'HOSTNAME="localhost"' >> "$CONF"
        grep -q '^NEED_VIRGL=' "$CONF" || echo 'NEED_VIRGL="1"' >> "$CONF"
        grep -q '^PSTYLE=' "$CONF" || echo 'PSTYLE="minimal"' >> "$CONF"
        if ! grep -q '^DO_AUTOSTART=' "$CONF"; then
            if [ -f "$HOME/.termux/boot/start-linux-services.sh" ] && \
               ! grep -q 'Desktop autostart is disabled' "$HOME/.termux/boot/start-linux-services.sh"; then
                echo 'DO_AUTOSTART="1"' >> "$CONF"
            else
                echo 'DO_AUTOSTART="0"' >> "$CONF"
            fi
        fi
        grep -q '^DO_SSH=' "$CONF" || echo 'DO_SSH="0"' >> "$CONF"
    fi

    # 2b. Offer the missing backend on an existing single-backend install.
    # Default is no, so an unattended migration never downloads packages.
    local _LEGACY_CLAMPED=0
    if [ "$DE" != "none" ]; then
        if [ "$IS_LEGACY" = "1" ] && [ "$SERVER" = "both" ]; then
            echo "[*] Android 5/6 cannot run Termux:X11; keeping VNC only."
            SERVER="vnc"
            _LEGACY_CLAMPED=1
        fi
        case "$SERVER" in
            x11)
                if ! vnc_guest_ready "$ROOTFS"; then
                    if ui_confirm "Add VNC to $INSTANCE_NAME? It installs $(vnc_pkg_for_distro)." n; then
                        echo "[*] Installing VNC packages..."
                        if guest_install_pkgs "$(vnc_pkg_for_distro)" && enable_vnc_backend; then
                            :
                        else
                            echo "[!] VNC install failed; keeping Termux:X11 only."
                        fi
                    fi
                elif ui_confirm "Enable VNC as a second backend for $INSTANCE_NAME?" n; then
                    enable_vnc_backend || echo "[!] VNC setup failed; keeping Termux:X11 only."
                fi
                ;;
            vnc)
                if [ "$IS_LEGACY" != "1" ] && ! command -v termux-x11 >/dev/null 2>&1; then
                    if ui_confirm "Add Termux:X11 to $INSTANCE_NAME? It installs the Termux X11 packages." n; then
                        echo "[*] Installing Termux:X11..."
                        if pkg install -y x11-repo && pkg install -y termux-x11-nightly; then
                            SERVER="both"
                        else
                            echo "[!] Termux:X11 install failed; keeping VNC only."
                        fi
                    fi
                elif [ "$IS_LEGACY" != "1" ] && ui_confirm "Enable Termux:X11 as a second backend for $INSTANCE_NAME?" n; then
                    SERVER="both"
                fi
                ;;
        esac
        if [ "$SERVER" = "both" ] && [ -f "$CONF" ]; then
            if grep -q '^SERVER=' "$CONF"; then
                sed -i 's/^SERVER=.*/SERVER="both"/' "$CONF"
            else
                echo 'SERVER="both"' >> "$CONF"
            fi
            # A backend added later starts with no remembered default.
            rm -f "$HOME/.config/linux-for-android/last-server-$INSTANCE_NAME" 2>/dev/null || true
        fi
        if [ "$_LEGACY_CLAMPED" = "1" ] && [ -f "$CONF" ]; then
            # Persist the clamp: leaving SERVER="both" in the file would make
            # start-linux show the unsupported X11 choice on the next boot.
            if grep -q '^SERVER=' "$CONF"; then
                sed -i 's/^SERVER=.*/SERVER="vnc"/' "$CONF"
            else
                echo 'SERVER="vnc"' >> "$CONF"
            fi
            if grep -q '^AUTOSTART_SERVER=' "$CONF"; then
                sed -i 's/^AUTOSTART_SERVER=.*/AUTOSTART_SERVER="vnc"/' "$CONF"
            else
                echo 'AUTOSTART_SERVER="vnc"' >> "$CONF"
            fi
            rm -f "$HOME/.config/linux-for-android/last-server-$INSTANCE_NAME" 2>/dev/null || true
        fi
        if [ -f "$CONF" ] && ! grep -q '^AUTOSTART_SERVER=' "$CONF"; then
            case "$SERVER" in
                both) echo 'AUTOSTART_SERVER="vnc"' >> "$CONF" ;;
                *)    echo "AUTOSTART_SERVER=\"$SERVER\"" >> "$CONF" ;;
            esac
        fi
    fi

    # 3. Realistic shell: prompt, banner, hostname command, clean env.
    if [ -f "$LFA_DIR/lib/real-feel.sh" ]; then
        LFA_ROOT="$ROOTFS" LFA_USER="$LINUX_USER" LFA_DE="$DE" \
            LFA_HOSTNAME="${HOSTNAME:-localhost}" LFA_PSTYLE="${PSTYLE:-minimal}" \
            sh "$LFA_DIR/lib/real-feel.sh" || true
        # Name proot-mapped Android GIDs inside the guest so `groups` stops
        # warning "cannot find name for group ID N" on every login.
        # shellcheck disable=SC2046  # flag list, not one argument
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- sh -c '
            gids="$(awk "/^Groups:/{for(i=2;i<=NF;i++) print \$i}" /proc/self/status 2>/dev/null)"
            for u in root "$1"; do gids="$gids $(id -G "$u" 2>/dev/null)"; done
            for g in $gids; do
                grep -q "^[^:]*:[^:]*:$g:" /etc/group 2>/dev/null || \
                    echo "lfa_gid_$g:x:$g:" >> /etc/group
            done
        ' sh "$LINUX_USER" >/dev/null 2>&1 || true
        echo "[*] Shell polished (prompt, banner, hostname, environment, gids)."
    fi

    # 3b. Distro wallpaper for GUI instances (skipped for CLI-only).
    if [ "$DE" != "none" ]; then
        local WALL_DISTRO="${DISTRO:-$INSTANCE_NAME}"
        apply_distro_wallpaper "$ROOTFS" "$LINUX_USER" "$WALL_DISTRO" "$DE" "${COLOR_MODE:-light}"
    fi

    # 4. Refresh the VNC xstartup (newer versions tolerate missing dbus).
    # TigerVNC 1.15 uses ~/.config/tigervnc and kills the session if xstartup
    # exits, so the desktop must be exec'd in the foreground. Write both the
    # legacy and modern locations, and carry the password across.
    local XVNC="$ROOTFS/home/$LINUX_USER/.vnc"
    local XCFG="$ROOTFS/home/$LINUX_USER/.config/tigervnc"
    if [ -f "$XVNC/xstartup" ] || server_has_vnc; then
        local SES=""
        case "$DE" in
            xfce4|xfce) SES="startxfce4" ;;
            lxde)       SES="startlxde" ;;
            mate)       SES="mate-session" ;;
            gnome)      SES="/usr/local/bin/start-gnome-session" ;;
        esac
        if [ -n "$SES" ]; then
            mkdir -p "$XVNC" "$XCFG"
            if [ -s "$XVNC/passwd" ] && [ ! -s "$XCFG/passwd" ]; then
                cp "$XVNC/passwd" "$XCFG/passwd"
            fi
            chmod 600 "$XVNC/passwd" "$XCFG/passwd" 2>/dev/null || true
            for XSTART in "$XVNC/xstartup" "$XCFG/xstartup"; do
                cat > "$XSTART" <<EOF
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PULSE_SERVER=127.0.0.1
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
export XDG_RUNTIME_DIR="/tmp/xdg-\$(id -un)"
mkdir -p "\$XDG_RUNTIME_DIR"
chmod 700 "\$XDG_RUNTIME_DIR"
if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- $SES
elif command -v dbus-launch >/dev/null 2>&1; then
    exec dbus-launch --exit-with-session $SES
else
    exec $SES
fi
EOF
                chmod 755 "$XSTART"
            done
            echo "[*] Refreshed VNC xstartup (legacy + modern TigerVNC)."
        fi
    fi

    # 5. Regenerate Termux launchers/shortcuts from current templates.
    write_launchers
    echo "[*] Launchers regenerated (start-linux / terminal-linux / stop-linux)."

    # 5b. A release can add packages an older install never had (dconf-cli
    # for GNOME, glycin loaders, ...). Report them with the exact command
    # instead of silently leaving a half-migrated distro.
    local _missing=""
    case "$DE" in
        xfce4) guest_has_path "$ROOTFS/usr/bin/xfce4-session" || _missing="$_missing xfce4-session" ;;
        lxde)  guest_has_path "$ROOTFS/usr/bin/startlxde" || _missing="$_missing lxde" ;;
        mate)  guest_has_path "$ROOTFS/usr/bin/mate-session" || _missing="$_missing mate-session" ;;
        gnome)
            guest_has_path "$ROOTFS/usr/bin/gnome-shell" || _missing="$_missing gnome-shell"
            guest_has_path "$ROOTFS/usr/bin/dconf" || _missing="$_missing dconf-cli"
            ;;
    esac
    if server_has_vnc; then
        if ! guest_has_path "$ROOTFS/usr/bin/vncserver" && ! guest_has_path "$ROOTFS/usr/bin/Xvnc"; then
            _missing="$_missing tigervnc"
        fi
    fi
    if [ -n "$_missing" ]; then
        echo ""
        echo "[!] This distro is missing components newer releases need:$_missing"
        case "$DISTRO" in
            ubuntu|debian|kali) echo "    Install with: proot-distro login $INSTANCE_NAME -- apt-get install -y$_missing" ;;
            fedora)             echo "    Install with: proot-distro login $INSTANCE_NAME -- dnf install -y$_missing" ;;
            opensuse)           echo "    Install with: proot-distro login $INSTANCE_NAME -- zypper install -y$_missing" ;;
            archlinux)          echo "    Install with: proot-distro login $INSTANCE_NAME -- pacman -S --noconfirm$_missing" ;;
            void)               echo "    Install with: proot-distro login $INSTANCE_NAME -- xbps-install -y$_missing" ;;
            alpine)             echo "    Install with: proot-distro login $INSTANCE_NAME -- apk add$_missing" ;;
            *)                  echo "    Install them with your package manager inside $INSTANCE_NAME." ;;
        esac
        echo "    Or re-run the installer for a clean install."
    fi

    # 6. Refresh the legacy bullseye plugin, if this device uses it.
    if [ -f "$PREFIX/etc/proot-distro/bullseye.sh" ] && [ -f "$LFA_DIR/plugins/bullseye.sh" ]; then
        cp "$LFA_DIR/plugins/bullseye.sh" "$PREFIX/etc/proot-distro/bullseye.sh"
        chmod +x "$PREFIX/etc/proot-distro/bullseye.sh"
        echo "[*] Refreshed legacy bullseye plugin."
    fi

    # 7. Guest-side tweaks (uid0 rebuild, EOL sources) on dpkg distros.
    if [ -d "$ROOTFS/var/lib/dpkg" ] && [ -f "$LFA_DIR/lib/uid0.c" ]; then
        cp "$LFA_DIR/lib/uid0.c" "$PREFIX/tmp/uid0.c"
        write_guest_upgrade_script
        # shellcheck disable=SC2046  # flag list, not one argument
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --shared-tmp -- bash /tmp/lfa-upgrade.sh || true
    fi

    echo "========================================="
    echo "Latest fixes applied!"
    echo "========================================="
    ui_pause
    show_menu 0
}

update_linux() {
    require_proot_distro || return
    select_installed_instance || return 1
    if [ -z "$INSTANCE_NAME" ]; then return 1; fi
    echo "[*] Updating $INSTANCE_NAME..."
    # Heal the guest first: stale statoverride rows and half-configured
    # packages make apt fail, and are repaired automatically here.
    run_guest_repair || true
    # shellcheck disable=SC2046  # flag list, not one argument
    proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --user root -- bash -c "export DEBIAN_FRONTEND=noninteractive; $UPDATE_CMD"
    echo "========================================="
    ui_ok "Update complete!"
    echo "========================================="
    ui_pause
    show_menu 0
}

start_ssh() {
    echo "[*] Starting Termux SSH Server..."
    if ! command -v sshd >/dev/null 2>&1; then
        pkg install -y openssh 2>/dev/null || pkg install openssh -y || true
    fi
    if ! command -v sshd >/dev/null 2>&1; then
        echo "ERROR: openssh unavailable on this repo."
        ui_pause
        show_menu
        return
    fi
    sshd 2>/dev/null || true
    IP=$(ifconfig 2>/dev/null | grep -E 'inet .*broadcast' | awk '{print $2}' | head -n 1 || true)
    if [ -z "$IP" ]; then IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1 || true); fi
    if [ -z "$IP" ]; then IP="YOUR_PHONE_IP"; fi
    echo "========================================="
    echo "SSH Server is running!"
    echo "To connect from your PC, run this command in your PC's terminal:"
    echo ""
    echo "   ssh $(whoami)@$IP -p 8022"
    echo ""
    echo "Note: If you have never set a Termux password, type 'passwd' right now to create one."
    echo "========================================="
    ui_pause
    show_menu
}

backup_linux() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    echo "[*] Backing up $INSTANCE_NAME (Internal)..."
    proot-distro backup "$INSTANCE_NAME" --output ~/${INSTANCE_NAME}-backup.tar.gz
    ui_ok "Backup saved to ~/${INSTANCE_NAME}-backup.tar.gz"
    ui_pause
    show_menu
}

restore_linux() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    if [ ! -f ~/${INSTANCE_NAME}-backup.tar.gz ]; then
        echo "Error: No internal backup found at ~/${INSTANCE_NAME}-backup.tar.gz"
    else
        echo "[*] Restoring $INSTANCE_NAME..."
        if ui_confirm "Restore $INSTANCE_NAME? This overwrites current data" n; then
            if pd_is_v4; then
                echo "[*] (modern proot-distro: restores the instance stored in the backup)"
                proot-distro restore ~/${INSTANCE_NAME}-backup.tar.gz
            else
                proot-distro restore "$INSTANCE_NAME" --input ~/${INSTANCE_NAME}-backup.tar.gz
            fi
            ui_ok "Restore complete!"
        fi
    fi
    ui_pause
    show_menu
}

export_distro() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    if [ ! -d ~/storage ]; then
        echo "[*] Requesting Android Storage Permission..."
        termux-setup-storage || true
        sleep 2
    fi
    mkdir -p ~/storage/downloads/
    echo "[*] Exporting $INSTANCE_NAME to Android Downloads folder (This may take a while)..."
    proot-distro backup "$INSTANCE_NAME" --output ~/storage/downloads/${INSTANCE_NAME}-shared.tar.gz
    echo "========================================="
    ui_ok "Export Complete!"
    echo "File saved to: Downloads/${INSTANCE_NAME}-shared.tar.gz"
    echo "You can now share this file with your friends via Google Drive or USB!"
    echo "========================================="
    ui_pause
    show_menu
}

import_distro() {
    require_proot_distro || return
    if [ ! -d ~/storage ]; then
        echo "[*] Requesting Android Storage Permission..."
        termux-setup-storage || true
        sleep 2
    fi
    read -p "Enter filename from Downloads folder to import (e.g. ubuntu-shared.tar.gz): " IMPORT_FILE
    if [ ! -f ~/storage/downloads/$IMPORT_FILE ]; then
        echo "========================================="
        echo "Error: File not found!"
        echo "Make sure your friend's file is named exactly '$IMPORT_FILE'"
        echo "and is placed inside your phone's 'Downloads' folder."
        echo "========================================="
    else
        if pd_is_v4; then
            echo "[*] (modern proot-distro: imports the instance stored in the file)"
            if ui_confirm "Import $IMPORT_FILE? This overwrites that instance" n; then
                proot-distro restore ~/storage/downloads/$IMPORT_FILE
                echo "========================================="
                echo "Import complete! You can now use start-linux to boot it."
                echo "========================================="
            fi
        else
            read -p "Enter new instance name for this import (e.g. my-ubuntu): " INSTANCE_NAME
            echo "[*] Importing $INSTANCE_NAME from Downloads..."
            if ui_confirm "Overwrite the current $INSTANCE_NAME installation?" n; then
                proot-distro restore "$INSTANCE_NAME" --input ~/storage/downloads/$IMPORT_FILE
                echo "========================================="
                echo "Import complete! You can now use start-linux to boot your friend's setup."
                echo "========================================="
            fi
        fi
    fi
    ui_pause
    show_menu
}

optimize_browser() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    if ! ui_select "Browser hardware acceleration" "1" \
        "1|Enable VirGL|smooth YouTube and GPU rendering" \
        "2|Disable|revert to Chromium defaults"; then
        show_menu
        return
    fi
    OPT_CHOICE="$UI_SELECTED"

    if [ "$OPT_CHOICE" == "1" ]; then
        echo "[*] Optimizing Chromium for Hardware Accelerated Video Decoding..."
        # shellcheck disable=SC2046  # flag list, not one argument
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- bash -c '
mkdir -p /etc
echo "--ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --use-gl=egl" > /etc/lfa-chromium-flags
if [ ! -x /usr/local/bin/chromium ]; then
    REAL=""
    [ -x /usr/bin/chromium ] && REAL=/usr/bin/chromium
    [ -z "$REAL" ] && [ -x /usr/bin/chromium-browser ] && REAL=/usr/bin/chromium-browser
    if [ -n "$REAL" ]; then
        cat > /usr/local/bin/chromium <<WRAP
#!/bin/sh
FLAGS="\$(cat /etc/lfa-chromium-flags 2>/dev/null)"
exec $REAL --no-sandbox --disable-dev-shm-usage \$FLAGS "\$@"
WRAP
        chmod +x /usr/local/bin/chromium
        ln -sf /usr/local/bin/chromium /usr/local/bin/chromium-browser
    fi
fi
'
        echo "========================================="
        ui_ok "Optimization complete! Chromium will now render using VirGL!"
        echo "========================================="
    elif [ "$OPT_CHOICE" == "2" ]; then
        echo "[*] Removing Hardware Acceleration Overrides..."
        # shellcheck disable=SC2046  # flag list, not one argument
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- bash -c '
rm -f /etc/lfa-chromium-flags
'
        echo "========================================="
        ui_ok "Hardware Acceleration disabled. Restored to default!"
        echo "========================================="
    else
        echo "Invalid selection."
    fi
    ui_pause
    show_menu
}

# Install the distro's default wallpaper into a GUI rootfs.
# CLI-only installs (DE=none) intentionally skip this: no desktop, no
# backdrop config, and no extra asset copied into the guest.
apply_distro_wallpaper() { # $1=rootfs $2=user $3=distro $4=desktop-env $5=mode
    local root="$1" user="$2" distro="$3" de="$4" mode="${5:-light}"
    [ "$de" = "none" ] && return 0
    [ -f "$LFA_DIR/lib/wallpaper.sh" ] || return 0
    [ -d "$root" ] || return 0
    LFA_ROOT="$root" LFA_USER="$user" LFA_DISTRO="$distro" LFA_DE="$de" \
        LFA_MODE="$mode" LFA_ASSET_DIR="$LFA_DIR/assets/wallpapers" \
        sh "$LFA_DIR/lib/wallpaper.sh" || true
}

write_launchers() {
    mkdir -p ~/.shortcuts
    cat > "$PREFIX/bin/lfa-lib.sh" << 'EOF'
#!/bin/bash
# Shared proot-distro layout helpers.
#   v3 and earlier: installed-rootfs/<name>
#   v4 and later:   containers/<name>/rootfs
PD_BASE="$PREFIX/var/lib/proot-distro"
lfa_instances() {
    _d=""
    {
        if [ -d "$PD_BASE/containers" ]; then
            for _d in "$PD_BASE/containers"/*; do
                [ -d "$_d" ] && basename "$_d"
            done
        fi
        for _d in "$PD_BASE/installed-rootfs"/*; do
            [ -d "$_d" ] || continue
            { [ -d "$_d/var" ] || [ -d "$_d/usr" ] || [ -d "$_d/bin" ]; } || continue
            basename "$_d"
        done
    } | awk '!seen[$0]++'
    unset _d
}
lfa_rootfs() {
    if [ -d "$PD_BASE/containers/$1/rootfs" ]; then
        echo "$PD_BASE/containers/$1/rootfs"
    else
        echo "$PD_BASE/installed-rootfs/$1"
    fi
}
lfa_conf() {
    local r
    r="$(lfa_rootfs "$1")/etc/termux-linux-manager.conf"
    if [ -f "$r" ]; then
        echo "$r"
    else
        echo "$PD_BASE/installed-rootfs/$1/etc/termux-linux-manager.conf"
    fi
}
# Display :1 is shared by every distro and by both back ends. A dead X server
# leaves /tmp/.X11-unix/X1 and /tmp/.X1-lock behind, and the next start then
# fails with "display :1 is taken" (VNC) or talks to a dead socket (X11).
# Only a real X server counts: this script line itself mentions Xvnc, so a
# `pgrep -f` match is not proof that anything is running.
lfa_x1_server_pid() {
    local pid lock="$PREFIX/tmp/.X1-lock" c a0
    # Is this argv[0] one of the X servers this script cares about?
    # Compare the basename:
    # inside proot the binary is exec'd with an absolute path, and the launcher
    # itself is a bash line that merely *mentions* Xvnc, so neither a bare
    # `pgrep -f Xvnc` nor an anchored `^Xvnc` is correct.
    lfa_is_x_server() {
        a0="${1%% *}"
        a0="${a0##*/}"
        case "$a0" in
            Xvnc|Xtigervnc|Xorg|X|termux-x11) return 0 ;;
        esac
        return 1
    }
    if [ -f "$lock" ]; then
        pid=$(tr -dc '0-9' < "$lock" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            c=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
            if lfa_is_x_server "$c"; then
                case " $c " in *" :1 "*) echo "$pid"; return 0 ;; esac
            fi
        fi
    fi
    # No usable lock (or it points at something else): scan /proc directly.
    # pgrep -f is avoided on purpose - its pattern language differs between
    # procps and busybox builds, and the match must be on argv[0].
    # LFA_X1_PROC_ROOT exists so the test suite can hide a real desktop
    # session while it exercises this function; production always uses /proc.
    for c in "${LFA_X1_PROC_ROOT:-/proc}"/[0-9]*/cmdline; do
        [ -r "$c" ] || continue
        pid="${c%/*}"; pid="${pid##*/}"
        [ "$pid" = "$$" ] && continue
        local _cmd
        _cmd=$(tr '\0' ' ' < "$c" 2>/dev/null) || continue
        [ -n "$_cmd" ] || continue
        lfa_is_x_server "$_cmd" || continue
        case " $_cmd " in *" :1 "*) echo "$pid"; return 0 ;; esac
    done
    return 1
}
lfa_clear_stale_x1() {
    lfa_x1_server_pid >/dev/null 2>&1 && return 0
    rm -f "$PREFIX/tmp/.X11-unix/X1" "$PREFIX/tmp/.X1-lock" 2>/dev/null || true
}
# Display :1 is a singleton. Starting one backend while the other still owns
# :1 makes the guest attach its desktop to the wrong X server: Xvnc then
# serves a display whose window manager dies with a GLX BadValue, or
# Termux:X11 shows only the root cursor. Free the display from the other
# backend first. Only the process holding :1 is touched.
lfa_stop_termux_x11() {
    local _p
    for _p in $(pgrep -f '^termux-x11 .* :1( |$)' 2>/dev/null); do
        kill "$_p" 2>/dev/null || true
    done
    sleep 1
    for _p in $(pgrep -f '^termux-x11 .* :1( |$)' 2>/dev/null); do
        kill -9 "$_p" 2>/dev/null || true
    done
}
lfa_stop_vnc_display() {
    local _inst _u
    for _inst in $(lfa_instances); do
        _u="$(sed -n 's/^USER_NAME="\(.*\)"$/\1/p' "$(lfa_conf "$_inst")" 2>/dev/null | head -n 1)"
        [ -n "$_u" ] || _u=user
        # A wedged guest must not block the next backend from starting.
        # shellcheck disable=SC2086  # NO_SYSVIPC is empty or one flag
        if command -v timeout >/dev/null 2>&1; then
            timeout 15 proot-distro login ${NO_SYSVIPC:-} "$_inst" --user "$_u" --shared-tmp -- \
                bash -c "vncserver -kill :1" >/dev/null 2>&1 || true
        else
            proot-distro login ${NO_SYSVIPC:-} "$_inst" --user "$_u" --shared-tmp -- \
                bash -c "vncserver -kill :1" >/dev/null 2>&1 || true
        fi
    done
    pkill -f '^/usr/bin/Xvnc :1( |$)' 2>/dev/null || true
    pkill -f '^/usr/bin/Xtigervnc :1( |$)' 2>/dev/null || true
    pkill -f '^/usr/bin/vncserver :1( |$)' 2>/dev/null || true
    pkill -f '^/usr/bin/perl /usr/bin/vncserver :1( |$)' 2>/dev/null || true
    rm -f "$PREFIX/tmp/lfa-vnc-"*.pid 2>/dev/null || true
    sleep 1
}
lfa_free_display_for() {  # $1 = backend about to start (x11|vnc)
    local _owner _cmd
    _owner="$(lfa_x1_server_pid 2>/dev/null || true)"
    if [ -n "$_owner" ]; then
        _cmd="$(tr '\0' ' ' < "/proc/$_owner/cmdline" 2>/dev/null)"
        case "$1" in
            x11)
                case "$_cmd" in
                    *Xvnc*|*Xtigervnc*)
                        echo "Stopping VNC on display :1 so Termux:X11 can use it..."
                        lfa_stop_vnc_display ;;
                esac ;;
            vnc)
                case "$_cmd" in
                    *termux-x11*)
                        echo "Stopping Termux:X11 on display :1 so VNC can use it..."
                        lfa_stop_termux_x11 ;;
                esac ;;
        esac
    fi
    lfa_clear_stale_x1
}
# VirGL can be present but unusable. Some Android GPU drivers expose
# virgl_test_server_android while GLX context creation still fails; the
# window manager then dies with "Could not create GLX context" and the
# desktop has no decorations. Watch the session log, and retry once with
# software rendering, recording the choice in the instance config so later
# starts skip the broken path.
lfa_virgl_watch() {  # $1=instance $2=backend $3...=logs
    local _inst="$1" _backend="$2" _conf _f _i _found=0 _lock _old
    shift 2
    [ "${NEED_VIRGL:-1}" = "1" ] || return 0
    # A start can be repeated quickly (menu, scripts, tests). Only one
    # watcher per instance/backend may act, or two fallbacks can stop each
    # other's fresh session.
    _lock="$PREFIX/tmp/lfa-virgl-$_inst-$_backend.lock"
    if ! mkdir "$_lock" 2>/dev/null; then
        _old="$(cat "$_lock/pid" 2>/dev/null || true)"
        if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then return 0; fi
        rm -rf "$_lock" 2>/dev/null || true
        mkdir "$_lock" 2>/dev/null || return 0
    fi
    echo "$$" > "$_lock/pid" 2>/dev/null || true
    trap 'rm -rf "$_lock" 2>/dev/null || true' EXIT
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        sleep 1
        _found=0
        for _f in "$@"; do
            [ -f "$_f" ] || continue
            if grep -qiE 'failed to create drisw screen|Could not create GLX context' "$_f" 2>/dev/null; then
                _found=1
                break
            fi
        done
        [ "$_found" = "1" ] || continue
        # Do not undo a deliberate stop: only retry while the desktop is
        # still supposed to be up.
        if [ "$_backend" = "vnc" ]; then
            (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null || return 0
        else
            pgrep -f '^termux-x11 .* :1( |$)' >/dev/null 2>&1 || return 0
        fi
        echo "[!] VirGL cannot create a GLX context; retrying $_inst with software rendering (llvmpipe)." >&2
        _conf="$(lfa_conf "$_inst")"
        sed -i 's/^NEED_VIRGL=.*/NEED_VIRGL="0"/' "$_conf" 2>/dev/null || true
        if grep -q '^NEED_VIRGL="0"' "$_conf" 2>/dev/null; then
            "$PREFIX/bin/stop-linux" -i "$_inst" >/dev/null 2>&1 || true
            nohup "$PREFIX/bin/start-linux" -i "$_inst" --backend "$_backend" --desktop >/dev/null 2>&1 &
            echo "[i] Restarted with llvmpipe. Re-enable VirGL from the installer if a driver update fixes it." >&2
        else
            echo "[!] Could not write NEED_VIRGL=0 to $_conf; not restarting." >&2
        fi
        return 0
    done
}
# A pidfile can outlive its process: after a reboot the recorded PID may
# belong to something completely unrelated. Verify the command line before
# signalling anything.
lfa_pid_matches() {   # $1 = pid, rest = patterns that must appear in cmdline
    local _pid="$1" _cmd _pat
    shift
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)" || return 1
    [ -n "$_cmd" ] || return 1
    for _pat in "$@"; do
        case "$_cmd" in *"$_pat"*) return 0 ;; esac
    done
    return 1
}
# Is a real desktop session for this instance running? A terminal login also
# contains the instance path, so only a session command counts.
lfa_instance_session_running() {  # $1 = instance
    local _c _cmd
    for _c in /proc/[0-9]*/cmdline; do
        [ -r "$_c" ] || continue
        _cmd="$(tr '\0' ' ' < "$_c" 2>/dev/null)" || continue
        case "$_cmd" in
            *"/containers/$1/"*|*"/installed-rootfs/$1/"*)
                case "$_cmd" in
                    *startxfce4*|*startlxde*|*mate-session*|*gnome-shell*|*start-gnome-session*) return 0 ;;
                esac ;;
        esac
    done
    return 1
}
EOF
    chmod +x "$PREFIX/bin/lfa-lib.sh"
    echo "[*] Generating Universal Quick-Launch Scripts..."
    cat << 'EOF' > $PREFIX/bin/start-linux
#!/bin/bash
if [ -f "$PREFIX/bin/lfa-lib.sh" ]; then
    . "$PREFIX/bin/lfa-lib.sh"
else
    lfa_instances() { ls -1 "$PREFIX/var/lib/proot-distro/installed-rootfs" 2>/dev/null; }
    lfa_rootfs() { echo "$PREFIX/var/lib/proot-distro/installed-rootfs/$1"; }
    lfa_conf() { echo "$(lfa_rootfs "$1")/etc/termux-linux-manager.conf"; }
    lfa_clear_stale_x1() { local _p=999999; [ -f "$PREFIX/tmp/.X1-lock" ] && _p=$(tr -dc '0-9' < "$PREFIX/tmp/.X1-lock" 2>/dev/null); [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null && return 0; rm -f "$PREFIX/tmp/.X11-unix/X1" "$PREFIX/tmp/.X1-lock" 2>/dev/null; }
    lfa_pid_matches() { local _p="$1" _c; shift; [ -n "$_p" ] || return 1; kill -0 "$_p" 2>/dev/null || return 1; _c="$(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null)" || return 1; for _pat in "$@"; do case "$_c" in *"$_pat"*) return 0 ;; esac; done; return 1; }
fi

usage() {
    cat <<'USAGE'
Usage: start-linux [options]

  -i, --instance NAME   start a specific distro
  -b, --backend NAME    x11 or vnc
      --x11             shortcut for --backend x11
      --vnc             shortcut for --backend vnc
      --desktop         start the desktop without the terminal menu
      --restart         stop a running desktop, then start a fresh one
      --no-notice       hide the start-linux change notice for this run
  -h, --help            show this help
USAGE
}

# Non-interactive entry used by Termux:Boot and the new CLI.
DESKTOP_ONLY=0
NO_NOTICE=0
RESTART_SESSION=0
EXPLICIT_INSTANCE=0
PRESELECT_INSTANCE=""
PRESELECT_SERVER=""
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--instance) PRESELECT_INSTANCE="${2:-}"; EXPLICIT_INSTANCE=1; shift 2 ;;
        -b|--backend|--server) PRESELECT_SERVER="${2:-}"; shift 2 ;;
        --x11) PRESELECT_SERVER="x11"; shift ;;
        --vnc) PRESELECT_SERVER="vnc"; shift ;;
        --desktop) DESKTOP_ONLY=1; shift ;;
        --restart) RESTART_SESSION=1; shift ;;
        --no-notice) NO_NOTICE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
if [ -n "$PRESELECT_SERVER" ]; then
    case "$PRESELECT_SERVER" in
        x11|vnc) ;;
        *) echo "Backend must be x11 or vnc." >&2; exit 2 ;;
    esac
fi

# One-time-change notice, shown on interactive classic runs. It goes to
# stderr so scripts that parse start-linux output are unaffected.
NOTICE_FILE="$HOME/.config/linux-for-android/preferences.conf"
START_NOTICE=1
if [ -r "$NOTICE_FILE" ]; then
    # shellcheck source=/dev/null
    . "$NOTICE_FILE" 2>/dev/null || true
fi
if [ "$DESKTOP_ONLY" != "1" ] && [ "$NO_NOTICE" != "1" ] && \
   [ "${LFA_NO_NOTICE:-0}" != "1" ] && [ "${START_NOTICE:-1}" != "0" ] && \
   [ -t 0 ] && [ -t 1 ]; then
    printf '%s\n' "" >&2
    printf '  [i] start-linux now opens the advanced menu.\n' >&2
    printf '\n' >&2
    printf '      For daily use:\n' >&2
    printf '        linux              start the desktop\n' >&2
    printf '        lfa shell          open a terminal\n' >&2
    printf '        lfa switch vnc     change backend\n' >&2
    printf '        lfa help           list all commands\n' >&2
    printf '\n' >&2
    printf '      Disable this notice: lfa notice off\n' >&2
    printf '\n' >&2
fi

# Prefer the last instance for the one-command desktop shortcut.
LAST_INSTANCE_FILE="$HOME/.config/linux-for-android/last-instance"
if [ -z "$PRESELECT_INSTANCE" ] && [ -r "$LAST_INSTANCE_FILE" ]; then
    PRESELECT_INSTANCE="$(cat "$LAST_INSTANCE_FILE" 2>/dev/null || true)"
fi

mapfile -t DISTROS < <(lfa_instances)
if [ -n "$PRESELECT_INSTANCE" ]; then
    _ok=0
    for _d in "${DISTROS[@]}"; do [ "$_d" = "$PRESELECT_INSTANCE" ] && _ok=1; done
    if [ "$_ok" != "1" ]; then
        if [ "$EXPLICIT_INSTANCE" = "1" ]; then
            echo "No installed distribution named '$PRESELECT_INSTANCE'." >&2
            exit 1
        fi
        PRESELECT_INSTANCE=""
    fi
fi
if [ ${#DISTROS[@]} -eq 0 ]; then
    echo "No distributions installed. Please run install_linux.sh first."
    exit 1
elif [ -n "$PRESELECT_INSTANCE" ]; then
    DISTRO="$PRESELECT_INSTANCE"
elif [ ${#DISTROS[@]} -eq 1 ]; then
    DISTRO=${DISTROS[0]}
else
    echo "Multiple distributions found. Please choose one to start:"
    for i in "${!DISTROS[@]}"; do
        echo "$((i+1))) ${DISTROS[$i]}"
    done
    read -p "Select a distro [1-${#DISTROS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DISTROS[@]}" ]; then
        echo "Invalid selection."
        exit 1
    fi
    idx=$((choice-1))
    DISTRO=${DISTROS[$idx]}
fi

mkdir -p "$(dirname "$LAST_INSTANCE_FILE")" 2>/dev/null || true
printf '%s\n' "$DISTRO" > "$LAST_INSTANCE_FILE" 2>/dev/null || true

CONF_FILE="$(lfa_conf "$DISTRO")"
INSTANCE_NAME="$DISTRO"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    DE="none"
    SERVER="none"
fi
# The conf stores the BASE distro name in $DISTRO; restore the instance
# (directory) name or every login targets a non-installed alias.
DISTRO="$INSTANCE_NAME"
X11_USER="${USER_NAME:-${LINUX_USER:-user}}"

# Old proot (frozen Android 5 repos) has no --sysvipc, but proot-distro
# login passes it by default -> opt out when the combination requires it.
NO_SYSVIPC=""
if ! proot --help 2>&1 | grep -q "sysvipc"; then
    if [ -f "$PREFIX/bin/proot-distro" ] && grep -q "no-sysvipc" "$PREFIX/bin/proot-distro" 2>/dev/null; then
        NO_SYSVIPC="--no-sysvipc"
    fi
fi

# GUI installs can boot the full desktop or drop straight to a shell.
# CLI-only installs go directly to a root terminal.
LAST_SERVER_FILE="$HOME/.config/linux-for-android/last-server-$INSTANCE_NAME"
LAST_SERVER=""
if [ -r "$LAST_SERVER_FILE" ]; then
    LAST_SERVER="$(cat "$LAST_SERVER_FILE" 2>/dev/null || true)"
fi
case "$LAST_SERVER" in x11|vnc) ;; *) LAST_SERVER="" ;; esac
SERVER_MODE="$SERVER"

MODE="desktop"
if [ "$DESKTOP_ONLY" = "1" ]; then
    if [ -n "$PRESELECT_SERVER" ]; then
        case "$SERVER:$PRESELECT_SERVER" in
            both:x11|x11:x11|both:vnc|vnc:vnc) SERVER="$PRESELECT_SERVER" ;;
            *)
                echo "Requested backend '$PRESELECT_SERVER' is not installed for $INSTANCE_NAME." >&2
                exit 1
                ;;
        esac
    elif [ "$SERVER" = "both" ]; then
        if [ -n "$LAST_SERVER" ]; then
            SERVER="$LAST_SERVER"
        elif [ -t 0 ]; then
            echo ""
            echo "Desktop available: $DE via Termux:X11 or VNC."
            echo "1) Full desktop with Termux:X11"
            echo "2) Full desktop with VNC"
            read -p "Select [1-2]: " MODE_CHOICE
            case "$MODE_CHOICE" in
                1) SERVER="x11" ;;
                2) SERVER="vnc" ;;
                *) echo "Invalid selection." >&2; exit 1 ;;
            esac
        else
            echo "Both backends are installed but no default is remembered." >&2
            echo "Run: linux --x11   or   linux --vnc" >&2
            exit 1
        fi
    elif [ "$SERVER" != "x11" ] && [ "$SERVER" != "vnc" ]; then
        echo "No desktop is installed for $INSTANCE_NAME." >&2
        exit 1
    fi
else
MODE="desktop"
if [ -n "$PRESELECT_SERVER" ]; then
    case "$SERVER:$PRESELECT_SERVER" in
        both:x11|x11:x11|both:vnc|vnc:vnc) SERVER="$PRESELECT_SERVER" ;;
        *)
            echo "Requested backend '$PRESELECT_SERVER' is not installed for $INSTANCE_NAME."
            exit 1
            ;;
    esac
elif [ "$SERVER" = "both" ]; then
    echo ""
    echo "Desktop available: $DE via Termux:X11 or VNC."
    echo "1) Full desktop with Termux:X11"
    echo "2) Full desktop with VNC"
    echo "3) Root terminal only (no display/audio servers)"
    echo "4) User terminal only (no display/audio servers)"
    if [ -n "$LAST_SERVER" ]; then
        if [ "$LAST_SERVER" = "x11" ]; then
            _last_choice="1"
            _last_label="Termux:X11"
        else
            _last_choice="2"
            _last_label="VNC"
        fi
        read -p "Select [1-4] (default: $_last_label): " MODE_CHOICE
        [ -z "$MODE_CHOICE" ] && MODE_CHOICE="$_last_choice"
    else
        read -p "Select [1-4]: " MODE_CHOICE
    fi
    case "$MODE_CHOICE" in
        1) SERVER="x11" ;;
        2) SERVER="vnc" ;;
        3) MODE="root" ;;
        4) MODE="user" ;;
        *)
            echo "Invalid selection."
            exit 1
            ;;
    esac
elif [ "$SERVER" == "x11" ] || [ "$SERVER" == "vnc" ]; then
    echo ""
    echo "Desktop available: $DE via $SERVER."
    echo "1) Start full desktop (default)"
    echo "2) Root terminal only (no display/audio servers)"
    echo "3) User terminal only (no display/audio servers)"
    read -p "Select [1-3]: " MODE_CHOICE
    if [ "$MODE_CHOICE" == "2" ]; then MODE="root"
    elif [ "$MODE_CHOICE" == "3" ]; then MODE="user"
    fi
else
    echo ""
    echo "No desktop installed (CLI only)."
    echo "1) Root terminal (default, admin)"
    echo "2) User terminal ('$X11_USER' account)"
    read -p "Select [1-2]: " MODE_CHOICE
    if [ "$MODE_CHOICE" == "2" ]; then MODE="user"; else MODE="root"; fi
fi

fi

if [ "$SERVER_MODE" = "both" ] && [ "$MODE" == "desktop" ]; then
    mkdir -p "$(dirname "$LAST_SERVER_FILE")" 2>/dev/null || true
    printf '%s\n' "$SERVER" > "$LAST_SERVER_FILE" 2>/dev/null || true
fi

if [ "$MODE" == "root" ]; then
    proot-distro login $NO_SYSVIPC $DISTRO --shared-tmp -- /bin/bash -l
    exit 0
elif [ "$MODE" == "user" ]; then
    proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- /bin/bash -l
    exit 0
fi

# Never start a second session on display :1. Two xfce4-session processes
# fight for the window manager, and the desktop that loses leaves only the
# root cross cursor. Replace a broken session with --restart.
if lfa_instance_session_running "$DISTRO"; then
    if [ "$RESTART_SESSION" = "1" ]; then
        echo "Restarting the desktop for $DISTRO..."
        "$PREFIX/bin/stop-linux" -i "$DISTRO" >/dev/null 2>&1 || true
    else
        echo "A desktop for $DISTRO is already running on display :1."
        echo "  stop it:    stop-linux -i $DISTRO"
        echo "  restart it: linux -i $DISTRO --restart"
        exit 0
    fi
fi

echo "Starting PulseAudio..."
if command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || echo "[!] PulseAudio not available on this device, continuing without audio."
else
    echo "[!] pulseaudio not installed, skipping audio (legacy device OK)."
fi

echo "Starting VirGL Server..."
VIRGL_ENV=""
if command -v virgl_test_server_android >/dev/null 2>&1 && [ "${NEED_VIRGL:-1}" = "1" ]; then
    nohup virgl_test_server_android >/dev/null 2>&1 &
    VIRGL_ENV="export GALLIUM_DRIVER=virpipe; export MESA_GL_VERSION_OVERRIDE=4.0;"
elif [ "${NEED_VIRGL:-1}" != "1" ]; then
    echo "[*] Hardware acceleration disabled by setup choice."
else
    echo "[!] virgl_test_server_android not found, continuing with software rendering (expected on Android 5/6)."
fi

if [ "$SERVER" == "x11" ]; then
    # Termux:X11 needs Android 8 (SDK 26). Configs copied from another
    # device can still say x11 on Android 7.0/7.1; fail with a clear
    # instruction instead of trying to install an unusable package.
    _lfa_sdk="$(getprop ro.build.version.sdk 2>/dev/null | tr -cd '0-9')"
    if [ -n "$_lfa_sdk" ] && [ "$_lfa_sdk" -gt 0 ] && [ "$_lfa_sdk" -lt 26 ]; then
        echo "ERROR: Termux:X11 requires Android 8 (SDK 26) or newer." >&2
        echo "This device reports SDK $_lfa_sdk. Start with VNC instead:" >&2
        echo "  linux --vnc" >&2
        exit 1
    fi
    # An install that chose VNC never pulled the X11 packages. Switching the
    # distro to X11 later (re-install / menu 12) used to dead-end here.
    if ! command -v termux-x11 >/dev/null 2>&1; then
        _x11log="$PREFIX/tmp/lfa-x11-install.log"
        echo "Termux:X11 is not installed yet - installing it now..."
        echo "  (log: $_x11log)"
        { pkg install -y x11-repo && pkg install -y termux-x11-nightly; } \
            >> "$_x11log" 2>&1 || true
    fi
    if ! command -v termux-x11 >/dev/null 2>&1; then
        echo "ERROR: Termux:X11 could not be installed."
        echo "Read the log:  tail -n 20 \"$PREFIX/tmp/lfa-x11-install.log\""
        echo "Common cause: the Termux mirror is mid-sync. Retry with:"
        echo "  pkg update && pkg install x11-repo && pkg install termux-x11-nightly"
        echo "or switch this distro to VNC by re-running the installer."
        exit 1
    fi
    echo "Starting Termux:X11..."
    # Every distro shares $PREFIX/tmp. A dead D-Bus or X socket left by a
    # previous session makes the new desktop reuse a dead bus ("Unable to
    # contact settings server"). Clear this user's per-session state first.
    rm -rf "$PREFIX/tmp/xdg-$X11_USER-$DISTRO" "$PREFIX/tmp/xdg-$X11_USER" 2>/dev/null || true
    rm -f "$PREFIX"/tmp/dbus-* 2>/dev/null || true
    rm -rf "$(lfa_rootfs "$DISTRO")/home/$X11_USER/.dbus/session-bus" 2>/dev/null || true
    # /tmp is shared with the guest. Pre-create the ICE socket directory as
    # root-owned 1777; the unprivileged desktop user cannot create it.
    mkdir -p "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.ICE-unix" 2>/dev/null || true
    chmod 1777 "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.ICE-unix" 2>/dev/null || true
    # A dead VNC server can leave /tmp/.X11-unix/X1 + /tmp/.X1-lock behind (all
    # distros share /tmp). Termux:X11 then refuses to start and clients talk to
    # a dead socket. Drop them only when no real X server holds display :1.
    # A live VNC server on :1 is stopped: only one backend can own the display.
    lfa_free_display_for x11
    nohup termux-x11 :1 >/dev/null 2>&1 &
    # Wait for the socket instead of guessing: slow devices need longer,
    # fast ones should not be delayed.
    for _i in $(seq 1 15); do
        [ -S "$PREFIX/tmp/.X11-unix/X1" ] && break
        sleep 1
    done
    # XDG_RUNTIME_DIR is required by xfce4-session/dbus; without it the
    # session dies instantly and Termux:X11 shows only the root 'X' cursor.
    # Session output goes to ~/start-linux-session.log so failures are
    # visible instead of hidden.
    echo "Starting $DISTRO desktop as '$X11_USER' (session log: ~/start-linux-session.log)..."
    if [ "$DE" == "xfce4" ]; then
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER-$DISTRO; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export LANG=\${LANG:-C.UTF-8}; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export XCURSOR_THEME=Adwaita; export XCURSOR_SIZE=24; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- startxfce4 > \$HOME/start-linux-session.log 2>&1; elif command -v dbus-launch >/dev/null 2>&1; then dbus-launch --exit-with-session startxfce4 > \$HOME/start-linux-session.log 2>&1; else startxfce4 > \$HOME/start-linux-session.log 2>&1; fi" &
    elif [ "$DE" == "lxde" ]; then
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER-$DISTRO; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export LANG=\${LANG:-C.UTF-8}; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export XCURSOR_THEME=Adwaita; export XCURSOR_SIZE=24; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- startlxde > \$HOME/start-linux-session.log 2>&1; elif command -v dbus-launch >/dev/null 2>&1; then dbus-launch --exit-with-session startlxde > \$HOME/start-linux-session.log 2>&1; else startlxde > \$HOME/start-linux-session.log 2>&1; fi" &
    elif [ "$DE" == "mate" ]; then
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER-$DISTRO; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export LANG=\${LANG:-C.UTF-8}; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export XCURSOR_THEME=Adwaita; export XCURSOR_SIZE=24; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- mate-session > \$HOME/start-linux-session.log 2>&1; elif command -v dbus-launch >/dev/null 2>&1; then dbus-launch --exit-with-session mate-session > \$HOME/start-linux-session.log 2>&1; else mate-session > \$HOME/start-linux-session.log 2>&1; fi" &
    elif [ "$DE" == "gnome" ]; then
        # Experimental: gnome-session is skipped (no systemd/logind in proot);
        # start-gnome-session runs lfa-set-wallpaper then `gnome-shell --x11`.
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER-$DISTRO; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export XCURSOR_THEME=Adwaita; export XCURSOR_SIZE=24; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- /usr/local/bin/start-gnome-session > \$HOME/start-linux-session.log 2>&1; else /usr/local/bin/start-gnome-session > \$HOME/start-linux-session.log 2>&1; fi" &
    fi
    echo "If the screen stays on the X cursor, the desktop failed to start:"
    echo "  cat ~/start-linux-session.log   (inside the distro) for the reason."
    (
        lfa_virgl_watch "$DISTRO" x11 \
            "$(lfa_rootfs "$DISTRO")/home/$X11_USER/start-linux-session.log"
    ) &
elif [ "$SERVER" == "vnc" ]; then
    echo "Starting VNC Server..."
    if [ -z "$RESOLUTION" ]; then RESOLUTION="1280x720"; fi
    VNC_PIDFILE="$PREFIX/tmp/lfa-vnc-$DISTRO.pid"
    VNC_LOG="$PREFIX/tmp/lfa-vnc-$DISTRO.log"
    if [ -f "$VNC_PIDFILE" ] && lfa_pid_matches "$(cat "$VNC_PIDFILE" 2>/dev/null)" "proot-distro" "proot"; then
        echo "VNC server is already running on port 5901."
    else
        # Port 5901 belongs to display :1 globally. If something else already
        # serves it, starting here would "succeed" by connecting to that server
        # and then claim a desktop this instance does not own.
        if (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null; then
            echo "ERROR: port 5901 is already used by another VNC server." >&2
            echo "Stop the instance that owns it (lfa list, then lfa stop -i NAME)." >&2
            exit 1
        fi
        # Free display :1 from a live Termux:X11 session; VNC cannot share it.
        lfa_free_display_for vnc
        # proot-distro uses --kill-on-exit: a daemonised Xvnc dies as soon as
        # the login command returns. Keep the login session alive in the
        # background so the VNC server (and its desktop) persists.
        VNC_SES="startxfce4"
        [ "$DE" = "lxde" ] && VNC_SES="startlxde"
        [ "$DE" = "mate" ] && VNC_SES="mate-session"
        [ "$DE" = "gnome" ] && VNC_SES="/usr/local/bin/start-gnome-session"
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "export PULSE_SERVER=127.0.0.1; mkdir -p \$HOME/.vnc \$HOME/.config/tigervnc; printf 'geometry=%s\n' '$RESOLUTION' > \$HOME/.vnc/config; printf 'geometry=%s\n' '$RESOLUTION' > \$HOME/.config/tigervnc/config; if command -v vncserver >/dev/null 2>&1; then $VIRGL_ENV vncserver :1; rc=\$?; [ \$rc -eq 0 ] || exit \$rc; else $VIRGL_ENV Xvnc :1 -geometry $RESOLUTION -depth 24 -rfbauth \$HOME/.config/tigervnc/passwd -SecurityTypes VncAuth > \$HOME/.vnc-xvnc.log 2>&1 & sleep 2; export XCURSOR_THEME=Adwaita; export XCURSOR_SIZE=24; DISPLAY=:1 dbus-run-session -- $VNC_SES > \$HOME/start-linux-session.log 2>&1; fi; exec sleep 2147483647" > "$VNC_LOG" 2>&1 &
        echo $! > "$VNC_PIDFILE"
        printf 'Waiting for VNC on port 5901'
        for _i in $(seq 1 20); do
            if (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null; then
                echo " - ready."
                break
            fi
            printf '.'
            sleep 1
        done
        if (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null; then
            echo "VNC server started on port 5901 (log: $VNC_LOG)."
            (
                lfa_virgl_watch "$DISTRO" vnc "$VNC_LOG" \
                    "$(lfa_rootfs "$DISTRO")/home/$VNC_USER"/.vnc/*.log
            ) &
        else
            echo " (not listening)"
            echo "ERROR: VNC server did not start. Read $VNC_LOG" >&2
            exit 1
        fi
    fi
fi
EOF
    chmod +x $PREFIX/bin/start-linux
    sed -i "s/__LUSER__/$LINUX_USER/g" "$PREFIX/bin/start-linux"
    
    cat << 'EOF' > $PREFIX/bin/stop-linux
#!/bin/bash
if [ -f "$PREFIX/bin/lfa-lib.sh" ]; then
    . "$PREFIX/bin/lfa-lib.sh"
else
    lfa_instances() { ls -1 "$PREFIX/var/lib/proot-distro/installed-rootfs" 2>/dev/null; }
    lfa_rootfs() { echo "$PREFIX/var/lib/proot-distro/installed-rootfs/$1"; }
    lfa_conf() { echo "$(lfa_rootfs "$1")/etc/termux-linux-manager.conf"; }
    lfa_clear_stale_x1() { local _p=999999; [ -f "$PREFIX/tmp/.X1-lock" ] && _p=$(tr -dc '0-9' < "$PREFIX/tmp/.X1-lock" 2>/dev/null); [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null && return 0; rm -f "$PREFIX/tmp/.X11-unix/X1" "$PREFIX/tmp/.X1-lock" 2>/dev/null; }
fi
EXPLICIT_INSTANCE=0
PRESELECT_INSTANCE=""
STOP_ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--instance) PRESELECT_INSTANCE="${2:-}"; EXPLICIT_INSTANCE=1; shift 2 ;;
        --all) STOP_ALL=1; shift ;;
        -h|--help) echo "Usage: stop-linux [-i NAME|--all]"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
if [ "$STOP_ALL" = "1" ]; then
    while IFS= read -r _si; do
        [ -n "$_si" ] && "$0" -i "$_si" >/dev/null 2>&1 || true
    done < <(lfa_instances)
    echo "All desktop sessions stopped."
    exit 0
fi
if [ -z "$PRESELECT_INSTANCE" ] && [ -r "$HOME/.config/linux-for-android/last-instance" ]; then
    PRESELECT_INSTANCE="$(cat "$HOME/.config/linux-for-android/last-instance" 2>/dev/null || true)"
fi
mapfile -t DISTROS < <(lfa_instances)
if [ -n "$PRESELECT_INSTANCE" ]; then
    _ok=0
    for _d in "${DISTROS[@]}"; do [ "$_d" = "$PRESELECT_INSTANCE" ] && _ok=1; done
    if [ "$_ok" != "1" ]; then
        if [ "$EXPLICIT_INSTANCE" = "1" ]; then
            echo "No installed distribution named '$PRESELECT_INSTANCE'." >&2
            exit 1
        fi
        PRESELECT_INSTANCE=""
    fi
fi
if [ ${#DISTROS[@]} -eq 0 ]; then
    echo "No distributions installed."
    exit 1
elif [ -n "$PRESELECT_INSTANCE" ]; then
    DISTRO="$PRESELECT_INSTANCE"
elif [ ${#DISTROS[@]} -eq 1 ]; then
    DISTRO=${DISTROS[0]}
else
    echo "Multiple distributions found. Which one do you want to stop?"
    for i in "${!DISTROS[@]}"; do
        echo "$((i+1))) ${DISTROS[$i]}"
    done
    read -p "Select a distro [1-${#DISTROS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DISTROS[@]}" ]; then
        echo "Invalid selection."
        exit 1
    fi
    idx=$((choice-1))
    DISTRO=${DISTROS[$idx]}
fi

CONF_FILE="$(lfa_conf "$DISTRO")"
INSTANCE_NAME="$DISTRO"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    SERVER="none"
fi
DISTRO="$INSTANCE_NAME"
VNC_USER="${USER_NAME:-${LINUX_USER:-user}}"

NO_SYSVIPC=""
if ! proot --help 2>&1 | grep -q "sysvipc"; then
    if [ -f "$PREFIX/bin/proot-distro" ] && grep -q "no-sysvipc" "$PREFIX/bin/proot-distro" 2>/dev/null; then
        NO_SYSVIPC="--no-sysvipc"
    fi
fi

echo "Stopping PulseAudio..."
if command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio -k 2>/dev/null || true
fi

echo "Stopping VirGL Server..."
if command -v virgl_test_server_android >/dev/null 2>&1; then
    pkill -f "^virgl_test_server" 2>/dev/null || true
fi

if [ "$SERVER" = "x11" ] || [ "$SERVER" = "both" ]; then
    echo "Stopping Termux:X11..."
    # Match the display owned by this session, not every Termux:X11 the
    # user may have started (this script manages display :1 only).
    for _p in $(pgrep -f '^termux-x11 .* :1( |$)' 2>/dev/null); do
        kill "$_p" 2>/dev/null || true
    done
    # The guest desktop is its own proot process. Killing the X server alone
    # leaves xfce4-session behind; the next start then has two session
    # managers on :1, no window manager, and only the root cross cursor.
    # Match /proc/<pid>/cwd so an orphaned session (its proot wrapper died
    # with the terminal) is still found and stopped.
    lfa_kill_guest_session() {
        local _pid _cmd _cwd _round _dir
        for _round in 1 2 3; do
            for _dir in /proc/[0-9]*; do
                _pid=${_dir#/proc/}
                [ -r "$_dir/cmdline" ] || continue
                _cmd="$(tr '\0' ' ' < "$_dir/cmdline" 2>/dev/null)" || continue
                case "$_cmd" in
                    *xfce4-session*|*xfwm4*|*xfdesktop*|*xfce4-panel*|*xfce4-power-manager*|*xfsettingsd*|*tumblerd*|*light-locker*|*startxfce4*|*startlxde*|*mate-session*|*start-gnome-session*|*gpg-agent*|*gpg-connect-agent*|*gnome-keyring*) ;;
                    *) continue ;;
                esac
                _cwd="$(readlink "$_dir/cwd" 2>/dev/null)"
                case "$_cwd" in
                    "$PREFIX/var/lib/proot-distro/containers/$DISTRO"/*|"$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"/*) ;;
                    *) continue ;;
                esac
                if [ "$_round" = "1" ]; then
                    kill "$_pid" 2>/dev/null || true
                else
                    kill -9 "$_pid" 2>/dev/null || true
                fi
            done
            [ "$_round" = "1" ] && sleep 2
        done
    }
    lfa_kill_guest_session
fi
if [ "$SERVER" = "vnc" ] || [ "$SERVER" = "both" ]; then
    echo "Stopping VNC Server..."
    # Ask the guest to stop its own server first. Killing the proot wrapper
    # before this leaves vncserver's perl parent alive with a defunct Xvnc
    # child, and it can no longer find its PID file.
    proot-distro login $NO_SYSVIPC $DISTRO --user "$VNC_USER" --shared-tmp -- bash -c "vncserver -kill :1" 2>/dev/null || true
    VNC_PIDFILE="$PREFIX/tmp/lfa-vnc-$DISTRO.pid"
    if [ -f "$VNC_PIDFILE" ]; then
        VNC_PID="$(cat "$VNC_PIDFILE" 2>/dev/null || true)"
        if [ -n "$VNC_PID" ]; then
            if lfa_pid_matches "$VNC_PID" "proot-distro" "proot" "Xvnc"; then
                kill "$VNC_PID" 2>/dev/null || true
                # The login wrapper runs `exec sleep`, so TERM reaches it
                # directly. Escalate for a wedged proot: kill its children
                # first, then the tracer, or an orphan keeps the session.
                for _i in 1 2 3 4 5; do
                    kill -0 "$VNC_PID" 2>/dev/null || break
                    sleep 1
                done
                if kill -0 "$VNC_PID" 2>/dev/null; then
                    pkill -9 -P "$VNC_PID" 2>/dev/null || true
                    kill -9 "$VNC_PID" 2>/dev/null || true
                fi
            else
                echo "  (stale pidfile: PID $VNC_PID is not the managed VNC session, ignored)"
            fi
        fi
        rm -f "$VNC_PIDFILE"
    fi
    # TigerVNC before 1.10 has no -kill (it prints usage and exits), and its
    # Xvnc can reparent to init and survive the proot wrapper. Stop the
    # managed display directly as a fallback.
    # Anchor on argv[0]: an unanchored -f pattern also matches the shell
    # command that invoked stop-linux and kills the caller.
    pkill -f '^/usr/bin/Xvnc :1( |$)' 2>/dev/null || true
    pkill -f '^/usr/bin/Xtigervnc :1( |$)' 2>/dev/null || true
    pkill -f '^/usr/bin/vncserver :1( |$)' 2>/dev/null || true
    pkill -f '^/usr/bin/perl /usr/bin/vncserver :1( |$)' 2>/dev/null || true
fi

# Hand display :1 back. A killed X server does not always remove its socket or
# lock file, and the next start (either back end) then fails with
# "display :1 is taken".
sleep 2
lfa_clear_stale_x1
EOF
    chmod +x $PREFIX/bin/stop-linux
    sed -i "s/__LUSER__/$LINUX_USER/g" "$PREFIX/bin/stop-linux"

    cat << 'EOF' > $PREFIX/bin/terminal-linux
#!/bin/bash
# Open a terminal inside a distro WITHOUT starting any display/audio
# servers. For GUI installs this is the "just give me a shell" shortcut.
if [ -f "$PREFIX/bin/lfa-lib.sh" ]; then
    . "$PREFIX/bin/lfa-lib.sh"
else
    lfa_instances() { ls -1 "$PREFIX/var/lib/proot-distro/installed-rootfs" 2>/dev/null; }
    lfa_rootfs() { echo "$PREFIX/var/lib/proot-distro/installed-rootfs/$1"; }
    lfa_conf() { echo "$(lfa_rootfs "$1")/etc/termux-linux-manager.conf"; }
    lfa_clear_stale_x1() { local _p=999999; [ -f "$PREFIX/tmp/.X1-lock" ] && _p=$(tr -dc '0-9' < "$PREFIX/tmp/.X1-lock" 2>/dev/null); [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null && return 0; rm -f "$PREFIX/tmp/.X11-unix/X1" "$PREFIX/tmp/.X1-lock" 2>/dev/null; }
fi

TERM_MODE=""
EXPLICIT_INSTANCE=0
PRESELECT_INSTANCE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--instance) PRESELECT_INSTANCE="${2:-}"; EXPLICIT_INSTANCE=1; shift 2 ;;
        --root) TERM_MODE="root"; shift ;;
        --user) TERM_MODE="user"; shift ;;
        -h|--help)
            echo "Usage: terminal-linux [-i NAME] [--root|--user]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$PRESELECT_INSTANCE" ] && [ -r "$HOME/.config/linux-for-android/last-instance" ]; then
    PRESELECT_INSTANCE="$(cat "$HOME/.config/linux-for-android/last-instance" 2>/dev/null || true)"
fi

mapfile -t DISTROS < <(lfa_instances)
if [ -n "$PRESELECT_INSTANCE" ]; then
    _ok=0
    for _d in "${DISTROS[@]}"; do [ "$_d" = "$PRESELECT_INSTANCE" ] && _ok=1; done
    if [ "$_ok" != "1" ]; then
        if [ "$EXPLICIT_INSTANCE" = "1" ]; then
            echo "No installed distribution named '$PRESELECT_INSTANCE'." >&2
            exit 1
        fi
        PRESELECT_INSTANCE=""
    fi
fi
if [ ${#DISTROS[@]} -eq 0 ]; then
    echo "No distributions installed. Please run install_linux.sh first."
    exit 1
elif [ -n "$PRESELECT_INSTANCE" ]; then
    DISTRO="$PRESELECT_INSTANCE"
elif [ ${#DISTROS[@]} -eq 1 ]; then
    DISTRO=${DISTROS[0]}
else
    echo "Multiple distributions found. Open a terminal in which one?"
    for i in "${!DISTROS[@]}"; do
        echo "$((i+1))) ${DISTROS[$i]}"
    done
    read -p "Select a distro [1-${#DISTROS[@]}]: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DISTROS[@]}" ]; then
        echo "Invalid selection."
        exit 1
    fi
    idx=$((choice-1))
    DISTRO=${DISTROS[$idx]}
fi

mkdir -p "$HOME/.config/linux-for-android" 2>/dev/null || true
printf '%s\n' "$DISTRO" > "$HOME/.config/linux-for-android/last-instance" 2>/dev/null || true

CONF_FILE="$(lfa_conf "$DISTRO")"
INSTANCE_NAME="$DISTRO"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
fi
DISTRO="$INSTANCE_NAME"
TERM_USER="${USER_NAME:-${LINUX_USER:-user}}"

NO_SYSVIPC=""
if ! proot --help 2>&1 | grep -q "sysvipc"; then
    if [ -f "$PREFIX/bin/proot-distro" ] && grep -q "no-sysvipc" "$PREFIX/bin/proot-distro" 2>/dev/null; then
        NO_SYSVIPC="--no-sysvipc"
    fi
fi

if [ -n "$TERM_MODE" ]; then
    TERM_CHOICE=1
    [ "$TERM_MODE" = "user" ] && TERM_CHOICE=2
else
    echo ""
    echo "1) Root terminal (admin)"
    echo "2) User terminal ('$TERM_USER' account)"
    read -p "Select [1-2, default 1]: " TERM_CHOICE
fi
if [ "$TERM_CHOICE" == "2" ]; then
    proot-distro login $NO_SYSVIPC $DISTRO --user "$TERM_USER" --shared-tmp -- /bin/bash -l
else
    proot-distro login $NO_SYSVIPC $DISTRO --shared-tmp -- /bin/bash -l
fi
EOF
    chmod +x $PREFIX/bin/terminal-linux
    sed -i "s/__LUSER__/$LINUX_USER/g" "$PREFIX/bin/terminal-linux"
    cat << 'EOF' > ~/.shortcuts/Terminal-Linux
#!/bin/bash
terminal-linux
EOF
    chmod +x ~/.shortcuts/Terminal-Linux 2>/dev/null || true

    # The unified CLI runs from a private copy so it works after the repo is
    # moved or removed. Do not copy the runtime into itself.
    if [ "$LFA_DIR" != "$LFA_RUNTIME" ] && [ -f "$LFA_DIR/install_linux.sh" ]; then
        mkdir -p "$LFA_RUNTIME"
        cp -f "$LFA_DIR/install_linux.sh" "$LFA_RUNTIME/install_linux.sh" 2>/dev/null || true
        for _d in lib plugins assets; do
            if [ -d "$LFA_DIR/$_d" ]; then
                rm -rf "${LFA_RUNTIME:?}/$_d"
                cp -R "$LFA_DIR/$_d" "$LFA_RUNTIME/$_d" 2>/dev/null || true
            fi
        done
    fi

    cat << 'EOF' > "$PREFIX/bin/linux"
#!/bin/bash
exec "$PREFIX/bin/start-linux" --desktop "$@"
EOF
    cat << 'EOF' > "$PREFIX/bin/lfa"
#!/bin/bash
LFA_HOME="$PREFIX/lib/linux-for-android"
if [ ! -f "$LFA_HOME/install_linux.sh" ]; then
    echo "lfa: runtime missing. Re-run install_linux.sh or menu 12." >&2
    exit 1
fi
exec bash "$LFA_HOME/install_linux.sh" --cli "$@"
EOF
    cat << 'EOF' > "$PREFIX/bin/switch-linux"
#!/bin/bash
exec "$PREFIX/bin/lfa" switch "$@"
EOF
    cat << 'EOF' > "$PREFIX/bin/autostart-linux"
#!/bin/bash
exec "$PREFIX/bin/lfa" autostart "$@"
EOF
    chmod +x "$PREFIX/bin/linux" "$PREFIX/bin/lfa" "$PREFIX/bin/switch-linux" "$PREFIX/bin/autostart-linux"
}

uninstall_linux() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi

    local ROOTFS
    ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"
    local SIZE=""
    # `du` can print a size and still exit non-zero on Android when a few
    # entries are unreadable. Under set -e/pipefail that aborted the whole
    # removal silently, so the size is best-effort.
    if [ -d "$ROOTFS" ]; then
        SIZE="$(du -sh "$ROOTFS" 2>/dev/null | awk '{print $1}' || true)"
    fi
    local STATE="ok"
    [ -x "$ROOTFS/bin/sh" ] || [ -L "$ROOTFS/bin/sh" ] || [ -e "$ROOTFS/bin/sh" ] || STATE="incomplete (partial removal?)"

    echo "========================================="
    echo " Uninstall: $INSTANCE_NAME"
    echo "========================================="
    echo " Distro   : ${DISTRO:-unknown}"
    [ -n "${DE:-}" ] && [ "$DE" != "none" ] && echo " Desktop  : $DE ($SERVER)"
    echo " Rootfs   : $ROOTFS"
    [ -n "$SIZE" ] && echo " Size     : $SIZE"
    echo " Status   : $STATE"
    echo " Backups in $HOME are kept."
    echo "========================================="
    UI_NO_CLEAR=1
    if ! ui_confirm "Delete $INSTANCE_NAME permanently?" n; then
        echo "Cancelled."
        ui_pause
        show_menu 0
        return
    fi

    # A running login keeps files open and makes proot-distro remove stop
    # half-way, leaving a ghost container. Stop sessions first.
    echo "[*] Stopping any running sessions for $INSTANCE_NAME..."
    proot-distro kill "$INSTANCE_NAME" >/dev/null 2>&1 || true

    echo "[*] Removing $INSTANCE_NAME (this can take a moment)..."
    proot-distro remove "$INSTANCE_NAME" >/dev/null 2>&1 || true

    # Clean leftovers: proot-distro can abort mid-delete on a busy or
    # already-broken rootfs. Removal was confirmed, so finish the job.
    local leftover
    for leftover in \
        "$PREFIX/var/lib/proot-distro/containers/$INSTANCE_NAME" \
        "$PREFIX/var/lib/proot-distro/installed-rootfs/$INSTANCE_NAME"; do
        if [ -e "$leftover" ]; then
            echo "[*] Cleaning leftover: $leftover"
            rm -rf "$leftover" 2>/dev/null || true
        fi
    done

    if [ -e "$PREFIX/var/lib/proot-distro/containers/$INSTANCE_NAME" ] || \
       [ -e "$PREFIX/var/lib/proot-distro/installed-rootfs/$INSTANCE_NAME" ]; then
        echo "[!] Could not fully remove $INSTANCE_NAME - check permissions."
    else
        ui_ok "$INSTANCE_NAME has been removed."
        echo "Backups, if any, were left in $HOME."
    fi

    # Termux-side leftovers (#49): pidfiles, logs, runtime dirs and the
    # home-screen shortcut. Only remove what belongs to this instance, and
    # only when no other distro is installed.
    local _leftovers
    for _leftovers in \
        "$PREFIX/tmp/lfa-vnc-$INSTANCE_NAME.pid" \
        "$PREFIX/tmp/lfa-vnc-$INSTANCE_NAME.log" \
        "$PREFIX/tmp/gui_setup_"*.sh; do
        [ -e "$_leftovers" ] && rm -f "$_leftovers" 2>/dev/null || true
    done
    # shellcheck disable=SC2115  # glob is prefixed, cannot escape $PREFIX/tmp
    rm -rf "$PREFIX/tmp/xdg-"*"-$INSTANCE_NAME" 2>/dev/null || true
    if [ -z "$(pd_instances)" ]; then
        rm -f "$HOME/.shortcuts/Start-Linux" 2>/dev/null || true
        rm -f "$HOME/.termux/boot/start-linux-services.sh" 2>/dev/null || true
        echo "Removed the home-screen shortcut and boot script (no distros left)."
    fi

    ui_pause
    show_menu 0
}

install_linux() {
    local INSTALL_START
    INSTALL_START="$(date +%s)"
    echo ""
    echo "========================================="
    echo "   Linux Installation Wizard             "
    echo "========================================="
    echo ""
    echo "⚠️ IMPORTANT WARNING FOR ANDROID 12+ USERS ⚠️"
    echo "If you are on Android 14+, you MUST toggle 'Disable child process restrictions'"
    echo "in your Android Developer Options for a stable desktop experience."
    echo "========================================="
    echo ""
    print_device_info
    echo ""
    if [ "$SETUP_ANSWERED" != "1" ]; then
        if ! select_os_flavor; then
            show_menu
            return
        fi
    fi
    # 32-bit ARM warning (Oppo A37fw and similar): some images lack armv7 builds
    if [ "$IS_32BIT_ARM" = "1" ]; then
        case "$DISTRO" in
            fedora|opensuse|void|archlinux)
                echo "[!] Warning: $DISTRO may not provide 32-bit ARM (armv7) images."
                echo "    If install fails, retry with Alpine, Ubuntu, Debian or Kali."
                ;;
        esac
    fi
    # Legacy Android 5/6 runs kernel 3.10: modern glibc (>= 2.36 in
    # Debian bookworm / Ubuntu mantic / Fedora 39 / ...) dies at the
    # first guest command (verified live). Debian auto-switches to the
    # bullseye plug-in (glibc 2.31, verified); Alpine (musl) is proven OK.
    PD_ALIAS="$DISTRO"
    if [ "$IS_LEGACY" = "1" ]; then
        case "$DISTRO" in
            alpine) ;;
            debian)
                PD_ALIAS="bullseye"
                echo "[*] Legacy Android: Debian bookworm cannot run on the 3.10 kernel;"
                echo "    installing Debian bullseye (oldstable) instead - same apt experience."
                ;;
            kali)
                echo "ERROR: Kali has no plugin in legacy proot-distro (Android 5/6)."
                echo "Please re-run and choose Debian (bullseye) or Alpine instead."
                ui_pause
                show_menu
                return
                ;;
            *)
                echo "[!] Warning: $DISTRO uses modern glibc which fails on the"
                echo "    Android 5/6 (3.10) kernel at the first guest command."
                echo "    Debian (auto-switches to bullseye) or Alpine (option 8) work here."
                if [ "$SETUP_ANSWERED" != "1" ]; then
                    if ! ui_confirm "Continue anyway? ($DISTRO may fail on this kernel)" n; then
                        show_menu
                        return
                    fi
                fi
                ;;
        esac
    fi
    
    if [ "$SETUP_ANSWERED" != "1" ]; then
    DE="none"
    SERVER="none"
    AUTOSTART_SERVER=""
    RESOLUTION="1280x720"
    COLOR_MODE="light"

    if ! ask_desktop_environment "XFCE4" "1"; then
        show_menu
        return
    fi
    fi
    # GNOME is experimental and only packaged for a few distros on Android 8+.
    # A saved setup.conf may still carry DE=gnome from another device/distro.
    if [ "$DE" = "gnome" ] && ! gnome_available; then
        echo "[!] GNOME is not available for $DISTRO on this device"
        echo "    (experimental; Android 8+, no Alpine/Void). Using XFCE4 instead."
        DE="xfce4"
    fi
    # Alpine repos ship no LXDE meta-package (and no startlxde). Fall back
    # to XFCE4 rather than installing a desktop that cannot start.
    if [ "$DISTRO" == "alpine" ] && [ "$DE" == "lxde" ]; then
        echo "[*] LXDE is not packaged for Alpine -> using XFCE4 instead."
        DE="xfce4"
    fi

    if [ "$DE" != "none" ] && [ "$SETUP_ANSWERED" != "1" ]; then
        # Termux:X11 needs Android 8+ (SDK 26). This covers both legacy
        # Android 5/6 and the SDK 24/25 gap where Termux is modern but X11 is not.
        if ! x11_supported; then
            echo ""
            echo "[*] Android SDK ${ANDROID_SDK:-unknown}: Termux:X11 unavailable -> using VNC."
            SERVER="vnc"
        else
            local _srvdef=1
            [ "$DE" = "gnome" ] && _srvdef=2
            if ! ask_display_server "$_srvdef"; then
                show_menu
                return
            fi
        fi
        
        if server_has_vnc; then
            if ! ui_select "Choose Display Resolution / UI Scaling" "1" \
                "1|Auto / 720p|lightweight, recommended" \
                "2|1080p|HD" \
                "3|Tablet (1440x1080)|iPad / tablet ratio"; then
                show_menu
                return
            fi
            case "$UI_SELECTED" in
                1) RESOLUTION="1280x720" ;;
                2) RESOLUTION="1920x1080" ;;
                3) RESOLUTION="1440x1080" ;;
            esac
        fi
    fi
    # Safety clamp for answered setups replayed on hardware that cannot run
    # Termux:X11 (Android 5/6 and the SDK 24/25 gap).
    if ! x11_supported && [ "$DE" != "none" ] && { [ "$SERVER" = "x11" ] || [ "$SERVER" = "both" ]; }; then
        echo "[*] Android SDK ${ANDROID_SDK:-unknown}: clamping display server to VNC."
        SERVER="vnc"
        AUTOSTART_SERVER="vnc"
        [ -z "$RESOLUTION" ] && RESOLUTION="1280x720"
    fi

    # SOFTWARE SELECTOR
    if [ "$SETUP_ANSWERED" != "1" ]; then
    if ! ui_multi "Software Selector (optional)" \
        "1|Python|python3 + pip" \
        "2|Git|version control" \
        "3|Node.js|npm and JS tooling" \
        "4|curl|HTTP client" \
        "5|wget|download tool" \
        "6|Antigravity IDE|AI-first editor" \
        "7|Firefox|web browser" \
        "8|Chromium|web browser" \
        "9|LibreOffice|office suite" \
        "10|VLC|media player" \
        "11|GIMP|image editor" \
        "12|htop|process monitor" \
        "13|neofetch|system info" \
        "14|VS Code|Microsoft editor"; then
        show_menu
        return
    fi
    APP_CHOICES="$UI_MULTI"
    fi

    INSTALL_PYTHON=0; INSTALL_GIT=0; INSTALL_NODEJS=0; INSTALL_CURL=0; INSTALL_WGET=0; INSTALL_IDE=0
    INSTALL_FIREFOX=0; INSTALL_CHROMIUM=0
    INSTALL_LIBREOFFICE=0; INSTALL_VLC=0; INSTALL_GIMP=0
    INSTALL_HTOP=0; INSTALL_NEOFETCH=0; INSTALL_VSCODE=0

    for choice in $APP_CHOICES; do
        case $choice in
            1) INSTALL_PYTHON=1 ;;
            2) INSTALL_GIT=1 ;;
            3) INSTALL_NODEJS=1 ;;
            4) INSTALL_CURL=1 ;;
            5) INSTALL_WGET=1 ;;
            6) INSTALL_IDE=1 ;;
            7) INSTALL_FIREFOX=1 ;;
            8) INSTALL_CHROMIUM=1 ;;
            9) INSTALL_LIBREOFFICE=1 ;;
            10) INSTALL_VLC=1 ;;
            11) INSTALL_GIMP=1 ;;
            12) INSTALL_HTOP=1 ;;
            13) INSTALL_NEOFETCH=1 ;;
            14) INSTALL_VSCODE=1 ;;
        esac
    done
    
    echo ""
    if [ "$SETUP_ANSWERED" != "1" ]; then
    read -p "Enter a custom name for this installation (Leave blank for auto-generation): " INSTANCE_NAME
    fi
    if [ -z "$INSTANCE_NAME" ]; then
        if pd_instance_exists "$DISTRO" || [ -f "$PREFIX/etc/proot-distro/$DISTRO.sh" ]; then
            INSTANCE_NAME="${DISTRO}-$(date +%M%S)"
        else
            INSTANCE_NAME="$DISTRO"
        fi
    fi
    
    echo ""
    echo "========================================="
    echo "Beginning Installation of $INSTANCE_NAME..."
    echo "========================================="

    if [ "${DO_STORAGE:-1}" = "1" ] && [ ! -d ~/storage ]; then
        echo "[*] Requesting Android Storage Permission..."
        termux-setup-storage || true
        sleep 2
    fi
    
    echo "[*] Installing dependencies (universal mode, tolerates old Termux repos)..."
    NEED_X11=0
    if server_has_x11; then NEED_X11=1; fi
    ensure_dependencies "$NEED_X11"
    deploy_legacy_plugins
    # Stale pre-v4 pkg builds lack --override-alias, so custom instance
    # names silently install under the wrong name. Upgrade those to v4.2.0.
    if [ "$IS_LEGACY" = "1" ] && ! lfa_match "$(proot-distro install --help 2>&1)" 'override-alias'; then
        echo "[!] proot-distro predates --override-alias; upgrading to v4.2.0..."
        install_proot_distro_from_source || {
            echo "FATAL: proot-distro upgrade failed. Cannot continue."
            ui_pause
            show_menu
            return
        }
        deploy_legacy_plugins
    fi

    # Refuse to start when the device cannot hold the result (issue #14).
    if ! lfa_check_disk_space; then
        ui_pause
        show_menu
        return
    fi

    echo "[*] Installing $DISTRO (as $INSTANCE_NAME)..."
    verify_proot_distro_plugin "$PD_ALIAS" || {
        ui_pause
        show_menu
        return
    }
    if lfa_match "$(proot-distro install --help 2>&1)" '(IMAGE:TAG|Docker image|registry)'; then
        # Rolling releases only publish a moving tag, so the image reference
        # is recorded in the manager config and can be overridden per install
        # (LFA_IMAGE_* env vars) to reproduce a known-good build.
        case "$DISTRO" in
            ubuntu) IMAGE="${LFA_IMAGE_UBUNTU:-ubuntu:24.04}" ;;
            debian) IMAGE="${LFA_IMAGE_DEBIAN:-debian:stable}" ;;
            kali) IMAGE="${LFA_IMAGE_KALI:-kalilinux/kali-rolling:latest}" ;;
            fedora) IMAGE="${LFA_IMAGE_FEDORA:-fedora:latest}" ;;
            opensuse) IMAGE="${LFA_IMAGE_OPENSUSE:-opensuse/tumbleweed:latest}" ;;
            void) IMAGE="${LFA_IMAGE_VOID:-ghcr.io/void-linux/void-musl:latest}" ;;
            alpine) IMAGE="${LFA_IMAGE_ALPINE:-alpine:latest}" ;;
            archlinux)
                CPU_ARCH=$(uname -m)
                if [[ "$CPU_ARCH" == *"aarch64"* || "$CPU_ARCH" == *"arm64"* || "$CPU_ARCH" == *"armv8"* ]]; then
                    IMAGE="danhunsaker/archlinuxarm:latest"
                else
                    IMAGE="archlinux/archlinux:latest"
                fi
                ;;
            *) IMAGE="$DISTRO" ;;
        esac
        proot-distro install --name "$INSTANCE_NAME" "$IMAGE"
    else
        proot-distro install --override-alias "$INSTANCE_NAME" "$PD_ALIAS" 2>/dev/null || proot-distro install "$PD_ALIAS"
    fi
    
    ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"
    mkdir -p "$PREFIX/tmp"
    SETUP_SCRIPT="$PREFIX/tmp/gui_setup_$$.sh"
    # Created 0600 *before* the first write: it will hold the install
    # passwords, and $PREFIX/tmp is shared with every guest as /tmp.
    ( umask 077; : > "$SETUP_SCRIPT" ) 2>/dev/null || true
    lfa_track_tmp "$SETUP_SCRIPT"
    if [ -f "$LFA_DIR/lib/real-feel.sh" ]; then
        cp "$LFA_DIR/lib/real-feel.sh" "$PREFIX/tmp/lfa-real-feel.sh"
    fi
    
    # Configure package manager mapping
    case "$DISTRO" in
        ubuntu|debian|kali)
            UPDATE_CMD="apt-get -o Acquire::Retries=5 update -y && apt-get -o Acquire::Retries=5 upgrade -y"
            INSTALL_CMD="apt-get install -y --fix-missing"
            XFCE_PKG="xfce4 xfce4-goodies dbus-x11"
            LXDE_PKG="lxde dbus-x11"
            MATE_PKG="mate-desktop-environment dbus-x11"
            # GNOME (experimental): gnome-shell only; gnome-session is NOT
            # used (it needs systemd + logind). Avoid the ubuntu-desktop
            # metapackage so snapd (unusable in proot) is never pulled in.
            GNOME_PKG="gnome-shell gnome-terminal gnome-control-center nautilus gnome-tweaks gnome-settings-daemon dbus-x11 x11-utils dconf-cli"
            VNC_PKG="tigervnc-standalone-server"
            LOADER_PKG="glycin-loaders"
            SUDO_PKG=""
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3 python3-pip"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs npm"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            # Ubuntu 24.04 ships snap-only Firefox/Chromium. They are installed
            # from official/real debs by the special block below. Debian/Kali
            # still have real packages (Firefox ESR).
            if [ "$INSTALL_FIREFOX" == "1" ] && [ "$DISTRO" != "ubuntu" ]; then SELECTED_PKGS="$SELECTED_PKGS firefox-esr"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ] && [ "$DISTRO" != "ubuntu" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium"; fi
            if [ "$INSTALL_LIBREOFFICE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS libreoffice"; fi
            if [ "$INSTALL_VLC" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vlc"; fi
            if [ "$INSTALL_GIMP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS gimp"; fi
            if [ "$INSTALL_HTOP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS htop"; fi
            if [ "$INSTALL_NEOFETCH" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS neofetch"; fi
            if [ "$INSTALL_VSCODE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS code"; fi
            ;;

        archlinux)
            UPDATE_CMD="sed -i '/\\[options\\]/a DisableSandbox' /etc/pacman.conf && pacman-key --init && pacman-key --populate archlinux archlinuxarm 2>/dev/null || true && pacman -Syu --noconfirm"
            INSTALL_CMD="pacman -S --noconfirm"
            XFCE_PKG="xfce4 xfce4-goodies dbus"
            LXDE_PKG="lxde dbus"
            MATE_PKG="mate dbus"
            GNOME_PKG="gnome-shell gnome-terminal gnome-control-center nautilus gnome-tweaks gnome-settings-daemon dbus xorg-xrandr"
            VNC_PKG="tigervnc"
            LOADER_PKG="glycin"
            SUDO_PKG=""
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python python-pip"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs npm"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            if [ "$INSTALL_FIREFOX" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS firefox"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium"; fi
            if [ "$INSTALL_LIBREOFFICE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS libreoffice-fresh"; fi
            if [ "$INSTALL_VLC" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vlc"; fi
            if [ "$INSTALL_GIMP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS gimp"; fi
            if [ "$INSTALL_HTOP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS htop"; fi
            if [ "$INSTALL_NEOFETCH" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS neofetch"; fi
            if [ "$INSTALL_VSCODE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS code"; fi
            ;;
        fedora)
            UPDATE_CMD="dnf update -y"
            INSTALL_CMD="dnf install -y"
            XFCE_PKG="xfce4-session xfce4-panel xfdesktop xfwm4 dbus-x11"
            LXDE_PKG="lxde-common lxsession dbus-x11"
            MATE_PKG="mate-desktop dbus-x11"
            GNOME_PKG="gnome-shell gnome-terminal gnome-control-center nautilus gnome-tweaks gnome-settings-daemon dbus-x11 xrandr"
            VNC_PKG="tigervnc-server"
            LOADER_PKG="glycin-loaders"
            SUDO_PKG=""
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3 python3-pip"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs npm"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            if [ "$INSTALL_FIREFOX" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS firefox"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium"; fi
            if [ "$INSTALL_LIBREOFFICE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS libreoffice"; fi
            if [ "$INSTALL_VLC" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vlc"; fi
            if [ "$INSTALL_GIMP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS gimp"; fi
            if [ "$INSTALL_HTOP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS htop"; fi
            if [ "$INSTALL_NEOFETCH" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS neofetch"; fi
            if [ "$INSTALL_VSCODE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS code"; fi
            ;;
        opensuse)
            UPDATE_CMD="zypper refresh && zypper update -y"
            INSTALL_CMD="zypper install -y"
            XFCE_PKG="patterns-xfce-xfce dbus-1-daemon dbus-1-tools"
            LXDE_PKG="patterns-lxde-lxde dbus-1-daemon dbus-1-tools"
            MATE_PKG="patterns-mate-mate dbus-1-daemon dbus-1-tools"
            GNOME_PKG="gnome-shell gnome-terminal gnome-control-center nautilus gnome-tweaks gnome-settings-daemon dbus-1-daemon dbus-1-tools xrandr"
            VNC_PKG="tigervnc"
            LOADER_PKG="glycin-loaders"
            SUDO_PKG=""
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3 python3-pip"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs npm"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            if [ "$INSTALL_FIREFOX" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS MozillaFirefox"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium"; fi
            if [ "$INSTALL_LIBREOFFICE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS libreoffice"; fi
            if [ "$INSTALL_VLC" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vlc"; fi
            if [ "$INSTALL_GIMP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS gimp"; fi
            if [ "$INSTALL_HTOP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS htop"; fi
            if [ "$INSTALL_NEOFETCH" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS neofetch"; fi
            if [ "$INSTALL_VSCODE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS code"; fi
            ;;
        void)
            UPDATE_CMD="xbps-install -Syu"
            INSTALL_CMD="xbps-install -y"
            XFCE_PKG="xfce4 dbus dejavu-fonts-ttf"
            LXDE_PKG="lxde dbus dejavu-fonts-ttf"
            MATE_PKG="mate dbus dejavu-fonts-ttf"
            GNOME_PKG=""
            VNC_PKG="tigervnc"
            LOADER_PKG="glycin-loaders"
            SUDO_PKG=""
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3 python3-pip"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs npm"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            if [ "$INSTALL_FIREFOX" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS firefox"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium"; fi
            if [ "$INSTALL_LIBREOFFICE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS libreoffice"; fi
            if [ "$INSTALL_VLC" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vlc"; fi
            if [ "$INSTALL_GIMP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS gimp"; fi
            if [ "$INSTALL_HTOP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS htop"; fi
            if [ "$INSTALL_NEOFETCH" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS neofetch"; fi
            if [ "$INSTALL_VSCODE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vscode"; fi
            ;;
        alpine)
            # Alpine (musl) - verified working on Android 5/6 kernel 3.10.
            # Package names verified against edge/aarch64 APKINDEX.
            # NOTE: no LXDE meta / startlxde (remapped to xfce4 above),
            # no neofetch (use fastfetch), no VS Code build (skipped).
            #
            # The proot-distro Alpine image ships *edge* repositories even
            # though its base is 3.18. Edge glib 2.90 / gtk abort on the
            # Android 5/6 3.10 kernel with "ENOSYS: Function not implemented"
            # (verified live on the Oppo A37fw), killing the XFCE session.
            # Legacy installs pin the 3.18 branch and use a minimal XFCE set
            # that avoids the huge webkit/llvm pulls.
            if [ "$IS_LEGACY" = "1" ]; then
                UPDATE_CMD="sed -i 's|/edge/|/v3.18/|g' /etc/apk/repositories && apk update && apk upgrade"
                XFCE_PKG="xfce4-session xfwm4 xfce4-panel xfce4-settings xfce4-terminal xfdesktop dbus dbus-x11 font-dejavu"
                LOADER_PKG=""
                GNOME_PKG=""
            else
                UPDATE_CMD="apk update && apk upgrade"
                XFCE_PKG="xfce4 xfce4-terminal dbus"
                LOADER_PKG="glycin-loaders-all"
                GNOME_PKG=""
            fi
            INSTALL_CMD="apk add"
            LXDE_PKG="xfce4 xfce4-terminal dbus"
            MATE_PKG="mate-desktop mate-session-manager marco mate-settings-daemon dbus"
            VNC_PKG="tigervnc"
            # shadow=useradd, bash=guest login shell (Alpine base lacks both).
            # No real sudo package: setuid elevation is impossible inside
            # proot (Android NO_NEW_PRIVS); setup installs a ritual-only
            # sudo shim instead (see below).
            SUDO_PKG="shadow bash"
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3 py3-pip"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs npm"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            if [ "$INSTALL_FIREFOX" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS firefox"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium"; fi
            if [ "$INSTALL_LIBREOFFICE" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS libreoffice"; fi
            if [ "$INSTALL_VLC" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS vlc"; fi
            if [ "$INSTALL_GIMP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS gimp"; fi
            if [ "$INSTALL_HTOP" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS htop"; fi
            if [ "$INSTALL_NEOFETCH" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS fastfetch"; fi
            if [ "$INSTALL_VSCODE" == "1" ]; then echo "[!] VS Code has no Alpine build, skipping."; fi
            ;;
    esac

    # Save the configuration for dynamic boot!
    LINUX_USER="${SETUP_USER:-user}"
    if ! echo "$LINUX_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then LINUX_USER="user"; fi
    UPASS_B64="${SETUP_USER_B64:-cm9vdA==}"
    RPASS_B64="${SETUP_ROOT_B64:-cm9vdA==}"
    # Salted hash for the sudo ritual (never the password itself).
    SPASS_SALT="$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [ -n "$SPASS_SALT" ] || SPASS_SALT="lfa-$(date +%s)"
    SPASS_HASH="$(printf '%s' "${SPASS_SALT}$(printf '%s' "$UPASS_B64" | base64 -d 2>/dev/null)" | sha256sum 2>/dev/null | cut -d' ' -f1)"
    [ -n "$SPASS_HASH" ] || SPASS_HASH=""
    mkdir -p "$ROOTFS/etc"
    if [ -z "${AUTOSTART_SERVER:-}" ]; then
        case "$SERVER" in
            both) AUTOSTART_SERVER="vnc" ;;
            x11|vnc) AUTOSTART_SERVER="$SERVER" ;;
            *) AUTOSTART_SERVER="none" ;;
        esac
    fi
    echo "DISTRO=\"$DISTRO\"" > "$ROOTFS/etc/termux-linux-manager.conf"
    echo "DE=\"$DE\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "SERVER=\"$SERVER\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "AUTOSTART_SERVER=\"$AUTOSTART_SERVER\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "DO_AUTOSTART=\"${DO_AUTOSTART:-0}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "DO_SSH=\"${DO_SSH:-0}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    if [ "$SERVER" = "both" ]; then
        rm -f "$HOME/.config/linux-for-android/last-server-$INSTANCE_NAME" 2>/dev/null || true
    fi
    echo "RESOLUTION=\"$RESOLUTION\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "UPDATE_CMD=\"$UPDATE_CMD\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "USER_NAME=\"$LINUX_USER\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "COLOR_MODE=\"${COLOR_MODE:-light}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "TIMEZONE=\"${TIMEZONE:-UTC}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "HOSTNAME=\"${HOSTNAME:-localhost}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "NEED_VIRGL=\"${NEED_VIRGL:-1}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "PSTYLE=\"${PSTYLE:-minimal}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    if [ -n "${IMAGE:-}" ]; then
        echo "IMAGE=\"$IMAGE\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    fi
    
    # (Removed broken universal wallpaper download)
    
    cat << EOF > "$SETUP_SCRIPT"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
EOF

    # Legacy Debian installs bullseye, whose -security suite is EOL and
    # pruned from deb.debian.org (pool 404s despite a live Release file).
    # Point it at archive.debian.org before the first update.
    if [ "$IS_LEGACY" = "1" ] && [ "$DISTRO" = "debian" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Pointing bullseye-security at archive.debian.org (EOL suite)..."
sed -i 's|^deb http://deb.debian.org/debian-security bullseye-security |deb http://archive.debian.org/debian-security bullseye-security/updates |' /etc/apt/sources.list || true
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99-no-check-valid-until
EOF
    fi

    # dpkg-statoverride under proot:
    #  * old proot cannot do the atomic rename dance (EPERM), which leaves
    #    dbus half-configured;
    #  * a statoverride row naming a user/group that does not exist makes
    #    dpkg abort every later run ("unknown system group 'messagebus' in
    #    statoverride file"), bricking apt.
    # Install a shim that rewrites the file in place and refuses to record
    # unknown users/groups, and sanitise any rows a previous bad state left
    # behind (e.g. the old unconditional dbus pre-seed).
    if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "kali" ]; then
        SHIM_SRC="$LFA_DIR/lib/dpkg-statoverride.sh"
        if [ -f "$SHIM_SRC" ]; then
            cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Installing proot-safe dpkg-statoverride shim..."
cat > /usr/local/bin/dpkg-statoverride << 'LFA_SO'
EOF
            cat "$SHIM_SRC" >> "$SETUP_SCRIPT"
            cat << 'EOF' >> "$SETUP_SCRIPT"
LFA_SO
chmod 755 /usr/local/bin/dpkg-statoverride
EOF
        else
            echo "[!] Warning: lib/dpkg-statoverride.sh missing; dbus may not configure on old proot."
        fi
        cat << 'EOF' >> "$SETUP_SCRIPT"

echo " -> Sanitising dpkg statoverride (proot-safe)..."
if [ -f /var/lib/dpkg/statoverride ]; then
    : > /var/lib/dpkg/statoverride.lfa
    while read -r _u _g _m _p; do
        [ -n "$_u" ] || continue
        [ -n "$_p" ] || continue
        if ! { getent passwd "$_u" >/dev/null 2>&1 || grep -q "^$_u:" /etc/passwd; }; then
            echo "    dropping statoverride row (missing user $_u): $_p"
            continue
        fi
        if ! { getent group "$_g" >/dev/null 2>&1 || grep -q "^$_g:" /etc/group; }; then
            echo "    dropping statoverride row (missing group $_g): $_p"
            continue
        fi
        printf '%s %s %s %s\n' "$_u" "$_g" "$_m" "$_p" >> /var/lib/dpkg/statoverride.lfa
    done < /var/lib/dpkg/statoverride
    cat /var/lib/dpkg/statoverride.lfa > /var/lib/dpkg/statoverride
    rm -f /var/lib/dpkg/statoverride.lfa
fi
EOF
    fi

    cat << EOF >> "$SETUP_SCRIPT"
echo " -> Updating repositories..."
_LFA_UPD_OK=0
for _lfa_i in 1 2 3; do
    if $UPDATE_CMD; then _LFA_UPD_OK=1; break; fi
    echo "[!] Repository update failed (attempt \$_lfa_i/3)."
    [ "\$_lfa_i" -lt 3 ] && sleep 5
done
[ "\$_LFA_UPD_OK" = "1" ] || echo "[!] Continuing; package caches may still be usable."
EOF
    
    APT_PKGS="$SUDO_PKG"
    if [ "$DE" == "xfce4" ]; then APT_PKGS="$APT_PKGS $XFCE_PKG"; fi
    if [ "$DE" == "lxde" ]; then APT_PKGS="$APT_PKGS $LXDE_PKG"; fi
    if [ "$DE" == "mate" ]; then APT_PKGS="$APT_PKGS $MATE_PKG"; fi
    if [ "$DE" == "gnome" ]; then APT_PKGS="$APT_PKGS $GNOME_PKG"; fi
    if server_has_vnc; then APT_PKGS="$APT_PKGS $VNC_PKG"; fi
    APT_PKGS=$(echo "$APT_PKGS" | xargs)
    
    if [ -n "$APT_PKGS" ]; then
        cat << EOF >> "$SETUP_SCRIPT"
echo " -> Installing core packages ($APT_PKGS)..."
_LFA_PKG_OK=0
for _lfa_i in 1 2 3; do
    if $INSTALL_CMD $APT_PKGS; then _LFA_PKG_OK=1; break; fi
    echo "[!] Core package install failed (attempt \$_lfa_i/3)."
    [ "\$_lfa_i" -lt 3 ] && sleep 8
done
[ "\$_LFA_PKG_OK" = "1" ] || echo "[!] Core package installation did not finish cleanly."
# gdk-pixbuf >= 2.42.11 delegates PNG/JPEG decoding to glycin. Install the
# loaders where the distro provides them; ignore distros that do not (older
# Ubuntu/Debian releases ship the classic in-tree loaders instead).
if [ "$DE" != "none" ] && [ -n "$LOADER_PKG" ]; then
    echo " -> Installing image loaders ($LOADER_PKG)..."
    $INSTALL_CMD $LOADER_PKG >/dev/null 2>&1 || true
fi
EOF
    fi

    # Build the uid0 emulation library on apt distros so the sudo shim can
    # satisfy dpkg's uid-0 check inside user shells (see lib/uid0.c).
    # Toolchain is transient: installed, used once, purged right after.
    # The guest /tmp is shared with the host ($PREFIX/tmp via --shared-tmp),
    # so stage the source host-side first.
    if [ "$DISTRO" == "ubuntu" ] || [ "$DISTRO" == "debian" ] || [ "$DISTRO" == "kali" ]; then
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        if [ -f "$SCRIPT_DIR/lib/uid0.c" ]; then
            cp "$SCRIPT_DIR/lib/uid0.c" "$PREFIX/tmp/uid0.c"
            if [ -f "$SCRIPT_DIR/lib/uid0-build.sh" ]; then
                cp "$SCRIPT_DIR/lib/uid0-build.sh" "$PREFIX/tmp/lfa-uid0-build.sh"
            fi
            cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Building uid0 emulation library (lets sudo satisfy dpkg)..."
if [ -f /tmp/lfa-uid0-build.sh ]; then
    sh /tmp/lfa-uid0-build.sh
else
    echo "[!] lib/uid0-build.sh missing; sudo stays ritual-only."
fi
echo " -> Letting apt methods skip privilege dropping (no setgroups in proot)..."
mkdir -p /etc/apt/apt.conf.d
echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99-proot-no-sandbox
echo " -> Silencing installer noise (debconf frontend, service autostart, locales)..."
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections || true
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d
apt-get install -y apt-utils locales || true
sed -i -E 's/# (en_US.UTF-8)/\1/' /etc/locale.gen 2>/dev/null || true
locale-gen en_US.UTF-8 2>/dev/null || true
EOF
        else
            echo "[!] Warning: lib/uid0.c not found next to the script; sudo stays ritual-only."
        fi
    fi

    if [ "$INSTALL_VSCODE" == "1" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Configuring VS Code Repository..."
EOF
        case "$DISTRO" in
            ubuntu|debian|kali)
                cat << 'EOF' >> "$SETUP_SCRIPT"
apt-get install -y wget gpg apt-transport-https ca-certificates
mkdir -p /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc > /tmp/ms.asc
# Verify the published key fingerprint before trusting it for apt.
if ! lfa_match "$(gpg --show-keys --with-fingerprint /tmp/ms.asc 2>/dev/null)" 'BC528686B50D79E339D3721CEB3E94ADBE1229CF'; then
    echo "[!] Microsoft signing key fingerprint did not match - refusing to add the VS Code repo."
else
    gpg --dearmor < /tmp/ms.asc > packages.microsoft.gpg
    install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
fi
rm -f /tmp/ms.asc
if [ -s /etc/apt/keyrings/packages.microsoft.gpg ]; then
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
fi
rm -f packages.microsoft.gpg
apt-get update -y
EOF
                ;;
            fedora)
                cat << 'EOF' >> "$SETUP_SCRIPT"
rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo
EOF
                ;;
            opensuse)
                cat << 'EOF' >> "$SETUP_SCRIPT"
rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/zypp/repos.d/vscode.repo
zypper refresh
EOF
                ;;
        esac
    fi

    # Install optional applications safely
    if [ -n "$SELECTED_PKGS" ]; then
        cat << EOF >> "$SETUP_SCRIPT"
echo " -> Installing Selected Applications..."
$INSTALL_CMD $SELECTED_PKGS || true
EOF
    fi
    # Alpine has no neofetch package; fastfetch is the supported replacement.
    # Expose the familiar `neofetch` command as well.
    if [ "$DISTRO" = "alpine" ] && [ "$INSTALL_NEOFETCH" = "1" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
if [ -x /usr/bin/fastfetch ]; then
    ln -sf /usr/bin/fastfetch /usr/local/bin/neofetch
fi
EOF
    fi
    
    cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Creating standard '__LUSER__' account (plus ritual-only sudo shim)..."
useradd -m -s /bin/bash __LUSER__ || true
LPASS_USER="$(echo '__UPASS_B64__' | base64 -d 2>/dev/null)"
if [ -n "$LPASS_USER" ]; then
    printf '%s:%s\n' "__LUSER__" "$LPASS_USER" | chpasswd || true
fi
unset LPASS_USER
LPASS_ROOT="$(echo '__RPASS_B64__' | base64 -d 2>/dev/null)"
if [ -n "$LPASS_ROOT" ]; then
    printf '%s:%s\n' "root" "$LPASS_ROOT" | chpasswd || true
fi
unset LPASS_ROOT
echo "__LUSER__ ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
echo "root ALL=(ALL) ALL" >> /etc/sudoers

echo " -> Linking Android Internal Storage..."
mkdir -p /home/__LUSER__/storage
if [ -d /data/data/com.termux/files/home/storage ]; then
    ln -sf /data/data/com.termux/files/home/storage/* /home/__LUSER__/storage/
fi
chown -R __LUSER__:__LUSER__ /home/__LUSER__/storage
mkdir -p /root/storage
if [ -d /data/data/com.termux/files/home/storage ]; then
    ln -sf /data/data/com.termux/files/home/storage/* /root/storage/
fi

echo " -> Installing ritual-only sudo shim (/usr/local/bin/sudo)..."
cat << 'SUDO' > /usr/local/bin/sudo
#!/bin/sh
# placebo-sudo for proot-on-Android (installed by Linux-for-Android manager).
#
# Real privilege elevation is IMPOSSIBLE inside proot on Android: app
# processes carry the irreversible kernel NO_NEW_PRIVS flag, so setuid
# binaries (real sudo/su) can never elevate - on any device. Nested
# re-execution from inside the guest is blocked too (host binaries cannot
# link under the outer proot session). It is also UNNECESSARY here: every
# guest file is already owned by you.
#
# So this shim only performs the familiar password ritual (it accepts the
# install-time user password), then runs your command and passes through
# its exit status. When /usr/local/lib/libuid0.so exists (built during
# setup on apt distros, see lib/uid0.c), it is preloaded so uid-gated tools
# like dpkg proceed; files still land owned by you either way.
# The accepted password is stored as a salted SHA-256 hash, so reading this
# file no longer reveals it (the file is also mode 0700).
SUDO_SALT="__SPASS_SALT__"
SUDO_HASH="__SPASS_HASH__"

_sha256() {
    printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1
}

usage() {
    echo "usage: sudo [-u user] [-i|-s] [-E] [-H] [-n] [-v] [-k] [-p prompt] [command [args...]]" >&2
}

ask_password() {
    _prompt="${SUDO_PROMPT:-[sudo] password for ${USER:-user}: }"
    # Prefer /dev/tty so piped stdin is never swallowed as a password.
    # Probe usability with a real redirect in a subshell: bare -r/-w tests
    # lie on systems without a controlling terminal, and a bare failed
    # redirect prints noise outside 2>/dev/null.
    if ( printf '%s' "$_prompt" > /dev/tty ) 2>/dev/null; then
        _in=/dev/tty
    elif [ -t 0 ]; then
        printf '%s' "$_prompt" >&2
        _in=stdin
    else
        echo "sudo: no tty present, cannot ask for password" >&2
        return 1
    fi
    # Silent input via stty, not 'read -s': -s is a bashism that dash
    # (Debian /bin/sh) rejects with 'Illegal option'. stty ships with
    # coreutils and busybox alike.
    if command -v stty >/dev/null 2>&1; then
        if [ "$_in" = stdin ]; then
            _old="$(stty -g 2>/dev/null)"
            stty -echo 2>/dev/null
            IFS= read -r _pw
            _rc=$?
            if [ -n "$_old" ]; then stty "$_old" 2>/dev/null; else stty echo 2>/dev/null; fi
            printf '\n' >&2
        else
            _old="$(stty -g < /dev/tty 2>/dev/null)"
            stty -echo < /dev/tty 2>/dev/null
            IFS= read -r _pw < /dev/tty
            _rc=$?
            if [ -n "$_old" ]; then stty "$_old" < /dev/tty 2>/dev/null; else stty echo < /dev/tty 2>/dev/null; fi
            printf '\n' > /dev/tty 2>/dev/null
        fi
    else
        # Last resort: password echoes. Better than nothing.
        if [ "$_in" = stdin ]; then IFS= read -r _pw || return 1
        else IFS= read -r _pw < /dev/tty || return 1; fi
        _rc=0
    fi
    return $_rc
}

SUDO_TARGET="root"
RUN_SHELL=0
NONINTERACTIVE=0
KEEP_ENV=0
CUSTOM_PROMPT=""
VALIDATE_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --) shift; break ;;
        -u) SUDO_TARGET="$2"; shift 2 ;;
        -u*) SUDO_TARGET="${1#-u}"; shift ;;
        -i|-s) RUN_SHELL=1; shift ;;
        -E) KEEP_ENV=1; shift ;;
        -H) shift ;;
        -A) shift ;;
        -n) NONINTERACTIVE=1; shift ;;
        -v) VALIDATE_ONLY=1; shift ;;
        -k|-K) exit 0 ;;
        -p) CUSTOM_PROMPT="$2"; shift 2 ;;
        -p*) CUSTOM_PROMPT="${1#-p}"; shift ;;
        -V|--version) echo "placebo-sudo 1.0 (proot-on-Android, ritual only)"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "sudo: unknown option: $1" >&2; usage; exit 1 ;;
        *) break ;;
    esac
done
[ -n "$CUSTOM_PROMPT" ] && SUDO_PROMPT="$CUSTOM_PROMPT"

_self="$(id -un 2>/dev/null)"
if [ -n "$SUDO_TARGET" ] && [ "$SUDO_TARGET" != "root" ] && [ "$SUDO_TARGET" != "$_self" ]; then
    echo "sudo: cannot switch to user '$SUDO_TARGET' inside proot (setuid is blocked by Android NO_NEW_PRIVS)" >&2
    exit 1
fi

if [ "$NONINTERACTIVE" -eq 1 ]; then
    echo "sudo: a password is required" >&2
    exit 1
fi

tries=0
authed=0
while [ "$tries" -lt 3 ]; do
    if ! ask_password; then authed=-1; break; fi
    if [ -z "$SUDO_HASH" ] || ! command -v sha256sum >/dev/null 2>&1; then
        echo "sudo: this shim is not configured (re-run menu 12)" >&2
        exit 1
    fi
    if [ "$(_sha256 "$SUDO_SALT$_pw")" = "$SUDO_HASH" ]; then authed=1; break; fi
    tries=$((tries + 1))
    [ "$tries" -lt 3 ] && echo "Sorry, try again." >&2
done
unset _pw
if [ "$authed" -eq 1 ]; then
    :
elif [ "$authed" = "-1" ]; then
    # ask_password already explained the problem (e.g. no tty); stay quiet.
    exit 1
else
    echo "sudo: 3 incorrect password attempts" >&2
    exit 1
fi

export SUDO_USER="${USER:-$_self}"
export SUDO_COMMAND="$*"

if [ "$VALIDATE_ONLY" -eq 1 ]; then exit 0; fi
# UID emulation (lib/uid0.c in the repo, built during setup): lets
# uid-gated tools such as dpkg proceed inside a user shell by answering
# identity queries as 0 and no-op'ing chown. Files really land owned by
# you, which is consistent everywhere in the guest. Only active when the
# library exists; harmlessly absent otherwise.
if [ -f /usr/local/lib/libuid0.so ]; then
    LD_PRELOAD="/usr/local/lib/libuid0.so${LD_PRELOAD:+:$LD_PRELOAD}"
    export LD_PRELOAD
fi
if [ "$RUN_SHELL" -eq 1 ] || [ $# -eq 0 ]; then
    if [ $# -eq 0 ] && [ "$RUN_SHELL" -eq 0 ]; then usage; exit 1; fi
    if [ "$KEEP_ENV" -ne 1 ]; then HOME=/root; export HOME; fi
    exec "${SHELL:-/bin/sh}"
fi
if [ "$KEEP_ENV" -ne 1 ]; then HOME=/root; export HOME; fi
exec "$@"
SUDO
chmod 700 /usr/local/bin/sudo
EOF
    
    if [ "$INSTALL_IDE" == "1" ]; then
        case "$DISTRO" in
            ubuntu|debian|kali)
                if [ "$DISTRO" == "ubuntu" ]; then
                    AG_DEPS="curl ca-certificates xz-utils libnss3 libgtk-3-0 libgbm1 libasound2t64 libatk-bridge2.0-0 libatspi2.0-0 libcups2 libsecret-1-0 libxss1 libxtst6 libxshmfence1 libxdamage1 libxrandr2 libxcomposite1 libxfixes3 libxkbcommon0 libpango-1.0-0 libcairo2"
                else
                    AG_DEPS="curl ca-certificates xz-utils libnss3 libgtk-3-0 libgbm1 libasound2 libatk-bridge2.0-0 libatspi2.0-0 libcups2 libsecret-1-0 libxss1 libxtst6 libxshmfence1 libxdamage1 libxrandr2 libxcomposite1 libxfixes3 libxkbcommon0 libpango-1.0-0 libcairo2"
                fi
                cat << EOF >> "$SETUP_SCRIPT"
echo " -> Installing Google Antigravity IDE (official ARM64 build)..."
$INSTALL_CMD $AG_DEPS || true
AG_PAGE="\$(curl -fsSL --compressed https://antigravity.google/download/ 2>/dev/null || true)"
AG_URL="\$(printf '%s' "\$AG_PAGE" | grep -oE 'https://[^"]*/linux-arm/Antigravity%20IDE\.tar\.gz' | head -n1)"
# Only follow links from the vendor's own hosts: the page is scraped, so it
# must not be able to point the installer at an arbitrary server.
case "\$AG_URL" in
    https://antigravity.google/*|https://*.google.com/*|https://*.googleapis.com/*|https://*.gvt1.com/*) ;;
    *) AG_URL="" ;;
esac
if [ -z "\$AG_URL" ]; then
    echo "[!] Could not resolve a trusted Antigravity URL; using the pinned release."
    AG_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-arm/Antigravity%20IDE.tar.gz"
fi
mkdir -p /opt/antigravity-ide
if curl -fL --retry 3 "\$AG_URL" -o /tmp/antigravity-ide.tar.gz; then
    tar -xzf /tmp/antigravity-ide.tar.gz -C /opt/antigravity-ide --strip-components=1
    rm -f /tmp/antigravity-ide.tar.gz
    if [ -x /opt/antigravity-ide/antigravity-ide ]; then
        cat > /usr/local/bin/antigravity-ide <<'WRAP'
#!/bin/sh
exec /opt/antigravity-ide/antigravity-ide --no-sandbox --disable-gpu --use-gl=swiftshader "\$@"
WRAP
        chmod +x /usr/local/bin/antigravity-ide
        ln -sf /usr/local/bin/antigravity-ide /usr/local/bin/antigravity
        echo "    Antigravity IDE installed at /opt/antigravity-ide"
    else
        echo "[!] Antigravity archive did not contain the expected binary."
    fi
else
    echo "[!] Antigravity download failed; skipping."
fi
EOF
                ;;
            *)
                cat << 'EOF' >> "$SETUP_SCRIPT"
echo "[!] Antigravity IDE: automatic Linux ARM64 install is supported on Ubuntu/Debian/Kali."
echo "    Download it for this distro from https://antigravity.google/download"
EOF
                ;;
        esac
    fi

    if [ "$INSTALL_FIREFOX" == "1" ] && [ "$DISTRO" == "ubuntu" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Installing Firefox (official ARM64 build, no snap)..."
apt-get install -y curl ca-certificates xz-utils || true
mkdir -p /opt
if curl -fL --retry 3 'https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=en-US' -o /tmp/firefox.tar.xz \
   && tar -tJf /tmp/firefox.tar.xz >/dev/null 2>&1; then
    tar -xJf /tmp/firefox.tar.xz -C /opt
    rm -f /tmp/firefox.tar.xz
    cat > /usr/local/bin/firefox <<'WRAP'
#!/bin/sh
export MOZ_DISABLE_CONTENT_SANDBOX=1
exec /opt/firefox/firefox "$@"
WRAP
    chmod +x /usr/local/bin/firefox
    echo "    Firefox installed at /opt/firefox"
else
    echo "[!] Firefox download failed; skipping."
fi
EOF
    fi
    if [ "$INSTALL_CHROMIUM" == "1" ] && [ "$DISTRO" == "ubuntu" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Installing Chromium (Debian arm64 build for Ubuntu)..."
apt-get install -y curl ca-certificates gnupg debian-archive-keyring || true
install -d -m 0755 /etc/apt/keyrings
if [ -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
    echo 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian bookworm main' > /etc/apt/sources.list.d/debian-chromium.list
    printf 'Package: *\nPin: release n=bookworm\nPin-Priority: 100\n' > /etc/apt/preferences.d/99-lfa-debian
    apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y chromium chromium-common || true
else
    echo "[!] Debian archive keyring missing; skipping Chromium."
fi
EOF
    fi
    # A proot-safe Chromium launcher: Chromium's sandbox cannot work inside
    # PRoot, and GPU flags are toggled through /etc/lfa-chromium-flags so the
    # browser-acceleration menu never destroys the launcher.
    if [ "$INSTALL_CHROMIUM" == "1" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Creating proot-safe Chromium launcher..."
REAL_CHROMIUM=""
[ -x /usr/bin/chromium ] && REAL_CHROMIUM=/usr/bin/chromium
[ -z "$REAL_CHROMIUM" ] && [ -x /usr/bin/chromium-browser ] && REAL_CHROMIUM=/usr/bin/chromium-browser
if [ -n "$REAL_CHROMIUM" ]; then
    cat > /usr/local/bin/chromium <<'WRAP'
#!/bin/sh
FLAGS="$(cat /etc/lfa-chromium-flags 2>/dev/null)"
exec __REAL__ --no-sandbox --disable-dev-shm-usage --use-gl=swiftshader $FLAGS "$@"
WRAP
    sed -i "s|__REAL__|$REAL_CHROMIUM|" /usr/local/bin/chromium
    chmod +x /usr/local/bin/chromium
    ln -sf /usr/local/bin/chromium /usr/local/bin/chromium-browser
    echo "    Chromium launcher ready ($REAL_CHROMIUM)."
else
    echo "[!] Chromium binary not found after package install."
fi
EOF
    fi
    if server_has_vnc; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Configuring VNC password..."
mkdir -p /home/__LUSER__/.vnc
VPW="$(echo '__UPASS_B64__' | base64 -d 2>/dev/null)"
if [ -n "$VPW" ]; then
    printf '%s\n' "$VPW" | vncpasswd -f > /home/__LUSER__/.vnc/passwd
fi
unset VPW
EOF
        local _vnc_ses=""
        case "$DE" in
            xfce4|xfce) _vnc_ses="startxfce4" ;;
            lxde)       _vnc_ses="startlxde" ;;
            mate)       _vnc_ses="mate-session" ;;
            gnome)      _vnc_ses="/usr/local/bin/start-gnome-session" ;;
        esac
        if [ -n "$_vnc_ses" ]; then
            cat << EOF >> "$SETUP_SCRIPT"
mkdir -p /home/__LUSER__/.vnc /home/__LUSER__/.config/tigervnc
cp -f /home/__LUSER__/.vnc/passwd /home/__LUSER__/.config/tigervnc/passwd 2>/dev/null || true
for _lfa_vdir in /home/__LUSER__/.vnc /home/__LUSER__/.config/tigervnc; do
cat > "\$_lfa_vdir/xstartup" <<'STARTUP'
#!/bin/sh
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PULSE_SERVER=127.0.0.1
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
export XDG_RUNTIME_DIR="/tmp/xdg-\$(id -un)"
mkdir -p "\$XDG_RUNTIME_DIR"
chmod 700 "\$XDG_RUNTIME_DIR"
if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- $_vnc_ses
elif command -v dbus-launch >/dev/null 2>&1; then
    exec dbus-launch --exit-with-session $_vnc_ses
else
    exec $_vnc_ses
fi
STARTUP
chmod +x "\$_lfa_vdir/xstartup"
done
chmod 600 /home/__LUSER__/.vnc/passwd /home/__LUSER__/.config/tigervnc/passwd 2>/dev/null || true
chown -R __LUSER__:__LUSER__ /home/__LUSER__/.vnc /home/__LUSER__/.config/tigervnc
EOF
        fi
    fi
    
    # Timezone / hostname / shell prompt (from guided setup; skipped when
    # unset, e.g. classic wizard path). Values are charset-validated at
    # input time; __TZ__/__HOSTNAME__ use '#' sed delimiter (may contain /).
    if [ -n "${TIMEZONE:-}" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Setting timezone (__TZ__)..."
if [ -f "/usr/share/zoneinfo/__TZ__" ]; then
    ln -sf "/usr/share/zoneinfo/__TZ__" /etc/localtime
    echo "__TZ__" > /etc/timezone 2>/dev/null || true
else
    echo "[!] Timezone __TZ__ not found in guest, keeping default."
fi
EOF
    fi
    if [ -n "${HOSTNAME:-}" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Setting hostname (__HOSTNAME__)..."
echo "__HOSTNAME__" > /etc/hostname
grep -q "__HOSTNAME__" /etc/hosts 2>/dev/null || echo "127.0.1.1 __HOSTNAME__" >> /etc/hosts
EOF
    fi
    # Realistic shell: Ubuntu-style colored prompt, login banner, a
    # `hostname` command that reports the chosen name, and cleanup of the
    # Termux/Android environment variables. lib/real-feel.sh is staged in
    # $PREFIX/tmp (shared with the guest as /tmp).
    if [ -f "$PREFIX/tmp/lfa-real-feel.sh" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Applying Linux polish (prompt, welcome, hostname, environment)..."
LFA_USER="__LUSER__" LFA_DE="__DE__" LFA_HOSTNAME="__HOSTNAME__" LFA_PSTYLE="__PSTYLE__" bash /tmp/lfa-real-feel.sh \
    || echo "[!] Shell polish failed; the prompt may look plain (re-run menu 12)."
EOF
    fi

    # A failed mirror download must not be reported as a successful install.
    # Verify the components that make the chosen session usable; software
    # choices are checked by their own installers but this gate catches the
    # common "apt/dnf died halfway" case.
    cat << EOF >> "$SETUP_SCRIPT"
echo " -> Verifying core desktop/VNC components..."
MISSING_CORE=""
if [ "$DE" = "xfce4" ] && ! command -v xfce4-session >/dev/null 2>&1; then MISSING_CORE="\$MISSING_CORE xfce4-session"; fi
if [ "$DE" = "lxde" ] && ! command -v startlxde >/dev/null 2>&1; then MISSING_CORE="\$MISSING_CORE lxde"; fi
if [ "$DE" = "mate" ] && ! command -v mate-session >/dev/null 2>&1; then MISSING_CORE="\$MISSING_CORE mate-session"; fi
if [ "$DE" = "gnome" ] && ! command -v gnome-shell >/dev/null 2>&1; then MISSING_CORE="\$MISSING_CORE gnome-shell"; fi
if { [ "$SERVER" = "vnc" ] || [ "$SERVER" = "both" ]; } && ! command -v vncserver >/dev/null 2>&1 && ! command -v Xvnc >/dev/null 2>&1; then MISSING_CORE="\$MISSING_CORE vncserver"; fi
if { [ "$SERVER" = "vnc" ] || [ "$SERVER" = "both" ]; } && [ ! -s /home/$LINUX_USER/.config/tigervnc/passwd ] && [ ! -s /home/$LINUX_USER/.vnc/passwd ]; then MISSING_CORE="\$MISSING_CORE vnc-password"; fi
if [ -n "\$MISSING_CORE" ]; then
    echo "========================================="
    echo "[!] Core installation incomplete:\$MISSING_CORE"
    echo "    This is usually a repository/network failure."
    echo "    Re-run the installer, or use menu 0 (Doctor) to retry the packages."
    echo "========================================="
    exit 1
fi
echo "    Core session components verified."
EOF

    # Substitute setup-chosen values (see comment at first sed call site).
    sed -i "s/__LUSER__/$LINUX_USER/g; s/__UPASS_B64__/$UPASS_B64/g; s/__RPASS_B64__/$RPASS_B64/g" "$SETUP_SCRIPT"
    sed -i "s/__SPASS_SALT__/$SPASS_SALT/g; s/__SPASS_HASH__/$SPASS_HASH/g" "$SETUP_SCRIPT"
    sed -i "s#__TZ__#${TIMEZONE:-UTC}#g; s#__HOSTNAME__#${HOSTNAME:-localhost}#g; s/__PSTYLE__/${PSTYLE:-minimal}/g; s/__DE__/${DE:-none}/g" "$SETUP_SCRIPT"

    echo "[*] Executing setup inside $INSTANCE_NAME (this will take a while)..."
    # Alpine base ships busybox sh only: pre-install bash/sudo/shadow via sh
    # first, otherwise the 'bash /tmp/...' setup invocation cannot start.
    if [ "$DISTRO" == "alpine" ]; then
        echo "[*] Bootstrapping Alpine base tools (bash, sudo, shadow)..."
        # shellcheck disable=SC2046  # flag list, not one argument
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- sh -c "apk update && apk add bash sudo shadow"
    elif [ "$DISTRO" == "void" ]; then
        # Void's musl base image has no /bin/bash (and no shadow tools), so
        # the bash setup below cannot start until they are installed.
        echo "[*] Bootstrapping Void base tools (bash, shadow)..."
        # Void's image declares an Entrypoint and has no bash, so `login`
        # refuses to start. `run` executes its image entrypoint with /bin/sh.
        # shellcheck disable=SC2046
        proot-distro run $(pd_login_flags) "$INSTANCE_NAME" -- /bin/sh -c "xbps-install -Syu && xbps-install -y bash shadow"
    fi
    local _setup_rc=0
    # shellcheck disable=SC2046  # flag list, not one argument
    proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --shared-tmp -- bash /tmp/gui_setup_$$.sh || _setup_rc=$?
    # The guest is done with it; do not leave passwords lying in shared /tmp.
    # The test harness sets LFA_KEEP_SETUP_SCRIPT=1 so it can inspect the
    # generated script after the run.
    if [ "${LFA_KEEP_SETUP_SCRIPT:-0}" != "1" ]; then
        rm -f "$SETUP_SCRIPT" 2>/dev/null || true
    fi
    if [ "$_setup_rc" -ne 0 ]; then
        echo ""
        echo "========================================="
        echo "[!] Setup did not complete (guest exit $_setup_rc)."
        echo "    '$INSTANCE_NAME' exists but its desktop/tools may be incomplete."
        echo "    Re-run the installer, or run menu 0 (Doctor) to repair it."
        echo "========================================="
        ui_pause
        return 1
    fi
    
    echo "[*] Setting up Home-Screen Widget Integration..."
    mkdir -p ~/.shortcuts
    cat << 'EOF' > ~/.shortcuts/Start-Linux
#!/bin/bash
start-linux
EOF
    chmod +x ~/.shortcuts/Start-Linux
    
    write_launchers

    # Distro wallpaper (GUI installs only). Applied on first desktop login
    # through an XDG autostart entry, with static LXDE config where possible.
    if [ "$DE" != "none" ]; then
        apply_distro_wallpaper "$ROOTFS" "$LINUX_USER" "$DISTRO" "$DE" "${COLOR_MODE:-light}"
    fi

    # Post-install extras chosen in guided setup (all optional, all safe to
    # skip: every block tolerates missing pieces).
    if [ "${DO_SSH:-0}" = "1" ]; then
        echo "[*] Setting up SSH server..."
        pkg install -y openssh 2>/dev/null || pkg install openssh -y 2>/dev/null || true
        if command -v sshd >/dev/null 2>&1; then
            sshd 2>/dev/null || true
            _ip=$(ifconfig 2>/dev/null | grep -E 'inet .*broadcast' | awk '{print $2}' | head -n 1 || true)
            if [ -z "$_ip" ]; then _ip="YOUR_PHONE_IP"; fi
            echo "========================================="
            echo "SSH server running! From your PC:"
            echo "   ssh $(whoami)@$_ip -p 8022"
            echo "(Run 'passwd' first if you never set a Termux password.)"
            echo "========================================="
        else
            echo "[!] openssh is not installed, so the SSH server was not started."
            echo "    Install it with: pkg install openssh"
        fi
    fi
    if [ "${DO_WIDGET:-0}" = "1" ]; then
        echo "[*] Widget shortcuts (~/.shortcuts/Start-Linux, Terminal-Linux) are ready."
        echo "    Long-press home screen -> Widgets -> Termux:Widget to place them."
    fi
    if [ "${DO_AUTOSTART:-0}" = "1" ]; then
        echo "[*] Setting up Termux:Boot autostart (needs the Termux:Boot app)..."
        if [ -z "${AUTOSTART_SERVER:-}" ]; then
            case "$SERVER" in
                both) AUTOSTART_SERVER="vnc" ;;
                x11|vnc) AUTOSTART_SERVER="$SERVER" ;;
                *) AUTOSTART_SERVER="none" ;;
            esac
        fi
        write_boot_script "$INSTANCE_NAME" "$AUTOSTART_SERVER" "${DO_SSH:-0}"
        echo "    Boot script written to ~/.termux/boot/start-linux-services.sh"
    fi

    local _elapsed=$(( $(date +%s) - INSTALL_START ))
    local _mins=$((_elapsed / 60)) _secs=$((_elapsed % 60)) _dur
    if [ "$_mins" -gt 0 ]; then _dur="${_mins}m ${_secs}s"; else _dur="${_secs}s"; fi
    echo ""
    echo "========================================="
    ui_ok "Installation complete! (${_dur})"
    echo "start-linux / terminal-linux ask each boot: root terminal"
    echo "(default, full admin) or user terminal. Install packages directly"
    echo "with apk add / apt install / dnf install ..."
    echo "GUI sessions run as '$LINUX_USER' (VNC password: the one you chose in setup)."
    echo "Daily use: linux (desktop) / lfa help (commands) / lfa shell (terminal)"
    echo "Classic commands: start-linux / terminal-linux / stop-linux"
    echo "If you installed the Termux:Widget app, a shortcut is on your home screen!"
    echo "========================================="
    ui_pause
    [ "$LFA_NONINTERACTIVE" = "1" ] && return 0
    show_menu
}

# --help and --version answer a question about the script itself, so they run
# before the device probe: piping `--version` should print one line, not a
# getprop warning on a non-Android machine.
case "${1:-}" in
    -h|--help|-V|--version) lfa_run_cli "$@" ;;
    --cli)
        shift
        LFA_CLI_MODE=1
        export LFA_CLI_MODE
        detect_environment
        lfa_cli "$@"
        exit $? ;;
esac

# Initialise device profile once so IS_LEGACY / ARCH are set for menu ops
detect_environment

if [ "$#" -gt 0 ]; then
    lfa_run_cli "$@"
fi

setup_entry
