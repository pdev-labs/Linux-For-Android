#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

if [ -z "$PREFIX" ]; then
    echo "Error: This script must be run inside Termux."
    exit 1
fi

# Directory containing this script (lib/ lives next to it).
LFA_DIR="$(cd "$(dirname "$0")" && pwd)"
LFA_VERSION="1.5.6"

# ============================================================
# Interactive UI (npm-style)
# Arrow keys / Enter / space work on a real terminal. When
# stdin is piped (CI, `curl | bash`, tests) we fall back to
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
                        local -a _new=()
                        for _c in "${_chosen[@]}"; do [ "$_c" != "$_k" ] && _new+=("$_c"); done
                        _chosen=("${_new[@]}")
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

ui_pause() {
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
    # Non-Android shells (PC debugging) report SDK 0 -> treat as modern
    # so script syntax can still be tested.

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
    # set +e: every step here is best-effort, we check manually
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
       proot-distro install --help 2>&1 | grep -iqE "(IMAGE:TAG|Docker image|registry)"; then
        return 0
    fi
    # NOTE: proot-distro prints EVERYTHING (including 'list' results)
    # to stderr via msg(), so capture 2>&1 here, not 2>/dev/null.
    set +e
    if command -v proot-distro >/dev/null 2>&1 && proot-distro list 2>&1 | grep -qw "$WANT"; then
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
    if proot-distro list 2>&1 | grep -qw "$WANT"; then
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
        if [ "$IS_LEGACY" = "1" ]; then
            echo "[!] Termux:X11 requires Android 8+. Cannot install on this device."
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
    if command -v proot >/dev/null 2>&1 && ! proot --help 2>&1 | grep -q "sysvipc"; then
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
    proot-distro restore --help 2>&1 | grep -q "BACKUP_FILE"
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
# Guided setup questionnaire (integrated first screen).
# Asks everything up front, saves answers to setup.conf for unattended
# re-runs, then hands off to install_linux() with SETUP_ANSWERED=1 so no
# question is asked twice. Passwords are stored base64-encoded only.
# ============================================================
SETUP_CONF="$HOME/.config/linux-for-android/setup.conf"
# Wallpaper mode: light (default) or dark. Guided setup asks for GUI
# installs; CLI-only installs keep the default and skip wallpaper setup.
COLOR_MODE="light"

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

setup_guess_timezone() {
    local _tz=""
    _tz=$(getprop persist.sys.timezone 2>/dev/null || true)
    case "$_tz" in
        ""|*[!A-Za-z0-9_+./-]*|*..*|/*|*/) _tz="UTC" ;;
    esac
    printf '%s' "${_tz:-UTC}"
}

setup_ram_mb() {
    local _m=""
    _m=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
    case "$_m" in
        ''|*[!0-9]*) _m=2048 ;;
    esac
    printf '%s' "$_m"
}

setup_save() {
    mkdir -p "$(dirname "$SETUP_CONF")"
    cat > "$SETUP_CONF" <<EOF
# Linux-for-Android setup answers (reused on re-install, chmod 600).
# Passwords are base64-encoded, never plaintext.
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
    [ "$SERVER" = "vnc" ] && printf '  %s%-13s%s %s\n' "$C_GRAY" "Resolution" "$C_RESET" "$RESOLUTION"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Software" "$C_RESET" "${APP_CHOICES:-none}"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Instance" "$C_RESET" "${INSTANCE_NAME:-(auto)}"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Username" "$C_RESET" "$SETUP_USER"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Password" "$C_RESET" "****"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Root passwd" "$C_RESET" "****"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Timezone" "$C_RESET" "$TIMEZONE"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Hostname" "$C_RESET" "$HOSTNAME"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "HW accel" "$C_RESET" "$([ "$NEED_VIRGL" = "1" ] && echo on || echo off)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Prompt style" "$C_RESET" "$PSTYLE"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Autostart" "$C_RESET" "$([ "$DO_AUTOSTART" = "1" ] && echo yes || echo no)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Storage perm" "$C_RESET" "$([ "$DO_STORAGE" = "1" ] && echo yes || echo no)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "SSH server" "$C_RESET" "$([ "$DO_SSH" = "1" ] && echo yes || echo no)"
    printf '  %s%-13s%s %s\n' "$C_GRAY" "Widget hint" "$C_RESET" "$([ "$DO_WIDGET" = "1" ] && echo yes || echo no)"
    ui_rule
}

