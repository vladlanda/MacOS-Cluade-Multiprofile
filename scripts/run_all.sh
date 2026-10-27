#!/usr/bin/env bash
# Quits Claude Profiles, rebuilds it, makes the DMG, installs the app into /Applications
# and opens it.
#   scripts/run_all.sh            build + DMG + install + open
#   scripts/run_all.sh --no-dmg   skip the DMG
set -euo pipefail

cd "$(dirname "$0")/.."            # project root, wherever the script is run from
APP_NAME="Claude Profiles.app"
INSTALLED="/Applications/$APP_NAME"

MAKE_DMG=1
[ "${1:-}" = "--no-dmg" ] && MAKE_DMG=0

# Quit running copies so the new build is what runs (no error if none are running).
pkill -x ClaudeProfiles 2>/dev/null || true

chmod +x scripts/*.sh
scripts/build-app.sh                         # → build/Claude Profiles.app
if [ "$MAKE_DMG" = 1 ]; then
  scripts/make-dmg.sh                        # → build/ClaudeProfiles-<version>.dmg
fi

# Replace the installed copy (copying onto an existing .app would nest it inside).
rm -rf "$INSTALLED"
ditto "build/$APP_NAME" "$INSTALLED"
echo "Installed $INSTALLED"

open "$INSTALLED"
