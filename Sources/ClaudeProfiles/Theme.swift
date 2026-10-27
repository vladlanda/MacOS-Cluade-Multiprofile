import ClaudeProfilesCore
import SwiftUI

/// Design tokens from the UI spec / mockups.
enum Theme {
    static let accent = Color(hex: 0xB5481F)
    static let destructive = Color(hex: 0xB3261E)

    static let textPrimary = Color(hex: 0x1D1D1F)
    static let textSecondary = Color(hex: 0x5F5F66)
    static let textMuted = Color(hex: 0x55555B)

    static let border = Color(hex: 0xE3E1DC)
    static let controlBorder = Color(hex: 0xCFCBC3)
    static let controlPressed = Color(hex: 0xF0EEEA)
    static let fieldBackground = Color(hex: 0xF7F6F3)
    static let footerBackground = Color(hex: 0xFAF9F7)
    static let menuBackground = Color(hex: 0xFBFAF8)

    static let runningForeground = Color(hex: 0x1B6B34)
    static let runningBackground = Color(hex: 0xE3F3E8)
    static let idleBackground = Color(hex: 0xF0EEEA)

    static let errorBackground = Color(hex: 0xFCEDEB)
    static let errorBorder = Color(hex: 0xF2C8C3)

    static let controlRadius: CGFloat = 8
    static let controlHeight: CGFloat = 40
    static let rowRadius: CGFloat = 12
    static let rowHeight: CGFloat = 76
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Light mode + accent tint on every scene root.
    func appTheme() -> some View {
        tint(Theme.accent)
            .environment(\.colorScheme, .light)
    }
}

// MARK: - Buttons

/// Solid primary button (accent by default, destructive for Delete).
struct FilledButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var fullWidth = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        StyledLabel(configuration: configuration, color: color, fullWidth: fullWidth)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: 72, maxWidth: fullWidth ? .infinity : nil)
                .frame(height: Theme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(color)
                        .brightness(configuration.isPressed ? -0.08 : 0)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

/// White button with a 1px border (Show, Cancel, Choose…, Settings).
struct OutlineButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        StyledLabel(configuration: configuration, fullWidth: fullWidth)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: 72, maxWidth: fullWidth ? .infinity : nil)
                .frame(height: Theme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(configuration.isPressed ? Theme.controlPressed : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.controlBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

/// Square 40×40 outline button for a single glyph (the row's Terminal button).
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Theme.controlHeight, height: Theme.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(configuration.isPressed ? Theme.controlPressed : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.controlBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

// MARK: - Fields

extension View {
    /// 40px rounded field chrome. Read-only fields get the tinted fill.
    func fieldBox(focused: Bool = false, readOnly: Bool = false) -> some View {
        textFieldStyle(.plain)
            .focusEffectDisabled()
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: Theme.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(readOnly ? Theme.fieldBackground : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.controlBorder, lineWidth: focused ? 1.5 : 1)
            )
    }
}

@MainActor
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.bottom, 6)
    }
}

// MARK: - Profile visuals

@MainActor
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 12
    var fontSize: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(profile.color.color)
            .frame(width: size, height: size)
            .overlay(
                Text(profile.initial)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Filled dot = running, hollow dot = not running. Always paired with text.
@MainActor
struct StatusDot: View {
    let isRunning: Bool
    var color: Color = Theme.runningForeground

    var body: some View {
        Group {
            if isRunning {
                Circle().fill(color)
            } else {
                Circle().strokeBorder(Theme.textMuted, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
    }
}

/// Pill used in the main window rows.
@MainActor
struct StatusPill: View {
    let isRunning: Bool
    /// Claude is running but its window was closed.
    var hasNoWindow = false

    private var label: String {
        guard isRunning else { return "Not running" }
        return hasNoWindow ? "Running · no window" : "Running"
    }

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(isRunning: isRunning)
            Text(label)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(isRunning ? Theme.runningForeground : Theme.textMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(isRunning ? Theme.runningBackground : Theme.idleBackground))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(label.lowercased())")
    }
}
