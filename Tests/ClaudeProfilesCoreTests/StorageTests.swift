import ClaudeProfilesCore
import Foundation
import XCTest

final class StorageTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: profiles.json migration

    /// Exactly what version 1.0 wrote (no lastWorkingDirectory).
    private let v1JSON = """
    [
      {
        "color" : "purple",
        "createdAt" : "2026-10-20T09:15:00Z",
        "dataPath" : "/Users/me/Library/Application Support/ClaudeProfiles/data/B91E40F3-6D27-4C1A-9C1B-2F0D1E2A3B4C",
        "id" : "B91E40F3-6D27-4C1A-9C1B-2F0D1E2A3B4C",
        "name" : "Acme client"
      }
    ]
    """

    func testOldProfilesFileStillLoads() throws {
        let profiles = try ProfileArchive.decode(Data(v1JSON.utf8))
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].name, "Acme client")
        XCTAssertEqual(profiles[0].color, .purple)
        XCTAssertNil(profiles[0].lastWorkingDirectory)
    }

    func testRoundTripKeepsLastWorkingDirectory() throws {
        var profiles = try ProfileArchive.decode(Data(v1JSON.utf8))
        profiles[0].lastWorkingDirectory = "/Users/me/code/my project"
        let reloaded = try ProfileArchive.decode(ProfileArchive.encode(profiles))
        XCTAssertEqual(reloaded, profiles)
    }

    func testNilWorkingDirectoryIsOmitted() throws {
        let profiles = try ProfileArchive.decode(Data(v1JSON.utf8))
        let json = String(decoding: try ProfileArchive.encode(profiles), as: UTF8.self)
        XCTAssertFalse(json.contains("lastWorkingDirectory"))
    }

    // MARK: Temp script file

    func testTempScriptIsMode0700() throws {
        let url = try TerminalScriptFile.write("#!/bin/bash\necho hi\n", in: sandbox)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o700)
        XCTAssertEqual(url.pathExtension, "command")
        XCTAssertTrue(url.lastPathComponent.hasPrefix(TerminalScriptFile.prefix))
    }

    func testTempScriptIs0700EvenWithPermissiveUmask() throws {
        let old = umask(0)
        defer { umask(old) }
        let url = try TerminalScriptFile.write("x", in: sandbox)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o700)
    }

    func testLeftoverCleanupOnlyTouchesOurScripts() throws {
        let ours = try TerminalScriptFile.write("x", in: sandbox)
        let other = sandbox.appendingPathComponent("someone-else.command")
        let similar = sandbox.appendingPathComponent("ClaudeProfiles-notes.txt")
        try "x".write(to: other, atomically: true, encoding: .utf8)
        try "x".write(to: similar, atomically: true, encoding: .utf8)

        XCTAssertEqual(TerminalScriptFile.removeLeftovers(in: sandbox), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ours.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: similar.path))
    }

    func testLeftoverCleanupKeepsFreshScriptsWhenAsked() throws {
        let fresh = try TerminalScriptFile.write("x", in: sandbox)
        XCTAssertEqual(TerminalScriptFile.removeLeftovers(in: sandbox, minimumAge: 60), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    // MARK: CLI config folder + delete

    func testCLIConfigPathIsStable() {
        let id = UUID(uuidString: "7F3A91C2-4B1E-4C1A-9C1B-2F0D1E2A3B4C")!
        let root = URL(fileURLWithPath: "/Users/me/Library/Application Support/ClaudeProfiles/cli", isDirectory: true)
        XCTAssertEqual(
            AppPaths.cliConfigPath(for: id, root: root),
            "/Users/me/Library/Application Support/ClaudeProfiles/cli/7F3A91C2-4B1E-4C1A-9C1B-2F0D1E2A3B4C"
        )
    }

    func testEnsureCLIConfigFolderIsUserOnly() throws {
        let id = UUID()
        let url = try ProfileFolders.ensureCLIConfigFolder(for: id, root: sandbox)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.int16Value, 0o700)
    }

    func testDeleteKeepsFoldersUnlessAsked() throws {
        let (profile, dataDir, cliDir) = try makeProfileWithFolders()
        try ProfileFolders.removeFolders(for: profile, alsoDeleteData: false, cliRoot: sandbox) {
            try FileManager.default.removeItem(at: $0)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cliDir.path))
    }

    func testDeleteRemovesDataAndCLIFoldersWhenAsked() throws {
        let (profile, dataDir, cliDir) = try makeProfileWithFolders()
        var removed: [String] = []
        try ProfileFolders.removeFolders(for: profile, alsoDeleteData: true, cliRoot: sandbox) {
            removed.append($0.path)
            try FileManager.default.removeItem(at: $0)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cliDir.path))
        XCTAssertEqual(Set(removed), [dataDir.path, cliDir.path])
    }

    func testDeleteSkipsFoldersThatDontExist() throws {
        let profile = Profile(
            id: UUID(), name: "Never launched", color: .blue,
            dataPath: sandbox.appendingPathComponent("missing").path, createdAt: Date()
        )
        var calls = 0
        try ProfileFolders.removeFolders(for: profile, alsoDeleteData: true, cliRoot: sandbox) { _ in calls += 1 }
        XCTAssertEqual(calls, 0)
    }

    private func makeProfileWithFolders() throws -> (Profile, URL, URL) {
        let id = UUID()
        let dataDir = sandbox.appendingPathComponent("data/\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let cliDir = try ProfileFolders.ensureCLIConfigFolder(for: id, root: sandbox)
        let profile = Profile(id: id, name: "Work", color: .blue, dataPath: dataDir.path, createdAt: Date())
        return (profile, dataDir, cliDir)
    }
}
