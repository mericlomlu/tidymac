import XCTest
@testable import TidyCore

/// Deletion-gate and data-loss tests. Everything runs in a temp "home"; the real home is never touched.
final class SafetyTests: XCTestCase {
    private var tmp = URL(fileURLWithPath: "/nonexistent")
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("tidy-safety-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
    }
    override func tearDown() {
        // Some tests remove read permission; restore it so the tree can be deleted.
        if let e = fm.enumerator(at: tmp, includingPropertiesForKeys: nil) {
            for case let u as URL in e { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path) }
        }
        try? fm.removeItem(at: tmp)
    }

    private func at(_ rel: String) -> URL { tmp.appendingPathComponent(rel) }
    @discardableResult private func file(_ rel: String, bytes: Int = 16, fill: UInt8 = 1) throws -> URL {
        let u = at(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: u)
        return u
    }
    private func dir(_ rel: String) throws -> URL {
        let u = at(rel)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: PathPolicy

    func testSiblingPrefixIsNotAllowed() {
        let p = PathPolicy(home: tmp)
        XCTAssertFalse(p.isDeletable(at("Library/Caches2/x")))
        XCTAssertFalse(p.isDeletable(at("Library/CachesX")))
        XCTAssertFalse(p.isDeletable(at("Documents")), "an allowed root itself is never removable")
    }

    func testDotDotIsRefused() {
        let p = PathPolicy(home: tmp)
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: tmp.path + "/Library/Caches/../Keychains/login.keychain-db")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: tmp.path + "/Library/Caches/a/../b")), "refused outright, not interpreted")
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: tmp.path + "/Library/Caches/./b")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/")))
    }

    func testLeafSymlinkIsJudgedByWhereTheLinkLives() throws {
        let p = PathPolicy(home: tmp)
        // A link inside an allowed root may go (only the link is removed), wherever it points.
        let inCaches = at("Library/Caches/link-out")
        try fm.createSymbolicLink(at: inCaches, withDestinationURL: URL(fileURLWithPath: "/usr/bin"))
        XCTAssertTrue(p.isDeletable(inCaches))
        // A link in a blocked place does not become removable by pointing into an allowed root.
        let target = try file("Library/Caches/real.bin")
        let blocked = try dir("Library/Keychains").appendingPathComponent("link-in")
        try fm.createSymbolicLink(at: blocked, withDestinationURL: target)
        XCTAssertFalse(p.isDeletable(blocked))
    }

    func testParentSymlinkIsResolved() throws {
        let p = PathPolicy(home: tmp)
        let secret = try file(".ssh/id_ed25519")
        try fm.createSymbolicLink(at: at("Library/Caches/escape"), withDestinationURL: secret.deletingLastPathComponent())
        XCTAssertFalse(p.isDeletable(at("Library/Caches/escape/id_ed25519")), "would delete ~/.ssh/id_ed25519 through the link")
        XCTAssertFalse(p.isDeletable(at("Library/Caches/escape/id_ed25519"), extraRoots: [tmp]))
    }

    func testApplicationsRule() throws {
        let p = PathPolicy(home: tmp)
        XCTAssertTrue(p.isDeletable(URL(fileURLWithPath: "/Applications/Foo.app")))
        XCTAssertTrue(p.isDeletable(at("Applications/Foo.app")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/Applications/Foo.app/Contents/MacOS/Foo")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/Applications/Suite/Foo.app")), "top level only")
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/Applications/readme.txt")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/System/Applications/Mail.app")))
        // A folder that merely links to /Applications is not /Applications.
        try fm.createSymbolicLink(at: at("Apps"), withDestinationURL: URL(fileURLWithPath: "/System/Applications"))
        XCTAssertFalse(p.isDeletable(at("Apps/Mail.app")))
    }

    func testExtraRootsMustBeInsideHome() throws {
        let p = PathPolicy(home: tmp)
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/opt/thing"), extraRoots: [URL(fileURLWithPath: "/")]))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/Users/Shared/thing"), extraRoots: [URL(fileURLWithPath: "/Users")]))
        let outside = fm.temporaryDirectory.appendingPathComponent("tidy-outside-\(UUID().uuidString)")
        XCTAssertFalse(p.isDeletable(outside.appendingPathComponent("a.bin"), extraRoots: [outside]))
        XCTAssertTrue(p.isDeletable(at("Projects/a.bin"), extraRoots: [at("Projects")]), "a root inside home still works")
    }

    func testHomeAtRootAllowsNothing() {
        let p = PathPolicy(home: URL(fileURLWithPath: "/"))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/Library/Caches/x")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/Documents/x")))
    }

    func testDenyRulesIgnoreCase() {
        let p = PathPolicy(home: tmp)
        XCTAssertFalse(p.isDeletable(at("library/Keychains/login.keychain-db"), extraRoots: [tmp]))
        XCTAssertFalse(p.isDeletable(at("LIBRARY/x"), extraRoots: [tmp]))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/SYSTEM/Library/x")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/private/var/db/x")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/var/db/x")))
    }

    func testUserDataStoresAreNeverRemovable() {
        let p = PathPolicy(home: tmp)
        for rel in ["Pictures/Photos Library.photoslibrary",
                    "Pictures/Photos Library.photoslibrary/database/Photos.sqlite",
                    "Pictures/Old/Trip.PhotosLibrary/originals/1.heic",
                    "Library/Group Containers/group.com.apple.notes",
                    "Library/Group Containers/group.com.apple.notes/NoteStore.sqlite",
                    "Library/Application Support/AddressBook/AddressBook-v22.abcddb",
                    "Library/Application Support/MobileSync/Backup/abc/Manifest.db"] {
            XCTAssertFalse(p.isDeletable(at(rel)), rel)
            XCTAssertFalse(p.isDeletable(at(rel), extraRoots: [tmp]), rel)
        }
        XCTAssertTrue(p.isDeletable(at("Pictures/holiday.jpg")))
        XCTAssertTrue(p.isDeletable(at("Library/Application Support/Acme/data.db")))
        XCTAssertTrue(p.isDeletable(at("Library/Group Containers/group.com.acme.app/x")))
    }

    func testEveryAllowedRootAllowsAChildButNotItself() {
        let p = PathPolicy(home: tmp)
        XCTAssertEqual(p.allowedRoots.count, 24, "widening the roots needs a deliberate test change")
        for r in p.allowedRoots {
            XCTAssertTrue(p.isDeletable(r.appendingPathComponent("child")), r.path)
            XCTAssertFalse(p.isDeletable(r), r.path)
        }
    }

    func testSymlinkedHomeStillWorks() throws {
        let real = try dir("real-home")
        try fm.createDirectory(at: real.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        let link = at("home-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        let p = PathPolicy(home: link)
        XCTAssertTrue(p.isDeletable(link.appendingPathComponent("Library/Caches/x")))
        XCTAssertTrue(p.isDeletable(real.appendingPathComponent("Library/Caches/x")))
        XCTAssertFalse(p.isDeletable(link))
        XCTAssertFalse(p.isDeletable(real.appendingPathComponent("Library/Keychains/x")))
    }

    // MARK: Cleaner

    private func cleaner(dryRun: Bool, permanent: Bool = true, log: String = "log.jsonl", extraRoots: [URL] = []) -> Cleaner {
        Cleaner(policy: PathPolicy(home: tmp), dryRun: dryRun, permanent: permanent, logURL: at(log), extraRoots: extraRoots)
    }

    func testLogHasOneJSONLinePerAction() throws {
        let a = try file("Library/Caches/a.bin"), b = try file("Library/Caches/b.bin")
        _ = cleaner(dryRun: true).clean([Finding(url: a, size: 16, category: "Caches")])
        let r = cleaner(dryRun: false).clean([Finding(url: a, size: 16, category: "Caches"), Finding(url: b, size: 16, category: "Caches")])
        XCTAssertFalse(r.logFailed)
        let lines = try String(contentsOf: at("log.jsonl"), encoding: .utf8).split(separator: "\n")
        let entries = try lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        XCTAssertEqual(entries.map { $0["action"] as? String }, ["dry-run", "deleted", "deleted"])
        XCTAssertEqual(entries[1]["path"] as? String, a.path)
        XCTAssertEqual(entries[1]["bytes"] as? Int, 16)
        XCTAssertNotNil(entries[1]["t"])
    }

    func testMissingFileIsSkippedNotCounted() {
        let r = cleaner(dryRun: false).clean([Finding(url: at("Library/Caches/gone.bin"), size: 99, category: "t")])
        XCTAssertTrue(r.removed.isEmpty)
        XCTAssertEqual(r.bytes, 0)
        XCTAssertEqual(r.skipped.first?.1, Cleaner.missingReason)
    }

    func testDryRunWinsOverPermanent() throws {
        let f = try file("Library/Caches/keep.bin")
        let r = cleaner(dryRun: true, permanent: true).clean([Finding(url: f, size: 16, category: "t")])
        XCTAssertEqual(r.removed, [f])
        XCTAssertTrue(fm.fileExists(atPath: f.path))
    }

    func testLogFailureIsReported() throws {
        let f = try file("Library/Caches/a.bin")
        try file("not-a-folder")
        let r = cleaner(dryRun: false, log: "not-a-folder/log.jsonl").clean([Finding(url: f, size: 16, category: "t")])
        XCTAssertTrue(r.logFailed)
        XCTAssertEqual(r.removed, [f])
    }

    func testRemovingASymlinkLeavesItsTarget() throws {
        let keep = try file("Documents/keep.txt")
        let link = at("Library/Caches/link")
        try fm.createSymbolicLink(at: link, withDestinationURL: keep)
        let dangling = at("Library/Caches/dangling")
        try fm.createSymbolicLink(at: dangling, withDestinationURL: at("nowhere"))
        let r = cleaner(dryRun: false).clean([Finding(url: link, size: 0, category: "t"), Finding(url: dangling, size: 0, category: "t")])
        XCTAssertEqual(r.removed.count, 2)
        XCTAssertTrue(fm.fileExists(atPath: keep.path))
        XCTAssertNil(try? fm.attributesOfItem(atPath: link.path))
    }

    func testSkipSummaryGroupsReasons() throws {
        let ok = try file("Library/Caches/ok.bin")
        let r = cleaner(dryRun: false).clean([Finding(url: at(".ssh/key"), size: 1, category: "t"),
                                              Finding(url: at("notes.txt"), size: 1, category: "t"),
                                              Finding(url: at("Library/Caches/gone"), size: 1, category: "t"),
                                              Finding(url: ok, size: 16, category: "t")])
        XCTAssertEqual(r.removed, [ok])
        XCTAssertEqual(r.skipSummary.map(\.reason), [Cleaner.blockedReason, Cleaner.missingReason])
        XCTAssertEqual(r.skipSummary.map(\.count), [2, 1])
    }

    // MARK: Duplicates

    func testKeeperRuleNeverRemovesEveryCopy() {
        let files = ["a", "b", "c"].map { Finding(url: at($0), size: 5, category: "Duplicate") }
        let g = DuplicateGroup(size: 5, files: files)
        XCTAssertEqual(g.removable(selected: Set(files.map(\.url))).map(\.url), [at("b"), at("c")])
        XCTAssertEqual(g.removable(selected: [at("a"), at("c")]).map(\.url), [at("a"), at("c")])
        XCTAssertTrue(g.removable(selected: []).isEmpty)
        XCTAssertNil(g.removing([at("b"), at("c")]), "one copy left is no longer a duplicate group")
        XCTAssertEqual(g.removing([at("c")])?.files.count, 2)
    }

    func testHardLinksAreNotDuplicates() async throws {
        let one = try file("Projects/one.bin", bytes: 5000)
        try fm.linkItem(at: one, to: at("Projects/two.bin"))
        let groups = await DuplicateScanner(root: tmp, minSize: 1000).scan()
        XCTAssertTrue(groups.isEmpty, "removing a hard link frees nothing")
    }

    func testDuplicateScanSkipsWhatItCannotOffer() async throws {
        for rel in ["Projects/app/node_modules/x/a.bin", "Projects/app/node_modules/y/a.bin",
                    "Projects/.git/objects/a.bin", ".config/a.bin", "Library/Application Support/X/a.bin", "Library/b.bin"] {
            try file(rel, bytes: 5000, fill: 7)
        }
        var groups = await DuplicateScanner(root: tmp, minSize: 1000).scan()
        XCTAssertTrue(groups.isEmpty)
        // A project's own "Library" folder is ordinary content.
        try file("Projects/game/Library/a.bin", bytes: 5000, fill: 7)
        try file("Projects/game/Assets/a.bin", bytes: 5000, fill: 7)
        groups = await DuplicateScanner(root: tmp, minSize: 1000).scan()
        XCTAssertEqual(groups.count, 1)
        let policy = PathPolicy(home: tmp)
        XCTAssertTrue(groups.flatMap(\.files).allSatisfy { policy.isDeletable($0.url, extraRoots: [tmp]) })
    }

    func testUnreadableFileHasNoHash() throws {
        XCTAssertNil(DuplicateScanner.hash(try dir("Projects/folder"), limit: nil), "a failed read must not produce a hash")
        XCTAssertNil(DuplicateScanner.hash(at("missing.bin"), limit: 65_536))
        let f = try file("Projects/a.bin", bytes: 5000)
        XCTAssertEqual(DuplicateScanner.hash(f, limit: nil), DuplicateScanner.hash(f, limit: 65_536), "short file: both read it all")
    }

    func testDuplicateOrderIsStable() async throws {
        try file("Projects/b.bin", bytes: 5000, fill: 3); try file("Projects/a.bin", bytes: 5000, fill: 3)
        let old = Date(timeIntervalSince1970: 1_000_000)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: at("Projects/b.bin").path)
        let g = await DuplicateScanner(root: tmp, minSize: 1000).scan()
        XCTAssertEqual(g.first?.files.first?.url.lastPathComponent, "b.bin", "oldest copy is the keeper")
        XCTAssertEqual(g.first?.id.lastPathComponent, "b.bin")
    }

    // MARK: Scanners offer only what is safe and removable

    func testLargeFilesOnlyListsRemovableFiles() async throws {
        try file("Projects/big.bin", bytes: 20_000)
        try file("Movies/clip.mov", bytes: 20_000)
        try file(".cache/hidden-big.bin", bytes: 20_000)
        try file("Library/Application Support/X/big.db", bytes: 20_000)
        try file("Projects/app/node_modules/big.bin", bytes: 20_000)
        try file("Pictures/Photos Library.photoslibrary/originals/big.heic", bytes: 20_000)
        try file("Projects/small.txt", bytes: 10)
        let scanner = LargeFileScanner(root: tmp, minSize: 10_000)
        let found = await scanner.scan()
        XCTAssertEqual(Set(found.map { $0.url.lastPathComponent }), ["big.bin", "clip.mov"])
        XCTAssertTrue(found.allSatisfy { $0.risk == .review })
        let policy = PathPolicy(home: tmp)
        XCTAssertTrue(found.allSatisfy { policy.isDeletable($0.url, extraRoots: scanner.extraRoots) })
    }

    func testEveryScannerOutputPassesThePolicy() async throws {
        try file("Library/Caches/com.acme.foo/blob", bytes: 5000)
        try file("Library/Logs/acme.log", bytes: 5000)
        try file(".cache/tool/blob", bytes: 5000)
        try file("Library/Containers/com.acme.foo/Data/doc.txt", bytes: 5000)
        try file("Library/Preferences/com.acme.foo.plist", bytes: 5000)
        try file("Library/Safari/History.db", bytes: 5000)
        try file("Library/Application Support/Firefox/Profiles/abc.default/cookies.sqlite", bytes: 5000)
        let contents = try dir("Applications/Foo.app/Contents")
        try (["CFBundleIdentifier": "com.acme.foo", "CFBundleName": "Foo"] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))

        let policy = PathPolicy(home: tmp)
        let junk = await JunkScanner(home: tmp).scan()
        let privacy = await PrivacyScanner(home: tmp).scan()
        let uninstaller = AppUninstaller(home: tmp, appDirs: [at("Applications")])
        let apps = await uninstaller.listApps()
        let plan = await uninstaller.removalPlan(for: try XCTUnwrap(apps.first))
        XCTAssertGreaterThanOrEqual(junk.count, 3)
        XCTAssertGreaterThanOrEqual(privacy.count, 2)
        XCTAssertGreaterThanOrEqual(plan.count, 4)
        for f in junk + privacy + plan { XCTAssertTrue(policy.isDeletable(f.url), f.url.path) }
    }

    func testPrivacyNeverOffersBookmarks() async throws {
        let profile = "Library/Application Support/Firefox/Profiles/abc.default"
        try file("\(profile)/places.sqlite", bytes: 5000)
        try file("\(profile)/cookies.sqlite", bytes: 5000)
        for name in ["History.db", "History.db-wal", "History.db-shm", "Bookmarks.plist"] { try file("Library/Safari/\(name)", bytes: 5000) }
        try file("Library/Application Support/Google/Chrome/Default/Network/Cookies", bytes: 5000)
        try file("Library/Application Support/Google/Chrome/Default/Bookmarks", bytes: 5000)
        let names = Set(await PrivacyScanner(home: tmp).scan().map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["cookies.sqlite", "History.db", "History.db-wal", "History.db-shm", "Cookies"])
    }

    func testUninstallerNeverPreselectsAppData() async throws {
        for rel in ["Library/Containers/com.acme.foo/Data/doc.txt", "Library/Group Containers/group.com.acme.foo/shared.db",
                    "Library/Caches/com.acme.foo/blob"] { try file(rel, bytes: 5000) }
        let app = InstalledApp(url: at("Applications/Foo.app"), name: "Foo", bundleID: "com.acme.foo", size: 1)
        let left = AppUninstaller(home: tmp, appDirs: []).leftovers(for: app)
        XCTAssertEqual(left.count, 3)
        XCTAssertEqual(left.first { $0.url.path.contains("/Containers/") }?.risk, .review)
        XCTAssertEqual(left.first { $0.url.path.contains("/Group Containers/") }?.risk, .review)
        XCTAssertEqual(left.first { $0.url.path.contains("/Caches/") }?.risk, .safe)
    }

    // MARK: Permissions

    func testUnreadableFolderIsDetected() throws {
        let check = PermissionCheck(home: tmp)
        XCTAssertTrue(check.hasFullDiskAccess, "nothing to probe yet")
        let safari = try dir("Library/Safari")
        XCTAssertTrue(check.hasFullDiskAccess)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: safari.path)
        XCTAssertEqual(check.unreadable().map(\.lastPathComponent), ["Safari"])
        XCTAssertFalse(check.hasFullDiskAccess)
    }
}

