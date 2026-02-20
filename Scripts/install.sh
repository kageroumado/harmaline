#!/bin/bash
set -euo pipefail

BINARY_NAME="harmaline"
INSTALL_PATH="/Library/PrivilegedHelperTools/$BINARY_NAME"
PLIST_NAME="glass.kagerou.harmaline.daemon"
DAEMON_PLIST="/Library/LaunchDaemons/$PLIST_NAME.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Build as current user before elevating to root.
echo "Building $BINARY_NAME..."
cd "$PROJECT_DIR"
swift build -c release --product harmaline 2>&1 | tail -5

BUILT_BINARY="$PROJECT_DIR/.build/release/$BINARY_NAME"
if [ ! -f "$BUILT_BINARY" ]; then
    echo -e "${RED}error:${NC} build failed — binary not found at $BUILT_BINARY"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}error:${NC} install requires root — re-run with sudo"
    echo "  The binary has been built. Run: sudo $0"
    exit 1
fi

# Stop existing daemon if running
if launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "Stopping existing daemon..."
    launchctl bootout system "$DAEMON_PLIST" 2>/dev/null || true
fi

# Install binary
echo "Installing binary to $INSTALL_PATH..."
mkdir -p /Library/PrivilegedHelperTools
cp "$BUILT_BINARY" "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"
chown root:wheel "$INSTALL_PATH"

# Install LaunchDaemon plist
echo "Installing LaunchDaemon..."
cp "$PROJECT_DIR/Resources/LaunchDaemons/$PLIST_NAME.plist" "$DAEMON_PLIST"
chmod 644 "$DAEMON_PLIST"
chown root:wheel "$DAEMON_PLIST"

# Start daemon
echo "Starting daemon..."
launchctl bootstrap system "$DAEMON_PLIST"

echo ""
echo -e "${GREEN}Installed successfully.${NC}"
echo "  Binary:  $INSTALL_PATH"
echo "  Daemon:  $DAEMON_PLIST"
echo "  Logs:    /Library/Logs/Harmaline.log"
echo ""
echo "The daemon is now monitoring for screen sharing display recovery."
echo "To uninstall: sudo Scripts/uninstall.sh"
