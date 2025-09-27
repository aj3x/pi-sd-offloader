#!/bin/bash
# Load Discord webhook config from environment file
CONFIG_FILE="/etc/pi-sd-offloader/config.env"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Error: Config file $CONFIG_FILE not found." >&2
    exit 1
fi

# Check required variables
if [[ -z "$DISCORD_WEBHOOK_URL" || -z "$DISCORD_USERNAME" || -z "$DISCORD_AVATAR_URL" ]]; then
  echo "Error: Discord webhook config missing in config.env" >&2
  exit 1
fi

# Function to send a message to a Discord channel via webhook
discord_message() {
  local message="$1"
  curl -H "Content-Type: application/json" \
    -X POST \
    -d "{\"content\": \"$message\", \"username\": \"$DISCORD_USERNAME\", \"avatar_url\": \"$DISCORD_AVATAR_URL\"}" \
    "$DISCORD_WEBHOOK_URL"
}

# Usage example:
# discord_message "Hello from shell script!"
