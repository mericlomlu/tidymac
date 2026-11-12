import Foundation

/// Detects folders macOS will not let the app read without Full Disk Access.
/// Scanners treat an unreadable folder as empty, so the UI uses this to say results are incomplete.
public struct PermissionCheck: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    /// Privacy-protected folders the scanners look into (relative to home).
    static let probes = ["Library/Safari", "Library/Application Support/com.apple.TCC", "Library/Mail",
                         "Library/Containers/com.apple.Safari"]

    /// Probe folders that exist but cannot be listed.
    public func unreadable() -> [URL] {
        let fm = FileManager.default
        return Self.probes.map { home.appendingPathComponent($0, isDirectory: true) }.filter { dir in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return false }
            return (try? fm.contentsOfDirectory(atPath: dir.path)) == nil
        }
    }

    public var hasFullDiskAccess: Bool { unreadable().isEmpty }

    /// Opens the Full Disk Access list in System Settings. The user grants access there.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
}