final class PresentationTests: XCTestCase {
    func testCleanSummaryWording() {
        var r = CleanResult()
        r.removed = [URL(fileURLWithPath: "/tmp/a")]; r.bytes = 2_000_000
        XCTAssertEqual(r.summary(dryRun: false, permanent: false), "Moved 1 item to the Trash, 2 MB.")
        XCTAssertTrue(r.summary(dryRun: true, permanent: true).hasPrefix("Dry run: would remove 1 item"))
        r.removed.append(URL(fileURLWithPath: "/tmp/b"))
        r.skipped = [(URL(fileURLWithPath: "/tmp/c"), Cleaner.blockedReason)]
        r.logFailed = true
        XCTAssertEqual(r.summary(dryRun: false, permanent: true),
                       "Deleted 2 items, 2 MB. Skipped 1 (blocked by safety rules). The log file could not be written.")
    }

    func testDisplayPathOnlyShortensARealHomePrefix() {
        let home = URL(fileURLWithPath: "/Users/sam")
        XCTAssertEqual(displayPath(URL(fileURLWithPath: "/Users/sam/Documents/a"), home: home), "~/Documents/a")
        XCTAssertEqual(displayPath(URL(fileURLWithPath: "/Users/sam2/Documents"), home: home), "/Users/sam2/Documents")
        XCTAssertEqual(displayPath(URL(fileURLWithPath: "/Volumes/x/Users/sam/a"), home: home), "/Volumes/x/Users/sam/a")
        XCTAssertEqual(displayPath(home, home: home), "~")
    }

