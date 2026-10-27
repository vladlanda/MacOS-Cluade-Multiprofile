#!/usr/bin/env bash
# Builds ClaudeProfiles.app into ./build. Run on macOS 14+ with Xcode 15+ installed.
#   BUNDLE_ID=com.yourname.ClaudeProfiles SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE_ID="${BUNDLE_ID:-dev.claudeprofiles.ClaudeProfiles}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc signature
APP="build/Claude Profiles.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeProfiles"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeProfiles"
sed "s/__BUNDLE_ID__/$BUNDLE_ID/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

TIMESTAMP="--timestamp"; [ "$SIGN_IDENTITY" = "-" ] && TIMESTAMP="--timestamp=none"
codesign --force --options runtime $TIMESTAMP --entitlements Resources/ClaudeProfiles.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP"
