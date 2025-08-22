# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pi-SD-Offloader is an automatic Raspberry Pi-based SD card offloading system that detects SD card insertion, transfers photos/videos to date-organized folders, validates transfers with checksums, and syncs to a Synology NAS.

## Architecture

The system is designed to run in a Docker container on Raspberry Pi OS (Lite) or DietPi. Key components:

- **Detection**: Monitors for SD card insertion events
- **Transfer**: Copies files to local date-based folders (YYYYMMDD format)
- **Validation**: Performs checksum verification to ensure transfer integrity
- **Cleanup**: Safely removes files from SD card after successful transfer
- **Sync**: Uploads to Synology NAS (local network or over internet/VPN)

## File Organization

### Target Structure (Synology)
```
Photos/
├── Sony A7C/
│   ├── 20240101/
│   │   ├── CLIP/     # Video files from PRIVATE/M4ROOT/CLIP
│   │   └── DCIM/     # Photo files from DCIM
│   └── 20250304/
├── Insta360 Go3/
└── DJI/
```

### Supported Camera Types
- **Sony A7C**: RAW/JPG files in DCIM, MP4 videos in PRIVATE/M4ROOT/CLIP
- **DJI Osmo Pocket 3**: JPG/MOV files in DCIM/100_FUJI  
- **Fujifilm FP XP150**: Files in DCIM/DJI_001

## Docker Configuration

The Dockerfile includes essential tools:
- `exiftool`: For metadata extraction and camera type detection
- `rsync`: For reliable file transfers with resume capability
- `sha256sum`: For checksum validation

Build and run:
```bash
docker build -t pi-sd-offloader .
docker run -v /media:/media -v /mnt/nas:/nas pi-sd-offloader
```

## Key Requirements

- Files must be imported within the correct date folder to prevent filename collisions
- No overwrites allowed during transfer process
- All transfers must be checksum-verified before SD card cleanup
- Camera type detection needed for proper folder organization
- Network connectivity validation required for NAS access

## Development Status

This is an early-stage project currently in the specification phase. The implementation will need to address:
- SD card detection mechanism
- Camera type identification logic
- Network/VPN connectivity handling
- User notification system
- Error handling and recovery procedures