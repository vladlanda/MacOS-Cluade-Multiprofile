import ClaudeProfilesCore
import AppKit
import SwiftUI

@MainActor
struct MainView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var renaming: Profile?
    @State private var deleting: Profile?

    var body: some View {
        VStack(spacing: 0) {
            header
            banners
            if store.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
            footer
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color.white)
        .sheet(isPresented: $store.isPresentingNewProfile) {
            NewProfileSheet().environmentObject(store).appTheme()
        }
        .sheet(item: $renaming) { profile in
            RenameProfileSheet(profile: profile).environmentObject(store).appTheme()
        }
        .sheet(item: $deleting) { profile in
            DeleteProfileSheet(profile: profile).environmentObject(store).appTheme()
        }
        .onAppear { DockPolicy.mainWindowDidOpen() }
        .onDisappear { DockPolicy.mainWindowDidClose() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                store.isPresentingNewProfile = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    Text("New Profile")
                }
            }
            .buttonStyle(FilledButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var summary: String {
        let count = store.profiles.count
        return "\(count) profile\(count == 1 ? "" : "s") · \(store.runningCount) running"
    }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        let claudeMissing = !store.claude.isFound
        if claudeMissing || store.launchFailure != nil || store.terminalFailure != nil || store.storageError != nil {
            VStack(spacing: 10) {
                if claudeMissing {
                    ErrorBanner(
                        title: missingTitle,
                        message: "Profiles can't launch until Claude Profiles knows where Claude.app is.",
                        details: store.claude.details,
                        action: BannerAction(title: "Choose Claude.app…") { store.chooseClaudeApp() }
                    )
                }
                if let failure = store.launchFailure {
                    ErrorBanner(
                        title: "Couldn't launch “\(failure.profileName)”",
                        message: failure.message,
                        details: failure.details,
                        action: BannerAction(title: "Choose Claude.app…") { store.chooseClaudeApp() },
                        onDismiss: { store.launchFailure = nil }
                    )
                }
                if let failure = store.terminalFailure {
                    ErrorBanner(
                        title: "Couldn't open Terminal for “\(failure.profileName)”",
                        message: failure.error.message,
                        details: failure.error.details,
                        action: terminalAction(for: failure),
                        onDismiss: { store.terminalFailure = nil }
                    )
                }
                if let storageError = store.storageError {
                    ErrorBanner(
                        title: "Profile list couldn't be saved or loaded",
                        message: "Changes may not be kept after you quit.",
                        details: "\(AppPaths.profilesFile.path)\n\(storageError)",
                        onDismiss: { store.storageError = nil }
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
        }
    }

    private func terminalAction(for failure: TerminalFailure) -> BannerAction? {
        switch failure.error.kind {
        case .terminalNotFound:
            return BannerAction(title: "Choose Terminal App…") { _ = store.chooseCustomTerminalApp() }
        case .workingDirectoryMissing, .invalidPath:
            guard let profile = store.profiles.first(where: { $0.id == failure.profileID }) else { return nil }
            return BannerAction(title: "Choose Folder…") { store.openTerminal(profile, chooseFolder: true) }
        case .configFolder, .scriptFailed, .openFailed:
            return nil
        }
    }

    private var missingTitle: String {
        if case .invalid = store.claude { return "The chosen Claude.app isn't valid" }
        return "Claude.app can't be found"
    }

    // MARK: List

    private var profileList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        onRename: { renaming = profile },
                        onDelete: { deleting = profile }
                    )
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text("No profiles yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Create a profile to run a separate copy of Claude with its own login.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Button("New Profile") { store.isPresentingNewProfile = true }
                .buttonStyle(FilledButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            ClaudeStatusLabel(location: store.claude)
            Spacer()
            SettingsLink {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
                    Text("Settings")
                }
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .padding(.horizontal, 32)
        .frame(height: 56)
        .background(Theme.footerBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

@MainActor
struct ClaudeStatusLabel: View {
    let location: ClaudeLocation

    var body: some View {
        HStack(spacing: 8) {
            if let app = location.app {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Theme.runningForeground)
                Text("Claude.app found at \(app.url.path)")
            } else {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(Theme.destructive)
                Text("Claude.app not found")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.textMuted)
        .lineLimit(1)
        .truncationMode(.middle)
        .accessibilityElement(children: .combine)
    }
}
