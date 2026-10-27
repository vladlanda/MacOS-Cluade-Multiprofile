import ClaudeProfilesCore
import Foundation
import XCTest

final class ScriptBuilderTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScriptBuilderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: Quoting / injection

    func testHostileNamesAndPathsAreInert() throws {
        let markerA = sandbox.appendingPathComponent("pwned-dollar").path
        let markerB = sandbox.appendingPathComponent("pwned-backtick").path
        let name = "Bob's \"Work\" $HOME $(touch \(markerA)) `touch \(markerB)` 🚀 Ünïcødé עברית * ?"
        let work = try makeDir("work dir 'quoted' $USER `id` \"dq\" ünï 🚀 *")
        let config = try makeDir("cli conf $(touch \(markerA)) 'x'")

        let result = try run(TerminalScriptRequest(
            profileName: name, configDirectory: config, workingDirectory: work, unsetAPIKey: true, extraPathDirectories: []
        ))

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(result.claude["PWD"], work)
        XCTAssertEqual(result.claude["CONFIG"], config)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerA), "command substitution ran")
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerB), "backticks ran")
        // Names are capped at 100 characters for display; this one is longer.
        let shown = ScriptBuilder.displayName(name)
        XCTAssertEqual(shown, String(name.prefix(100)))
        XCTAssertTrue(result.output.contains("\u{1B}]0;Claude \u{00B7} \(shown)\u{07}"), "title")
        XCTAssertTrue(result.output.contains("Claude profile: \(shown)\n"), "banner name")
        XCTAssertTrue(result.output.contains("Config folder:  \(config)\n"), "banner config")
        XCTAssertTrue(result.output.contains("First time? Run /login. Run /status to confirm the account."))
    }

    func testShortUnicodeNameIsShownExactly() throws {
        let name = "Bob's \"Work\" $HOME `id` 🚀 Ünïcødé עברית"
        let result = try run(TerminalScriptRequest(
            profileName: name, configDirectory: try makeDir("c"), workingDirectory: try makeDir("w"),
            unsetAPIKey: true, extraPathDirectories: []
        ))
        XCTAssertTrue(result.output.contains("\u{1B}]0;Claude \u{00B7} \(name)\u{07}"), "title")
        XCTAssertTrue(result.output.contains("Claude profile: \(name)\n"), "banner name")
    }

    func testScriptIsValidBashSyntax() throws {
        let script = try ScriptBuilder.build(TerminalScriptRequest(
            profileName: "a'b", configDirectory: "/tmp/x y", workingDirectory: "/tmp", unsetAPIKey: false
        ))
        let url = try TerminalScriptFile.write(script, in: sandbox)
        let check = try shell(["/bin/bash", "-n", url.path])
        XCTAssertEqual(check.exitCode, 0, check.output)
    }

    func testShellQuote() {
        XCTAssertEqual(ScriptBuilder.shellQuote("plain"), "'plain'")
        XCTAssertEqual(ScriptBuilder.shellQuote("it's"), "'it'\\''s'")
        XCTAssertEqual(ScriptBuilder.shellQuote("$HOME `x`"), "'$HOME `x`'")
        XCTAssertEqual(ScriptBuilder.shellQuote(""), "''")
    }

    // MARK: Control characters

    func testControlCharactersInNameAreReplaced() throws {
        let script = try ScriptBuilder.build(TerminalScriptRequest(
            profileName: "Evil\u{1B}]0;pwn\u{07}\nrm -rf ~\r\u{2028}x",
            configDirectory: "/tmp/c", workingDirectory: "/tmp", unsetAPIKey: true
        ))
        XCTAssertFalse(script.contains("\u{1B}]0;pwn"))
        XCTAssertFalse(script.contains("\u{07}"))
        XCTAssertFalse(script.contains("\r"))
        XCTAssertFalse(script.contains("\u{2028}"))
        XCTAssertTrue(script.contains("PROFILE_NAME='Evil ]0;pwn  rm -rf ~  x'\n"))
        XCTAssertEqual(ScriptBuilder.displayName("\n\t"), "Profile")
    }

    func testControlCharactersInPathsAreRejected() {
        XCTAssertThrowsError(try ScriptBuilder.build(TerminalScriptRequest(
            profileName: "A", configDirectory: "/tmp/a\nb", workingDirectory: "/tmp", unsetAPIKey: true
        ))) { XCTAssertEqual($0 as? ScriptBuilderError, .controlCharacters(field: "Claude Code config folder")) }

        XCTAssertThrowsError(try ScriptBuilder.build(TerminalScriptRequest(
            profileName: "A", configDirectory: "/tmp/a", workingDirectory: "/tmp/\u{1B}x", unsetAPIKey: true
        ))) { XCTAssertEqual($0 as? ScriptBuilderError, .controlCharacters(field: "working folder")) }

        XCTAssertThrowsError(try ScriptBuilder.build(TerminalScriptRequest(
            profileName: "A", configDirectory: "relative/dir", workingDirectory: "/tmp", unsetAPIKey: true
        ))) { XCTAssertEqual($0 as? ScriptBuilderError, .notAbsolute(field: "Claude Code config folder")) }
    }

    // MARK: API key toggle

    func testUnsetAPIKeyOn() throws {
        let request = TerminalScriptRequest(
            profileName: "A", configDirectory: try makeDir("c"), workingDirectory: try makeDir("w"),
            unsetAPIKey: true, extraPathDirectories: []
        )
        XCTAssertTrue(try ScriptBuilder.build(request).contains("\nunset ANTHROPIC_API_KEY\n"))
        let result = try run(request, extraEnv: ["ANTHROPIC_API_KEY": "sk-test-not-real-123"])
        XCTAssertEqual(result.claude["APIKEY"], "unset")
        XCTAssertFalse(result.output.contains("sk-test-not-real-123"))
    }

    func testUnsetAPIKeyOff() throws {
        let request = TerminalScriptRequest(
            profileName: "A", configDirectory: try makeDir("c"), workingDirectory: try makeDir("w"),
            unsetAPIKey: false, extraPathDirectories: []
        )
        XCTAssertFalse(try ScriptBuilder.build(request).contains("unset ANTHROPIC_API_KEY"))
        let result = try run(request, extraEnv: ["ANTHROPIC_API_KEY": "sk-test-not-real-123"])
        XCTAssertEqual(result.claude["APIKEY"], "set")
        XCTAssertFalse(result.output.contains("sk-test-not-real-123"), "the key's value must never be printed")
    }

    func testSecureStorageOverrideIsAlwaysCleared() throws {
        let request = TerminalScriptRequest(
            profileName: "A", configDirectory: try makeDir("c"), workingDirectory: try makeDir("w"),
            unsetAPIKey: false, extraPathDirectories: []
        )
        let result = try run(request, extraEnv: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/shared"])
        XCTAssertEqual(result.claude["SECURE"], "unset")
    }

    // MARK: Fallbacks

    func testMissingClaudePrintsInstallLink() throws {
        let request = TerminalScriptRequest(
            profileName: "A", configDirectory: try makeDir("c"), workingDirectory: try makeDir("w"),
            unsetAPIKey: true, extraPathDirectories: []
        )
        let result = try run(request, installFakeClaude: false)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.output.contains("Claude Code (the \"claude\" command) was not found."))
        XCTAssertTrue(result.output.contains("Install it: https://docs.claude.com/en/docs/claude-code/overview"))
    }

    func testMissingWorkingDirectoryFallsBackToHome() throws {
        let missing = sandbox.appendingPathComponent("gone").path
        let request = TerminalScriptRequest(
            profileName: "A", configDirectory: try makeDir("c"), workingDirectory: missing,
            unsetAPIKey: true, extraPathDirectories: []
        )
        let result = try run(request)
        XCTAssertTrue(result.output.contains("Folder not found: \(missing)"))
        XCTAssertEqual(result.claude["PWD"], sandbox.appendingPathComponent("home").path)
    }

    func testScriptDeletesItself() throws {
        let request = TerminalScriptRequest(
            profileName: "A", configDirectory: try makeDir("c"), workingDirectory: try makeDir("w"),
            unsetAPIKey: true, extraPathDirectories: []
        )
        let result = try run(request)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.scriptPath))
    }

    // MARK: Helpers

    private struct RunResult {
        let exitCode: Int32
        let output: String
        let claude: [String: String]
        let scriptPath: String
    }

    private func makeDir(_ name: String) throws -> String {
        let url = sandbox.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    /// Runs the generated script with bash and a fake `claude` that records what it saw.
    private func run(_ request: TerminalScriptRequest, extraEnv: [String: String] = [:], installFakeClaude: Bool = true) throws -> RunResult {
        let bin = try makeDir("bin")
        let home = try makeDir("home")
        let report = sandbox.appendingPathComponent("claude-report.txt")
        try? FileManager.default.removeItem(at: report)

        if installFakeClaude {
            let fake = """
            #!/bin/bash
            {
              printf 'PWD=%s\\n' "$PWD"
              printf 'CONFIG=%s\\n' "$CLAUDE_CONFIG_DIR"
              if [ -n "${ANTHROPIC_API_KEY+x}" ]; then echo APIKEY=set; else echo APIKEY=unset; fi
              if [ -n "${CLAUDE_SECURESTORAGE_CONFIG_DIR+x}" ]; then echo SECURE=set; else echo SECURE=unset; fi
            } > "$FAKE_CLAUDE_REPORT"
            """
            let path = bin + "/claude"
            try fake.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        } else {
            try? FileManager.default.removeItem(atPath: bin + "/claude")
        }

        let script = try ScriptBuilder.build(request)
        let url = try TerminalScriptFile.write(script, in: sandbox)

        var env = ["PATH": "\(bin):/usr/bin:/bin", "HOME": home, "FAKE_CLAUDE_REPORT": report.path, "LANG": "C.UTF-8"]
        env.merge(extraEnv) { $1 }
        let result = try shell([url.path], environment: env)

        var claude: [String: String] = [:]
        if let text = try? String(contentsOf: report, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { claude[parts[0]] = parts[1] }
            }
        }
        return RunResult(exitCode: result.exitCode, output: result.output, claude: claude, scriptPath: url.path)
    }

    private func shell(_ args: [String], environment: [String: String]? = nil) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        if let environment { process.environment = environment }
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