setup_quick() {
    echo "[*] Quick setup: taking every default."
    if [ "$IS_LEGACY" = "1" ]; then DISTRO="alpine"; else DISTRO="debian"; fi
    if [ "$IS_LEGACY" = "1" ] || [ "$(setup_ram_mb)" -le 2048 ]; then DE="none"; else DE="xfce4"; fi
    if [ "$DE" = "none" ]; then SERVER="none"; elif [ "$IS_LEGACY" = "1" ]; then SERVER="vnc"; else SERVER="x11"; fi
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
    if ! ui_select "Choose Desktop Environment (suggested: $_de)" "$_dedef" \
        "1|XFCE4|light, familiar, great on phones" \
        "2|LXDE|ultra light, minimal" \
        "3|MATE|classic GNOME 2 feel" \
        "4|None (CLI only)|terminal only - lightest and fastest"; then
        show_menu
        return
    fi
    case "$UI_SELECTED" in
        1) DE="xfce4" ;;
        2) DE="lxde" ;;
        3) DE="mate" ;;
        4) DE="none" ;;
    esac
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
    if [ "$DE" != "none" ]; then
        if [ "$IS_LEGACY" = "1" ]; then
            echo "[*] Legacy Android: display server auto-set to VNC, HW acceleration off."
            SERVER="vnc"
        else
            if ! ui_select "Choose Display Server" "1" \
                "1|Termux:X11|hardware acceleration, faster, smoother" \
                "2|VNC|software rendering, works everywhere, slower"; then
                show_menu
                return
            fi
            case "$UI_SELECTED" in
                1) SERVER="x11" ;;
                2) SERVER="vnc" ;;
            esac
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
        if [ "$SERVER" = "vnc" ]; then
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
    setup_read_secret _pw "Password for $SETUP_USER [default: root]: " "root"
    SETUP_USER_B64="$(b64enc "$_pw")"
    _pw=""
    setup_read_secret _pw "Root password [default: root]: " "root"
    SETUP_ROOT_B64="$(b64enc "$_pw")"
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
    if ui_confirm "Autostart at boot via Termux:Boot? (needs the Termux:Boot app)" n; then DO_AUTOSTART=1; else DO_AUTOSTART=0; fi
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
    SETUP_ANSWERED=1
    echo "[*] Loaded saved answers from $SETUP_CONF"
    setup_summary
    install_linux
}

