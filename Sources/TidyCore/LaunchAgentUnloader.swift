import Foundation

/// Stops a user launch agent that is still running after its plist was removed.
/// Only the current user's own session (`gui/<uid>`) is ever addressed; system services are out of reach by design.
public struct LaunchAgentUnloader: Sendable {
    public enum Outcome: Sendable, Equatable {
        case stopped
        /// launchd had no such service loaded, so there was nothing to stop.
        case notRunning
        case failed(Int32)
    }

    public typealias Runner = @Sendable (_ executable: String, _ arguments: [String]) -> Int32

    let uid: UInt32
    let run: Runner

    public init(uid: UInt32 = getuid(), run: @escaping Runner = LaunchAgentUnloader.launch) {
        self.uid = uid; self.run = run
    }

    /// Labels are reverse-DNS names. Anything else is refused rather than passed to a command line.
    static func isValid(label: String) -> Bool {
        !label.isEmpty && label.count <= 255 && !label.hasPrefix("-")
            && label.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }
    }

    static func arguments(label: String, uid: UInt32) -> [String] { ["bootout", "gui/\(uid)/\(label)"] }

    public func unload(label: String) -> Outcome {
        guard Self.isValid(label: label) else { return .failed(-1) }
        switch run("/bin/launchctl", Self.arguments(label: label, uid: uid)) {
        case 0: return .stopped
        case 3, 113: return .notRunning      // ESRCH / "Could not find service"
        case let code: return .failed(code)
        }
    }

    /// Runs the command and returns its exit status (-1 if it could not be started).
    public static let launch: Runner = { executable, arguments in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
