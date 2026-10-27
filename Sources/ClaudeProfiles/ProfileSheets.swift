import ClaudeProfilesCore
import AppKit
import SwiftUI

// MARK: - New Profile

@MainActor
struct NewProfileSheet: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var color: ProfileColor = .blue
    @State private var parentFolder = AppPaths.defaultDataRoot
    @State private var launchAfterCreating = true
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Profile")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Each profile opens its own copy of Claude with its own login. You will sign in once, inside Claude.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            FieldLabel("Name").padding(.top, 20)
            TextField("Name", text: $name, prompt: Text("e.g. Work"))
                .labelsHidden()
                .focused($nameFocused)
                .fieldBox(focused: nameFocused)
                .onSubmit(create)

            FieldLabel("Color").padding(.top, 20)
            ColorSwatchPicker(selection: $color)

            FieldLabel("Data folder").padding(.top, 20)
            HStack(spacing: 8) {
                Text(AppPaths.abbreviated(parentFolder.path))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldBox(readOnly: true)
                    .help(parentFolder.path)
                    .accessibilityLabel("Data folder: \(parentFolder.path)")
                Button("Choose…", action: chooseFolder)
                    .buttonStyle(OutlineButtonStyle())
            }
            Text("Created automatically. Claude Profiles only creates this folder and passes its path to Claude. It never reads what is inside.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Toggle("Launch Claude right after creating", isOn: $launchAfterCreating)
                .toggleStyle(.checkbox)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 16)

            if let errorMessage {
                InlineError(message: errorMessage).padding(.top, 12)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(OutlineButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Create Profile", action: create)
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.top, 24)
        }
        .padding(32)
        .frame(width: 500)
        .background(Color.white)
        .onAppear {
            color = store.suggestedColor
            nameFocused = true
        }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        do {
            let profile = try store.createProfile(name: trimmedName, color: color, parentFolder: parentFolder)
            dismiss()
            if launchAfterCreating { store.launch(profile) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where profile data folders are created"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: parentFolder.path)
            ? parentFolder
            : parentFolder.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            parentFolder = url
        }
    }
}

@MainActor
struct ColorSwatchPicker: View {
    @Binding var selection: ProfileColor

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProfileColor.allCases) { color in
                let selected = color == selection
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 30, height: 30)
                        .padding(5)
                        .overlay(Circle().strokeBorder(selected ? Theme.textPrimary : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.leading, -5) // align the swatch, not its selection ring, with the fields
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color")
    }
}

@MainActor
struct InlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.destructive)
    }
}

// MARK: - Rename

@MainActor
struct RenameProfileSheet: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let profile: Profile

    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename Profile")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            FieldLabel("Name").padding(.top, 16)
            TextField("Name", text: $name)
                .labelsHidden()
                .focused($focused)
                .fieldBox(focused: focused)
                .onSubmit(save)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(OutlineButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: save)
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.top, 20)
        }
        .padding(28)
        .frame(width: 360)
        .background(Color.white)
        .onAppear {
            name = profile.name
            focused = true
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        store.rename(profile.id, to: trimmedName)
        dismiss()
    }
}

// MARK: - Delete

@MainActor
struct DeleteProfileSheet: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let profile: Profile

    @State private var alsoDeleteData = false
    @State private var errorMessage: String?

    var body: some View {
        let running = store.isRunning(profile)

        VStack(spacing: 0) {
            ProfileAvatar(profile: profile, size: 56, cornerRadius: 14, fontSize: 24)

            Text("Delete “\(profile.name)”?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text("This removes the profile from Claude Profiles. Its Claude desktop and Claude Code logins and settings stay in these folders unless you also delete them:")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                FolderPathLabel(caption: "Claude desktop", path: profile.dataPath)
                FolderPathLabel(caption: "Claude Code", path: AppPaths.cliConfigPath(for: profile.id))
            }
            .padding(.top, 12)

            Toggle("Also delete this profile’s data folders", isOn: $alsoDeleteData)
                .toggleStyle(.checkbox)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(running)
                .padding(.top, 14)

            if running {
                Text("This profile is running. Quit it in Claude to delete its data folders.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else if alsoDeleteData {
                Text("Both folders are moved to the Trash. The Claude Code sign-in is kept in your Keychain; run /logout in the profile’s terminal first to remove it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            if let errorMessage {
                InlineError(message: errorMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(OutlineButtonStyle(fullWidth: true))
                    .keyboardShortcut(.cancelAction)
                Button("Delete Profile", action: delete)
                    .buttonStyle(FilledButtonStyle(color: Theme.destructive, fullWidth: true))
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(width: 360)
        .background(Theme.menuBackground)
    }

    private func delete() {
        do {
            try store.delete(profile, alsoDeleteData: alsoDeleteData && !store.isRunning(profile))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct FolderPathLabel: View {
    let caption: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(AppPaths.abbreviated(path))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.idleBackground))
        .accessibilityElement(children: .combine)
    }
}
