import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Temporary `.command` files handed to the terminal app.
public enum TerminalScriptFile {
    public static let prefix = "ClaudeProfiles-"
    public static let fileExtension = "command"

    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// Creates a new file readable and executable only by the user (0700).
    /// O_EXCL refuses to follow or reuse an existing path.
    public static func write(_ contents: String, in directory: URL = defaultDirectory) throws -> URL {
        let url = directory.appendingPathComponent("\(prefix)\(UUID().uuidString).\(fileExtension)")
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o700)
        guard fd >= 0 else { throw posixError() }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            // The mode passed to open() is reduced by the umask; set it explicitly.
            guard fchmod(fd, 0o700) == 0 else { throw posixError() }
            try handle.write(contentsOf: Data(contents.utf8))
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return url
    }

    /// Removes scripts this app left behind. Files younger than `minimumAge` are kept,
    /// in case a terminal has been asked to open one but hasn't started it yet.
    @discardableResult
    public static func removeLeftovers(in directory: URL = defaultDirectory, minimumAge: TimeInterval = 0, now: Date = Date()) -> Int {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".\(fileExtension)") {
            let url = directory.appendingPathComponent(name)
            if minimumAge > 0,
               let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               now.timeIntervalSince(modified) < minimumAge {
                continue
            }
            if (try? fileManager.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    private static func posixError() -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
