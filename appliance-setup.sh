#!/bin/bash

LOGFILE="/home/nick/appliance-setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "Starting appliance setup..."

# Prompt for hostname at the beginning
echo "Please enter the hostname for the system:"
read -r NEW_HOSTNAME

# Validate input (empty check)
if [ -z "$NEW_HOSTNAME" ]; then
    echo "Hostname cannot be empty. Exiting."
    exit 1
fi

# Confirm with the user
echo "You have entered the hostname: $NEW_HOSTNAME"
read -r -p "Is this correct? (y/n): " CONFIRMATION
if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
    echo "Hostname change canceled."
    exit 1
fi

# Function to apply the hostname (but not run it yet)
apply_hostname() {
    hostnamectl hostname "$NEW_HOSTNAME" || { echo "Failed to set hostname."; exit 1; }
    echo "Hostname has been set to: $NEW_HOSTNAME"
    
    # Restart Avahi (if needed)
    systemctl restart avahi-daemon || { echo "Failed to restart avahi-daemon"; exit 1; }
}

# Define the function to download and configure necessary files
download_config_files() {
    # Define the configuration repository
    local CONFIG_REPO="https://raw.githubusercontent.com/nwilson97/config-files/main"

    # Ensure the target directory exists and download the file
    download_and_set_permissions() {
        local DEST_DIR="$1"
        local FILENAME="$2"
        local OWNER="$3"
        local PERMS="$4"

        # Ensure target directory exists
        mkdir -p "$DEST_DIR"

        # Download the file into the target directory, keeping its original name
        wget --tries=3 --timeout=10 -P "$DEST_DIR" "$CONFIG_REPO/$FILENAME" || {
            echo "Failed to download $CONFIG_REPO/$FILENAME to $DEST_DIR"
            exit 1
        }

        local DEST="${DEST_DIR%/}/$FILENAME"  # Prevent double slashes

        # Set ownership if specified
        if [[ -n "$OWNER" ]]; then
            chown "$OWNER" "$DEST" || { echo "Failed to set ownership for $DEST"; exit 1; }
        fi

        # Set permissions if specified
        if [[ -n "$PERMS" ]]; then
            chmod "$PERMS" "$DEST" || { echo "Failed to set permissions for $DEST"; exit 1; }
        fi
    }

    # List of files (format: "directory filename owner permissions")
    local FILES_TO_DOWNLOAD=(
        "/etc/yum.repos.d google-chrome.repo"
        "/etc mdns.allow"
        "/etc/dconf/db/local.d 00-extensions"
        "/etc/dconf/db/local.d 00-gnome-settings"
        "/etc/systemd/system poweroff-at-9pm.timer"
        "/etc/systemd/system poweroff-at-9pm.service"
        "/etc/ssh/sshd_config.d sshd_secure.conf"
        "/home/nick/.ssh authorized_keys nick:nick 600"
        "/home/nick .vimrc nick:nick"
    )

    # Loop through the list and call the function for each file
    for entry in "${FILES_TO_DOWNLOAD[@]}"; do
        download_and_set_permissions "$entry"
    done
}

# Call the function
download_config_files

# Function to install packages and Google Chrome
install_packages() {
    # Enable CRB repository
    dnf config-manager --set-enabled crb

    # Install EPEL and necessary releases
    dnf -y install epel-release epel-next-release || { echo "Failed to install epel-release"; exit 1; }

    # Upgrade system
    dnf --refresh -y upgrade || { echo "Failed to upgrade system"; exit 1; }

    # Swap nano for vim-enhanced
    dnf -y swap nano vim-enhanced || { echo "Failed to swap nano for vim-enhanced"; exit 1; }

    # Install required packages
    dnf -y install dnf-automatic \
                   dconf-editor gnome-tweaks gnome-extensions-app gnome-shell-extension-no-overview \
                   nss-mdns avahi-tools || { echo "Failed to install required packages"; exit 1; }

    # Install Google Chrome
    dnf -y install google-chrome-stable || { echo "Failed to install Google Chrome"; exit 1; }
}

# Call the function to install packages
install_packages

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

# Ensure proper permissions for /etc/skel
chmod -R o+rX "$SKEL_DIR/.config" || { echo "Failed to set permissions for /etc/skel"; exit 1; }

# Create 'kiosk' user with home directory and group if it doesn't exist
if ! id kiosk &>/dev/null; then
    useradd kiosk || { echo "Failed to create kiosk user"; exit 1; }
    passwd -d kiosk || { echo "Failed to delete kiosk user password"; exit 1; }
fi

# Define the function to download and configure the necessary files
download_kiosk_config_files() {
    # Define the configuration repository
    local CONFIG_REPO="https://raw.githubusercontent.com/nwilson97/config-files/main"

    # Function to download the file and set ownership
    download_and_set_ownership() {
        local DEST_DIR="$1"
        local FILENAME="$2"
        local OWNER="$3"

        # Ensure the target directory exists
        mkdir -p "$DEST_DIR"

        # Download the file into the target directory
        wget --tries=3 --timeout=10 -P "$DEST_DIR" "$CONFIG_REPO/$FILENAME" || {
            echo "Failed to download $FILENAME"
            exit 1
        }

        # Set ownership of the downloaded file
        chown "$OWNER" "$DEST_DIR/$FILENAME" || {
            echo "Failed to set ownership for $DEST_DIR/$FILENAME"
            exit 1
        }
    }

    # List of files (format: "directory filename owner")
    local FILES_TO_DOWNLOAD=(
        "/home/kiosk OWS-Recorders.automa.json kiosk:kiosk"
        "/home/kiosk OWS-Login.automa.json kiosk:kiosk"
    )

    # Loop through the list and call the function for each file
    for entry in "${FILES_TO_DOWNLOAD[@]}"; do
        # Split the entry into directory, filename, and owner
        IFS=" " read -r DEST_DIR FILENAME OWNER <<< "$entry"
        download_and_set_ownership "$DEST_DIR" "$FILENAME" "$OWNER"
    done
}

# Call the function to download and configure necessary files
download_kiosk_config_files

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

# Change firewall zone to home
firewall-cmd --set-default-zone=home || { echo "Failed to set default firewall zone"; exit 1; }
firewall-cmd --runtime-to-permanent || { echo "Failed to apply firewall changes"; exit 1; }

# Call the function to set the hostname
apply_hostname

# Final message
echo "Appliance setup complete. Please reboot the system."

# Prompt user for reboot
read -r -p "Would you like to reboot now? (y/n): " REBOOT_CONFIRM
if [[ "$REBOOT_CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Rebooting now..."
    systemctl reboot
else
    echo "Reboot skipped. Please remember to reboot later."
fi
