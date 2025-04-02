#!/bin/bash

set -uo pipefail
set -x

LOGFILE="/home/nick/appliance-setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "Starting appliance setup..."

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
download_file "/etc/yum.repos.d/google-chrome.repo" "$CONFIG_REPO/google-chrome.repo"
download_file "/etc/mdns.allow" "$CONFIG_REPO/mdns.allow"
download_file "/etc/dconf/db/local.d/00-extensions" "$CONFIG_REPO/00-extensions"
download_file "/etc/systemd/system/poweroff-at-9pm.timer" "$CONFIG_REPO/poweroff-at-9pm.timer"
download_file "/etc/systemd/system/poweroff-at-9pm.service" "$CONFIG_REPO/poweroff-at-9pm.service"
download_file "/etc/ssh/sshd_config.d/sshd_secure.conf" "$CONFIG_REPO/sshd_secure.conf"
download_file "/home/nick/.ssh/authorized_keys" "$CONFIG_REPO/authorized_keys"
download_file "/home/nick/.vimrc" "$CONFIG_REPO/.vimrc"

# Set ownership and permisisons for files downloaded to nick home
chown -R nick:nick /home/nick/.ssh/ || { echo "Failed to set ownership for .ssh directory"; exit 1; }
chmod 600 /home/nick/.ssh/authorized_keys || { echo "Failed to set permissions for authorized_keys"; exit 1; }
chown nick:nick /home/nick/.vimrc || { echo "Failed to set ownership for .ssh directory"; exit 1; }

# Install packages
install_packages() {
    dnf config-manager --set-enabled crb
    dnf -y install epel-release epel-next-release || { echo "Failed to install epel-release"; exit 1; }
    dnf --refresh -y upgrade || { echo "Failed to upgrade system"; exit 1; }
    dnf -y swap nano vim-enhanced || { echo "Failed to swap nano for vim-enhanced"; exit 1; }
    dnf -y install dnf-automatic \
                   dconf-editor gnome-tweaks gnome-extensions-app gnome-shell-extension-no-overview \
                   nss-mdns avahi-tools || { echo "Failed to install required packages"; exit 1; }
}

install_packages

# Install Google Chrome
dnf -y install google-chrome-stable || { echo "Failed to install Google Chrome"; exit 1; }

# Enforce shell extension no-overveiew for all users
dconf update

# Set vim as default editor by adding to /etc/profile.d/vim.sh
echo -e 'export VISUAL=vim\nexport EDITOR=vim' > /etc/profile.d/vim.sh
chmod +x /etc/profile.d/vim.sh || { echo "Failed to set vim as default editor"; exit 1; }

# Configure dnf automatic to apply updates
sed -i 's/^apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf

# Enable timers
systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }
systemctl enable poweroff-at-9pm.timer || { echo "Failed to enable poweroff timer"; exit 1; }
systemctl enable dnf-automatic.timer || { echo "Failed to enable dnf-automatic.timer"; exit 1; }

# First login tasks for 'kiosk' using /etc/skel
SKEL_DIR="/etc/skel"

# Ensure the .config/autostart directory exists in /etc/skel
mkdir -p "$SKEL_DIR/.config/autostart" || { echo "Failed to create autostart directory in /etc/skel"; exit 1; }

# Create Google Chrome desktop entry for autostart if it doesn't exist
if [ -f /usr/share/applications/google-chrome.desktop ]; then
    cp /usr/share/applications/google-chrome.desktop "$SKEL_DIR/.config/autostart/" || { echo "Failed to copy Google Chrome desktop entry"; exit 1; }
    
    # Append desired parameters to the first "Exec" line in the desktop entry
    sed -i '/^Exec=/{s|$| --incognito --start-fullscreen "ows.openeye.net/login"|}' "$SKEL_DIR/.config/autostart/google-chrome.desktop" || { echo "Failed to modify desktop entry"; exit 1; }
fi

# Suppress Google Chrome first run pop-up
mkdir -p "$SKEL_DIR/.config/google-chrome"
touch "$SKEL_DIR/.config/google-chrome/First\ Run"

# Ensure proper permissions for /etc/skel
chmod -R o+rX "$SKEL_DIR/.config" || { echo "Failed to set permissions for /etc/skel"; exit 1; }

# Create 'kiosk' user with home directory and group if it doesn't exist
if ! id kiosk &>/dev/null; then
    useradd kiosk || { echo "Failed to create kiosk user"; exit 1; }
    passwd -d kiosk || { echo "Failed to delete kiosk user password"; exit 1; }
fi

# Set 'kiosk' as the auto-login user for GDM
GDM_CONF="/etc/gdm/custom.conf"
if grep -q "^\[daemon\]" "$GDM_CONF"; then
    sed -i '/^\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=kiosk' "$GDM_CONF" || { echo "Failed to modify GDM configuration"; exit 1; }
else
    echo -e "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=kiosk" >> "$GDM_CONF" || { echo "Failed to write GDM configuration"; exit 1; }
fi

# Create '_ssh' group and add 'nick'
groupadd -f _ssh || { echo "Failed to create _ssh group"; exit 1; }
usermod -aG _ssh nick || { echo "Failed to add 'nick' to _ssh group"; exit 1; }

# Configure mDNS with authselect
# Modify the hosts line in /etc/authselect/user-nsswitch.conf
sed -i '/^hosts:/c\hosts:      files mdns [NOTFOUND=return] dns myhostname' /etc/authselect/user-nsswitch.conf

# Apply the changes
authselect apply-changes

: <<'EOF'
# Configure mDNS with authselect
configure_mdns() {
    if authselect check &>/dev/null; then
        authselect enable-feature with-mdns4 || return 1
        authselect enable-feature with-mdns6 || return 1
        authselect apply-changes || return 1
    else
        echo "Authselect is not available or not functioning correctly." >&2
        return 1
    fi
}

if ! configure_mdns; then
    echo "mDNS configuration failed"; exit 1
fi
EOF

# Change firewall zone to home
firewall-cmd --set-default-zone=home || { echo "Failed to set default firewall zone"; exit 1; }
firewall-cmd --runtime-to-permanent || { echo "Failed to apply firewall changes"; exit 1; }

# Set hostname and restart Avahi
hostnamectl set-hostname centos-appliance || { echo "Failed to set hostname"; exit 1; }
systemctl restart avahi-daemon || { echo "Failed to restart avahi-daemon"; exit 1; }

echo "Appliance setup complete."
