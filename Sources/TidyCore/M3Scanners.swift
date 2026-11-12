import Foundation

// MARK: Uninstaller

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let size: Int64
}

public struct AppUninstaller: Sendable {
    public let home: URL
    public let appDirs: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                appDirs: [URL]? = nil) {
        self.home = home
        self.appDirs = appDirs ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    static let leftoverDirs = ["Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Containers",
                               "Library/Group Containers", "Library/Saved Application State", "Library/LaunchAgents",
                               "Library/HTTPStorages", "Library/WebKit", "Library/Logs"]

    /// Third-party apps only: Apple (com.apple.*) bundles are never listed.
    public func listApps() async -> [InstalledApp] {
        await offMain { [appDirs] in
            let fm = FileManager.default
            var apps: [InstalledApp] = []
            for dir in appDirs {
                guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for u in items where u.pathExtension == "app" {
                    if Task.isCancelled { return [] }
                    guard let info = NSDictionary(contentsOfFile: u.appendingPathComponent("Contents/Info.plist").path),
                          let id = info["CFBundleIdentifier"] as? String, !id.hasPrefix("com.apple.") else { continue }
                    let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
                        ?? u.deletingPathExtension().lastPathComponent
                    apps.append(InstalledApp(url: u, name: name, bundleID: id, size: allocatedSize(of: u)))
                }
            }
            return apps.sorted { $0.size > $1.size }
        }
    }

    /// Folders that hold an app's own documents and data, not just settings and caches.
    /// Matches here are always `.review`, so they are never pre-selected.
    static let dataDirs: Set<String> = ["Library/Containers", "Library/Group Containers"]

    /// Leftover files for an app. Exact bundle-id matches are `.safe`, except in `dataDirs`; looser matches are `.review`.
    public func leftovers(for app: InstalledApp) -> [Finding] {
        let fm = FileManager.default
        let id = app.bundleID
        var out: [Finding] = []
        for rel in Self.leftoverDirs {
            let dir = home.appendingPathComponent(rel, isDirectory: true)
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in items {
                let n = u.lastPathComponent
                let exact = n == id || n == id + ".plist" || n == id + ".savedState" || n == "group." + id
                let loose = n.hasPrefix(id + ".") || n.hasSuffix("." + id)
                let byName = rel == "Library/Application Support" && n == app.name
                guard exact || loose || byName else { continue }
                let folder = (rel as NSString).lastPathComponent
                out.append(Finding(url: u, size: allocatedSize(of: u), category: String(localized: "Leftover · \(folder)"),
                                   risk: exact && !Self.dataDirs.contains(rel) ? .safe : .review))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// The app bundle itself as a Finding, followed by leftovers.
    public func removalPlan(for app: InstalledApp) async -> [Finding] {
        await offMain {
            [Finding(url: app.url, size: app.size, category: String(localized: "Application"), risk: .safe)] + leftovers(for: app)
        }
    }
}

// MARK: Login items / launch agents

public struct LaunchItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let label: String
    public let program: String
    public let runAtLoad: Bool
    public let scope: String        // "User" or "System"
    public var removable: Bool { scope == "User" }
}

public struct LoginItemScanner: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public func scan() -> [LaunchItem] {
        let dirs: [(URL, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), "User"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "System"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System"),
        ]
        var out: [LaunchItem] = []
        for (dir, scope) in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in items where u.pathExtension == "plist" {
                guard let d = NSDictionary(contentsOfFile: u.path) else { continue }
                let program = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first ?? "?"
                out.append(LaunchItem(url: u, label: (d["Label"] as? String) ?? u.deletingPathExtension().lastPathComponent,
                                      program: program, runAtLoad: (d["RunAtLoad"] as? Bool) ?? false, scope: scope))
            }
        }
        return out.sorted { $0.label.lowercased() < $1.label.lowercased() }
    }
}

// MARK: Privacy

public enum Browser: String, CaseIterable, Sendable {
    case safari = "Safari", chrome = "Chrome", firefox = "Firefox"
    public var bundleID: String {
        switch self { case .safari: "com.apple.Safari"; case .chrome: "com.google.Chrome"; case .firefox: "org.mozilla.firefox" }
    }
}

public struct PrivacyScanner: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public func scan() async -> [Finding] {
        await offMain { [home] in Self.run(home: home) }
    }

    static func run(home: URL) -> [Finding] {
        let fm = FileManager.default
        var out: [Finding] = []
        let cache = String(localized: "Cache"), history = String(localized: "History"), cookies = String(localized: "Cookies")
        func add(_ rel: String, _ browser: Browser, _ kind: String, _ risk: Risk) {
            let u = home.appendingPathComponent(rel)
            guard fm.fileExists(atPath: u.path) else { return }
            out.append(Finding(url: u, size: allocatedSize(of: u), category: "\(browser.rawValue) · \(kind)", risk: risk))
        }
        add("Library/Caches/com.apple.Safari", .safari, cache, .safe)
        for name in ["History.db", "History.db-wal", "History.db-shm"] {   // the database and its journal go together
            add("Library/Safari/\(name)", .safari, history, .review)
        }
        add("Library/Safari/LastSession.plist", .safari, String(localized: "Last session"), .review)
        add("Library/Caches/Google/Chrome", .chrome, cache, .safe)
        let chromeBase = "Library/Application Support/Google/Chrome"
        if let profiles = try? fm.contentsOfDirectory(atPath: home.appendingPathComponent(chromeBase).path) {
            for p in profiles where p == "Default" || p.hasPrefix("Profile ") {
                add("\(chromeBase)/\(p)/History", .chrome, "\(history) (\(p))", .review)
                add("\(chromeBase)/\(p)/Cookies", .chrome, "\(cookies) (\(p))", .review)             // before Chrome 96
                add("\(chromeBase)/\(p)/Network/Cookies", .chrome, "\(cookies) (\(p))", .review)
            }
        }
        add("Library/Caches/Firefox", .firefox, cache, .safe)
        let ffBase = "Library/Application Support/Firefox/Profiles"
        if let profiles = try? fm.contentsOfDirectory(atPath: home.appendingPathComponent(ffBase).path) {
            for p in profiles {
                // places.sqlite is not offered: it holds bookmarks as well as history.
                add("\(ffBase)/\(p)/cookies.sqlite", .firefox, cookies, .review)
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// Browser a finding belongs to, derived from its category prefix.
    public static func browser(of f: Finding) -> Browser? {
        Browser.allCases.first { f.category.hasPrefix($0.rawValue) }
    }
}
