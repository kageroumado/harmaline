#!/bin/bash
set -euo pipefail

BINARY_NAME="harmaline"
INSTALL_PATH="/Library/PrivilegedHelperTools/$BINARY_NAME"
PLIST_NAME="glass.kagerou.harmaline.daemon"
DAEMON_PLIST="/Library/LaunchDaemons/$PLIST_NAME.plist"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}error:${NC} uninstall requires root — run with sudo"
    exit 1
fi

# Stop daemon
if launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "Stopping daemon..."
    launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || true
fi

# Remove files
[ -f "$INSTALL_PATH" ] && rm "$INSTALL_PATH" && echo "Removed $INSTALL_PATH"
[ -f "$DAEMON_PLIST" ] && rm "$DAEMON_PLIST" && echo "Removed $DAEMON_PLIST"

echo -e "${GREEN}Uninstalled successfully.${NC}"
