# Claude Profiles

A small macOS menu-bar app for running several Claude accounts side by side, in both the
**Claude desktop app** and **Claude Code** (the `claude` CLI).

- **Desktop app:** each profile launches its own copy of Claude.app with its own data folder
  (`--user-data-dir`), so each one stays signed in to a different account. The same works as
  `open -n -a Claude.app --args --user-data-dir=…`.
- **Claude Code:** each profile can open a terminal running `claude` with its own
  `CLAUDE_CONFIG_DIR`, so the CLI logins are separate too.
- **Menu bar:** launch, show, or open a terminal for any profile, plus status for each one
  (running, not running, or running with its window closed).

Claude Profiles only creates each profile's folders and passes their paths on. It never reads
what's inside them.

Requires macOS 14 (Sonoma) or later. You build it yourself with Xcode 15 or later (see
[Build](#build)). The current version is **1.1**; see [CHANGELOG.md](CHANGELOG.md).

## Claude Code in Terminal

Each profile can also run **Claude Code** (the `claude` command-line tool) signed in to that
profile's account. Click the terminal button on a profile's row, choose **Open Terminal** from its
"…" menu, or Option-click the profile in the menu-bar dropdown. Each profile in the dropdown also
has a submenu with **Open Terminal** and **Open Terminal in Folder…**.

How it works: Claude Code keeps its login, settings, memory and history in the folder named by the
`CLAUDE_CONFIG_DIR` environment variable. Each profile gets its own folder:

    ~/Library/Application Support/ClaudeProfiles/cli/<profile id>

The new terminal window starts with `CLAUDE_CONFIG_DIR` set to that folder. On macOS, Claude Code
keeps each folder's login in its own Keychain item, named `Claude Code-credentials-<8-character hash
of the folder path>`. So the accounts stay separate. This works whether or not the profile's Claude
desktop app is running.

**First time for each profile:** the CLI login is separate from the desktop app's login. In the new
terminal, run `/login` and sign in to that profile's account. Then run `/status` to check which
account it's using. You only need to do this once per profile.

The first time you open Terminal for a profile, you're asked which folder Claude Code should start
in. After that it reuses the profile's last folder. To pick a different one, use **Open Terminal in
Folder…**.

Settings › Terminal:
- **Terminal app:** Terminal (the default), iTerm, or any other app. The app has to be able to open
  `.command` files.
- **Default working folder:** the folder the picker starts in the first time.
- **Unset ANTHROPIC_API_KEY in profile terminals** (on by default). See the API-key note below.

To launch Claude Code without AppleScript, and without macOS's Automation permission prompt, the app
writes a small temporary script and opens it with your terminal app. The script is private to you
(mode 0700). It deletes itself when it starts, and the app also clears any leftovers at launch and
at quit. The script sets the window title to "Claude · <profile>", prints the profile name and its
config folder, and runs `claude`. When Claude Code exits, press Return to start it again. If
`claude` isn't installed, the window says so and links to
https://docs.claude.com/en/docs/claude-code/overview.

### The API-key gotcha

If `ANTHROPIC_API_KEY` is set in your environment (often in `~/.zshrc`), Claude Code uses that key
instead of the account you signed in to with `/login`, and every profile ends up on the same key.
That's why the "Unset ANTHROPIC_API_KEY" setting is on by default. The same applies to
`ANTHROPIC_AUTH_TOKEN` if you've set that yourself.

The script also always unsets `CLAUDE_SECURESTORAGE_CONFIG_DIR`. If that variable is set, Claude Code
uses it instead of `CLAUDE_CONFIG_DIR` to pick the Keychain item, which would put all profiles on one
login.

### Troubleshooting: both terminals show the same account

1. In each terminal, check that the banner shows a different **Config folder**, and that this matches
   what Claude Code itself sees:
   `echo "$CLAUDE_CONFIG_DIR"`
2. Make sure nothing in your shell setup overrides the login:
   `env | grep -E '^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|CLAUDE_SECURESTORAGE_CONFIG_DIR)='`
   This should print nothing. If it lists a variable, turn on the "Unset" setting or remove it from
   `~/.zshrc`. This command only shows the variable names, never their values.
3. List the Keychain items by name. This shows names only, never secrets:
   `security dump-keychain | grep -o '"Claude Code-credentials[^"]*"' | sort -u`
   There should be one `Claude Code-credentials-xxxxxxxx` per profile you've logged in to.
4. Check your version with `claude --version`. Per-folder Keychain items were confirmed with
   2.1.296. A much older version may share one login. Update with `claude update`.
5. Still the same account? In that profile's terminal, run `/logout`, then `/login` again and choose
   the other account.

**Deleting a profile:** ticking "Also delete this profile's data folders" moves both the desktop data
folder and the Claude Code folder to the Trash. The Claude Code sign-in stays in your Keychain. To
remove it, run `/logout` in the profile's terminal before deleting the profile.

## Build

Needs macOS 14+ and Xcode 15+ (or the matching command-line tools).

```sh
scripts/build-app.sh                 # ad-hoc signed → build/Claude Profiles.app
BUNDLE_ID=com.you.ClaudeProfiles SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
```

For development you can also `open Package.swift` in Xcode and run the `ClaudeProfiles` scheme.

Run the unit tests with `swift test`. They cover the launch-script builder (quoting, injection, the
API-key setting), the temp-file permissions, loading older `profiles.json` files, and profile
deletion. They live in the `ClaudeProfilesCore` library, so they also run on Linux.
"Launch at login" (SMAppService) only works from a signed `.app` bundle, not from `swift run`.

## Rebuild and install in one step

```sh
scripts/run_all.sh            # quit app, build, make DMG, install to /Applications, open
scripts/run_all.sh --no-dmg   # same without the DMG
```

## Make a DMG

```sh
scripts/build-app.sh
scripts/make-dmg.sh                  # → build/ClaudeProfiles-1.1.dmg
```

The DMG holds the app and an Applications shortcut to drag it onto.

An ad-hoc signed DMG works on your own Mac. On other Macs, Gatekeeper blocks it until the
person right-clicks the app and chooses **Open**. To avoid that you need an Apple Developer
account ($99/year):

```sh
# one time: store notarization credentials (app-specific password from appleid.apple.com)
xcrun notarytool store-credentials claude-profiles --apple-id you@example.com --team-id TEAMID

export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
scripts/build-app.sh
NOTARY_PROFILE=claude-profiles scripts/make-dmg.sh   # signs, notarizes and staples the DMG
```

## App icon

`Resources/AppIcon.icns` is the app icon, with `Resources/AppIcon.png` (1024px) as its source.
To change it, replace both files and rebuild.

`scripts/make-icon.py` draws the older stacked-cards icon. Running it overwrites the current icon.

## How it works

| Piece | File |
|---|---|
| Scenes: main window, Settings, MenuBarExtra, ⌘N / ⌘O commands, Dock-icon policy | `ClaudeProfilesApp.swift` |
| Profiles list, persistence (`~/Library/Application Support/ClaudeProfiles/profiles.json`), launch / show, running detection | `ProfileStore.swift` |
| Finding Claude.app and checking its `Info.plist` | `ClaudeLocator.swift` |
| Opening Claude Code in a terminal (app lookup, temp script, Launch Services) | `Services/TerminalLaunchService.swift` |
| Model, `profiles.json` format, paths, launch-script builder, temp-script file, folder removal (pure Foundation, unit-tested) | `Sources/ClaudeProfilesCore/` |
| Reading a running Claude's `--user-data-dir` (`sysctl KERN_PROCARGS2`) to match it to a profile | `ProcessInspector.swift` |
| Design tokens, buttons, fields, avatar, status pill | `Theme.swift` |
| Screens | `MainView.swift`, `ProfileRow.swift`, `ProfileSheets.swift` (new / rename / delete), `MenuBarContent.swift`, `SettingsView.swift`, `ErrorBanner.swift` |

- **Running state:** refreshed on NSWorkspace launch/terminate notifications, with a 3-second poll as a backstop.
- **Show:** activates the running instance for that profile. If its window was closed (Claude keeps running in
  the background), Show sends Claude a "reopen" event, the same as clicking its Dock icon. The first time,
  macOS asks to allow Claude Profiles to control Claude; click **OK**. The status reads "Running · no window" in
  that state, and the "…" menu has **Quit Claude for This Profile**.
- **Launch failures:** shown in a banner on the main window. That covers macOS refusing to open the app and Claude exiting within 5 seconds of launch.
- **Delete:** removes the profile. If you tick "Also delete this profile's data folder", the folder goes to the Trash. You can't delete the folder while that profile is running.
- The app is not sandboxed, because it has to launch Claude with arguments and read other processes' arguments.
