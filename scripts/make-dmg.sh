#!/usr/bin/env bash
# Packs build/Claude Profiles.app into build/ClaudeProfiles.dmg (drag-to-Applications layout).
# Run scripts/build-app.sh first.
#
# Optional, for a DMG that opens on other Macs without Gatekeeper warnings:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"  signs the DMG
#   NOTARY_PROFILE=claude-profiles   notarizes + staples it (create the profile once with
#                                    xcrun notarytool store-credentials claude-profiles …)
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Claude Profiles.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/ClaudeProfiles-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

[ -d "$APP" ] || { echo "Missing $APP — run scripts/build-app.sh first." >&2; exit 1; }

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Claude Profiles" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
