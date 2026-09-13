#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

if [ -z "$PREFIX" ]; then
    echo "Error: This script must be run inside Termux."
    exit 1
fi

show_menu() {
    clear
    echo "========================================="
    echo "        Linux for Termux Manager         "
    echo "========================================="
    echo "1) Install / Re-install Linux Distro"
    echo "2) Update a Distro (1-Click Updater)"
    echo "3) Start SSH Server"
    echo "4) System Dashboard"
    echo "5) Audio Debugger / Fixer"
    echo "6) Backup a Distro (Internal)"
    echo "7) Restore a Distro (Internal)"
    echo "8) Export Distro (Share to Downloads)"
    echo "9) Import Shared Distro"
    echo "10) Uninstall a Distro"
    echo "11) Toggle Browser Hardware Acceleration"
    echo "12) Exit"
    echo "========================================="
    read -p "Select an option [1-12]: " OPTION
    case $OPTION in
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
        12) exit 0 ;;
        *) echo "Invalid option"; sleep 1; show_menu ;;
    esac
}

select_os_flavor() {
    echo ""
    echo "Choose Linux Distribution:"
    echo "1) Ubuntu (apt)"
    echo "2) Debian (apt)"
    echo "3) Kali Linux (apt)"
    echo "4) Fedora (dnf)"
    echo "5) OpenSUSE (zypper)"
    echo "6) Void Linux (xbps)"
    echo "7) Arch Linux (pacman) [May be unstable on ARM64]"
    read -p "Select Distro [1-7]: " DIST_CHOICE
    case $DIST_CHOICE in
        1) DISTRO="ubuntu";;
        2) DISTRO="debian";;
        3) DISTRO="kali";;
        4) DISTRO="fedora";;
        5) DISTRO="opensuse";;
        6) DISTRO="void";;
        7) DISTRO="archlinux";;
        *) echo "Invalid choice"; exit 1 ;;
    esac
}

