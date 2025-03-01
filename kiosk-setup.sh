#!/bin/bash
set -e

# Variables
USER_NAME="kiosk"
ADMIN_USER="nick"
SSH_GROUP="_ssh"
SSH_DIR="/home/$USER_NAME/.ssh"
CONFIG_BASE_URL="https://raw.githubusercontent.com/nwilson97/config-files/refs/heads/main/"
VIMRC_URL="${CONFIG_BASE_URL}.vimrc"
SSHD_CONFIG_URL="${CONFIG_BASE_URL}sshd_secure.conf"
AUTHORIZED_KEYS_URL="${CONFIG_BASE_URL}authorized_keys"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"

# Create unprivileged user with no password
useradd -m -s /bin/bash "$USER_NAME"
passwd -d "$USER_NAME"

# Create _ssh group and add the administrative user 'nick'
groupadd -f "$SSH_GROUP"
usermod -aG "$SSH_GROUP" "$ADMIN_USER"

# Download and set up .vimrc, sshd_secure.conf, and authorized_keys
mkdir -p "$SSH_DIR" "$SSHD_CONFIG_DIR"
curl -o "/home/$USER_NAME/.vimrc" "$VIMRC_URL"
chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.vimrc"
curl -o "$SSHD_CONFIG_DIR/sshd_secure.conf" "$SSHD_CONFIG_URL"
chmod 644 "$SSHD_CONFIG_DIR/sshd_secure.conf"
curl -o "$SSH_DIR/authorized_keys" "$AUTHORIZED_KEYS_URL"
chmod 600 "$SSH_DIR/authorized_keys"

# Ensure correct permissions
chown -R "$USER_NAME:$USER_NAME" "$SSH_DIR"
restorecon -Rv "$SSH_DIR" "/home/$USER_NAME/.vimrc" "$SSHD_CONFIG_DIR/sshd_secure.conf"

# Restart SSH service to apply new configuration
systemctl restart sshd

# Install and enable dnf-automatic
dnf install -y dnf-automatic
systemctl enable --now dnf-automatic.timer

# Swap nano-default-editor for vim-default-editor
dnf swap -y nano-default-editor vim-default-editor

# Install additional software: dconf-editor, gnome-extensions, gnome-tweaks, Google Chrome
dnf install -y dconf-editor gnome-extensions gnome-tweaks
dnf -y install https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm

# Cleanup
dnf clean all

echo "Setup complete. Reboot recommended."
