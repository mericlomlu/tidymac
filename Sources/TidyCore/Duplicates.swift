import Foundation
import CryptoKit

public struct DuplicateGroup: Identifiable, Sendable {
    /// The keeper's URL: stable across rescans and partial cleans.
    public var id: URL { files.first?.url ?? URL(fileURLWithPath: "/") }
    public let size: Int64
    public let files: [Finding]   // sorted oldest first; first is the suggested keeper
    public var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
    public init(size: Int64, files: [Finding]) { self.size = size; self.files = files }

    /// The selected copies that may be removed. Never every copy: if all are selected, the keeper stays.
    public func removable(selected: Set<URL>) -> [Finding] {
        let picked = files.filter { selected.contains($0.url) }
        return picked.count == files.count ? Array(picked.dropFirst()) : picked
    }

    /// This group without the removed files, or nil when fewer than two copies remain.
    public func removing(_ gone: Set<URL>) -> DuplicateGroup? {
        let left = files.filter { !gone.contains($0.url) }
        return left.count > 1 ? DuplicateGroup(size: size, files: left) : nil
    }
}

public struct DuplicateScanner: Sendable {
    public let root: URL
    public let minSize: Int64
    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser, minSize: Int64 = 1_000_000) {
        self.root = root; self.minSize = minSize
    }

    /// Returns an empty list if the calling task is cancelled.
    public func scan() async -> [DuplicateGroup] {
        await offMain { [root, minSize] in Self.run(root: root, minSize: minSize) }
    }

    static func run(root: URL, minSize: Int64) -> [DuplicateGroup] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey,
                                      .fileResourceIdentifierKey]
        // Hidden items (.git, .Trash, .ssh…) are skipped: the policy would refuse to remove them anyway.
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsPackageDescendants, .skipsHiddenFiles],
                                                      errorHandler: { _, _ in true }) else { return [] }
        let library = root.appendingPathComponent("Library").standardizedFileURL.path
        var bySize: [Int64: [(URL, Date?)]] = [:]
        var seenFiles = Set<AnyHashable>()   // one entry per file on disk, so hard links are not "duplicates"
        for case let u as URL in e {
            if Task.isCancelled { return [] }
            guard let r = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            if r.isDirectory == true {
                if u.lastPathComponent == "node_modules" || u.standardizedFileURL.path == library { e.skipDescendants() }
                continue
            }
            guard r.isRegularFile == true, let s = r.fileSize, Int64(s) >= minSize else { continue }
            if let ident = r.fileResourceIdentifier as? NSObject, !seenFiles.insert(AnyHashable(ident)).inserted { continue }
            bySize[Int64(s), default: []].append((u, r.contentModificationDate))
        }
        var groups: [DuplicateGroup] = []
        for (size, files) in bySize where files.count > 1 {
            // stage 1: hash first 64KB, stage 2: full hash
            var byPartial: [String: [(URL, Date?)]] = [:]
            for f in files { if let h = hash(f.0, limit: 65_536) { byPartial[h, default: []].append(f) } }
            for (_, cand) in byPartial where cand.count > 1 {
                if Task.isCancelled { return [] }
                var byFull: [String: [(URL, Date?)]] = [:]
                for f in cand { if let h = hash(f.0, limit: nil) { byFull[h, default: []].append(f) } }
                for (_, same) in byFull where same.count > 1 {
                    let sorted = same.sorted {
                        let a = $0.1 ?? .distantFuture, b = $1.1 ?? .distantFuture
                        return a != b ? a < b : $0.0.path < $1.0.path
                    }
                    groups.append(DuplicateGroup(size: size, files: sorted.map {
                        Finding(url: $0.0, size: size, category: String(localized: "Duplicate"), risk: .review, modified: $0.1)
                    }))
                }
            }
        }
        return groups.sorted { $0.wasted != $1.wasted ? $0.wasted > $1.wasted : $0.id.path < $1.id.path }
    }

    /// SHA-256 of the first `limit` bytes (or the whole file). Nil if the file cannot be read in full:
    /// a partial read must never produce a hash, or two unreadable files could look identical.
    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        do {
            while remaining > 0 {
                if Task.isCancelled { return nil }
                guard let d = try h.read(upToCount: min(remaining, 1 << 20)), !d.isEmpty else { break }
                hasher.update(data: d); remaining -= d.count
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
