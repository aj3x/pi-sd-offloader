# pi-sd-offloader

An automatic Raspberry Pi-based SD card offloading script for photos and videos.

This system waits for an SD card to be plugged in and then begins pulling the files off the SD card, organizing them by camera type and import date, with checksum verification and duplicate detection.

## Features

- **Automatic SD Card Detection**: Uses udev rules to detect SD card insertion
- **Multi-Camera Support**: Identifies Sony A7C, DJI Osmo Pocket 3, Fujifilm XP150, and more
- **Flexible Transfer Options**: Direct to NAS or local-first with network fallback
- **Web Interface**: User-friendly dashboard for confirmations and configuration
- **Checksum Verification**: Ensures file integrity during transfers
- **Duplicate Detection**: Per-device-per-day duplicate checking
- **Extensible Configuration**: Easy to add new cameras via YAML config

## Quick Start

### Installation on Raspberry Pi

```bash
# Clone the repository
git clone https://github.com/yourusername/pi-sd-offloader.git
cd pi-sd-offloader

# Run installation script (requires sudo)
sudo ./scripts/install.sh
```

The installer will:
- Install system dependencies (Python, exiftool, rsync, etc.)
- Set up systemd services for automatic SD card handling
- Create udev rules for SD card detection
- Start the web interface on port 8080

### Access Web Interface

After installation, access the web interface at:
```
http://your-pi-ip:8080
```

## System Architecture

### Core Components

- **Camera Detector** (`src/core/camera_detector.py`): Identifies camera types using folder structure, file patterns, and EXIF data
- **Transfer Manager** (`src/core/transfer_manager.py`): Handles file transfers with checksum verification and network fallback
- **Web Interface** (`src/web/`): Flask-based dashboard for user interaction
- **Main Coordinator** (`src/main.py`): Orchestrates the entire workflow

### File Organization

Files are organized by import date in this structure:
```
Photos/
├── Sony A7C/
│   ├── 20240315/
│   │   ├── DCIM/     # Photo files
│   │   └── CLIP/     # Video files
└── DJI Osmo Pocket 3/
    └── 20240315/
        └── DCIM/
```

### Workflow

1. **Detection**: SD card insertion triggers udev rule → systemd service
2. **Identification**: Analyze folder structure, file patterns, and EXIF data
3. **Preparation**: Build file list and check for duplicates/conflicts
4. **Confirmation**: Present details to user via web interface
5. **Transfer**: Copy files with checksum verification
6. **Cleanup**: Optionally delete files from SD card after successful transfer

## Configuration

### Camera Configuration (`camera_config.yaml`)

Add new cameras by defining detection rules and file sources:

```yaml
cameras:
  my_new_camera:
    name: "My Camera Model"
    detection_rules:
      folder_structure:
        - path: "DCIM/100MYCAM"
          required: true
      file_patterns:
        - pattern: "IMG_*.JPG"
          confidence: 85
    file_sources:
      photos:
        - path: "DCIM/100MYCAM"
          extensions: [".JPG", ".RAW"]
    destination_structure: "My Camera/{date}/DCIM"
```

### Transfer Settings

- **Transfer Mode**: `auto`, `direct_nas`, or `local_first`
- **Network Fallback**: Automatic fallback to local storage if NAS unavailable
- **Checksum Verification**: SHA256 verification of all transfers
- **Duplicate Handling**: Per-device-per-day scope prevents overwrites

## Supported Cameras

### Currently Configured
- **Sony A7C**: ARW/JPG photos in DCIM, MP4 videos in PRIVATE/M4ROOT/CLIP
- **DJI Osmo Pocket 3**: JPG/MOV files in DCIM/100_FUJI
- **Fujifilm XP150**: LRF/MP4/WAV files in DCIM/DJI_001

### Adding New Cameras
1. Edit `camera_config.yaml` with detection rules
2. Restart service: `sudo systemctl restart pi-sd-offloader`
3. Test with actual SD card from the camera

## Network Configuration

### NAS Setup
- Configure NAS mount point in settings
- Test connectivity via web interface
- Supports both local network and VPN connections

### VPN Support
- Automatic VPN detection
- Fallback to local storage when VPN/NAS unavailable
- Background sync when network becomes available

## Monitoring and Logs

### View System Status
```bash
# Service status
sudo systemctl status pi-sd-offloader

# Live logs
sudo journalctl -u pi-sd-offloader -f

# Application logs
tail -f /var/log/pi-sd-offloader.log
```

### Web Interface Features
- Real-time transfer progress
- Network connectivity status
- Configuration management
- Transfer history and statistics

## Troubleshooting

### SD Card Not Detected
```bash
# Check udev rules
udevadm monitor --subsystem-match=block

# Test mount points
ls -la /media/sdcard/

# Check systemd services
systemctl status sd-card-handler@*
```

### Transfer Issues
- Check NAS connectivity in web interface
- Verify file permissions on destination paths
- Review logs for specific error messages
- Test with smaller SD cards first

### Web Interface Not Loading
```bash
# Check service status
sudo systemctl status pi-sd-offloader

# Check if port is bound
sudo netstat -tlnp | grep :8080

# Restart service
sudo systemctl restart pi-sd-offloader
```

## Development

### Local Testing
```bash
# Install dependencies
pip install -r requirements.txt

# Run locally (without udev integration)
python src/main.py

# Test camera detection
python -c "
from src.core.camera_detector import CameraDetector
detector = CameraDetector('camera_config.yaml')
result = detector.detect_camera('/path/to/test/sd/card')
print(result)
"
```

### Docker Support
```bash
# Build container
docker build -t pi-sd-offloader .

# Run with volume mounts
docker run -d \
  -p 8080:8080 \
  -v /media:/media \
  -v /mnt/nas:/nas \
  --privileged \
  pi-sd-offloader
```

## Future Enhancements

- [ ] Support for MTP devices (Insta360 Go3)
- [ ] Email notifications for transfer completion
- [ ] Advanced duplicate detection across all devices
- [ ] Cloud storage integration (Google Drive, Dropbox)
- [ ] Mobile app for remote monitoring
- [ ] Batch processing of multiple SD cards

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add your camera configurations or improvements
4. Test thoroughly with actual hardware
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.