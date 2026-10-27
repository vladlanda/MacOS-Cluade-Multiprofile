import ClaudeProfilesCore
import AppKit
import SwiftUI

@main
struct ClaudeProfilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        Window("Claude Profiles", id: SceneID.main) {
            MainView()
                .environmentObject(store)
                .appTheme()
        }
        .defaultSize(width: 880, height: 580)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView()
                .environmentObject(store)
                .appTheme()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
                .appTheme()
        } label: {
            Image(systemName: "person.2")
                .accessibilityLabel("Claude Profiles")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.dockOnlyWhileWindowOpen: true,
            DefaultsKey.terminalApp: TerminalApp.terminal.rawValue,
            DefaultsKey.unsetAPIKeyInTerminals: true,
        ])
        NSApp.appearance = NSAppearance(named: .aqua)
        TerminalScriptFile.removeLeftovers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Keep scripts a terminal may still be starting; the next launch removes them.
        TerminalScriptFile.removeLeftovers(minimumAge: 10)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockPolicy.update()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keeps running in the menu bar
    }
}

/// Shows the Dock icon only while the main window is open (when that setting is on).
@MainActor
enum DockPolicy {
    private static var mainWindowOpen = false

    static func mainWindowDidOpen() {
        mainWindowOpen = true
        update()
    }

    static func mainWindowDidClose() {
        mainWindowOpen = false
        update()
    }

    static func update() {
        let onlyWhileOpen = UserDefaults.standard.bool(forKey: DefaultsKey.dockOnlyWhileWindowOpen)
        let policy: NSApplication.ActivationPolicy = (!onlyWhileOpen || mainWindowOpen) ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if policy == .regular, mainWindowOpen { NSApp.activate() }
    }
}

struct AppCommands: Commands {
    let store: ProfileStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            WindowCommandButtons(store: store)
        }
    }
}

@MainActor
private struct WindowCommandButtons: View {
    let store: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Profile…") {
            openMainWindow(openWindow, store: store, presentNewProfile: true)
        }
        .keyboardShortcut("n")

        Button("Open Claude Profiles") {
            openMainWindow(openWindow, store: store)
        }
        .keyboardShortcut("o")
    }
}

@MainActor
func openMainWindow(_ openWindow: OpenWindowAction, store: ProfileStore, presentNewProfile: Bool = false) {
    openWindow(id: SceneID.main)
    NSApp.activate()
    if presentNewProfile {
        // Let the window appear before attaching the sheet to it.
        DispatchQueue.main.async { store.isPresentingNewProfile = true }
    }
}
