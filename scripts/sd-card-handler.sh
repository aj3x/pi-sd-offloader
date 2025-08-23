#!/bin/bash
# SD Card Handler Script for Pi SD Offloader
# Called automatically when SD cards are inserted

set -e

DEVICE="$1"
LOG_FILE="/var/log/pi-sd-offloader.log"
MOUNT_BASE="/media/pi-sd-offloader"
SCRIPT_DIR="/opt/pi-sd-offloader"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SD-Handler] $1" | tee -a "$LOG_FILE"
}

log "SD card detected: $DEVICE"

# Validate device exists
if [ ! -b "/dev/$DEVICE" ]; then
    log "ERROR: Device /dev/$DEVICE not found"
    exit 1
fi

# Wait for device to be fully ready
sleep 2

# Create mount base directory
mkdir -p "$MOUNT_BASE"

# Find and mount partitions
MOUNTED_PARTITIONS=()
for partition in /dev/${DEVICE}*; do
    if [ -b "$partition" ] && [ "$partition" != "/dev/$DEVICE" ]; then
        # Check if already mounted
        if mountpoint -q "$partition" 2>/dev/null; then
            MOUNT_POINT=$(findmnt -n -o TARGET "$partition")
            log "Partition $partition already mounted at $MOUNT_POINT"
            MOUNTED_PARTITIONS+=("$MOUNT_POINT")
            continue
        fi
        
        # Create mount point
        MOUNT_POINT="$MOUNT_BASE/$(basename "$partition")"
        mkdir -p "$MOUNT_POINT"
        
        # Detect filesystem type
        FSTYPE=$(blkid -o value -s TYPE "$partition" 2>/dev/null || echo "unknown")
        
        # Mount with appropriate options
        case "$FSTYPE" in
            "vfat"|"fat32"|"exfat")
                if mount -t "$FSTYPE" -o uid=1000,gid=1000,umask=0022 "$partition" "$MOUNT_POINT" 2>/dev/null; then
                    log "Successfully mounted $partition ($FSTYPE) to $MOUNT_POINT"
                    MOUNTED_PARTITIONS+=("$MOUNT_POINT")
                else
                    log "Failed to mount $partition ($FSTYPE)"
                    rmdir "$MOUNT_POINT" 2>/dev/null || true
                fi
                ;;
            "ext4"|"ext3"|"ext2")
                if mount -t "$FSTYPE" "$partition" "$MOUNT_POINT" 2>/dev/null; then
                    log "Successfully mounted $partition ($FSTYPE) to $MOUNT_POINT"
                    MOUNTED_PARTITIONS+=("$MOUNT_POINT")
                else
                    log "Failed to mount $partition ($FSTYPE)"
                    rmdir "$MOUNT_POINT" 2>/dev/null || true
                fi
                ;;
            *)
                # Try auto-detection
                if mount "$partition" "$MOUNT_POINT" 2>/dev/null; then
                    log "Successfully mounted $partition (auto-detected) to $MOUNT_POINT"
                    MOUNTED_PARTITIONS+=("$MOUNT_POINT")
                else
                    log "Failed to mount $partition (unknown filesystem: $FSTYPE)"
                    rmdir "$MOUNT_POINT" 2>/dev/null || true
                fi
                ;;
        esac
    fi
done

# Check if any partitions were mounted
if [ ${#MOUNTED_PARTITIONS[@]} -eq 0 ]; then
    log "ERROR: No partitions could be mounted for device $DEVICE"
    exit 1
fi

# Process each mounted partition
SUCCESS=false
for mount_point in "${MOUNTED_PARTITIONS[@]}"; do
    log "Processing mount point: $mount_point"
    
    # Check if this looks like a camera SD card
    if [ -d "$mount_point/DCIM" ] || [ -d "$mount_point/PRIVATE/M4ROOT/CLIP" ]; then
        log "Found camera directory structure in $mount_point"
        
        # Run the main processing script
        if "$SCRIPT_DIR/proto.sh" "$mount_point" 2>&1 | tee -a "$LOG_FILE"; then
            log "Successfully processed SD card from $mount_point"
            SUCCESS=true
        else
            log "ERROR: Failed to process SD card from $mount_point"
        fi
        
        # Only process the first valid camera directory found
        break
    else
        log "No camera directory structure found in $mount_point"
    fi
done

if [ "$SUCCESS" = false ]; then
    log "WARNING: No valid camera SD card structure found on device $DEVICE"
fi

# Unmount partitions after processing
for mount_point in "${MOUNTED_PARTITIONS[@]}"; do
    if mountpoint -q "$mount_point" 2>/dev/null; then
        if umount "$mount_point" 2>/dev/null; then
            log "Unmounted $mount_point"
            rmdir "$mount_point" 2>/dev/null || true
        else
            log "WARNING: Failed to unmount $mount_point"
        fi
    fi
done

log "SD card processing complete for device $DEVICE"