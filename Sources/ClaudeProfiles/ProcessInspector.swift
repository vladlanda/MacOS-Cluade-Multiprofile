import ClaudeProfilesCore
import AppKit
import CoreGraphics
import CoreServices

/// Reads another process's launch arguments so we can tell which profile a Claude instance belongs to.
enum ProcessInspector {
    static let userDataDirFlag = "--user-data-dir"

    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        // Layout: argc (Int32), exec path, NUL padding, argv[0..<argc], env…
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        var start = index
        while index < size, args.count < Int(argc) {
            if buffer[index] == 0 {
                args.append(String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return args
    }

    static func userDataDir(in args: [String]) -> String? {
        for (i, arg) in args.enumerated() {
            if arg.hasPrefix(userDataDirFlag + "=") {
                return String(arg.dropFirst(userDataDirFlag.count + 1))
            }
            if arg == userDataDirFlag, i + 1 < args.count {
                return args[i + 1]
            }
        }
        return nil
    }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Sends the "reopen" Apple event (what a Dock-icon click sends). Claude answers it by opening a window.
    static func sendReopenEvent(to pid: pid_t) {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: [.noReply], timeout: 2)
    }

    /// Processes that currently have a normal window on screen.
    static func pidsWithOnScreenWindows() -> Set<pid_t> {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        var pids = Set<pid_t>()
        for window in windows {
            guard
                (window[kCGWindowLayer as String] as? Int) == 0,
                let pid = window[kCGWindowOwnerPID as String] as? Int
            else { continue }
            pids.insert(pid_t(pid))
        }
        return pids
    }
}
