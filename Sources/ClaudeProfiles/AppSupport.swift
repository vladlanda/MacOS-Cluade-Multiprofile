import ClaudeProfilesCore
import SwiftUI

extension ProfileColor {
    var color: Color {
        switch self {
        case .blue: Color(hex: 0x2F5BD3)
        case .green: Color(hex: 0x1F7A5A)
        case .purple: Color(hex: 0x7A4BC2)
        case .slate: Color(hex: 0x3D4A5C)
        case .rust: Color(hex: 0xB5481F)
        case .plum: Color(hex: 0xA12B6B)
        }
    }
}

enum DefaultsKey {
    static let claudeAppPath = "claudeAppPath"
    static let dockOnlyWhileWindowOpen = "dockOnlyWhileWindowOpen"
    static let terminalApp = "terminalApp"
    static let customTerminalAppPath = "customTerminalAppPath"
    static let defaultWorkingDirectory = "defaultWorkingDirectory"
    static let unsetAPIKeyInTerminals = "unsetAPIKeyInTerminals"
}

enum SceneID {
    static let main = "main"
}
