#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Exiting."
  exit 1
fi

# Define a log file and redirect stdout and stderr
LOGFILE="/tmp/agent_install.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "Agent installation script started at $(date)"

# Create a temporary directory for downloads
TMP_DIR="/tmp/agent_install"
mkdir -p "$TMP_DIR"

# Function to download files using curl or wget
download_file() {
  local url="$1"
  local dest="$2"
  echo "Downloading from $url ..."
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url"
  else
    echo "Error: Neither curl nor wget is installed. Please install one to continue."
    exit 1
  fi

  echo "Downloaded file to $dest"
}

# Example 1: Download and install a Monitoring Agent
MONITOR_AGENT_URL="https://example.com/path/to/monitor-agent-installer.sh"  # Replace with your actual URL
MONITOR_AGENT_INSTALLER="$TMP_DIR/monitor-agent-installer.sh"

download_file "$MONITOR_AGENT_URL" "$MONITOR_AGENT_INSTALLER"
chmod +x "$MONITOR_AGENT_INSTALLER"

echo "Installing Monitoring Agent..."
# Modify the installer options as required (e.g., --quiet, --install, etc.)
"$MONITOR_AGENT_INSTALLER" --quiet || { echo "Monitoring Agent installation failed"; exit 1; }
echo "Monitoring Agent installation completed."

# Example 2: Download and install a Custom Agent
CUSTOM_AGENT_URL="https://example.com/path/to/custom-agent-installer.sh"  # Replace with your actual URL
CUSTOM_AGENT_INSTALLER="$TMP_DIR/custom-agent-installer.sh"

download_file "$CUSTOM_AGENT_URL" "$CUSTOM_AGENT_INSTALLER"
chmod +x "$CUSTOM_AGENT_INSTALLER"

echo "Installing Custom Agent..."
# Adjust the options below as needed for your installer
"$CUSTOM_AGENT_INSTALLER" --quiet || { echo "Custom Agent installation failed"; exit 1; }
echo "Custom Agent installation completed."

echo "Agent installation script completed successfully at $(date)"
