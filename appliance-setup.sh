#!/bin/bash

set -u
set -x

LOGFILE="/home/nick/appliance_setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "Starting appliance setup..."

# Install packages
dnf upgrade -y
dnf -y install epel-release
dnf -y swap nano vim-enhanced
dnf -y install dnf-automatic \
               dconf-editor gnome-extensions-app gnome-shell-extension-no-overview \
               nss-mdns

# Install Google Chrome
dnf -y install https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm

# Set vim as default editor by adding to /etc/profile.d/vim.sh
echo -e 'export VISUAL=vim\nexport EDITOR=vim' > /etc/profile.d/vim.sh
chmod +x /etc/profile.d/vim.sh

# Download all necessary files
CONFIG_REPO="https://raw.githubusercontent.com/nwilson97/config-files/main"

download_file() {
    local DEST="$1"
    local URL="$2"
    local DIR
    DIR=$(dirname "$DEST")

    mkdir -p "$DIR"  # Ensure target directory exists

    wget --tries=3 --timeout=10 -O "$DEST" "$URL" || {
        echo "Failed to download $DEST from $URL"
        exit 1
    }
}

# List of files to download
download_file "/etc/systemd/system/poweroff-at-9pm.timer" "$CONFIG_REPO/poweroff-at-9pm.timer"
download_file "/etc/systemd/system/poweroff-at-9pm.service" "$CONFIG_REPO/poweroff-at-9pm.service"
download_file "/home/nick/.vimrc" "$CONFIG_REPO/.vimrc"
download_file "/etc/ssh/sshd_config.d/sshd_secure.conf" "$CONFIG_REPO/sshd_secure.conf"
download_file "/home/nick/.ssh/authorized_keys" "$CONFIG_REPO/authorized_keys"

# Set permissions and ownership for downloaded files
chmod 644 /etc/systemd/system/poweroff-at-9pm.* || { echo "Failed to set permissions for poweroff timer"; exit 1; }
chown root:root /etc/systemd/system/poweroff-at-9pm.* || { echo "Failed to set ownership for poweroff timer"; exit 1; }
chmod 600 /home/nick/.ssh/authorized_keys || { echo "Failed to set permissions for authorized_keys"; exit 1; }
chown -R nick:nick /home/nick/.ssh || { echo "Failed to set ownership for .ssh directory"; exit 1; }

# Enable the poweroff timer
systemctl daemon-reload
systemctl enable poweroff-at-9pm.timer

# Enable dnf-automatic if installed
if rpm -q dnf-automatic &>/dev/null; then
    systemctl enable dnf-automatic.timer
fi

# Create 'kiosk' user with home directory and group if it doesn't exist
if ! id kiosk &>/dev/null; then
    useradd kiosk
    passwd -d kiosk
fi

# Create '_ssh' group and add 'nick'
groupadd -f _ssh
usermod -aG _ssh nick

# Create .ssh directory for nick user if it doesn't exist
if [ ! -d /home/nick/.ssh ]; then
    mkdir -p /home/nick/.ssh
    chmod 700 /home/nick/.ssh
    chown nick:nick /home/nick/.ssh
fi

# Configure mDNS with authselect
if authselect check &>/dev/null; then
    authselect enable-feature with-mdns4
    authselect enable-feature with-mdns6
    authselect apply-changes
else
    echo "Authselect is not available or not functioning correctly." >&2
fi

# Change firewall zone to home
firewall-cmd --set-default-zone=home
firewall-cmd --runtime-to-permanent

# Set hostname and restart Avahi
hostnamectl set-hostname centos-appliance
systemctl restart avahi-daemon

# Set 'kiosk' as the auto-login user for GDM
GDM_CONF="/etc/gdm/custom.conf"
if grep -q "^\[daemon\]" "$GDM_CONF"; then
    sed -i '/^\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=kiosk' "$GDM_CONF"
else
    echo -e "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=kiosk" >> "$GDM_CONF"
fi

# First login tasks for 'kiosk' using /etc/skel
SKEL_DIR="/etc/skel"

# Ensure the .config/autostart directory exists in /etc/skel
mkdir -p "$SKEL_DIR/.config/autostart"

# Create Google Chrome desktop entry for autostart if it doesn't exist
if [ -f /usr/share/applications/google-chrome.desktop ]; then
    cp /usr/share/applications/google-chrome.desktop "$SKEL_DIR/.config/autostart/"
    
    # Append desired parameters to the first "Exec" line in the desktop entry
    sed -i '/^Exec=/{s|$| --incognito --start-fullscreen "ows.openeye.net/login"|}' "$SKEL_DIR/.config/autostart/google-chrome.desktop"
fi

# Ensure proper permissions for /etc/skel
chmod -R o+rX "$SKEL_DIR/.config"

echo "Appliance setup complete."
