import Foundation

public enum AppPaths {
    public static var supportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeProfiles", isDirectory: true)
    }

    /// Parent folder for new profiles' Claude desktop data folders.
    public static var defaultDataRoot: URL { supportRoot.appendingPathComponent("data", isDirectory: true) }

    /// Parent folder for the per-profile Claude Code (CLI) config folders.
    public static var cliRoot: URL { supportRoot.appendingPathComponent("cli", isDirectory: true) }

    public static var profilesFile: URL { supportRoot.appendingPathComponent("profiles.json") }

    /// The profile's CLAUDE_CONFIG_DIR.
    ///
    /// Claude Code names the profile's Keychain login after a hash of this exact string,
    /// so it must always be produced the same way (no trailing slash, no symlink resolution).
    public static func cliConfigURL(for id: UUID, root: URL = cliRoot) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public static func cliConfigPath(for id: UUID, root: URL = cliRoot) -> String {
        cliConfigURL(for: id, root: root).path
    }

    /// "/Users/me/x" → "~/x" for display.
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
