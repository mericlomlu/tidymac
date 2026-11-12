import Foundation

public struct JunkScanner: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    /// (relative path, category, risk). Children of each location are reported individually.
    static let locations: [(String, String, Risk)] = [
        ("Library/Caches", String(localized: "App Caches"), .safe),
        ("Library/Logs", String(localized: "Logs"), .safe),
        ("Library/Developer/Xcode/DerivedData", String(localized: "Xcode DerivedData"), .safe),
        ("Library/Developer/Xcode/Archives", String(localized: "Xcode Archives"), .review),
        ("Library/Developer/Xcode/iOS DeviceSupport", String(localized: "iOS Device Support"), .safe),
        ("Library/Developer/CoreSimulator/Caches", String(localized: "Simulator Caches"), .safe),
        (".npm/_cacache", String(localized: "npm Cache"), .safe),
        (".cache", String(localized: "User .cache"), .safe),
    ]

    public func scan() async -> [Finding] {
        await withTaskGroup(of: [Finding].self) { group in
            for (rel, cat, risk) in Self.locations {
                let dir = home.appendingPathComponent(rel, isDirectory: true)
                group.addTask { Self.children(of: dir, category: cat, risk: risk) }
            }
            var all: [Finding] = []
            for await r in group { all += r }
            return all.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        }
    }

    static func children(of dir: URL, category: String, risk: Risk) -> [Finding] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return items.map { u in
            Finding(url: u, size: allocatedSize(of: u), category: category, risk: risk,
                    modified: (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate)
        }
    }
}

public struct LargeFileScanner: Sendable {
    public let root: URL
    public let minSize: Int64
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser, minSize: Int64 = 100 * 1_000_000) {
        self.root = root; self.minSize = minSize
    }

    /// Roots a clean of these findings must pass to `Cleaner` (the weaker extra-root rule applies).
    public var extraRoots: [URL] { [root] }

    public func scan() async -> [Finding] {
        await offMain { [root, minSize] in Self.walk(root: root, minSize: minSize) }
    }

    /// Only files the policy would let the user remove are reported, so the list never offers a dead end.
    static func walk(root: URL, minSize: Int64) -> [Finding] {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsPackageDescendants, .skipsHiddenFiles],
                                                      errorHandler: { _, _ in true }) else { return [] }
        let policy = PathPolicy(home: root)
        let library = root.appendingPathComponent("Library").standardizedFileURL.path
        var out: [Finding] = []
        for case let u as URL in e {
            if Task.isCancelled { return [] }
            guard let r = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if r.isDirectory == true {
                if u.lastPathComponent == "node_modules" || u.standardizedFileURL.path == library { e.skipDescendants() }
                continue
            }
            guard r.isRegularFile == true, let sz = r.totalFileAllocatedSize, Int64(sz) >= minSize,
                  policy.isDeletable(u, extraRoots: [root]) else { continue }
            out.append(Finding(url: u, size: Int64(sz), category: String(localized: "Large File"), risk: .review, modified: r.contentModificationDate))
        }
        return out.sorted { $0.size > $1.size }
    }
}
