import ClaudeProfilesCore
import AppKit
import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: ProfileStore
    @AppStorage(DefaultsKey.dockOnlyWhileWindowOpen) private var dockOnlyWhileWindowOpen = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?
    @AppStorage(DefaultsKey.terminalApp) private var terminalApp = TerminalApp.terminal.rawValue
    @AppStorage(DefaultsKey.customTerminalAppPath) private var customTerminalAppPath = ""
    @AppStorage(DefaultsKey.defaultWorkingDirectory) private var defaultWorkingDirectory = ""
    @AppStorage(DefaultsKey.unsetAPIKeyInTerminals) private var unsetAPIKey = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                claudeSection
                SectionHeader("Terminal").padding(.top, 32)
                terminalSection
                SectionHeader("General").padding(.top, 32)
                generalSection
                SectionHeader("Profile data").padding(.top, 32)
                profileDataSection
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 560, height: 490)
        .background(Color.white)
        .onAppear {
            store.locateClaude()
            refreshLoginItemStatus()
        }
    }

    // MARK: Claude app

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Claude app")
            Text("Location of Claude.app")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                Text(displayedPath)
                    .font(.system(size: 13))
                    .foregroundStyle(store.claude.isFound ? Theme.textSecondary : Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldBox(readOnly: true)
                    .accessibilityLabel("Claude.app location: \(displayedPath)")
                Button("Choose…") { store.chooseClaudeApp() }
                    .buttonStyle(OutlineButtonStyle())
            }

            claudeStatus.padding(.top, 10)
        }
    }

    private var displayedPath: String {
        switch store.claude {
        case .found(let app, _): app.url.path
        case .invalid(let path, _): path
        case .notFound: "Not found"
        }
    }

    @ViewBuilder
    private var claudeStatus: some View {
        switch store.claude {
        case .found(let app, let source):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").accessibilityHidden(true)
                Text(source == .automatic
                     ? "Detected automatically from Info.plist"
                     : "Chosen manually · verified from Info.plist")
                if let version = app.version {
                    Text("· version \(version)").fontWeight(.regular)
                }
                if source == .manual {
                    Spacer()
                    Button("Use automatic detection") { store.useAutomaticClaudeDetection() }
                        .buttonStyle(.link)
                        .tint(Theme.accent)
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.runningForeground)
        case .notFound:
            statusError("Not found. Choose Claude.app to launch profiles.")
        case .invalid(_, let reason):
            statusError("Not a valid Claude.app: \(reason)")
        }
    }

    private func statusError(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "xmark.circle").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(Theme.destructive)
    }

    // MARK: Terminal

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("“Open Terminal” starts Claude Code signed in to the profile’s own account.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HStack {
                Text("Terminal app")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityHidden(true)
                Spacer()
                Picker("Terminal app", selection: terminalSelection) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(app == .custom && !customTerminalAppPath.isEmpty ? customAppName : app.title).tag(app)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.top, 14)

            terminalAppStatus.padding(.top, 6)

            Text("Default working folder")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 16)
                .padding(.bottom, 8)
            HStack(spacing: 8) {
                Text(AppPaths.abbreviated(workingDirectoryURL.path))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldBox(readOnly: true)
                    .accessibilityLabel("Default working folder: \(workingDirectoryURL.path)")
                Button("Choose…", action: chooseWorkingDirectory)
                    .buttonStyle(OutlineButtonStyle())
            }
            Text("Used the first time a profile opens Terminal. After that, each profile remembers its last folder.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            SwitchRow(title: "Unset ANTHROPIC_API_KEY in profile terminals", isOn: $unsetAPIKey)
                .padding(.top, 16)
            Text("If ANTHROPIC_API_KEY is set (for example in ~/.zshrc), Claude Code uses that key instead of the account you signed in to with /login, so every profile would use the same key.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private var terminalSelection: Binding<TerminalApp> {
        Binding(
            get: { TerminalApp(rawValue: terminalApp) ?? .terminal },
            set: { choice in
                if choice == .custom {
                    // Picking "Other app…" always asks which app; keep the old choice if cancelled.
                    _ = store.chooseCustomTerminalApp()
                } else {
                    terminalApp = choice.rawValue
                }
            }
        )
    }

    private var customAppName: String {
        URL(fileURLWithPath: customTerminalAppPath).deletingPathExtension().lastPathComponent
    }

    @ViewBuilder
    private var terminalAppStatus: some View {
        switch TerminalLaunchService.resolveApp(.current) {
        case .success(let url):
            Text(url.path)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .failure(let error):
            statusError(error.message)
        }
    }

    private var workingDirectoryURL: URL {
        defaultWorkingDirectory.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
            : URL(fileURLWithPath: defaultWorkingDirectory, isDirectory: true)
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Default Working Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = workingDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            defaultWorkingDirectory = url.path
        }
    }

    // MARK: General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwitchRow(
                title: "Launch Claude Profiles at login",
                isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)
            )
            if let loginItemMessage {
                InlineError(message: loginItemMessage)
            }
            SwitchRow(
                title: "Show Dock icon only while the window is open",
                isOn: $dockOnlyWhileWindowOpen
            )
        }
        .padding(.top, 12)
        .onChange(of: dockOnlyWhileWindowOpen) { DockPolicy.update() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemMessage = nil
        } catch {
            loginItemMessage = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemMessage = "Allow Claude Profiles in System Settings › General › Login Items."
        }
    }

    // MARK: Profile data

    private var profileDataSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Each profile keeps its own login and settings in its own folder. Claude Profiles never opens these folders’ contents.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Button { store.revealDataRoot() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 13, weight: .medium))
                    Text("Reveal in Finder")
                }
            }
            .buttonStyle(OutlineButtonStyle())
            .padding(.top, 12)
        }
    }
}

@MainActor
private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
    }
}
