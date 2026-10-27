import ClaudeProfilesCore
import AppKit

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal, iterm, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        case .custom: "Other app…"
        }
    }

    var bundleIdentifier: String? {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .custom: nil
        }
    }
}

struct TerminalLaunchError: Error, Equatable {
    enum Kind: Equatable {
        case terminalNotFound, configFolder, workingDirectoryMissing, invalidPath, scriptFailed, openFailed
    }

    let kind: Kind
    let message: String
    let details: String
}

/// Opens Claude Code for a profile in a terminal window.
///
/// No AppleScript or Apple Events (so no Automation permission prompt): it writes a temporary
/// `.command` script and asks Launch Services to open it with the chosen terminal app.
@MainActor
final class TerminalLaunchService {
    struct Settings {
        var app: TerminalApp
        var customAppPath: String?
        var unsetAPIKey: Bool
        var defaultWorkingDirectory: URL

        static var current: Settings {
            let defaults = UserDefaults.standard
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dir = defaults.string(forKey: DefaultsKey.defaultWorkingDirectory).map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            return Settings(
                app: TerminalApp(rawValue: defaults.string(forKey: DefaultsKey.terminalApp) ?? "") ?? .terminal,
                customAppPath: defaults.string(forKey: DefaultsKey.customTerminalAppPath),
                unsetAPIKey: defaults.bool(forKey: DefaultsKey.unsetAPIKeyInTerminals),
                defaultWorkingDirectory: dir ?? home
            )
        }
    }

    /// Where the chosen terminal app is installed.
    static func resolveApp(_ settings: Settings) -> Result<URL, TerminalLaunchError> {
        if let bundleID = settings.app.bundleIdentifier {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return .success(url)
            }
            return .failure(TerminalLaunchError(
                kind: .terminalNotFound,
                message: "\(settings.app.title) isn't installed. Choose another terminal app in Settings.",
                details: "No app with bundle identifier \(bundleID) is registered with Launch Services."
            ))
        }
        guard let path = settings.customAppPath, !path.isEmpty else {
            return .failure(TerminalLaunchError(
                kind: .terminalNotFound,
                message: "No terminal app is chosen. Choose one in Settings.",
                details: "Settings › Terminal › Terminal app is set to “Other app…” without an app."
            ))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(TerminalLaunchError(
                kind: .terminalNotFound,
                message: "The chosen terminal app is no longer there.",
                details: path
            ))
        }
        return .success(URL(fileURLWithPath: path, isDirectory: true))
    }

    func open(profile: Profile, in workingDirectory: URL, settings: Settings = .current) async -> TerminalLaunchError? {
        let appURL: URL
        switch Self.resolveApp(settings) {
        case .success(let url): appURL = url
        case .failure(let error): return error
        }

        // 1. The profile's CLAUDE_CONFIG_DIR. Only created, never read.
        let configPath = AppPaths.cliConfigPath(for: profile.id)
        do {
            try ProfileFolders.ensureCLIConfigFolder(for: profile.id)
        } catch {
            return TerminalLaunchError(
                kind: .configFolder,
                message: "Its Claude Code folder couldn't be created.",
                details: "\(configPath)\n\(error.localizedDescription)"
            )
        }

        // 2. The folder the session starts in.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return TerminalLaunchError(
                kind: .workingDirectoryMissing,
                message: "The folder it starts in no longer exists.",
                details: workingDirectory.path
            )
        }

        // 3. The script.
        let script: String
        do {
            script = try ScriptBuilder.build(TerminalScriptRequest(
                profileName: profile.name,
                configDirectory: configPath,
                workingDirectory: workingDirectory.path,
                unsetAPIKey: settings.unsetAPIKey
            ))
        } catch {
            return TerminalLaunchError(
                kind: .invalidPath,
                message: error.localizedDescription,
                details: "Choose a folder whose name has no line breaks or other control characters."
            )
        }

        let scriptURL: URL
        do {
            scriptURL = try TerminalScriptFile.write(script)
        } catch {
            return TerminalLaunchError(
                kind: .scriptFailed,
                message: "The launch script couldn't be written.",
                details: "\(NSTemporaryDirectory())\n\(error.localizedDescription)"
            )
        }

        // 4. Hand it to the terminal app.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open([scriptURL], withApplicationAt: appURL, configuration: configuration)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            let nsError = error as NSError
            return TerminalLaunchError(
                kind: .openFailed,
                message: "\(appURL.deletingPathExtension().lastPathComponent) couldn't open the launch script.",
                details: "\(appURL.path)\n\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
            )
        }
    }
}
