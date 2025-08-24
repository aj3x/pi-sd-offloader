#!/bin/bash
set -e

# Pi SD Offloader - Main processing script
# Usage: proto.sh [SOURCE_PATH] [DESTINATION_PATH]


# List of accepted file types (extensions, lowercase, no dot)
ACCEPTED_TYPES=(jpg jpeg mp4 mov heic heif png arw raw)


# Default paths for testing
DEFAULT_SRC="/Volumes/Untitled"
# Source config file for DEFAULT_DEST
CONFIG_FILE="/etc/pi-sd-offloader/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    DEFAULT_DEST="/mnt/nas/photos"
fi

# Accept command line parameters
SRC="${1:-$DEFAULT_SRC}"
DEST="${2:-$DEFAULT_DEST}"

# If DEST is not absolute, make it relative to script directory
if [[ "$DEST" != /* ]]; then
    DEST="$(pwd)/$DEST"
fi

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [Proto] $1"
}

log "Processing SD card from: $SRC"
log "Destination: $DEST"

mkdir -p "$DEST"

# Check that DCIM directory exists
if [ ! -d "$SRC/DCIM" ]; then
    log "ERROR: DCIM directory does not exist in source: $SRC"
    exit 1
fi

# Check that it is not empty and contains files

# Build find expression for accepted types
FIND_EXPR=""
for ext in "${ACCEPTED_TYPES[@]}"; do
    FIND_EXPR+=" -o -iname '*.$ext'"
done
FIND_EXPR="${FIND_EXPR:4}" # Remove leading ' -o'

if [ -z "$(eval find "$SRC/DCIM" $FIND_EXPR 2>/dev/null | head -n 1)" ]; then
    log "ERROR: No valid media files found in DCIM directory: $SRC/DCIM"
    exit 1
fi

# Get first media file for camera detection

# Build find expression for first media file
FIRST_MEDIA_EXPR=""
for ext in "${ACCEPTED_TYPES[@]}"; do
    FIRST_MEDIA_EXPR+=" -o -iname '*.$ext'"
done
FIRST_MEDIA_EXPR="${FIRST_MEDIA_EXPR:4}"
first_media_file=$(eval find "$SRC/DCIM" -type f $FIRST_MEDIA_EXPR | head -n 1)

if [ -z "$first_media_file" ]; then
    log "ERROR: No valid media files found in source: $SRC"
    exit 1
fi


# 1. Determine camera type
log "Detecting camera type from: $first_media_file"
camera_type="Unknown"
exifData=$(exiftool "$first_media_file")

if echo "$exifData" | grep -q "DJI OsmoPocket3"; then
    camera_type="DJI Osmo Pocket 3"
    log "Camera detected: DJI Osmo Pocket 3"
elif echo "$exifData" | grep -q "ILCE-7C"; then
    camera_type="Sony A7C"
    log "Camera detected: Sony A7C"
elif echo "$exifData" | grep -q "FinePix XP150"; then
    camera_type="Fujifilm FP XP150"
    log "Camera detected: Fujifilm FP XP150"
else
    log "ERROR: No supported camera type detected in source: $SRC"
    log "First media file EXIF data:"
    exiftool "$first_media_file" | head -20
    exit 1
fi

# Add camera type to destination path with date
today=$(date +%Y%m%d)
DEST="$DEST/$camera_type/$today"

# Validate path doesn't already exist (prevents overwriting)
if [ -d "$DEST" ]; then
    log "ERROR: Destination path already exists: $DEST"
    log "This prevents accidental overwriting. Remove the directory or change the date if this is intentional."
    exit 1
fi

log "Creating destination directory: $DEST"
mkdir -p "$DEST"

# 2. Copy files using rsync
log "Copying files from $SRC to $DEST..."
RSYNC_INCLUDES=(--include='DCIM/**' --include='PRIVATE/M4ROOT/CLIP/**' --include='*/')
for ext in "${ACCEPTED_TYPES[@]}"; do
    RSYNC_INCLUDES+=(--include="*.$ext")
done
RSYNC_INCLUDES+=(--exclude='*')

if rsync -ahv --progress --checksum --prune-empty-dirs --exclude='.*' "${RSYNC_INCLUDES[@]}" "$SRC/" "$DEST/"; then
    log "File copy completed successfully"
else
    log "ERROR: File copy failed"
    exit 1
fi

# 3. Checksum verification
log "Running checksum verification..."

# Create temporary checksum files with unique names
SRC_CHECKSUM="/tmp/source_checksum_$(date +%s).txt"
DEST_CHECKSUM="/tmp/dest_checksum_$(date +%s).txt"


# Build grep pattern for accepted types
GREP_PATTERN="\\.($(IFS='|'; echo "${ACCEPTED_TYPES[*]}"))$"

cd "$SRC"
# Find files, handling cases where PRIVATE directory might not exist
(find "DCIM" -type f 2>/dev/null || true; find "PRIVATE/M4ROOT/CLIP" -type f 2>/dev/null || true) | \
grep -E "$GREP_PATTERN" | \
grep -v '/\.' | grep -v '/._' | \
sort | xargs -I {} sha256sum "{}" | sort > "$SRC_CHECKSUM"


cd "$DEST"
(find "DCIM" -type f 2>/dev/null || true; find "PRIVATE/M4ROOT/CLIP" -type f 2>/dev/null || true) | \
grep -E "$GREP_PATTERN" | \
grep -v '/\.' | grep -v '/._' | \
sort | xargs -I {} sha256sum "{}" | sort > "$DEST_CHECKSUM"

if diff "$SRC_CHECKSUM" "$DEST_CHECKSUM" > /dev/null; then
    log "✓ Checksums match. Transfer verified successfully."
    log "Files are safe to delete from SD card."
    # Uncomment the next line to enable automatic deletion after successful verification
    # TODO: Implement automatic deletion
    # rm -rf "$SRC"/*
    log "NOTICE: Automatic deletion is disabled for safety. Enable it by uncommenting line in script."
else
    log "✗ ERROR: Checksum mismatch detected!"
    log "Source checksum file: $SRC_CHECKSUM"
    log "Destination checksum file: $DEST_CHECKSUM"
    log "Transfer verification failed. SD card files will NOT be deleted."
    exit 1
fi

# Clean up temporary checksum files
rm -f "$SRC_CHECKSUM" "$DEST_CHECKSUM"

log "✓ Transfer complete successfully!"
exit 0
