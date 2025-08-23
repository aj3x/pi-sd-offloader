#!/bin/bash
# Installation script for Pi SD Offloader automatic detection

set -e

INSTALL_DIR="/opt/pi-sd-offloader"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔧 Installing Pi SD Offloader automatic detection..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Create installation directory
echo "📁 Creating installation directory..."
mkdir -p "$INSTALL_DIR"

# Copy scripts to installation directory
echo "📄 Copying scripts..."
cp "$PROJECT_ROOT/proto.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/sd-card-handler.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/proto.sh"
chmod +x "$INSTALL_DIR/sd-card-handler.sh"

# Install systemd service
echo "⚙️ Installing systemd service..."
cp "$SCRIPT_DIR/pi-sd-offloader@.service" /etc/systemd/system/

# Install udev rules
echo "🔌 Installing udev rules..."
cp "$SCRIPT_DIR/99-pi-sd-offloader.rules" /etc/udev/rules.d/

# Create log file
echo "📝 Setting up logging..."
touch /var/log/pi-sd-offloader.log
chown root:root /var/log/pi-sd-offloader.log
chmod 644 /var/log/pi-sd-offloader.log

# Reload systemd and udev
echo "🔄 Reloading system services..."
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger

echo "✅ Installation complete!"
echo ""
echo "Pi SD Offloader automatic detection is now active."
echo "Insert an SD card to test the system."
echo ""
echo "📝 View logs: tail -f /var/log/pi-sd-offloader.log"
echo "🔧 Check service status: systemctl status pi-sd-offloader@DEVICE.service"
echo ""
echo "Note: The system will automatically detect and process SD cards when inserted."