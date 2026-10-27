import ClaudeProfilesCore
import AppKit

struct ClaudeApp: Equatable {
    let url: URL
    let bundleIdentifier: String
    let version: String?
}

enum ClaudeLocation: Equatable {
    enum Source: Equatable { case automatic, manual }

    case found(ClaudeApp, Source)
    case notFound(searched: [String])
    case invalid(path: String, reason: String)

    var app: ClaudeApp? {
        if case .found(let app, _) = self { return app }
        return nil
    }

    var isFound: Bool { app != nil }

    /// Text for the "Show details" disclosure.
    var details: String {
        switch self {
        case .found(let app, let source):
            return "Using \(app.url.path) (\(app.bundleIdentifier) \(app.version ?? "")), \(source == .manual ? "chosen manually" : "detected automatically")."
        case .notFound(let searched):
            let list = searched.isEmpty ? "  (none)" : searched.map { "  • \($0)" }.joined(separator: "\n")
            return "Looked for a Claude.app whose Info.plist has bundle identifier "
                + ClaudeLocator.knownBundleIdentifiers.joined(separator: ", ")
                + " in:\n" + list
        case .invalid(let path, let reason):
            return "\(path)\n\(reason)"
        }
    }
}

enum ClaudeLocator {
    static let knownBundleIdentifiers = ["com.anthropic.claudefordesktop"]

    struct InspectionFailure: Error {
        let message: String
    }

    static func locate(manualPath: String?) -> ClaudeLocation {
        if let manualPath, !manualPath.isEmpty {
            switch inspect(URL(fileURLWithPath: manualPath)) {
            case .success(let app): return .found(app, .manual)
            case .failure(let failure): return .invalid(path: manualPath, reason: failure.message)
            }
        }

        var candidates: [URL] = knownBundleIdentifiers.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Claude.app"))
        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Claude.app")
        )

        var searched: [String] = []
        for url in candidates where !searched.contains(url.path) {
            searched.append(url.path)
            if case .success(let app) = inspect(url) {
                return .found(app, .automatic)
            }
        }
        return .notFound(searched: searched)
    }

    /// Validates a bundle by reading its Info.plist.
    static func inspect(_ url: URL) -> Result<ClaudeApp, InspectionFailure> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return .failure(InspectionFailure(message: "Nothing exists at this path."))
        }
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else {
            return .failure(InspectionFailure(message: "Contents/Info.plist is missing or unreadable."))
        }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? ""
        guard knownBundleIdentifiers.contains(bundleID) || name == "Claude" else {
            let identity = name.isEmpty ? (bundleID.isEmpty ? "an unknown app" : bundleID) : "“\(name)” (\(bundleID))"
            return .failure(InspectionFailure(message: "Info.plist identifies this as \(identity), not Claude."))
        }

        guard
            let executable = plist["CFBundleExecutable"] as? String,
            fileManager.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/\(executable)").path)
        else {
            return .failure(InspectionFailure(message: "The app's executable is missing from Contents/MacOS."))
        }

        return .success(ClaudeApp(
            url: url,
            bundleIdentifier: bundleID,
            version: plist["CFBundleShortVersionString"] as? String
        ))
    }
}
