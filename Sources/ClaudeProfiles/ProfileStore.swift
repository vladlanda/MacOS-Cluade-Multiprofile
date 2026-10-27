import ClaudeProfilesCore
import AppKit
import UniformTypeIdentifiers

struct LaunchFailure: Equatable {
    let profileName: String
    let message: String
    let details: String
}

struct TerminalFailure: Equatable {
    let profileID: UUID
    let profileName: String
    let error: TerminalLaunchError
}

enum ProfileError: LocalizedError {
    case emptyName
    case runningCantDeleteData

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name for the profile."
        case .runningCantDeleteData: "Quit this profile's Claude window before deleting its data folders."
        }
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var runningPIDs: [UUID: pid_t] = [:]
    /// Running profiles whose Claude has no window on screen (window closed, hidden or minimized).
    @Published private(set) var windowless: Set<UUID> = []
    @Published private(set) var launching: Set<UUID> = []
    @Published private(set) var claude: ClaudeLocation = .notFound(searched: [])
    @Published var launchFailure: LaunchFailure?
    @Published var terminalFailure: TerminalFailure?
    @Published var storageError: String?
    @Published var isPresentingNewProfile = false

    private let fileManager = FileManager.default
    private let terminalService = TerminalLaunchService()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        load()
        locateClaude()
        startMonitoring()
    }

    // MARK: - Queries

    var runningCount: Int { profiles.filter { runningPIDs[$0.id] != nil }.count }

    func isRunning(_ profile: Profile) -> Bool { runningPIDs[profile.id] != nil }

    func hasNoWindow(_ profile: Profile) -> Bool { windowless.contains(profile.id) }

    func isLaunching(_ profile: Profile) -> Bool { launching.contains(profile.id) }

    var suggestedColor: ProfileColor {
        let used = Set(profiles.map(\.color))
        return ProfileColor.allCases.first { !used.contains($0) }
            ?? ProfileColor.allCases[profiles.count % ProfileColor.allCases.count]
    }

    // MARK: - Profiles

    @discardableResult
    func createProfile(name: String, color: ProfileColor, parentFolder: URL) throws -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileError.emptyName }

        let id = UUID()
        let folder = parentFolder.appendingPathComponent(id.uuidString, isDirectory: true)
        // The only thing this app ever does with the folder: create it.
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let profile = Profile(id: id, name: trimmed, color: color, dataPath: folder.path, createdAt: Date())
        profiles.append(profile)
        save()
        return profile
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        save()
    }

    func setColor(_ color: ProfileColor, for id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].color = color
        save()
    }

    func revealDataFolder(_ profile: Profile) {
        try? fileManager.createDirectory(at: profile.dataURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([profile.dataURL])
    }

    func revealDataRoot() {
        try? fileManager.createDirectory(at: AppPaths.defaultDataRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppPaths.defaultDataRoot)
    }

    /// Removes the profile. Its desktop data folder and Claude Code folder are moved to the Trash
    /// only when asked.
    func delete(_ profile: Profile, alsoDeleteData: Bool) throws {
        if alsoDeleteData, isRunning(profile) { throw ProfileError.runningCantDeleteData }
        try ProfileFolders.removeFolders(for: profile, alsoDeleteData: alsoDeleteData) { url in
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
        profiles.removeAll { $0.id == profile.id }
        runningPIDs[profile.id] = nil
        if launchFailure?.profileName == profile.name { launchFailure = nil }
        if terminalFailure?.profileID == profile.id { terminalFailure = nil }
        save()
    }

    // MARK: - Terminal (Claude Code)

    /// Opens Claude Code for the profile in a new terminal window. Asks for the folder the first
    /// time (and whenever `chooseFolder` is set); afterwards reuses the profile's last folder.
    func openTerminal(_ profile: Profile, chooseFolder: Bool = false) {
        let settings = TerminalLaunchService.Settings.current
        let directory: URL
        if chooseFolder || profile.lastWorkingDirectory == nil {
            guard let picked = pickWorkingDirectory(for: profile, settings: settings) else { return }
            directory = picked
        } else {
            directory = URL(fileURLWithPath: profile.lastWorkingDirectory!, isDirectory: true)
        }

        terminalFailure = nil
        Task {
            if let error = await terminalService.open(profile: profile, in: directory, settings: settings) {
                terminalFailure = TerminalFailure(profileID: profile.id, profileName: profile.name, error: error)
            } else {
                setLastWorkingDirectory(directory.path, for: profile.id)
            }
        }
    }

    private func pickWorkingDirectory(for profile: Profile, settings: TerminalLaunchService.Settings) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Terminal for “\(profile.name)”"
        panel.message = "Choose the folder Claude Code starts in for “\(profile.name)”."
        panel.prompt = "Open Terminal"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let last = profile.lastWorkingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let last, fileManager.fileExists(atPath: last.path) {
            panel.directoryURL = last
        } else {
            panel.directoryURL = settings.defaultWorkingDirectory
        }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func setLastWorkingDirectory(_ path: String, for id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              profiles[index].lastWorkingDirectory != path else { return }
        profiles[index].lastWorkingDirectory = path
        save()
    }

    /// Lets the user pick any terminal app; used from Settings and the "not found" banner.
    func chooseCustomTerminalApp() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose a Terminal App"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        UserDefaults.standard.set(url.path, forKey: DefaultsKey.customTerminalAppPath)
        UserDefaults.standard.set(TerminalApp.custom.rawValue, forKey: DefaultsKey.terminalApp)
        if terminalFailure?.error.kind == .terminalNotFound { terminalFailure = nil }
        return true
    }

    // MARK: - Launching

    func launchOrShow(_ profile: Profile) {
        isRunning(profile) ? show(profile) : launch(profile)
    }

    func launch(_ profile: Profile) {
        guard !launching.contains(profile.id) else { return }
        guard let app = claude.app else {
            // The "can't be found" banner is already on screen.
            NSSound.beep()
            return
        }

        do {
            try fileManager.createDirectory(at: profile.dataURL, withIntermediateDirectories: true)
        } catch {
            launchFailure = LaunchFailure(
                profileName: profile.name,
                message: "Its data folder couldn't be created.",
                details: "\(profile.dataPath)\n\(Self.describe(error))"
            )
            return
        }

        let argument = "\(ProcessInspector.userDataDirFlag)=\(profile.dataPath)"
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = [argument]

        let id = profile.id
        let name = profile.name
        let command = "open -n -a \"\(app.url.path)\" --args \(argument)"
        launching.insert(id)
        launchFailure = nil

        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { running, error in
            let pid = running?.processIdentifier
            let errorDetails = error.map { Self.describe($0) }
            Task { @MainActor in
                self.finishLaunch(id: id, name: name, pid: pid, errorDetails: errorDetails, command: command)
            }
        }
    }

    func show(_ profile: Profile) {
        guard
            let pid = runningPIDs[profile.id],
            let app = NSRunningApplication(processIdentifier: pid),
            !app.isTerminated
        else {
            refreshRunning()
            return
        }
        app.unhide()
        app.activate(options: [.activateAllWindows])
        // Closing Claude's last window leaves it running with nothing to bring forward.
        // A "reopen" event is what a Dock-icon click sends; Claude answers it by opening its window again.
        ProcessInspector.sendReopenEvent(to: pid)
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshRunning()
        }
    }

    /// Quits the Claude instance belonging to this profile.
    func quit(_ profile: Profile) {
        guard let pid = runningPIDs[profile.id], let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refreshRunning()
        }
    }

    private func finishLaunch(id: UUID, name: String, pid: pid_t?, errorDetails: String?, command: String) {
        launching.remove(id)
        if let errorDetails {
            launchFailure = LaunchFailure(
                profileName: name,
                message: "macOS couldn't open Claude.app.",
                details: "\(errorDetails)\n\nCommand:\n\(command)"
            )
            return
        }
        if let pid { runningPIDs[id] = pid }

        // Catch instances that start and immediately quit.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.verifyLaunch(id: id, name: name, pid: pid, command: command)
        }
    }

    private func verifyLaunch(id: UUID, name: String, pid: pid_t?, command: String) {
        refreshRunning()
        guard profiles.contains(where: { $0.id == id }), runningPIDs[id] == nil else { return }
        launchFailure = LaunchFailure(
            profileName: name,
            message: "Claude quit right after it started.",
            details: "Process \(pid.map(String.init) ?? "?") exited within 5 seconds.\n"
                + "Claude may not support separate data folders in this version, or it crashed on start.\n\n"
                + "Command:\n\(command)"
        )
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        if let reason = nsError.localizedFailureReason { text += "\n\(reason)" }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += "\nUnderlying: \(underlying.localizedDescription) (\(underlying.domain) \(underlying.code))"
        }
        return text
    }

    // MARK: - Claude.app

    func locateClaude() {
        claude = ClaudeLocator.locate(manualPath: UserDefaults.standard.string(forKey: DefaultsKey.claudeAppPath))
        refreshRunning()
    }

    func chooseClaudeApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Claude.app"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        UserDefaults.standard.set(url.path, forKey: DefaultsKey.claudeAppPath)
        locateClaude()
        if claude.isFound { launchFailure = nil }
    }

    func useAutomaticClaudeDetection() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.claudeAppPath)
        locateClaude()
    }

    // MARK: - Running state

    func refreshRunning() {
        guard let bundleID = claude.app?.bundleIdentifier else {
            if !runningPIDs.isEmpty { runningPIDs = [:] }
            return
        }

        var pidsByDataDir: [String: pid_t] = [:]
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isTerminated {
            let pid = app.processIdentifier
            guard
                let args = ProcessInspector.arguments(of: pid),
                let dir = ProcessInspector.userDataDir(in: args)
            else { continue }
            pidsByDataDir[ProcessInspector.normalize(dir)] = pid
        }

        var result: [UUID: pid_t] = [:]
        for profile in profiles {
            if let pid = pidsByDataDir[ProcessInspector.normalize(profile.dataPath)] {
                result[profile.id] = pid
            }
        }
        if result != runningPIDs { runningPIDs = result }

        let pidsWithWindows = ProcessInspector.pidsWithOnScreenWindows()
        let noWindow = Set(result.filter { !pidsWithWindows.contains($0.value) }.keys)
        if noWindow != windowless { windowless = noWindow }
    }

    private func startMonitoring() {
        refreshRunning()

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in self.refreshRunning() }
            })
        }
        // Launch notifications can arrive before the arguments are readable; poll as a backstop.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in self.refreshRunning() }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.profilesFile) else { return }
        do {
            profiles = try ProfileArchive.decode(data)
        } catch {
            storageError = "profiles.json couldn't be read: \(Self.describe(error))"
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: AppPaths.supportRoot, withIntermediateDirectories: true)
            try ProfileArchive.encode(profiles).write(to: AppPaths.profilesFile, options: .atomic)
            storageError = nil
        } catch {
            storageError = "profiles.json couldn't be saved: \(Self.describe(error))"
        }
    }
}
