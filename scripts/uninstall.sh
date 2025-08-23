#!/bin/bash
# Uninstallation script for Pi SD Offloader

set -e

INSTALL_DIR="/opt/pi-sd-offloader"
CONFIG_DIR="/etc/pi-sd-offloader"
SERVICE_USER="pi"

echo "🗑️  Uninstalling Pi SD Offloader..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Confirmation prompt
echo "⚠️  This will completely remove Pi SD Offloader and all its components."
echo "The following will be removed:"
echo "  - Application files in $INSTALL_DIR"
echo "  - Configuration files in $CONFIG_DIR"
echo "  - Systemd services (pi-sd-offloader.service, sd-card-handler@.service)"
echo "  - Udev rules (/etc/udev/rules.d/99-pi-sd-offloader.rules)"
echo "  - Mount script (/usr/local/bin/mount-sd-card.sh)"
echo "  - Log rotation config (/etc/logrotate.d/pi-sd-offloader)"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Stop and disable services
echo "⏹️  Stopping and disabling services..."
systemctl stop pi-sd-offloader.service 2>/dev/null || true
systemctl disable pi-sd-offloader.service 2>/dev/null || true

# Stop any running sd-card-handler instances
echo "⏹️  Stopping SD card handler instances..."
systemctl stop 'sd-card-handler@*' 2>/dev/null || true

# Remove systemd service files
echo "🗑️  Removing systemd services..."
rm -f /etc/systemd/system/pi-sd-offloader.service
rm -f /etc/systemd/system/sd-card-handler@.service

# Reload systemd daemon
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# Remove udev rules
echo "🔌 Removing udev rules..."
rm -f /etc/udev/rules.d/99-pi-sd-offloader.rules

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Remove mount script
echo "📁 Removing mount script..."
rm -f /usr/local/bin/mount-sd-card.sh

# Remove log rotation config
echo "📝 Removing log rotation config..."
rm -f /etc/logrotate.d/pi-sd-offloader

# Remove application directories
echo "📁 Removing application directories..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "  Removed $INSTALL_DIR"
fi

if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo "  Removed $CONFIG_DIR"
fi

# Remove mount points (but keep /media/sdcard if it has other content)
echo "📁 Cleaning up mount points..."
if [ -d "/media/sdcard" ]; then
    # Only remove if empty or contains only our mount points
    if [ -z "$(ls -A /media/sdcard 2>/dev/null)" ]; then
        rmdir /media/sdcard 2>/dev/null && echo "  Removed /media/sdcard (was empty)"
    else
        echo "  Kept /media/sdcard (contains other files)"
    fi
fi

# Remove log file
echo "📝 Removing log files..."
rm -f /var/log/pi-sd-offloader.log*

# Optional: Ask about removing system packages
echo ""
echo "🤔 System packages installed during setup:"
echo "  - python3-venv, exiftool, rsync, udev, systemd, util-linux"
echo "  - findutils, coreutils (core system packages)"
echo ""
read -p "Remove Python packages that were installed? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing Python packages..."
    apt remove -y python3-venv exiftool rsync 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    echo "  Note: Core system packages (udev, systemd, util-linux, findutils, coreutils) were kept for system stability"
fi

# Clean up any remaining processes
echo "🧹 Final cleanup..."
pkill -f "pi-sd-offloader" 2>/dev/null || true
pkill -f "sd-card-handler" 2>/dev/null || true

echo ""
echo "✅ Pi SD Offloader has been completely uninstalled!"
echo ""
echo "📋 Summary of actions taken:"
echo "  ✓ Stopped and removed systemd services"
echo "  ✓ Removed udev rules for SD card detection"
echo "  ✓ Deleted application and configuration directories"
echo "  ✓ Removed mount script and log rotation"
echo "  ✓ Cleaned up log files and mount points"
echo ""
echo "🔄 A system reboot is recommended to ensure all changes take effect."
echo "💡 To reboot now: sudo reboot"