setup_entry() {
    detect_environment
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
    DISTROS=($(pd_instances))
    if [ ${#DISTROS[@]} -eq 0 ]; then
        echo "No distributions installed."
        ui_pause
        show_menu
    elif [ ${#DISTROS[@]} -eq 1 ]; then
        INSTANCE_NAME=${DISTROS[0]}
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
    du -sh $PREFIX 2>/dev/null | awk '{print $1}'
    echo "-----------------------------------------"
    echo "Available Phone Storage:"
    df -h /data 2>/dev/null | awk 'NR==2 {print $4}'
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
    local ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"

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
    proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --shared-tmp -- bash /tmp/lfa-repair.sh
}

repair_linux() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    echo "[*] Running Doctor on $INSTANCE_NAME..."
    echo "========================================="
    if run_guest_repair; then
        echo "Repair complete!"
    else
        echo "[!] Doctor hit an error - review the output above."
    fi
    echo "========================================="
    ui_pause
    show_menu
}

# Guest-side migration tweaks for an already-installed distro.
write_guest_upgrade_script() {
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
if [ -d /var/lib/dpkg ] && [ ! -f /usr/local/lib/libuid0.so ] && [ -f /tmp/uid0.c ]; then
    echo " -> Rebuilding uid0 emulation library (one-time)..."
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y gcc >/dev/null 2>&1 || true
    if command -v gcc >/dev/null 2>&1; then
        gcc -shared -nostdlib -O2 -o /usr/local/lib/libuid0.so /tmp/uid0.c             && chmod 644 /usr/local/lib/libuid0.so             && echo "    uid0 library rebuilt."
    else
        echo "    [!] gcc unavailable; sudo stays ritual-only."
    fi
    apt-get purge -y gcc >/dev/null 2>&1 || true
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

    local ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"
    local CONF="$ROOTFS/etc/termux-linux-manager.conf"
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
    if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        source "$CONF" 2>/dev/null || true
    fi
    LINUX_USER="${USER_NAME:-user}"
    if ! echo "$LINUX_USER" | grep -Eq '^[a-z_][a-z0-9_-]*$'; then LINUX_USER="user"; fi

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
    fi

    # 3. Realistic shell: prompt, banner, hostname command, clean env.
    if [ -f "$LFA_DIR/lib/real-feel.sh" ]; then
        LFA_ROOT="$ROOTFS" LFA_USER="$LINUX_USER" \
            LFA_HOSTNAME="${HOSTNAME:-localhost}" LFA_PSTYLE="${PSTYLE:-minimal}" \
            sh "$LFA_DIR/lib/real-feel.sh" || true
        # Name proot-mapped Android GIDs inside the guest so `groups` stops
        # warning "cannot find name for group ID N" on every login.
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
    if [ -f "$XVNC/xstartup" ] || [ "$SERVER" = "vnc" ]; then
        local SES=""
        case "$DE" in
            xfce4|xfce) SES="startxfce4" ;;
            lxde)       SES="startlxde" ;;
            mate)       SES="mate-session" ;;
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
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --shared-tmp -- bash /tmp/lfa-upgrade.sh || true
    fi

    echo "========================================="
    echo "Latest fixes applied!"
    echo "========================================="
    ui_pause
    show_menu
}

