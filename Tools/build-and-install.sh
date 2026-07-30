#!/bin/sh
# Builds a Release build and installs it as /Applications/CoteDOs.app,
# so Cmd+Space always launches the version built by this script.
set -e

cd "$(dirname "$0")/.."

BUILD_DIR="build/install"
rm -rf "$BUILD_DIR"

xcodebuild -project CoteDOs.xcodeproj -scheme CoteDOs -configuration Release \
  -derivedDataPath "$BUILD_DIR" build

APP="$BUILD_DIR/Build/Products/Release/CoteDOs.app"

osascript -e 'quit app "CoteDOs"' 2>/dev/null || true
sleep 1

rm -rf /Applications/CoteDOs.app
# ditto, not cp: it preserves the code signature, and a broken signature costs
# the audio-capture grant with nobody around to click Allow again.
ditto "$APP" /Applications/CoteDOs.app
rm -rf "$BUILD_DIR"

echo "Installed /Applications/CoteDOs.app"
