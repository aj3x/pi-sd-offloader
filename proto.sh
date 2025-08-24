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
    DEFAULT_DELETE_AFTER_TRANSFER=true
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
elif echo "$exifData" | grep -q "ILCE-7C"; then
    camera_type="Sony A7C"
elif echo "$exifData" | grep -q "FinePix XP150"; then
    camera_type="Fujifilm FP XP150"
else
    log "ERROR: No supported camera type detected in source: $SRC"
    log "First media file EXIF data:"
    exiftool "$first_media_file" | head -20
    exit 1
fi

log "Camera type: $camera_type"

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

# verify rsync exists
if ! command -v rsync &> /dev/null; then
    log "ERROR: rsync is not installed"
    exit 1
fi

if rsync -ahv --progress --checksum --prune-empty-dirs --exclude='.*' "${RSYNC_INCLUDES[@]}" "$SRC/" "$DEST/"; then
    log "File copy completed successfully"
else
    log "ERROR: File copy failed"
    exit 1
fi

# 3. Verification (checksum and size)
log "Running checksum and size verification..."

# Create temporary verification files with unique names
TIMESTAMP=$(date +%s)
SRC_CHECKSUM="/tmp/source_checksum_${TIMESTAMP}.txt"
DEST_CHECKSUM="/tmp/dest_checksum_${TIMESTAMP}.txt"
SRC_SIZES="/tmp/source_sizes_${TIMESTAMP}.txt"
DEST_SIZES="/tmp/dest_sizes_${TIMESTAMP}.txt"

# Create function to find files matching rsync criteria
find_matching_files() {
    local base_dir="$1"
    local target_dir="$2"
    
    # Build find expression for accepted types (same logic as rsync includes)
    local find_expr=""
    for ext in "${ACCEPTED_TYPES[@]}"; do
        find_expr+=" -o -iname '*.$ext'"
    done
    find_expr="${find_expr:4}" # Remove leading ' -o'
    
    cd "$base_dir"
    # Find files in DCIM and PRIVATE/M4ROOT/CLIP directories, matching accepted types
    (
        if [ -d "DCIM" ]; then
            eval find "DCIM" -type f $find_expr 2>/dev/null || true
        fi
        if [ -d "PRIVATE/M4ROOT/CLIP" ]; then
            eval find "PRIVATE/M4ROOT/CLIP" -type f $find_expr 2>/dev/null || true
        fi
    ) | \
    grep -v '/\.' | grep -v '/._' | \
    grep -v '/@eaDir/' | \
    grep -v '/.DS_Store' | \
    grep -v '/Thumbs.db' | \
    sort
}

# Generate checksums for source files
log "Computing source checksums and sizes..."
find_matching_files "$SRC" | while IFS= read -r file; do
    if [ -f "$SRC/$file" ]; then
        echo "$file"
    fi
done | xargs -I {} sh -c 'cd "$1" && sha256sum "$2"' _ "$SRC" {} | sort > "$SRC_CHECKSUM"

# Generate sizes for source files  
find_matching_files "$SRC" | while IFS= read -r file; do
    if [ -f "$SRC/$file" ]; then
        echo "$file"
    fi
done | xargs -I {} sh -c 'cd "$1" && stat -c "%s %n" "$2" 2>/dev/null || stat -f "%z %N" "$2"' _ "$SRC" {} | sort > "$SRC_SIZES"

# Generate checksums for destination files
log "Computing destination checksums and sizes..."
find_matching_files "$DEST" | while IFS= read -r file; do
    if [ -f "$DEST/$file" ]; then
        echo "$file"
    fi
done | xargs -I {} sh -c 'cd "$1" && sha256sum "$2"' _ "$DEST" {} | sort > "$DEST_CHECKSUM"

# Generate sizes for destination files
find_matching_files "$DEST" | while IFS= read -r file; do
    if [ -f "$DEST/$file" ]; then
        echo "$file"
    fi
done | xargs -I {} sh -c 'cd "$1" && stat -c "%s %n" "$2" 2>/dev/null || stat -f "%z %N" "$2"' _ "$DEST" {} | sort > "$DEST_SIZES"

# Verify checksums
CHECKSUM_MATCH=true
if ! diff "$SRC_CHECKSUM" "$DEST_CHECKSUM" > /dev/null; then
    CHECKSUM_MATCH=false
fi

# Verify sizes
SIZE_MATCH=true
if ! diff "$SRC_SIZES" "$DEST_SIZES" > /dev/null; then
    SIZE_MATCH=false
fi

# Report verification results
if [ "$CHECKSUM_MATCH" = true ] && [ "$SIZE_MATCH" = true ]; then
    log "✓ Checksums and file sizes match. Transfer verified successfully."
    log "Files are safe to delete from SD card."
    VERIFICATION_PASSED=true
elif [ "$CHECKSUM_MATCH" = false ] && [ "$SIZE_MATCH" = false ]; then
    log "✗ ERROR: Both checksum and size mismatches detected!"
    log "Source checksum file: $SRC_CHECKSUM"
    log "Destination checksum file: $DEST_CHECKSUM"
    log "Differences:"
    diff "$SRC_CHECKSUM" "$DEST_CHECKSUM" | log
    log "Source size file: $SRC_SIZES"
    log "Destination size file: $DEST_SIZES"
    log "Transfer verification failed. SD card files will NOT be deleted."
    VERIFICATION_PASSED=false
elif [ "$CHECKSUM_MATCH" = false ]; then
    log "✗ ERROR: Checksum mismatch detected!"
    log "Source checksum file: $SRC_CHECKSUM"
    log "Destination checksum file: $DEST_CHECKSUM"
    log "Transfer verification failed. SD card files will NOT be deleted."
    VERIFICATION_PASSED=false
else
    log "✗ ERROR: File size mismatch detected!"
    log "Source size file: $SRC_SIZES"
    log "Destination size file: $DEST_SIZES"
    log "Transfer verification failed. SD card files will NOT be deleted."
    VERIFICATION_PASSED=false
fi

# Clean up temporary verification files
rm -f "$SRC_CHECKSUM" "$DEST_CHECKSUM" "$SRC_SIZES" "$DEST_SIZES"

# Delete Files on Source SD Card (only if verification passed)
if [ "$VERIFICATION_PASSED" = true ]; then
    if [ "$DEFAULT_DELETE_AFTER_TRANSFER" = true ]; then
        log "Deleting files from source: $SRC"
        rm -rf "$SRC"/*
        log "✓ Source files deleted successfully"
    else
        log "NOTICE: Automatic deletion is disabled. Enable it by setting DEFAULT_DELETE_AFTER_TRANSFER=true"
    fi
    log "✓ Transfer complete successfully!"
    exit 0
else
    log "✗ Transfer verification failed - source files preserved for safety"
    exit 1
fi