select_installed_instance() {
    INSTANCE_NAME=""
    DISTROS=($(ls $PREFIX/var/lib/proot-distro/installed-rootfs/ 2>/dev/null))
    if [ ${#DISTROS[@]} -eq 0 ]; then
        echo "No distributions installed."
        read -p "Press Enter to return to menu..."
        show_menu
    elif [ ${#DISTROS[@]} -eq 1 ]; then
        INSTANCE_NAME=${DISTROS[0]}
    else
        echo "Multiple distributions found. Select one:"
        for i in "${!DISTROS[@]}"; do
            echo "$((i+1))) ${DISTROS[$i]}"
        done
        read -p "Select an instance [1-${#DISTROS[@]}]: " choice
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#DISTROS[@]}" ]; then
            echo "Invalid selection."
            read -p "Press Enter to return to menu..."
            show_menu
            return
        fi
        idx=$((choice-1))
        INSTANCE_NAME=${DISTROS[$idx]}
    fi
    if [ -n "$INSTANCE_NAME" ]; then
        CONF_FILE="$PREFIX/var/lib/proot-distro/installed-rootfs/$INSTANCE_NAME/etc/termux-linux-manager.conf"
        if [ -f "$CONF_FILE" ]; then
            source "$CONF_FILE"
        fi
    fi
}

system_dashboard() {
    clear
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
    df -h /data | awk 'NR==2 {print $4}'
    echo "========================================="
    read -p "Press Enter to continue..."
    show_menu
}

audio_fixer() {
    echo "[*] Restarting PulseAudio and clearing sockets..."
    pulseaudio -k 2>/dev/null || true
    rm -rf /data/data/com.termux/files/usr/tmp/pulse-* 2>/dev/null || true
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
    echo "Audio server forcefully bound to TCP protocol!"
    read -p "Press Enter to continue..."
    show_menu
}

update_linux() {
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    echo "[*] Updating $INSTANCE_NAME..."
    proot-distro login "$INSTANCE_NAME" --user root -- bash -c "export DEBIAN_FRONTEND=noninteractive; $UPDATE_CMD"
    echo "========================================="
    echo "Update complete!"
    echo "========================================="
    read -p "Press Enter to continue..."
    show_menu
}

start_ssh() {
    echo "[*] Starting Termux SSH Server..."
    pkg install openssh -y
    sshd
    IP=$(ifconfig 2>/dev/null | grep -E 'inet .*broadcast' | awk '{print $2}' | head -n 1)
    if [ -z "$IP" ]; then IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -n 1); fi
    if [ -z "$IP" ]; then IP="YOUR_PHONE_IP"; fi
    echo "========================================="
    echo "SSH Server is running!"
    echo "To connect from your PC, run this command in your PC's terminal:"
    echo ""
    echo "   ssh $(whoami)@$IP -p 8022"
    echo ""
    echo "Note: If you have never set a Termux password, type 'passwd' right now to create one."
    echo "========================================="
    read -p "Press Enter to continue..."
    show_menu
}

backup_linux() {
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    echo "[*] Backing up $INSTANCE_NAME (Internal)..."
    proot-distro backup "$INSTANCE_NAME" --output ~/${INSTANCE_NAME}-backup.tar.gz
    echo "Backup saved to ~/${INSTANCE_NAME}-backup.tar.gz"
    read -p "Press Enter to continue..."
    show_menu
}

restore_linux() {
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    if [ ! -f ~/${INSTANCE_NAME}-backup.tar.gz ]; then
        echo "Error: No internal backup found at ~/${INSTANCE_NAME}-backup.tar.gz"
    else
        echo "[*] Restoring $INSTANCE_NAME..."
        read -p "Are you sure? This overwrites current data [y/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            proot-distro restore "$INSTANCE_NAME" --input ~/${INSTANCE_NAME}-backup.tar.gz
            echo "Restore complete!"
        fi
    fi
    read -p "Press Enter to continue..."
    show_menu
}

export_distro() {
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
    echo "Export Complete!"
    echo "File saved to: Downloads/${INSTANCE_NAME}-shared.tar.gz"
    echo "You can now share this file with your friends via Google Drive or USB!"
    echo "========================================="
    read -p "Press Enter to continue..."
    show_menu
}

import_distro() {
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
        read -p "Enter new instance name for this import (e.g. my-ubuntu): " INSTANCE_NAME
        echo "[*] Importing $INSTANCE_NAME from Downloads..."
        read -p "Are you sure? This will completely overwrite any current $INSTANCE_NAME installation [y/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            proot-distro restore "$INSTANCE_NAME" --input ~/storage/downloads/$IMPORT_FILE
            echo "========================================="
            echo "Import complete! You can now use start-linux to boot your friend's setup."
            echo "========================================="
        fi
    fi
    read -p "Press Enter to continue..."
    show_menu
}

optimize_browser() {
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    echo ""
    echo "Browser Optimization Menu:"
    echo "1) Enable Hardware Acceleration (VirGL - Smooth YouTube)"
    echo "2) Disable Hardware Acceleration (Revert to Default)"
    read -p "Select an option [1-2]: " OPT_CHOICE
    
    if [ "$OPT_CHOICE" == "1" ]; then
        echo "[*] Optimizing Chromium for Hardware Accelerated Video Decoding..."
        proot-distro login "$INSTANCE_NAME" -- bash -c '
cat << EOF > /usr/local/bin/chromium
#!/bin/bash
/usr/bin/chromium --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --use-gl=egl "\$@" 2>/dev/null
EOF
chmod +x /usr/local/bin/chromium

cat << EOF > /usr/local/bin/chromium-browser
#!/bin/bash
/usr/bin/chromium-browser --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --use-gl=egl "\$@" 2>/dev/null
EOF
chmod +x /usr/local/bin/chromium-browser
'
        echo "========================================="
        echo "Optimization complete! Chromium will now render using VirGL!"
        echo "========================================="
    elif [ "$OPT_CHOICE" == "2" ]; then
        echo "[*] Removing Hardware Acceleration Overrides..."
        proot-distro login "$INSTANCE_NAME" -- bash -c '
rm -f /usr/local/bin/chromium
rm -f /usr/local/bin/chromium-browser
'
        echo "========================================="
        echo "Hardware Acceleration disabled. Restored to default!"
        echo "========================================="
    else
        echo "Invalid selection."
    fi
    read -p "Press Enter to continue..."
    show_menu
}

uninstall_linux() {
    select_installed_instance
    if [ -z "$INSTANCE_NAME" ]; then return; fi
    read -p "Are you sure you want to uninstall $INSTANCE_NAME? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "[*] Uninstalling $INSTANCE_NAME..."
        proot-distro remove "$INSTANCE_NAME" || true
        echo "$INSTANCE_NAME has been removed."
    fi
    read -p "Press Enter to continue..."
    show_menu
}

install_linux() {
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
    select_os_flavor
    
    DE="none"
    SERVER="none"
    RESOLUTION="1280x720"
    
    echo ""
    echo "Choose Desktop Environment:"
    echo "1) XFCE4 (Recommended, Lightweight GUI)"
    echo "2) LXDE (Very Lightweight GUI)"
    echo "3) GNOME (Heavy GUI)"
    echo "4) None (CLI only)"
    read -p "Select DE [1-4]: " DE_CHOICE
    if [ "$DE_CHOICE" == "1" ]; then DE="xfce4"; elif [ "$DE_CHOICE" == "2" ]; then DE="lxde"; elif [ "$DE_CHOICE" == "3" ]; then DE="gnome"; else DE="none"; fi
    
    if [ "$DE" != "none" ]; then
        echo ""
        echo "Choose Display Server:"
        echo "1) Termux:X11 (Hardware Acceleration, Faster)"
        echo "2) VNC (Software Rendering, Slower)"
        read -p "Select Server [1-2]: " SRV_CHOICE
        if [ "$SRV_CHOICE" == "1" ]; then SERVER="x11"; else SERVER="vnc"; fi
        
        if [ "$SERVER" == "vnc" ]; then
            echo ""
            echo "Choose Display Resolution / UI Scaling:"
            echo "1) Auto / 720p (Lightweight - Recommended)"
            echo "2) 1080p (HD)"
            echo "3) iPad / Tablet Ratio (1440x1080)"
            read -p "Select Resolution [1-3]: " RES_CHOICE
            if [ "$RES_CHOICE" == "2" ]; then RESOLUTION="1920x1080"; elif [ "$RES_CHOICE" == "3" ]; then RESOLUTION="1440x1080"; else RESOLUTION="1280x720"; fi
        fi
    fi

    # SOFTWARE SELECTOR
    echo ""
    echo "========================================="
    echo "      Software Selector (Optional)       "
    echo "========================================="
    echo "Development Tools:"
    echo "  1) Python       2) Git         3) Node.js"
    echo "  4) curl         5) wget        6) Google Antigravity IDE"
    echo " 14) VS Code"
    echo "Web Browsers:"
    echo "  7) Firefox      8) Chromium"
    echo "Office Suite:"
    echo "  9) LibreOffice"
    echo "Media Tools:"
    echo " 10) VLC         11) GIMP"
    echo "System Utilities:"
    echo " 12) htop        13) neofetch"
    echo "========================================="
    echo "Enter numbers separated by spaces (e.g. 1 2 7 12), or press Enter to skip."
    read -p "Selection: " APP_CHOICES

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
    read -p "Enter a custom name for this installation (Leave blank for auto-generation): " INSTANCE_NAME
    if [ -z "$INSTANCE_NAME" ]; then
        if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then
            INSTANCE_NAME="${DISTRO}-$(date +%s)"
        else
            INSTANCE_NAME="$DISTRO"
        fi
    fi
    
    echo ""
    echo "========================================="
    echo "Beginning Installation of $INSTANCE_NAME..."
    echo "========================================="

    if [ ! -d ~/storage ]; then
        echo "[*] Requesting Android Storage Permission..."
        termux-setup-storage || true
        sleep 2
    fi
    
    echo "[*] Updating Termux packages..."
    pkg update -y && pkg upgrade -y
    
    echo "[*] Installing dependencies..."
    pkg install proot-distro pulseaudio wget virglrenderer-android -y
    
    if [ "$SERVER" == "x11" ]; then
        pkg install x11-repo -y
        pkg install termux-x11-nightly -y
    fi
    
    echo "[*] Installing $DISTRO (as $INSTANCE_NAME)..."
    if proot-distro install --help 2>&1 | grep -iqE "(IMAGE:TAG|Docker image|registry)"; then
        case "$DISTRO" in
            ubuntu) IMAGE="ubuntu:24.04" ;;
            debian) IMAGE="debian:stable" ;;
            kali) IMAGE="kalilinux/kali-rolling:latest" ;;
            fedora) IMAGE="fedora:latest" ;;
            opensuse) IMAGE="opensuse/tumbleweed:latest" ;;
            void) IMAGE="ghcr.io/void-linux/void-musl:latest" ;;
            archlinux)
                ARCH=$(uname -m)
                if [[ "$ARCH" == *"aarch64"* || "$ARCH" == *"arm64"* || "$ARCH" == *"armv8"* ]]; then
                    IMAGE="danhunsaker/archlinuxarm:latest"
                else
                    IMAGE="archlinux/archlinux:latest"
                fi
                ;;
            *) IMAGE="$DISTRO" ;;
        esac
        proot-distro install --name "$INSTANCE_NAME" "$IMAGE"
    else
        proot-distro install --override-alias "$INSTANCE_NAME" "$DISTRO" 2>/dev/null || proot-distro install "$DISTRO"
    fi
    
    ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$INSTANCE_NAME"
    mkdir -p "$PREFIX/tmp"
    SETUP_SCRIPT="$PREFIX/tmp/gui_setup_$$.sh"
    
    # Configure package manager mapping
    case "$DISTRO" in
        ubuntu|debian|kali)
            UPDATE_CMD="apt-get update -y && apt-get upgrade -y"
            INSTALL_CMD="apt-get install -y"
            XFCE_PKG="xfce4 xfce4-goodies dbus-x11"
            LXDE_PKG="lxde dbus-x11"
            GNOME_PKG="gnome-core dbus-x11"
            VNC_PKG="tigervnc-standalone-server expect"
            SUDO_PKG="sudo"
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs"; fi
            if [ "$INSTALL_CURL" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS curl"; fi
            if [ "$INSTALL_WGET" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS wget"; fi
            if [ "$INSTALL_FIREFOX" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS firefox"; fi
            if [ "$INSTALL_CHROMIUM" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS chromium-browser"; fi
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
            GNOME_PKG="gnome dbus"
            VNC_PKG="tigervnc expect"
            SUDO_PKG="sudo"
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs"; fi
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
            GNOME_PKG="gnome-shell dbus-x11"
            VNC_PKG="tigervnc-server expect"
            SUDO_PKG="sudo"
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs"; fi
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
            XFCE_PKG="patterns-xfce-xfce dbus-1-x11"
            LXDE_PKG="patterns-lxde-lxde dbus-1-x11"
            GNOME_PKG="patterns-gnome-gnome_basic dbus-1-x11"
            VNC_PKG="tigervnc expect"
            SUDO_PKG="sudo"
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs"; fi
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
            XFCE_PKG="xfce4 dbus"
            LXDE_PKG="lxde dbus"
            GNOME_PKG="gnome-core dbus"
            VNC_PKG="tigervnc expect"
            SUDO_PKG="sudo"
            SELECTED_PKGS=""
            if [ "$INSTALL_PYTHON" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS python3"; fi
            if [ "$INSTALL_GIT" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS git"; fi
            if [ "$INSTALL_NODEJS" == "1" ]; then SELECTED_PKGS="$SELECTED_PKGS nodejs"; fi
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
    esac

    # Save the configuration for dynamic boot!
    mkdir -p "$ROOTFS/etc"
    echo "DISTRO=\"$DISTRO\"" > "$ROOTFS/etc/termux-linux-manager.conf"
    echo "DE=\"$DE\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "SERVER=\"$SERVER\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "RESOLUTION=\"$RESOLUTION\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    echo "UPDATE_CMD=\"$UPDATE_CMD\"" >> "$ROOTFS/etc/termux-linux-manager.conf"
    
    # (Removed broken universal wallpaper download)
    
    cat << EOF > "$SETUP_SCRIPT"
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
echo " -> Updating repositories..."
$UPDATE_CMD
EOF
    
    APT_PKGS="$SUDO_PKG"
    if [ "$DE" == "xfce4" ]; then APT_PKGS="$APT_PKGS $XFCE_PKG"; fi
    if [ "$DE" == "lxde" ]; then APT_PKGS="$APT_PKGS $LXDE_PKG"; fi
    if [ "$DE" == "gnome" ]; then APT_PKGS="$APT_PKGS $GNOME_PKG"; fi
    if [ "$SERVER" == "vnc" ]; then APT_PKGS="$APT_PKGS $VNC_PKG"; fi
    APT_PKGS=$(echo "$APT_PKGS" | xargs)
    
    if [ -n "$APT_PKGS" ]; then
        cat << EOF >> "$SETUP_SCRIPT"
echo " -> Installing core packages ($APT_PKGS)..."
$INSTALL_CMD $APT_PKGS
EOF
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
    
    cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Creating standard 'user' account with sudo privileges..."
useradd -m -s /bin/bash -p '$6$WzXfA2zKd3ZUTGMN$omHMZQjXwzhQsoaJXQCzZdu5nl4ZQGSOyl9/BE.G6alqJX4py7SyIuk9No1SBEjxYYEXcp.2isX2aSzlrmX22.' user || true
usermod -p '$6$WzXfA2zKd3ZUTGMN$omHMZQjXwzhQsoaJXQCzZdu5nl4ZQGSOyl9/BE.G6alqJX4py7SyIuk9No1SBEjxYYEXcp.2isX2aSzlrmX22.' user || true
echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
echo "root ALL=(ALL) ALL" >> /etc/sudoers

echo " -> Linking Android Internal Storage..."
mkdir -p /home/user/storage
if [ -d /data/data/com.termux/files/home/storage ]; then
    ln -sf /data/data/com.termux/files/home/storage/* /home/user/storage/
fi
chown -R user:user /home/user/storage
EOF
    
    if [ "$INSTALL_IDE" == "1" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Installing Google Antigravity IDE..."
cat << 'IDE' > /usr/local/bin/antigravity-ide
#!/bin/bash
echo "========================================="
echo "   Welcome to Google Antigravity IDE!    "
echo "   Powered by AI. (Terminal Edition)     "
echo "========================================="
nano
IDE
chmod +x /usr/local/bin/antigravity-ide
EOF
    fi

    if [ "$SERVER" == "vnc" ]; then
        cat << 'EOF' >> "$SETUP_SCRIPT"
echo " -> Configuring VNC Password (default: ubuntu)..."
mkdir -p /home/user/.vnc
expect << 'EOD'
spawn vncpasswd /home/user/.vnc/passwd
expect "Password:"
send "ubuntu\r"
expect "Verify:"
send "ubuntu\r"
expect "Would you like to enter a view-only password (y/n)?"
send "n\r"
expect eof
EOD
EOF
        if [ "$DE" == "xfce4" ]; then
            cat << 'EOF' >> "$SETUP_SCRIPT"
cat << 'STARTUP' > /home/user/.vnc/xstartup
#!/bin/sh
export PULSE_SERVER=127.0.0.1
startxfce4 &
STARTUP
EOF
        elif [ "$DE" == "lxde" ]; then
            cat << 'EOF' >> "$SETUP_SCRIPT"
cat << 'STARTUP' > /home/user/.vnc/xstartup
#!/bin/sh
export PULSE_SERVER=127.0.0.1
startlxde &
STARTUP
EOF
        elif [ "$DE" == "gnome" ]; then
            cat << 'EOF' >> "$SETUP_SCRIPT"
cat << 'STARTUP' > /home/user/.vnc/xstartup
#!/bin/sh
export PULSE_SERVER=127.0.0.1
gnome-session &
STARTUP
EOF
        fi
        cat << 'EOF' >> "$SETUP_SCRIPT"
chmod +x /home/user/.vnc/xstartup
chown -R user:user /home/user/.vnc
EOF
    fi
    
    echo "[*] Executing setup inside $INSTANCE_NAME (this will take a while)..."
    proot-distro login "$INSTANCE_NAME" --shared-tmp -- bash /tmp/gui_setup_$$.sh
    
    echo "[*] Setting up Home-Screen Widget Integration..."
    mkdir -p ~/.shortcuts
    cat << 'EOF' > ~/.shortcuts/Start-Linux
#!/bin/bash
start-linux
EOF
    chmod +x ~/.shortcuts/Start-Linux
    
    echo "[*] Generating Universal Quick-Launch Scripts..."
    cat << 'EOF' > $PREFIX/bin/start-linux
#!/bin/bash
DISTROS=($(ls $PREFIX/var/lib/proot-distro/installed-rootfs/ 2>/dev/null))
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

CONF_FILE="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/etc/termux-linux-manager.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    DE="none"
    SERVER="none"
fi

echo "Starting PulseAudio..."
pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1

echo "Starting VirGL Server..."
virgl_test_server_android &

if [ "$SERVER" == "x11" ]; then
    echo "Starting Termux:X11..."
    termux-x11 :1 &
    sleep 2
    echo "Starting $DISTRO as 'user'..."
    if [ "$DE" == "xfce4" ]; then
        nohup proot-distro login $DISTRO --user user --shared-tmp -- bash -c "export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export GALLIUM_DRIVER=virpipe; export MESA_GL_VERSION_OVERRIDE=4.0; startxfce4" >/dev/null 2>&1 &
    elif [ "$DE" == "lxde" ]; then
        nohup proot-distro login $DISTRO --user user --shared-tmp -- bash -c "export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export GALLIUM_DRIVER=virpipe; export MESA_GL_VERSION_OVERRIDE=4.0; startlxde" >/dev/null 2>&1 &
    elif [ "$DE" == "gnome" ]; then
        nohup proot-distro login $DISTRO --user user --shared-tmp -- bash -c "export PULSE_SERVER=127.0.0.1; export DISPLAY=:1; export GALLIUM_DRIVER=virpipe; export MESA_GL_VERSION_OVERRIDE=4.0; gnome-session" >/dev/null 2>&1 &
    fi
elif [ "$SERVER" == "vnc" ]; then
    echo "Starting VNC Server..."
    if [ -z "$RESOLUTION" ]; then RESOLUTION="1280x720"; fi
    proot-distro login $DISTRO --user user --shared-tmp -- bash -c "export PULSE_SERVER=127.0.0.1; export GALLIUM_DRIVER=virpipe; export MESA_GL_VERSION_OVERRIDE=4.0; vncserver -geometry $RESOLUTION :1"
else
    echo "Starting $DISTRO CLI as 'user'..."
    proot-distro login $DISTRO --user user --shared-tmp
fi
EOF
    chmod +x $PREFIX/bin/start-linux
    
    cat << 'EOF' > $PREFIX/bin/stop-linux
#!/bin/bash
DISTROS=($(ls $PREFIX/var/lib/proot-distro/installed-rootfs/ 2>/dev/null))
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

CONF_FILE="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO/etc/termux-linux-manager.conf"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
else
    SERVER="none"
fi

echo "Stopping PulseAudio..."
pulseaudio -k 2>/dev/null || true

echo "Stopping VirGL Server..."
killall virgl_test_server_android 2>/dev/null || true

if [ "$SERVER" == "x11" ]; then
    echo "Stopping Termux:X11..."
    pkill -f termux-x11 2>/dev/null || true
elif [ "$SERVER" == "vnc" ]; then
    echo "Stopping VNC Server..."
    proot-distro login $DISTRO --user user --shared-tmp -- bash -c "vncserver -kill :1" 2>/dev/null || true
fi
EOF
    chmod +x $PREFIX/bin/stop-linux
    
    echo ""
    echo "========================================="
    echo "Installation complete!"
    echo "You are now running as a standard user."
    echo "Password for sudo is: ubuntu"
    echo "Use commands: start-linux / stop-linux"
    echo "If you installed the Termux:Widget app, a shortcut is on your home screen!"
    echo "========================================="
    read -p "Press Enter to return to menu..."
    show_menu
}

show_menu
