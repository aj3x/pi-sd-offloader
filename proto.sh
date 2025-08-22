#!/bin/bash
set -e

SRC="test/src"
DEST="test/dest"

SRC="/Volumes/Untitled"

# TEMP reset test
# rm -rf "$SRC"/*
# rm -rf "$DEST"/*

mkdir -p "$DEST"

# check that DCIM directory exists
if [ ! -d "$SRC/DCIM" ]; then
    echo "DCIM directory does not exist in source: $SRC"
    exit 1
fi
# check that it is not empty and contains files
if [ -z "$(ls -A "$SRC/DCIM/"*/)" ]; then
    echo "DCIM directory is empty in source: $SRC"
    exit 1
fi

# check that the files are the expected types
if ! find "$SRC/DCIM/"* -type f \
    \( -iname "*.jpg" -o \
       -iname "*.jpeg" -o \
       -iname "*.mp4" -o \
       -iname "*.mov" -o \
       -iname "*.heic" -o \
       -iname "*.heif" -o \
       -iname "*.png" -o \
       -iname "*.arw" \
    \) | grep -q .; then
    echo "No valid media files found in source: $SRC"
    exit 1
fi


# 1. Determine camera type
DCIM="$SRC/DCIM"
camera_type="Unknown"
if exiftool "$DCIM"/* | grep -q "DJI OsmoPocket3"; then
    echo "Camera: DJI Osmo Pocket 3"
    camera_type="DJI Osmo Pocket 3"
elif exiftool "$DCIM"/* | grep -q "ILCE-7C"; then
    echo "Camera: Sony A7C"
    camera_type="Sony A7C"
elif exiftool "$DCIM"/* | grep -q "FinePix XP150"; then
    echo "Camera: FinePix XP150"
    camera_type="Fujifilm FP XP150"
else
    echo "Camera: Unknown"
    echo "No supported camera type detected in source: $SRC"
    exit 1
fi
# elif exiftool "$SRC"/* | grep -q "Canon"; then
#     echo "Camera: Canon"
# elif exiftool "$SRC"/* | grep -q "Nikon"; then
#     echo "Camera: Nikon"
# else
#     echo "Camera: Unknown"
# fi

echo "Camera type detected: $camera_type"

# add camera type to destination path with date
today=$(date +%Y%m%d)
DEST="$DEST/$camera_type/$today"
# validate path doesn't already exist
if [ -d "$DEST" ]; then
    echo "Destination path already exists: $DEST"
    exit 1
fi
mkdir -p "$DEST"

exit 0

# 2. Copy files using rsync
echo "Copying files..."
rsync -av --progress "$SRC"/ "$DEST"/

# 3. Checksum verification
echo "Running checksums..."
cd "$SRC"
find . -type f -exec sha256sum "{}" \; | sort > /tmp/source_checksum.txt

cd "$DEST"
find . -type f -exec sha256sum "{}" \; | sort > /tmp/dest_checksum.txt

if diff /tmp/source_checksum.txt /tmp/dest_checksum.txt; then
    echo "Checksums match. Deleting source files."
    rm -rf "$SRC"/*
else
    echo "Checksum mismatch. Aborting deletion."
    exit 1
fi

echo "Transfer complete."
