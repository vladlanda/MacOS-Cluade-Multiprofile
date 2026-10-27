import ClaudeProfilesCore
import AppKit
import SwiftUI

/// The MenuBarExtra dropdown (window style, 340pt wide).
@MainActor
struct MenuBarContent: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var optionDown = false
    @State private var flagsMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROFILES")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            if store.profiles.isEmpty {
                Text("No profiles yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
            } else {
                ForEach(store.profiles) { profile in
                    MenuProfileRow(profile: profile, optionDown: optionDown)
                }
            }

            MenuDivider()

            MenuActionRow(title: "New Profile…", shortcut: "⌘N") {
                closeMenuBarPanel()
                openMainWindow(openWindow, store: store, presentNewProfile: true)
            }
            .keyboardShortcut("n")

            MenuActionRow(title: "Open Claude Profiles", shortcut: "⌘O") {
                closeMenuBarPanel()
                openMainWindow(openWindow, store: store)
            }
            .keyboardShortcut("o")

            MenuActionRow(title: "Settings…", shortcut: "⌘,") {
                closeMenuBarPanel()
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",")

            MenuDivider()

            MenuActionRow(title: "Quit Claude Profiles", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 340)
        .onAppear {
            optionDown = NSEvent.modifierFlags.contains(.option)
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionDown = event.modifierFlags.contains(.option)
                return event
            }
        }
        .onDisappear {
            if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
            flagsMonitor = nil
        }
        .background(Theme.menuBackground)
    }
}

/// Option-click (or the row's submenu) opens Claude Code in a terminal instead of the desktop app.
@MainActor
private struct MenuProfileRow: View {
    @EnvironmentObject private var store: ProfileStore
    let profile: Profile
    let optionDown: Bool
    @State private var hovering = false

    var body: some View {
        let running = store.isRunning(profile)

        HStack(spacing: 0) {
            Button {
                if NSEvent.modifierFlags.contains(.option) {
                    openTerminal()
                } else {
                    closeMenuBarPanel()
                    store.launchOrShow(profile)
                }
            } label: {
                HStack(spacing: 12) {
                    ProfileAvatar(profile: profile, size: 28, cornerRadius: 7, fontSize: 13)
                    Text(profile.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hovering ? Color.white : Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    trailing(running: running)
                }
                .padding(.leading, 10)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(profile.name), \(running ? "running" : "not running")")
            .accessibilityHint(running ? "Brings this profile's Claude window to the front" : "Launches Claude with this profile")
            .accessibilityAction(named: "Open Terminal") { openTerminal() }

            Menu {
                Button(running ? "Show Claude" : "Launch Claude") {
                    closeMenuBarPanel()
                    store.launchOrShow(profile)
                }
                Button("Open Terminal") { openTerminal() }
                Button("Open Terminal in Folder…") { openTerminal(chooseFolder: true) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Color.white : Theme.textSecondary)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(profile.name)")
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.accent : .clear)
        )
        .onHover { hovering = $0 }
    }

    private func openTerminal(chooseFolder: Bool = false) {
        closeMenuBarPanel()
        store.openTerminal(profile, chooseFolder: chooseFolder)
    }

    @ViewBuilder
    private func trailing(running: Bool) -> some View {
        if store.isLaunching(profile) {
            Text("Launching…")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : Theme.textSecondary)
        } else if hovering {
            Text(optionDown ? "Open Terminal" : (running ? "Show" : "Launch"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            HStack(spacing: 6) {
                StatusDot(isRunning: running)
                Text(running ? (store.hasNoWindow(profile) ? "Running · no window" : "Running") : "Not running")
            }
            .font(.system(size: 12.5, weight: running ? .semibold : .regular))
            .foregroundStyle(running ? Theme.runningForeground : Theme.textSecondary)
        }
    }
}

@MainActor
private struct MenuActionRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(hovering ? Color.white : Theme.textPrimary)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 13))
                    .foregroundStyle(hovering ? Color.white.opacity(0.85) : Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.accent : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

@MainActor
private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

/// MenuBarExtra(.window) has no public dismiss API; close its panel directly.
@MainActor
private func closeMenuBarPanel() {
    for window in NSApp.windows where window.isVisible && String(describing: type(of: window)).contains("MenuBarExtra") {
        window.close()
    }
}
