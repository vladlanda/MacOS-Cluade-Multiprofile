// swift-tools-version:5.9
import PackageDescription

var targets: [Target] = [
    // Pure Foundation logic (model, script building, file helpers); unit-testable on any platform.
    .target(
        name: "ClaudeProfilesCore",
        path: "Sources/ClaudeProfilesCore"
    ),
    .testTarget(
        name: "ClaudeProfilesCoreTests",
        dependencies: ["ClaudeProfilesCore"],
        path: "Tests/ClaudeProfilesCoreTests"
    ),
]

#if os(macOS)
// The SwiftUI/AppKit app only builds on macOS; elsewhere `swift test` runs the core tests alone.
targets.append(
    .executableTarget(
        name: "ClaudeProfiles",
        dependencies: ["ClaudeProfilesCore"],
        path: "Sources/ClaudeProfiles"
    )
)
#endif

let package = Package(
    name: "ClaudeProfiles",
    platforms: [.macOS(.v14)],
    targets: targets
)
