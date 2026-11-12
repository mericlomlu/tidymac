import Foundation

public struct CleanResult: Sendable {
    public var removed: [URL] = []
    public var skipped: [(URL, String)] = []
    public var bytes: Int64 = 0
    /// True when at least one action could not be written to the log file.
    public var logFailed = false

    /// Skip reasons with how many items each one applied to, most common first.
    public var skipSummary: [(reason: String, count: Int)] {
        Dictionary(grouping: skipped, by: \.1).map { (reason: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
    }

    /// One sentence for the UI: what happened, and why anything was skipped.
    public func summary(dryRun: Bool, permanent: Bool) -> String {
        let items = removed.count == 1 ? String(localized: "1 item") : String(localized: "\(removed.count) items")
        let size = formatBytes(bytes)
        var parts = [dryRun ? String(localized: "Dry run: would remove \(items), \(size). Nothing was changed.")
                     : permanent ? String(localized: "Deleted \(items), \(size).")
                     : String(localized: "Moved \(items) to the Trash, \(size).")]
        if !skipped.isEmpty {
            let reasons = skipSummary.map { "\($0.count) (\($0.reason))" }.joined(separator: ", ")
            parts.append(String(localized: "Skipped \(reasons)."))
        }
        if logFailed { parts.append(String(localized: "The log file could not be written.")) }
        return parts.joined(separator: " ")
    }
}

/// Removes findings, always through PathPolicy. Trash by default; dry-run touches nothing.
public struct Cleaner: Sendable {
    public static let blockedReason = String(localized: "blocked by safety rules")
    public static let missingReason = String(localized: "no longer there")

    public let policy: PathPolicy
    public let logURL: URL
    public let dryRun: Bool
    public let permanent: Bool
    let extraRoots: [URL]

    public init(policy: PathPolicy = PathPolicy(), dryRun: Bool = true, permanent: Bool = false,
                logURL: URL? = nil, extraRoots: [URL] = []) {
        self.policy = policy; self.dryRun = dryRun; self.permanent = permanent; self.extraRoots = extraRoots
        self.logURL = logURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TidyMac/log.jsonl")
    }

    public func clean(_ findings: [Finding]) -> CleanResult {
        var result = CleanResult()
        let fm = FileManager.default
        for f in findings {
            guard policy.isDeletable(f.url, extraRoots: extraRoots) else {
                result.skipped.append((f.url, Self.blockedReason)); continue
            }
            // attributesOfItem does not follow symlinks, so a dangling link still counts as present.
            guard (try? fm.attributesOfItem(atPath: f.url.path)) != nil else {
                result.skipped.append((f.url, Self.missingReason)); continue
            }
            if dryRun {
                result.removed.append(f.url); result.bytes += f.size
                if !log(f, "dry-run") { result.logFailed = true }
                continue
            }
            do {
                if permanent { try fm.removeItem(at: f.url) } else { try fm.trashItem(at: f.url, resultingItemURL: nil) }
                result.removed.append(f.url); result.bytes += f.size
                if !log(f, permanent ? "deleted" : "trashed") { result.logFailed = true }
            } catch {
                result.skipped.append((f.url, error.localizedDescription))
            }
        }
        return result
    }

    private func log(_ f: Finding, _ action: String) -> Bool {
        let entry: [String: Any] = ["t": Date().ISO8601Format(), "action": action,
                                    "path": f.url.path, "bytes": f.size, "category": f.category]
        let fm = FileManager.default
        do {
            let line = try JSONSerialization.data(withJSONObject: entry) + Data("\n".utf8)
            try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.fileExists(atPath: logURL.path) else { try line.write(to: logURL); return true }
            let h = try FileHandle(forWritingTo: logURL)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }
}
