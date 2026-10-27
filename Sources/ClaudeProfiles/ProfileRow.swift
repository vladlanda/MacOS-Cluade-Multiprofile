import ClaudeProfilesCore
import AppKit
import SwiftUI

@MainActor
struct ProfileRow: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: Profile
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let running = store.isRunning(profile)

        HStack(spacing: 16) {
            ProfileAvatar(profile: profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(profile.shortDataPath)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(profile.dataPath)
            }

            Spacer(minLength: 12)

            // Fixed-width columns so the buttons line up from row to row,
            // whatever the status text or button label.
            StatusPill(isRunning: running, hasNoWindow: store.hasNoWindow(profile))
                .frame(width: Self.statusColumnWidth, alignment: .trailing)

            Button { store.openTerminal(profile) } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(IconButtonStyle())
            .help("Open Claude Code in Terminal for \(profile.name)")
            .accessibilityLabel("Open Terminal for \(profile.name)")

            primaryButton(running: running)
                .frame(width: Self.primaryButtonWidth)

            Menu {
                ProfileMenuItems(profile: profile, onRename: onRename, onDelete: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions for \(profile.name)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous).fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .contextMenu {
            ProfileMenuItems(profile: profile, onRename: onRename, onDelete: onDelete)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(profile.name)
    }

    /// Fits the widest status, "Running · no window".
    private static let statusColumnWidth: CGFloat = 170
    private static let primaryButtonWidth: CGFloat = 88

    @ViewBuilder
    private func primaryButton(running: Bool) -> some View {
        if store.isLaunching(profile) {
            Button {} label: {
                ProgressView().controlSize(.small)
            }
            .buttonStyle(FilledButtonStyle(fullWidth: true))
            .disabled(true)
            .accessibilityLabel("Launching \(profile.name)")
        } else if running {
            Button("Show") { store.show(profile) }
                .buttonStyle(OutlineButtonStyle(fullWidth: true))
                .accessibilityHint("Brings \(profile.name)'s Claude window to the front")
        } else {
            Button("Launch") { store.launch(profile) }
                .buttonStyle(FilledButtonStyle(fullWidth: true))
                .accessibilityHint("Opens Claude with the \(profile.name) profile")
        }
    }
}

/// Shared by the "…" menu and the row's context menu.
@MainActor
struct ProfileMenuItems: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: Profile
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Rename…", action: onRename)

        Picker("Change color", selection: Binding(
            get: { profile.color },
            set: { store.setColor($0, for: profile.id) }
        )) {
            ForEach(ProfileColor.allCases) { color in
                Text(color.name).tag(color)
            }
        }
        .pickerStyle(.menu)

        Button("Open Terminal") { store.openTerminal(profile) }
        Button("Open Terminal in Folder…") { store.openTerminal(profile, chooseFolder: true) }

        Divider()

        Button("Reveal data folder") { store.revealDataFolder(profile) }

        if store.isRunning(profile) {
            Button("Quit Claude for This Profile") { store.quit(profile) }
        }

        Divider()

        Button("Delete…", role: .destructive, action: onDelete)
    }
}
