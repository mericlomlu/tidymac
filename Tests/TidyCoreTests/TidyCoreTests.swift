import XCTest
@testable import TidyCore

private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }

final class TidyCoreTests: XCTestCase {
    var tmp: URL!
    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testPolicyBlocksProtected() {
        let p = PathPolicy(home: tmp)
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/System/Library/foo")))
        XCTAssertFalse(p.isDeletable(URL(fileURLWithPath: "/usr/bin/ls")))
        XCTAssertFalse(p.isDeletable(tmp))
        XCTAssertFalse(p.isDeletable(tmp.appendingPathComponent("Library/Caches")), "root itself must not be deletable")
        XCTAssertFalse(p.isDeletable(tmp.appendingPathComponent("Library/Keychains/login.keychain-db")))
    }

    func testExtraRootStillBlocksHiddenAndLibrary() {
        let p = PathPolicy(home: tmp)
        XCTAssertFalse(p.isDeletable(tmp.appendingPathComponent(".ssh/id_ed25519"), extraRoots: [tmp]))
        XCTAssertFalse(p.isDeletable(tmp.appendingPathComponent("Library/Keychains/x"), extraRoots: [tmp]))
        XCTAssertTrue(p.isDeletable(tmp.appendingPathComponent("Projects/a/b.jpg"), extraRoots: [tmp]))
        XCTAssertFalse(p.isDeletable(tmp.appendingPathComponent("Projects/a/b.jpg")), "no extra root → not allowed unless in default roots")
    }

    func testPolicyAllowsCacheChild() {
        let p = PathPolicy(home: tmp)
        XCTAssertTrue(p.isDeletable(tmp.appendingPathComponent("Library/Caches/com.x.app")))
    }

