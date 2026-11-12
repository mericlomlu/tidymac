import Foundation

/// Central safety gate. Every deletion goes through `isDeletable`.
public struct PathPolicy: Sendable {
    /// Home folder with symlinks resolved, so it compares equal to resolved targets.
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = Self.canonical(home)
    }

    /// One normal form for every root and every checked path.
    static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    /// The item a removal would act on: symlinks resolved in the parent folder, last component kept as is,
    /// because removing a symlink removes the link and not what it points to.
    /// Paths with `.` or `..` components are refused outright rather than interpreted.
    static func target(of url: URL) -> URL? {
        let parts = url.pathComponents
        guard url.isFileURL, parts.count > 1, !parts.contains(".."), !parts.contains(".") else { return nil }
        return canonical(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent)
    }

    static let protectedRoots: [String] = ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple", "/etc", "/dev", "/cores"]
        .map { canonical(URL(fileURLWithPath: $0)).path.lowercased() }

    /// User data stores inside the allowed roots that are never removable (relative to home, lowercased).
    static let deniedInHome = ["library/group containers/group.com.apple.notes",
                               "library/application support/addressbook",
                               "library/application support/mobilesync"]

    /// Only paths under these roots (inside home) may be removed.
    public var allowedRoots: [URL] {
        ["Library/Caches", "Library/Logs", "Library/Developer/Xcode/DerivedData",
         "Library/Developer/Xcode/Archives", "Library/Developer/Xcode/iOS DeviceSupport",
         "Library/Developer/CoreSimulator/Caches", "Library/Application Support",
         "Library/Preferences", "Library/Containers", "Library/Group Containers",
         "Library/Saved Application State", "Library/LaunchAgents", "Library/HTTPStorages",
         "Library/WebKit", "Library/Safari",
         ".npm/_cacache", ".cache", "Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures",
         ".Trash"]
            .map { home.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
    }

    /// Deny rules compare case-insensitively (the default file system is); allow rules compare exactly.
    public func isDeletable(_ url: URL, extraRoots: [URL] = []) -> Bool {
        guard home.path != "/", let target = Self.target(of: url) else { return false }
        let path = target.path
        let lower = path.lowercased()
        let homeLower = home.path.lowercased()
        if lower == homeLower { return false }
        for p in Self.protectedRoots where lower == p || lower.hasPrefix(p + "/") { return false }

        if lower.hasPrefix(homeLower + "/") {
            let rel = String(lower.dropFirst(homeLower.count + 1))
            if rel.split(separator: "/").contains(where: { $0.hasSuffix(".photoslibrary") }) { return false }
            for d in Self.deniedInHome where rel == d || rel.hasPrefix(d + "/") { return false }
        }

        for r in allowedRoots where path.hasPrefix(r.path + "/") { return true }

        // Caller-supplied roots (e.g. home for duplicates) are weaker: they must be home or inside it,
        // and never allow hidden folders (.ssh, .gnupg…) or Library.
        for r in extraRoots.map(Self.canonical) where r.path == home.path || r.path.hasPrefix(home.path + "/") {
            guard path.hasPrefix(r.path + "/") else { continue }
            let rel = path.dropFirst(r.path.count + 1).split(separator: "/")
            if rel.contains(where: { $0.hasPrefix(".") }) || rel.first?.lowercased() == "library" { return false }
            return true
        }

        // Top-level .app bundles in /Applications and ~/Applications only.
        let parent = target.deletingLastPathComponent().path
        if target.pathExtension == "app",
           parent == "/Applications" || parent == home.appendingPathComponent("Applications").path { return true }
        return false
    }
}