    func testMemoryOtherNeverUnderflows() {
        XCTAssertEqual(MemoryStats(total: 100, used: 60, app: 30, wired: 10, compressed: 5, free: 20).other, 35)
        XCTAssertEqual(MemoryStats(total: 10, used: 60, app: 30, wired: 10, compressed: 5, free: 20).other, 0)
    }
}

final class LaunchAgentUnloaderTests: XCTestCase {
    /// Records what would be run; the real launchctl is never started by a test.
    private final class Recorder: @unchecked Sendable {
        var calls: [(String, [String])] = []
        var status: Int32 = 0
    }

    private func unloader(_ r: Recorder) -> LaunchAgentUnloader {
        LaunchAgentUnloader(uid: 501) { exe, args in r.calls.append((exe, args)); return r.status }
    }

    func testBootoutTargetsOnlyTheUsersOwnSession() {
        let r = Recorder()
        XCTAssertEqual(unloader(r).unload(label: "com.acme.helper"), .stopped)
        XCTAssertEqual(r.calls.count, 1)
        XCTAssertEqual(r.calls[0].0, "/bin/launchctl")
        XCTAssertEqual(r.calls[0].1, ["bootout", "gui/501/com.acme.helper"])
    }

    func testExitCodesAreInterpreted() {
        let r = Recorder()
        r.status = 3;   XCTAssertEqual(unloader(r).unload(label: "com.acme.helper"), .notRunning)
        r.status = 113; XCTAssertEqual(unloader(r).unload(label: "com.acme.helper"), .notRunning)
        r.status = 5;   XCTAssertEqual(unloader(r).unload(label: "com.acme.helper"), .failed(5))
    }

    func testSuspiciousLabelsNeverReachTheCommandLine() {
        let r = Recorder()
        for label in ["", "system/com.apple.x", "../gui/0/x", "a b", "-flag", "x;rm", "a\nb", String(repeating: "a", count: 300)] {
            XCTAssertEqual(unloader(r).unload(label: label), .failed(-1), label)
        }
        XCTAssertTrue(r.calls.isEmpty)
    }
}
