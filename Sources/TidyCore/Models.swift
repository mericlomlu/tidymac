import Foundation

public enum Risk: String, Codable, Sendable { case safe, review }

public struct Finding: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let category: String
    public let risk: Risk
    public let modified: Date?

    public init(url: URL, size: Int64, category: String, risk: Risk = .safe, modified: Date? = nil) {
        self.url = url; self.size = size; self.category = category; self.risk = risk; self.modified = modified
    }
}

public func totalBytes(_ items: [Finding]) -> Int64 { items.reduce(0) { $0 + $1.size } }

public struct FindingGroup: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let size: Int64
    public let items: [Finding]
}

/// Groups findings by category: groups sorted by total size, items sorted by size, both descending.
public func groupByCategory(_ items: [Finding]) -> [FindingGroup] {
    Dictionary(grouping: items, by: \.category)
        .map { FindingGroup(name: $0.key, size: totalBytes($0.value), items: $0.value.sorted { $0.size > $1.size }) }
        .sorted { $0.size > $1.size }
}

public func formatBytes(_ b: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}

/// Folder path for display, with the home folder shortened to `~`. Only a real prefix is shortened,
/// so `/Users/sam2/x` stays as it is when home is `/Users/sam`.
public func displayPath(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
    let path = url.path, h = home.standardizedFileURL.path
    if path == h { return "~" }
    return path.hasPrefix(h + "/") ? "~" + path.dropFirst(h.count) : path
}

/// Runs blocking file work off the calling actor. Cancelling the caller cancels the work,
/// which is expected to poll `Task.isCancelled` and return early.
func offMain<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
    let task = Task.detached(priority: .userInitiated, operation: work)
    return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
}

/// Recursive allocated size of a file or directory.
public func allocatedSize(of url: URL) -> Int64 {
    let fm = FileManager.default
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
    guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
    if v.isSymbolicLink == true { return 0 }
    if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
    var total: Int64 = 0
    guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
    for case let f as URL in e {
        if Task.isCancelled { return total }
        guard let r = try? f.resourceValues(forKeys: keys), r.isSymbolicLink != true, r.isDirectory != true else { continue }
        total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
    }
    return total
}
