#!/bin/bash

# Exit on errors, treat unset variables as errors, and fail on pipeline errors
set -euo pipefail

# Log all output to a file
LOGFILE="/var/log/setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

# Variables
NEW_USER="mediauser"
GROUP="_media"
SOFTWARE_PACKAGES=("ffmpeg" "vlc" "gimp" "htop" "tmux" "dnf-automatic")

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $*"
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    log "This script must be run as root."
    exit 1
fi

log "Starting system setup..."

# Update system packages
log "Updating system packages..."
dnf -y update

# Install essential software packages
log "Installing required packages..."
dnf -y install "${SOFTWARE_PACKAGES[@]}"

# Create user and group for media processing
log "Creating user and group..."
groupadd -f "$GROUP"
useradd -m -s /bin/bash -G "$GROUP" "$NEW_USER"

# Set up SSH access (allow only key-based login)
log "Configuring SSH settings..."
mkdir -p /home/$NEW_USER/.ssh
chmod 700 /home/$NEW_USER/.ssh
touch /home/$NEW_USER/.ssh/authorized_keys
chmod 600 /home/$NEW_USER/.ssh/authorized_keys
chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh

# Configure SSH to disallow password authentication
log "Updating SSHD configuration..."
echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/custom.conf
systemctl restart sshd

# Enable automatic updates
log "Enabling automatic updates..."
if command -v dnf5 >/dev/null; then
    dnf5 install -y dnf-automatic
else
    dnf install -y dnf-automatic
fi

# Configure DNF Automatic for security updates only
log "Configuring automatic updates..."
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

# Adjust system performance settings
log "Applying system performance tweaks..."
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
sysctl -p

# Open firewall for SSH access
log "Configuring firewall..."
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

log "Setup complete!"