update_linux() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    echo "[*] Updating $INSTANCE_NAME..."
    # Heal the guest first: stale statoverride rows and half-configured
    # packages make apt fail, and are repaired automatically here.
    run_guest_repair || true
    proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --user root -- bash -c "export DEBIAN_FRONTEND=noninteractive; $UPDATE_CMD"
    echo "========================================="
    ui_ok "Update complete!"
    echo "========================================="
    ui_pause
    show_menu
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
fi
DISTROS=($(lfa_instances))
if [ ${#DISTROS[@]} -eq 0 ]; then
    echo "No distributions installed. Please run install_linux.sh first."
    exit 1
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
MODE="desktop"
if [ "$SERVER" == "x11" ] || [ "$SERVER" == "vnc" ]; then
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

if [ "$MODE" == "root" ]; then
    proot-distro login $NO_SYSVIPC $DISTRO --shared-tmp -- /bin/bash -l
    exit 0
elif [ "$MODE" == "user" ]; then
    proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- /bin/bash -l
    exit 0
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
    if ! command -v termux-x11 >/dev/null 2>&1; then
        echo "ERROR: Termux:X11 backend requested but 'termux-x11' not installed."
        echo "This backend requires Android 8+. Re-install with VNC instead."
        exit 1
    fi
    echo "Starting Termux:X11..."
    # Every distro shares $PREFIX/tmp. A dead D-Bus or X socket left by a
    # previous session makes the new desktop reuse a dead bus ("Unable to
    # contact settings server"). Clear this user's per-session state first.
    rm -rf "$PREFIX/tmp/xdg-$X11_USER" 2>/dev/null || true
    rm -f "$PREFIX"/tmp/dbus-* 2>/dev/null || true
    rm -rf "$(lfa_rootfs "$DISTRO")/home/$X11_USER/.dbus/session-bus" 2>/dev/null || true
    # /tmp is shared with the guest. Pre-create the ICE socket directory as
    # root-owned 1777; the unprivileged desktop user cannot create it.
    mkdir -p "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.ICE-unix" 2>/dev/null || true
    chmod 1777 "$PREFIX/tmp/.X11-unix" "$PREFIX/tmp/.ICE-unix" 2>/dev/null || true
    nohup termux-x11 :1 >/dev/null 2>&1 &
    sleep 2
    # XDG_RUNTIME_DIR is required by xfce4-session/dbus; without it the
    # session dies instantly and Termux:X11 shows only the root 'X' cursor.
    # Session output goes to ~/start-linux-session.log so failures are
    # visible instead of hidden.
    echo "Starting $DISTRO desktop as '$X11_USER' (session log: ~/start-linux-session.log)..."
    if [ "$DE" == "xfce4" ]; then
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- startxfce4 > \$HOME/start-linux-session.log 2>&1; elif command -v dbus-launch >/dev/null 2>&1; then dbus-launch --exit-with-session startxfce4 > \$HOME/start-linux-session.log 2>&1; else startxfce4 > \$HOME/start-linux-session.log 2>&1; fi" &
    elif [ "$DE" == "lxde" ]; then
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- startlxde > \$HOME/start-linux-session.log 2>&1; elif command -v dbus-launch >/dev/null 2>&1; then dbus-launch --exit-with-session startlxde > \$HOME/start-linux-session.log 2>&1; else startlxde > \$HOME/start-linux-session.log 2>&1; fi" &
    elif [ "$DE" == "mate" ]; then
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "mkdir -p /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; export XDG_RUNTIME_DIR=/tmp/xdg-\$USER; mkdir -p "\$XDG_RUNTIME_DIR"; chmod 700 "\$XDG_RUNTIME_DIR"; export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; $VIRGL_ENV if command -v dbus-run-session >/dev/null 2>&1; then dbus-run-session -- mate-session > \$HOME/start-linux-session.log 2>&1; elif command -v dbus-launch >/dev/null 2>&1; then dbus-launch --exit-with-session mate-session > \$HOME/start-linux-session.log 2>&1; else mate-session > \$HOME/start-linux-session.log 2>&1; fi" &
    fi
    echo "If the screen stays on the X cursor, the desktop failed to start:"
    echo "  cat ~/start-linux-session.log   (inside the distro) for the reason."
elif [ "$SERVER" == "vnc" ]; then
    echo "Starting VNC Server..."
    if [ -z "$RESOLUTION" ]; then RESOLUTION="1280x720"; fi
    VNC_PIDFILE="$PREFIX/tmp/lfa-vnc-$DISTRO.pid"
    VNC_LOG="$PREFIX/tmp/lfa-vnc-$DISTRO.log"
    if [ -f "$VNC_PIDFILE" ] && kill -0 "$(cat "$VNC_PIDFILE")" 2>/dev/null; then
        echo "VNC server is already running on port 5901."
    else
        # proot-distro uses --kill-on-exit: a daemonised Xvnc dies as soon as
        # the login command returns. Keep the login session alive in the
        # background so the VNC server (and its desktop) persists.
        VNC_SES="startxfce4"
        [ "$DE" = "lxde" ] && VNC_SES="startlxde"
        [ "$DE" = "mate" ] && VNC_SES="mate-session"
        nohup proot-distro login $NO_SYSVIPC $DISTRO --user "$X11_USER" --shared-tmp -- bash -c "export PULSE_SERVER=127.0.0.1; mkdir -p \$HOME/.vnc \$HOME/.config/tigervnc; printf 'geometry=%s\n' '$RESOLUTION' > \$HOME/.vnc/config; printf 'geometry=%s\n' '$RESOLUTION' > \$HOME/.config/tigervnc/config; if command -v vncserver >/dev/null 2>&1; then $VIRGL_ENV vncserver :1; rc=\$?; [ \$rc -eq 0 ] || exit \$rc; else $VIRGL_ENV Xvnc :1 -geometry $RESOLUTION -depth 24 -rfbauth \$HOME/.config/tigervnc/passwd -SecurityTypes VncAuth > \$HOME/.vnc-xvnc.log 2>&1 & sleep 2; DISPLAY=:1 dbus-run-session -- $VNC_SES > \$HOME/start-linux-session.log 2>&1; fi; while :; do sleep 3600; done" > "$VNC_LOG" 2>&1 &
        echo $! > "$VNC_PIDFILE"
        echo "VNC server started on port 5901 (log: $VNC_LOG)."
    fi
fi
EOF
    chmod +x $PREFIX/bin/start-linux
    sed -i "s/__LUSER__/$LINUX_USER/g" $PREFIX/bin/start-linux
    
    cat << 'EOF' > $PREFIX/bin/stop-linux
#!/bin/bash
if [ -f "$PREFIX/bin/lfa-lib.sh" ]; then
    . "$PREFIX/bin/lfa-lib.sh"
else
    lfa_instances() { ls -1 "$PREFIX/var/lib/proot-distro/installed-rootfs" 2>/dev/null; }
    lfa_rootfs() { echo "$PREFIX/var/lib/proot-distro/installed-rootfs/$1"; }
    lfa_conf() { echo "$(lfa_rootfs "$1")/etc/termux-linux-manager.conf"; }
fi
DISTROS=($(lfa_instances))
if [ ${#DISTROS[@]} -eq 0 ]; then
    echo "No distributions installed."
    exit 1
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

if [ "$SERVER" == "x11" ]; then
    echo "Stopping Termux:X11..."
    pkill -f "^termux-x11" 2>/dev/null || true
elif [ "$SERVER" == "vnc" ]; then
    echo "Stopping VNC Server..."
    VNC_PIDFILE="$PREFIX/tmp/lfa-vnc-$DISTRO.pid"
    if [ -f "$VNC_PIDFILE" ]; then
        VNC_PID="$(cat "$VNC_PIDFILE" 2>/dev/null || true)"
        [ -n "$VNC_PID" ] && kill "$VNC_PID" 2>/dev/null || true
        rm -f "$VNC_PIDFILE"
    fi
    proot-distro login $NO_SYSVIPC $DISTRO --user "$VNC_USER" --shared-tmp -- bash -c "vncserver -kill :1" 2>/dev/null || true
fi
EOF
    chmod +x $PREFIX/bin/stop-linux
    sed -i "s/__LUSER__/$LINUX_USER/g" $PREFIX/bin/stop-linux

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
fi
DISTROS=($(lfa_instances))
if [ ${#DISTROS[@]} -eq 0 ]; then
    echo "No distributions installed. Please run install_linux.sh first."
    exit 1
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

echo ""
echo "1) Root terminal (admin)"
echo "2) User terminal ('$TERM_USER' account)"
read -p "Select [1-2, default 1]: " TERM_CHOICE
if [ "$TERM_CHOICE" == "2" ]; then
    proot-distro login $NO_SYSVIPC $DISTRO --user "$TERM_USER" --shared-tmp -- /bin/bash -l
else
    proot-distro login $NO_SYSVIPC $DISTRO --shared-tmp -- /bin/bash -l
fi
EOF
    chmod +x $PREFIX/bin/terminal-linux
    sed -i "s/__LUSER__/$LINUX_USER/g" $PREFIX/bin/terminal-linux
    cat << 'EOF' > ~/.shortcuts/Terminal-Linux
#!/bin/bash
terminal-linux
EOF
    chmod +x ~/.shortcuts/Terminal-Linux 2>/dev/null || true
}

uninstall_linux() {
    require_proot_distro || return
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi

    local ROOTFS="$(pd_rootfs "$INSTANCE_NAME")"
    local SIZE=""
    [ -d "$ROOTFS" ] && SIZE="$(du -sh "$ROOTFS" 2>/dev/null | awk '{print $1}')"
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
        show_menu
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

    ui_pause
    show_menu
}

install_linux() {
    local INSTALL_START="$(date +%s)"
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
    RESOLUTION="1280x720"
    COLOR_MODE="light"

    if ! ui_select "Choose Desktop Environment" "1" \
        "1|XFCE4|recommended, light GUI" \
        "2|LXDE|very light GUI" \
        "3|MATE|classic GNOME, stable" \
        "4|None (CLI only)|terminal only"; then
        show_menu
        return
    fi
    case "$UI_SELECTED" in
        1) DE="xfce4" ;;
        2) DE="lxde" ;;
        3) DE="mate" ;;
        4) DE="none" ;;
    esac
    fi
    # Alpine repos ship no LXDE meta-package (and no startlxde). Fall back
    # to XFCE4 rather than installing a desktop that cannot start.
    if [ "$DISTRO" == "alpine" ] && [ "$DE" == "lxde" ]; then
        echo "[*] LXDE is not packaged for Alpine -> using XFCE4 instead."
        DE="xfce4"
    fi

    if [ "$DE" != "none" ] && [ "$SETUP_ANSWERED" != "1" ]; then
        # Legacy Android (5/6, SDK < 24): Termux:X11 needs Android 8+.
        # Force VNC so install never dead-ends on Oppo A37fw-class devices.
        if [ "$IS_LEGACY" = "1" ]; then
            echo ""
            echo "[*] Legacy Android detected: Termux:X11 unavailable -> using VNC."
            SERVER="vnc"
        else
            if ! ui_select "Choose Display Server" "1" \
                "1|Termux:X11|hardware acceleration, faster" \
                "2|VNC|software rendering, slower"; then
                show_menu
                return
            fi
            case "$UI_SELECTED" in
                1) SERVER="x11" ;;
                2) SERVER="vnc" ;;
            esac
        fi
        
        if [ "$SERVER" == "vnc" ]; then
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
    # Safety clamp for answered setups replayed on legacy hardware (e.g. a
    # config saved elsewhere): X11 can never work there.
    if [ "$IS_LEGACY" = "1" ] && [ "$DE" != "none" ] && [ "$SERVER" = "x11" ]; then
        echo "[*] Legacy Android: clamping display server to VNC."
        SERVER="vnc"
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
    if [ "$SERVER" == "x11" ]; then NEED_X11=1; fi
    ensure_dependencies "$NEED_X11"
    deploy_legacy_plugins
    # Stale pre-v4 pkg builds lack --override-alias, so custom instance
    # names silently install under the wrong name. Upgrade those to v4.2.0.
    if [ "$IS_LEGACY" = "1" ] && ! proot-distro install --help 2>&1 | grep -q "override-alias"; then
        echo "[!] proot-distro predates --override-alias; upgrading to v4.2.0..."
        install_proot_distro_from_source || {
            echo "FATAL: proot-distro upgrade failed. Cannot continue."
            ui_pause
            show_menu
            return
        }
        deploy_legacy_plugins
    fi

    echo "[*] Installing $DISTRO (as $INSTANCE_NAME)..."
    verify_proot_distro_plugin "$PD_ALIAS" || {
        ui_pause
        show_menu
        return
    }
    if proot-distro install --help 2>&1 | grep -iqE "(IMAGE:TAG|Docker image|registry)"; then
        case "$DISTRO" in
            ubuntu) IMAGE="ubuntu:24.04" ;;
            debian) IMAGE="debian:stable" ;;
            kali) IMAGE="kalilinux/kali-rolling:latest" ;;
            fedora) IMAGE="fedora:latest" ;;
            opensuse) IMAGE="opensuse/tumbleweed:latest" ;;
            void) IMAGE="ghcr.io/void-linux/void-musl:latest" ;;
            alpine) IMAGE="alpine:latest" ;;
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
            else
                UPDATE_CMD="apk update && apk upgrade"
                XFCE_PKG="xfce4 xfce4-terminal dbus"
                LOADER_PKG="glycin-loaders-all"
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
    SPASS_B64="$UPASS_B64"
    mkdir -p "$ROOTFS/etc"
    echo "DISTRO=\"$DISTRO\"" > "$ROOTFS/etc/termux-linux-manager.conf"
    echo "DE=\"$DE\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "SERVER=\"$SERVER\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "RESOLUTION=\"$RESOLUTION\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "UPDATE_CMD=\"$UPDATE_CMD\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "USER_NAME=\"$LINUX_USER\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "COLOR_MODE=\"${COLOR_MODE:-light}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "TIMEZONE=\"${TIMEZONE:-UTC}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "HOSTNAME=\"${HOSTNAME:-localhost}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "NEED_VIRGL=\"${NEED_VIRGL:-1}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "PSTYLE=\"${PSTYLE:-minimal}\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    
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
    # behind (e.g. our old unconditional dbus pre-seed).
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
    if [ "$SERVER" == "vnc" ]; then APT_PKGS="$APT_PKGS $VNC_PKG"; fi
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
            cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Building uid0 emulation library (lets sudo satisfy dpkg)..."
