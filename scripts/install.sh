#!/bin/bash
# Installation script for Pi SD Offloader

set -e

INSTALL_DIR="/opt/pi-sd-offloader"
CONFIG_DIR="/etc/pi-sd-offloader"
SERVICE_USER="pi"

echo "🔧 Installing Pi SD Offloader..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Update system
echo "📦 Updating system packages..."
apt update

# Install required system packages
echo "📦 Installing system dependencies..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    exiftool \
    rsync \
    udev \
    systemd \
    util-linux \
    findutils \
    coreutils

# Create installation directory
echo "📁 Creating installation directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p /var/log
mkdir -p /media/sdcard

# Copy application files
echo "📄 Copying application files..."
cp -r src/* "$INSTALL_DIR/"
cp camera_config.yaml "$CONFIG_DIR/"

# Set up Python virtual environment
echo "🐍 Setting up Python environment..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install -r ../requirements.txt

# Create systemd service for main application
echo "⚙️ Creating systemd service..."
cat > /etc/systemd/system/pi-sd-offloader.service << EOF
[Unit]
Description=Pi SD Offloader Web Interface
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin
ExecStart=$INSTALL_DIR/venv/bin/python main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service template for SD card handling
cat > /etc/systemd/system/sd-card-handler@.service << EOF
[Unit]
Description=Handle SD Card %i
After=systemd-udevd.service

[Service]
Type=oneshot
User=root
Group=root
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/main.py %i
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# Create udev rules for SD card detection
echo "🔌 Creating udev rules..."
cat > /etc/udev/rules.d/99-pi-sd-offloader.rules << EOF
# Pi SD Offloader udev rules for SD card detection

# Built-in SD card readers (e.g., Raspberry Pi SD slot)
ACTION=="add", KERNEL=="mmcblk[0-9]*", SUBSYSTEM=="block", TAG+="systemd", ENV{SYSTEMD_WANTS}="sd-card-handler@%k.service"

# USB SD card readers
ACTION=="add", KERNEL=="sd[a-z]*", SUBSYSTEM=="block", SUBSYSTEMS=="usb", ATTRS{model}=="*Card*Reader*", TAG+="systemd", ENV{SYSTEMD_WANTS}="sd-card-handler@%k.service"

# Alternative: Detect any removable storage
ACTION=="add", KERNEL=="sd[a-z]*", SUBSYSTEM=="block", ATTRS{removable}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}="sd-card-handler@%k.service"
EOF

# Create mount script for reliable mounting
cat > /usr/local/bin/mount-sd-card.sh << EOF
#!/bin/bash
# Reliable SD card mounting script

DEVICE="\$1"
MOUNT_BASE="/media/sdcard"

# Wait for device to be ready
sleep 2

# Check if device exists
if [ ! -b "/dev/\$DEVICE" ]; then
    logger "SD card device /dev/\$DEVICE not found"
    exit 1
fi

# Find partitions
for partition in /dev/\${DEVICE}*; do
    if [ -b "\$partition" ] && [ "\$partition" != "/dev/\$DEVICE" ]; then
        # Check if already mounted
        if findmnt "\$partition" > /dev/null; then
            logger "Partition \$partition already mounted"
            continue
        fi
        
        # Create mount point
        MOUNT_POINT="\$MOUNT_BASE/\$(basename "\$partition")"
        mkdir -p "\$MOUNT_POINT"
        
        # Detect filesystem type
        FSTYPE=\$(blkid -o value -s TYPE "\$partition" 2>/dev/null)
        
        # Mount with appropriate options
        case "\$FSTYPE" in
            "vfat"|"fat32"|"exfat")
                mount -t "\$FSTYPE" -o uid=1000,gid=1000,umask=0022 "\$partition" "\$MOUNT_POINT"
                ;;
            "ext4"|"ext3"|"ext2")
                mount -t "\$FSTYPE" "\$partition" "\$MOUNT_POINT"
                ;;
            *)
                # Try auto-detection
                mount "\$partition" "\$MOUNT_POINT"
                ;;
        esac
        
        if [ \$? -eq 0 ]; then
            logger "Successfully mounted \$partition to \$MOUNT_POINT"
        else
            logger "Failed to mount \$partition"
            rmdir "\$MOUNT_POINT" 2>/dev/null
        fi
    fi
done
EOF

chmod +x /usr/local/bin/mount-sd-card.sh

# Set up log rotation
echo "📝 Setting up log rotation..."
cat > /etc/logrotate.d/pi-sd-offloader << EOF
/var/log/pi-sd-offloader.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 $SERVICE_USER $SERVICE_USER
}
EOF

# Set correct permissions
echo "🔒 Setting permissions..."
chown -R $SERVICE_USER:$SERVICE_USER "$INSTALL_DIR"
chown -R $SERVICE_USER:$SERVICE_USER "$CONFIG_DIR"
chmod +x "$INSTALL_DIR/main.py"

# Enable and start services
echo "🚀 Enabling services..."
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger

systemctl enable pi-sd-offloader.service
systemctl start pi-sd-offloader.service

# Final setup
echo "✨ Installation complete!"
echo ""
echo "Pi SD Offloader has been installed and started."
echo ""
echo "🌐 Web interface: http://$(hostname -I | awk '{print $1}'):8080"
echo "📝 Logs: /var/log/pi-sd-offloader.log"
echo "⚙️  Config: $CONFIG_DIR/camera_config.yaml"
echo ""
echo "To check status: sudo systemctl status pi-sd-offloader"
echo "To view logs: sudo journalctl -u pi-sd-offloader -f"
echo ""
echo "Insert an SD card to test the system!"
EOF