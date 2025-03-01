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
PROFILE_D_EDITOR="/etc/profile.d/editor.sh"
NEW_HOSTNAME="centos-appliance"

# Set hostname and restart Avahi if needed
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "$NEW_HOSTNAME" ]; then
  hostnamectl set-hostname "$NEW_HOSTNAME"
  systemctl restart avahi-daemon
fi

# Create unprivileged user with no password if not exists
if ! id "$USER_NAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USER_NAME"
  passwd -d "$USER_NAME"
fi

# Create _ssh group and add the administrative user 'nick' if the group doesn't exist
if ! getent group "$SSH_GROUP" &>/dev/null; then
  groupadd "$SSH_GROUP"
fi

if ! id -nG "$ADMIN_USER" | grep -qw "$SSH_GROUP"; then
  usermod -aG "$SSH_GROUP" "$ADMIN_USER"
fi

# Download and set up .vimrc, sshd_secure.conf, and authorized_keys
mkdir -p "$SSH_DIR" "$SSHD_CONFIG_DIR"

if [ ! -f "/home/$USER_NAME/.vimrc" ]; then
  curl -o "/home/$USER_NAME/.vimrc" "$VIMRC_URL"
  chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.vimrc"
fi

if [ ! -f "$SSHD_CONFIG_DIR/sshd_secure.conf" ]; then
  curl -o "$SSHD_CONFIG_DIR/sshd_secure.conf" "$SSHD_CONFIG_URL"
  chmod 644 "$SSHD_CONFIG_DIR/sshd_secure.conf"
fi

if [ ! -f "$SSH_DIR/authorized_keys" ]; then
  curl -o "$SSH_DIR/authorized_keys" "$AUTHORIZED_KEYS_URL"
  chmod 600 "$SSH_DIR/authorized_keys"
fi

# Ensure correct permissions and apply restorecon
if [ "$(stat -c %U "$SSH_DIR")" != "$USER_NAME" ]; then
  chown -R "$USER_NAME:$USER_NAME" "$SSH_DIR"
fi

if [ "$(stat -c %U /home/$USER_NAME/.vimrc)" != "$USER_NAME" ]; then
  chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.vimrc"
fi

if [ "$(stat -c %U "$SSHD_CONFIG_DIR/sshd_secure.conf")" != "root" ]; then
  chown root:root "$SSHD_CONFIG_DIR/sshd_secure.conf"
  chmod 644 "$SSHD_CONFIG_DIR/sshd_secure.conf"
fi

# Apply restorecon only if needed
if [ "$(restor