apt-get install -y gcc || true
if command -v gcc >/dev/null 2>&1; then
    gcc -shared -nostdlib -O2 -o /usr/local/lib/libuid0.so /tmp/uid0.c && chmod 644 /usr/local/lib/libuid0.so && echo "    uid0 library ready." || echo "[!] uid0 build failed (sudo stays ritual-only)."
else
    echo "[!] gcc unavailable, skipping uid0 build (sudo stays ritual-only)."
fi
rm -f /tmp/uid0.c
apt-get purge -y gcc 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
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
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
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
# The accepted password is stored base64-encoded (never plaintext): the
# typed password is encoded the same way before comparing.
SUDO_SHIM_B64="__SPASS_B64__"

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
    if [ "$(printf '%s' "$_pw" | base64 2>/dev/null | tr -d '\n')" = "$SUDO_SHIM_B64" ]; then authed=1; break; fi
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
chmod +x /usr/local/bin/sudo
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
if [ -z "\$AG_URL" ]; then
    echo "[!] Could not resolve the latest Antigravity URL; using known release."
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
if curl -fL --retry 3 'https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64-aarch64&lang=en-US' -o /tmp/firefox.tar.xz; then
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
    if [ "$SERVER" == "vnc" ]; then
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
LFA_USER="__LUSER__" LFA_HOSTNAME="__HOSTNAME__" LFA_PSTYLE="__PSTYLE__" bash /tmp/lfa-real-feel.sh || true
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
if [ "$SERVER" = "vnc" ] && ! command -v vncserver >/dev/null 2>&1 && ! command -v Xvnc >/dev/null 2>&1; then MISSING_CORE="\$MISSING_CORE vncserver"; fi
if [ "$SERVER" = "vnc" ] && [ ! -s /home/$LINUX_USER/.config/tigervnc/passwd ] && [ ! -s /home/$LINUX_USER/.vnc/passwd ]; then MISSING_CORE="\$MISSING_CORE vnc-password"; fi
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
    sed -i "s/__LUSER__/$LINUX_USER/g; s/__UPASS_B64__/$UPASS_B64/g; s/__RPASS_B64__/$RPASS_B64/g; s/__SPASS_B64__/$SPASS_B64/g" "$SETUP_SCRIPT"
    sed -i "s#__TZ__#${TIMEZONE:-UTC}#g; s#__HOSTNAME__#${HOSTNAME:-localhost}#g; s/__PSTYLE__/${PSTYLE:-minimal}/g" "$SETUP_SCRIPT"

    echo "[*] Executing setup inside $INSTANCE_NAME (this will take a while)..."
    # Alpine base ships busybox sh only: pre-install bash/sudo/shadow via sh
    # first, otherwise the 'bash /tmp/...' setup invocation cannot start.
    if [ "$DISTRO" == "alpine" ]; then
        echo "[*] Bootstrapping Alpine base tools (bash, sudo, shadow)..."
        proot-distro login $(pd_login_flags) "$INSTANCE_NAME" -- sh -c "apk update && apk add bash sudo shadow"
    elif [ "$DISTRO" == "void" ]; then
        # Void's musl base image has no /bin/bash (and no shadow tools), so
        # the bash setup below cannot start until they are installed.
        echo "[*] Bootstrapping Void base tools (bash, shadow)..."
        # Void's image declares an Entrypoint and has no bash, so `login`
        # refuses to start. `run` executes its image entrypoint with /bin/sh.
        proot-distro run $(pd_login_flags) "$INSTANCE_NAME" -- /bin/sh -c "xbps-install -Syu && xbps-install -y bash shadow"
    fi
    local _setup_rc=0
    proot-distro login $(pd_login_flags) "$INSTANCE_NAME" --shared-tmp -- bash /tmp/gui_setup_$$.sh || _setup_rc=$?
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
            echo "[!] openssh unavailable, skipping SSH server."
        fi
    fi
    if [ "${DO_WIDGET:-0}" = "1" ]; then
        echo "[*] Widget shortcuts (~/.shortcuts/Start-Linux, Terminal-Linux) are ready."
        echo "    Long-press home screen -> Widgets -> Termux:Widget to place them."
    fi
    if [ "${DO_AUTOSTART:-0}" = "1" ]; then
        echo "[*] Setting up Termux:Boot autostart (needs the Termux:Boot app)..."
        mkdir -p ~/.termux/boot
        {
            echo "#!/bin/bash"
            echo "# Generated by Linux-for-Android setup: starts services at boot."
            echo "termux-wake-lock 2>/dev/null || true"
            if [ "${DO_SSH:-0}" = "1" ]; then
                echo "sshd 2>/dev/null || true"
            fi
            if [ "$SERVER" = "vnc" ]; then
                echo "sleep 5"
                # Keep the proot session alive: vncserver daemonises and would
                # otherwise be killed by proot-distro --kill-on-exit.
                echo "nohup proot-distro login $(pd_login_flags) $INSTANCE_NAME --user $LINUX_USER --shared-tmp -- bash -c \"mkdir -p \$HOME/.vnc \$HOME/.config/tigervnc; printf 'geometry=%s\n' '${RESOLUTION:-1280x720}' > \$HOME/.vnc/config; printf 'geometry=%s\n' '${RESOLUTION:-1280x720}' > \$HOME/.config/tigervnc/config; vncserver :1; while :; do sleep 3600; done\" >/dev/null 2>&1 &"
                echo "echo \$! > \"\$PREFIX/tmp/lfa-vnc-$INSTANCE_NAME.pid\""
            elif [ "$SERVER" = "x11" ]; then
                echo "# NOTE: Termux:X11 needs its app window open, so it cannot"
                echo "# autostart unattended. Start it with start-linux instead."
            fi
        } > ~/.termux/boot/start-linux-services.sh
        chmod +x ~/.termux/boot/start-linux-services.sh
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
    echo "Use commands: start-linux / terminal-linux (shell only) / stop-linux"
    echo "If you installed the Termux:Widget app, a shortcut is on your home screen!"
    echo "========================================="
    ui_pause
    show_menu
}

# Initialise device profile once so IS_LEGACY / ARCH are set for menu ops
detect_environment

setup_entry
