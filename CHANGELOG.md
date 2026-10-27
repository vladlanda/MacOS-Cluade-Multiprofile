# Changelog

## 1.1

### Added
- **Open in Terminal:** runs Claude Code (`claude`) signed in to the profile's own account.
  Each profile gets its own `CLAUDE_CONFIG_DIR` under
  `~/Library/Application Support/ClaudeProfiles/cli/<profile id>`.
  - Where to find it: a terminal button on each row, **Open Terminal** and **Open Terminal in
    Folder…** in the row's "…" menu, Option-click on a profile in the menu-bar dropdown, and a
    submenu on each dropdown row.
  - Each profile remembers the folder it last opened in.
  - New **Settings › Terminal** section: terminal app (Terminal, iTerm or another app), default
    working folder, and "Unset ANTHROPIC_API_KEY in profile terminals" (on by default).
  - Launches without AppleScript, via a temporary `.command` script (mode 0700) that deletes
    itself when it starts. Profile names and paths are strictly quoted.
- **Running · no window** status, shown when Claude is running but its window was closed.
- **Quit Claude for This Profile** in the row's "…" menu.
- App icon.
- `scripts/make-dmg.sh` builds a DMG, with optional signing and notarization.
- `scripts/run_all.sh` quits the app, rebuilds it, makes the DMG, installs it to
  /Applications and opens it.
- Unit tests (`swift test`) for the launch script, temp-file permissions, loading `profiles.json`,
  and profile deletion. They run on macOS and Linux.

### Changed
- **Show** now reopens Claude's window when it was closed. It sends the same "reopen" event as
  clicking the Dock icon.
- Deleting a profile with "Also delete this profile's data folders" ticked now also moves its
  Claude Code folder to the Trash. The dialog shows both folders.
- On each row, the status and the Show/Launch button sit in fixed-width columns, so the buttons
  line up from row to row.
- Testable logic moved into a `ClaudeProfilesCore` library. `profiles.json` files from 1.0 still
  load unchanged.

## 1.0

- First version: a main window with a list of profiles, a New Profile sheet, the menu-bar
  dropdown, Settings, the Delete dialog, and error banners for a missing Claude.app and failed
  launches.
