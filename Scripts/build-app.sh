#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Harmaline"
APP_DIR="$PROJECT_DIR/.build/$APP_NAME.app"

cd "$PROJECT_DIR"

echo "Building daemon..."
swift build -c release --product harmaline 2>&1 | tail -3

echo "Building app..."
swift build -c release --product HarmalineApp 2>&1 | tail -3

echo "Assembling $APP_NAME.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/LaunchDaemons"

# App binary
cp .build/release/HarmalineApp "$APP_DIR/Contents/MacOS/Harmaline"

# Daemon binary (bundled for install, distinct name to avoid case collision)
cp .build/release/harmaline "$APP_DIR/Contents/MacOS/harmaline-daemon"

# Plist (bundled for install)
cp Resources/LaunchDaemons/glass.kagerou.harmaline.daemon.plist \
   "$APP_DIR/Contents/Resources/LaunchDaemons/"

# Info.plist
cp Resources/Info.plist "$APP_DIR/Contents/"

# App icon
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

# Ad-hoc sign so macOS doesn't quarantine-block it
codesign --force --sign - "$APP_DIR/Contents/MacOS/harmaline-daemon"
codesign --force --sign - "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo ""
echo "To install, open the app:"
echo "  open \"$APP_DIR\""