    func testDryRunTouchesNothing() throws {
        let f = tmp.appendingPathComponent("Library/Caches/junk.bin")
        try Data(count: 4096).write(to: f)
        let c = Cleaner(policy: PathPolicy(home: tmp), dryRun: true, logURL: tmp.appendingPathComponent("log.jsonl"))
        let r = c.clean([Finding(url: f, size: 4096, category: "t")])
        XCTAssertEqual(r.removed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.path))
    }

    func testRealCleanRemovesAndLogs() throws {
        let f = tmp.appendingPathComponent("Library/Caches/junk.bin")
        try Data(count: 4096).write(to: f)
        let log = tmp.appendingPathComponent("log.jsonl")
        let c = Cleaner(policy: PathPolicy(home: tmp), dryRun: false, permanent: true, logURL: log)
        _ = c.clean([Finding(url: f, size: 4096, category: "t")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: log.path))
    }

    func testCleanerRefusesOutsidePolicy() throws {
        let f = tmp.appendingPathComponent("important.txt")
        try Data(count: 10).write(to: f)
        let c = Cleaner(policy: PathPolicy(home: tmp), dryRun: false, permanent: true, logURL: tmp.appendingPathComponent("l.jsonl"))
        let r = c.clean([Finding(url: f, size: 10, category: "t")])
        XCTAssertEqual(r.skipped.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.path))
    }

    func testDuplicatesFoundAndUniqueIgnored() async throws {
        let a = Data(repeating: 7, count: 2_000_000), b = Data(repeating: 9, count: 2_000_000)
        try a.write(to: tmp.appendingPathComponent("one.bin"))
        try a.write(to: tmp.appendingPathComponent("two.bin"))
        try b.write(to: tmp.appendingPathComponent("other.bin"))   // same size, different content
        let groups = await DuplicateScanner(root: tmp, minSize: 1000).scan()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].wasted, 2_000_000)
    }

    func testTreemapCoversBoundsWithoutOverlap() {
        let sizes: [Int64] = [500, 300, 100, 60, 40]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = SpaceLens.layout(sizes: sizes, in: bounds)
        XCTAssertEqual(rects.reduce(0) { $0 + $1.width * $1.height }, bounds.width * bounds.height, accuracy: 0.01)
        for i in rects.indices { for j in rects.indices where i < j {
            XCTAssertTrue(rects[i].intersection(rects[j]).isNull || rects[i].intersection(rects[j]).area < 0.01)
        } }
        XCTAssertGreaterThan(rects[0].width * rects[0].height, rects[4].width * rects[4].height)
    }

    func testUninstallerLeftoversAndAppleExclusion() async throws {
        let fm = FileManager.default
        let apps = tmp.appendingPathComponent("Applications")
        func makeApp(_ name: String, _ id: String) throws {
            let c = apps.appendingPathComponent("\(name).app/Contents")
            try fm.createDirectory(at: c, withIntermediateDirectories: true)
            try (["CFBundleIdentifier": id, "CFBundleName": name] as NSDictionary).write(to: c.appendingPathComponent("Info.plist"))
        }
        try makeApp("Foo", "com.acme.foo"); try makeApp("Safari", "com.apple.Safari")
        let lib = tmp.appendingPathComponent("Library")
        for p in ["Caches/com.acme.foo", "Preferences/com.acme.foo.plist", "Application Support/Foo", "Caches/com.acme.foobar", "Caches/com.other.x"] {
            let u = lib.appendingPathComponent(p)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: 5000).write(to: u)
        }
        let un = AppUninstaller(home: tmp, appDirs: [apps])
        let list = await un.listApps()
        XCTAssertEqual(list.map(\.bundleID), ["com.acme.foo"], "Apple apps must not be listed")
        let left = un.leftovers(for: list[0])
        let names = Set(left.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["com.acme.foo", "com.acme.foo.plist", "Foo"], "must not match com.acme.foobar or other apps")
        XCTAssertEqual(left.first { $0.url.lastPathComponent == "com.acme.foo" }?.risk, .safe)
        XCTAssertEqual(left.first { $0.url.lastPathComponent == "Foo" }?.risk, .review)
    }

    func testLoginItemsParsed() throws {
        let dir = tmp.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try (["Label": "com.acme.helper", "ProgramArguments": ["/opt/acme/helper", "-x"], "RunAtLoad": true] as NSDictionary)
            .write(to: dir.appendingPathComponent("com.acme.helper.plist"))
        let item = LoginItemScanner(home: tmp).scan().first { $0.label == "com.acme.helper" }
        XCTAssertEqual(item?.program, "/opt/acme/helper")
        XCTAssertEqual(item?.runAtLoad, true)
        XCTAssertEqual(item?.removable, true)
    }

    func testPrivacyScannerFindsChromeAndClassifies() async throws {
        let fm = FileManager.default
        let d = tmp.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(count: 9000).write(to: d.appendingPathComponent("History"))
        let c = tmp.appendingPathComponent("Library/Caches/Google/Chrome")
        try fm.createDirectory(at: c, withIntermediateDirectories: true)
        try Data(count: 9000).write(to: c.appendingPathComponent("blob"))
        let found = await PrivacyScanner(home: tmp).scan()
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.first { $0.category.contains("Cache") }?.risk, .safe)
        XCTAssertEqual(found.first { $0.category.contains("History") }?.risk, .review)
        XCTAssertTrue(found.allSatisfy { PrivacyScanner.browser(of: $0) == .chrome })
        XCTAssertTrue(found.allSatisfy { PathPolicy(home: tmp).isDeletable($0.url) }, "everything we offer must pass PathPolicy")
    }

    func testSystemSamplerSanity() {
        let s = SystemSampler()
        let m = s.memory()
        XCTAssertGreaterThan(m.total, 0)
        XCTAssertGreaterThan(m.used, 0)
        XCTAssertLessThanOrEqual(m.used, m.total)
        XCTAssertEqual(s.cpuUsage(), 0)                       // first sample has no baseline
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue((0...1).contains(s.cpuUsage()))
        let d = s.disk()
        XCTAssertGreaterThan(d.total, d.free)
        XCTAssertFalse(s.topProcesses(limit: 5).isEmpty)
    }

    func testParsePS() {
        let out = "  101  2048  1.5 /usr/sbin/foo\n  7 10240 0.0 /Applications/My App.app/Contents/MacOS/My App\nbad line\n"
        let rows = SystemSampler.parsePS(out, limit: 5)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].pid, 7)                        // sorted by memory
        XCTAssertEqual(rows[0].rssBytes, 10240 * 1024)
        XCTAssertEqual(rows[0].name, "My App")
    }

    func testGroupByCategorySortsAndTotals() {
        let u = { (n: String) in URL(fileURLWithPath: "/tmp/\(n)") }
        let items = [Finding(url: u("a"), size: 10, category: "Logs"),
                     Finding(url: u("b"), size: 500, category: "Caches"),
                     Finding(url: u("c"), size: 300, category: "Caches"),
                     Finding(url: u("d"), size: 100, category: "Logs", risk: .review)]
        let g = groupByCategory(items)
        XCTAssertEqual(g.map(\.name), ["Caches", "Logs"])
        XCTAssertEqual(g.map(\.size), [800, 110])
        XCTAssertEqual(g[0].items.map(\.size), [500, 300])
        XCTAssertEqual(totalBytes(items), 910)
        XCTAssertTrue(groupByCategory([]).isEmpty)
    }

    func testJunkScannerFindsSize() async throws {
        try Data(count: 50_000).write(to: tmp.appendingPathComponent("Library/Caches/a.bin"))
        let found = await JunkScanner(home: tmp).scan()
        XCTAssertEqual(found.count, 1)
        XCTAssertGreaterThan(found[0].size, 0)
    }
}
