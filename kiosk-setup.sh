#!/bin/bash

LOG_FILE="/home/nick/setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting appliance setup script..."

# Ensure nick user exists before proceeding
if ! id "nick" &>/dev/null; then
    echo "Error: User 'nick' does not exist. Exiting."
    exit 1
fi

# Ensure epel-release is installed first
echo "Installing epel-release..."
dnf -y install epel-release && dnf makecache

# Install required packages
echo "Installing required packages..."
dnf -y install vim-enhanced dconf-editor gnome-extensions-app gnome-shell-extension-dash-to-dock nss-mdns dnf-automatic

echo "Installing Google Chrome..."
dnf -y install https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm

echo "Configuring system settings..."

# Set hostname if not already set
CURRENT_HOSTNAME=$(hostnamectl --static)
if [[ "$CURRENT_HOSTNAME" != "centos-appliance" ]]; then
    hostnamectl set-hostname centos-appliance
    systemctl restart avahi-daemon
fi

# Ensure _ssh group exists and add nick to it
if ! getent group _ssh >/dev/null; then
    groupadd _ssh
fi
if ! groups nick | grep -q '\b_ssh\b'; then
    usermod -aG _ssh nick
fi

# Ensure kiosk user exists as an unprivileged user
if ! id "kiosk" &>/dev/null; then
    useradd -m -s /sbin/nologin kiosk
fi

# Ensure necessary directories exist
mkdir -p /home/nick/.ssh
mkdir -p /etc/ssh/sshd_config.d

# Download configuration files
CONFIG_BASE_URL="https://raw.githubusercontent.com/nwilson97/config-files/refs/heads/main/"
wget -O /home/nick/.vimrc "$CONFIG_BASE_URL/.vimrc"
wget -O /etc/ssh/sshd_config.d/sshd_secure.conf "$CONFIG_BASE_URL/sshd_secure.conf"
wget -O /home/nick/.ssh/authorized_keys "$CONFIG_BASE_URL/authorized_keys"

# Ensure correct permissions and apply restorecon
chown nick:nick /home/nick/.vimrc
chown -R nick:nick /home/nick/.ssh
chmod 700 /home/nick/.ssh
chmod 600 /home/nick/.ssh/authorized_keys
restorecon -Rv /home/nick/.ssh /home/nick/.vimrc

# Configure SSH
systemctl restart sshd

# Configure firewall if needed
if [[ $(firewall-cmd --get-default-zone) != "home" ]]; then
    firewall-cmd --set-default-zone=home
    firewall-cmd --runtime-to-permanent
fi

# Configure authselect for mdns
if ! authselect current | grep -q "with-mdns"; then
    authselect enable-feature with-mdns
    authselect apply-changes
fi

# Enable and start dnf-automatic
systemctl enable --now dnf-automatic.timer

# Ensure first-login script for kiosk user exists
FIRST_LOGIN_SCRIPT="/home/kiosk/.config/autostart/kiosk-first-login.sh"
FIRST_LOGIN_DESKTOP="/home/kiosk/.config/autostart/kiosk-first-login.desktop"

mkdir -p /home/kiosk/.config/autostart
cat > "$FIRST_LOGIN_SCRIPT" <<EOF
#!/bin/bash
gnome-extensions enable dash-to-dock@micxgx.gmail.com
gsettings set org.gnome.shell.extensions.dash-to-dock disable-overview-on-startup true
rm -f "$FIRST_LOGIN_SCRIPT" "$FIRST_LOGIN_DESKTOP"
EOF
chmod +x "$FIRST_LOGIN_SCRIPT"

cat > "$FIRST_LOGIN_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Exec=/home/kiosk/.config/autostart/kiosk-first-login.sh
Hidden=false
X-GNOME-Autostart-enabled=true
Name=Kiosk First Login
EOF

chown -R kiosk:kiosk /home/kiosk/.config/autostart

echo "Setup complete. Please restart the system manually."
