import SwiftUI
import TidyCore

enum Pane: String, CaseIterable, Identifiable {
    case smart = "Quick Scan", junk = "System Junk", large = "Large Files"
    case dupes = "Duplicates", uninstall = "Uninstaller"
    case lens = "Disk Map", perf = "Performance"
    case privacy = "Privacy", login = "Login Items"

    /// The raw value is a stable identifier (saved window state); `title` is what the user sees.
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: String(localized: "Quick Scan"); case .junk: String(localized: "System Junk")
        case .large: String(localized: "Large Files"); case .dupes: String(localized: "Duplicates")
        case .uninstall: String(localized: "Uninstaller"); case .lens: String(localized: "Disk Map")
        case .perf: String(localized: "Performance"); case .privacy: String(localized: "Privacy")
        case .login: String(localized: "Login Items")
        }
    }
    var icon: String {
        switch self {
        case .smart: "sparkles"; case .junk: "trash"; case .large: "externaldrive"
        case .dupes: "doc.on.doc"; case .uninstall: "xmark.app"
        case .lens: "square.grid.3x3.fill"; case .perf: "speedometer"
        case .privacy: "hand.raised"; case .login: "power"
        }
    }
    /// Panes with a scan the user can start (and rerun) from the menu.
    var scannable: Bool { self != .lens && self != .perf }
    /// Sidebar order, which is also the ⌘1…⌘9 order.
    static var ordered: [Pane] { PaneGroup.all.flatMap(\.panes) }
}

struct PaneGroup: Identifiable {
    let id: String
    let title: String
    let panes: [Pane]
    static var all: [PaneGroup] {
        [PaneGroup(id: "Cleanup", title: String(localized: "Cleanup"), panes: [.smart, .junk, .large, .dupes, .uninstall]),
         PaneGroup(id: "Analyze", title: String(localized: "Analyze"), panes: [.lens, .perf]),
         PaneGroup(id: "Protect", title: String(localized: "Protect"), panes: [.privacy, .login])]
    }
}

/// A clean the user still has to confirm (shown in the confirm sheet when dry run is off).
struct PendingClean: Identifiable {
    let id = UUID()
    let items: [Finding]
    let extraRoots: [URL]
    let label: String
    /// Appended to the result message (e.g. why some items were left out).
    var note = ""
    var bytes: Int64 { totalBytes(items) }
}

@Observable @MainActor
final class AppModel {
    var pane: Pane = .smart
    var junk: [Finding] = []
    var large: [Finding] = []
    var privacy: [Finding] = []
    var duplicates: [DuplicateGroup] = []
    var apps: [InstalledApp] = []
    var launchItems: [LaunchItem] = []
    var selectedApp: InstalledApp?
    var plan: [Finding] = []

    /// One selection set shared by all panes; each scan only replaces its own pane's entries.
    var selected: Set<URL> = []
    /// Scans that are running, and panes whose scan has finished at least once.
    private(set) var active: Set<Pane> = []
    private(set) var scanned: Set<Pane> = []
    private(set) var cleaning = false
    /// Quick Scan progress: stages finished (0...3) and the running total found so far.
    private(set) var scanStep = 0
    private(set) var foundSoFar: Int64 = 0
    /// Always on at launch. Turning it off goes through `setDryRun`, which asks first.
    private(set) var dryRun = true
    var askGoLive = false
    var message = ""
    var pending: PendingClean?
    /// Protected folders the app cannot read without Full Disk Access (results are incomplete while non-empty).
    private(set) var unreadable: [URL] = []

    private var scans: [Pane: Task<Void, Never>] = [:]
    private var planTask: Task<Void, Never>?
    private static let smartStages: Set<Pane> = [.junk, .large, .privacy]

    func isScanning(_ p: Pane) -> Bool { active.contains(p) || (Self.smartStages.contains(p) && active.contains(.smart)) }
    func hasScanned(_ p: Pane) -> Bool { scanned.contains(p) }

    // MARK: Summary numbers for Quick Scan and the menu bar

    /// Pre-checked, low-risk bytes found by the last scan.
    var safeBytes: Int64 { totalBytes((junk + privacy).filter { $0.risk == .safe }) }
    /// Bytes that need a human decision first.
    var reviewBytes: Int64 { totalBytes((junk + privacy).filter { $0.risk == .review }) + totalBytes(large) }
    var duplicateWaste: Int64 { duplicates.reduce(0) { $0 + $1.wasted } }
    var selectedDuplicates: [Finding] { duplicates.flatMap(\.files).filter { selected.contains($0.url) } }

    // MARK: Safety mode

    func setDryRun(_ on: Bool) {
        if on { dryRun = true } else if dryRun { askGoLive = true }
    }
    func confirmGoLive() { dryRun = false }

    // MARK: Scans

    /// Starts the pane's scan unless it (or a Quick Scan that covers it) is already running.
    func scan(_ p: Pane) {
        guard p.scannable, !cleaning, !isScanning(p) else { return }
        if p == .smart, !active.isDisjoint(with: Self.smartStages) { return }
        active.insert(p)
        message = ""
        unreadable = PermissionCheck().unreadable()
        scans[p] = Task {
            await run(p)
            active.remove(p)
            scans[p] = nil
        }
    }

    func cancelScan(_ p: Pane) { scans[p]?.cancel() }

    /// Results are only adopted if the scan was not cancelled; a cancelled scan leaves the previous results alone.
    private func run(_ p: Pane) async {
        switch p {
        case .smart:
            scanStep = 0; foundSoFar = 0
            for (i, stage) in [Pane.junk, .large, .privacy].enumerated() {
                await run(stage)
                if Task.isCancelled { return }
                withAnimation(.snappy) { scanStep = i + 1; foundSoFar = totalBytes(junk + large + privacy) }
            }
            try? await Task.sleep(for: .milliseconds(450))   // let the final stage tick over before the results appear
        case .junk:
            let r = await JunkScanner().scan()
            if Task.isCancelled { return }
            adopt(r, replacing: junk, preselectSafe: true); junk = r
        case .large:
            let r = await LargeFileScanner(minSize: Prefs.largeFileBytes).scan()
            if Task.isCancelled { return }
            adopt(r, replacing: large, preselectSafe: false); large = r
        case .privacy:
            let r = await PrivacyScanner().scan()
            if Task.isCancelled { return }
            adopt(r, replacing: privacy, preselectSafe: true); privacy = r
        case .dupes:
            let r = await DuplicateScanner(minSize: Prefs.duplicateBytes).scan()
            if Task.isCancelled { return }
            selected.subtract(duplicates.flatMap { $0.files.map(\.url) })
            selected.formUnion(r.flatMap { $0.files.dropFirst().map(\.url) })   // keeper (oldest) stays unchecked
            duplicates = r
        case .uninstall:
            let r = await AppUninstaller().listApps()
            if Task.isCancelled { return }
            apps = r
        case .login:
            launchItems = await Task.detached { LoginItemScanner().scan() }.value
        case .lens, .perf:
            return
        }
        if !Task.isCancelled { scanned.insert(p) }
    }

    private func adopt(_ new: [Finding], replacing old: [Finding], preselectSafe: Bool) {
        selected.subtract(old.map(\.url))
        if preselectSafe { selected.formUnion(new.filter { $0.risk == .safe }.map(\.url)) }
    }

    /// Picks an app and works out what removing it would take, off the main actor.
    func choose(_ app: InstalledApp) {
        planTask?.cancel()
        selected.subtract(plan.map(\.url))
        selectedApp = app
        plan = []
        planTask = Task {
            let p = await AppUninstaller().removalPlan(for: app)
            guard !Task.isCancelled, selectedApp == app else { return }
            plan = p
            selected.formUnion(p.filter { $0.risk == .safe }.map(\.url))
        }
    }

    // MARK: Selection

    func toggle(_ url: URL) {
        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
    }

    /// What the pane lists for cleaning (empty for read-only panes).
    func findings(in p: Pane) -> [Finding] {
        switch p {
        case .junk: junk
        case .large: large
        case .privacy: privacy
        case .dupes: duplicates.flatMap(\.files)
        case .uninstall: plan
        case .smart, .lens, .perf, .login: []
        }
    }

    func selectAllSafe(in p: Pane) { selected.formUnion(findings(in: p).filter { $0.risk == .safe }.map(\.url)) }
    func selectNone(in p: Pane) { selected.subtract(findings(in: p).map(\.url)) }

    // MARK: Cleaning

    /// Cleans the pane's ticked items: a preview in dry run, otherwise after the confirm sheet.
    func cleanSelection(in p: Pane) {
        switch p {
        case .junk, .privacy:
            requestClean(findings(in: p), label: p.title)
        case .large:
            requestClean(large, extraRoots: LargeFileScanner().extraRoots, label: p.title)
        case .dupes:
            submit(duplicates.flatMap { $0.removable(selected: selected) },
                   extraRoots: [FileManager.default.homeDirectoryForCurrentUser], label: p.title)
        case .uninstall:
            requestClean(plan, label: selectedApp?.name ?? p.title)
        case .smart, .lens, .perf, .login:
            break
        }
    }

    func requestRemove(_ item: LaunchItem) {
        guard item.removable else { return }
        submit([Finding(url: item.url, size: 0, category: String(localized: "Login Item"), risk: .review)], label: Pane.login.title,
               note: dryRun ? String(localized: "A real removal also stops the agent if it is running.") : "")
    }

    /// Browsers that are running: their history/cookie databases are locked and in use.
    private func runningBrowserIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).intersection(Browser.allCases.map(\.bundleID))
    }

    private func requestClean(_ list: [Finding], extraRoots: [URL] = [], label: String) {
        let running = runningBrowserIDs()
        var blocked = 0
        let chosen = list.filter { selected.contains($0.url) }.filter { f in
            if f.risk == .review, let b = PrivacyScanner.browser(of: f), running.contains(b.bundleID) { blocked += 1; return false }
            return true
        }
        let note = blocked == 0 ? "" : blocked == 1
            ? String(localized: "Left out 1 browser data item because the browser is running. Quit it first.")
            : String(localized: "Left out \(blocked) browser data items because the browser is running. Quit it first.")
        submit(chosen, extraRoots: extraRoots, label: label, note: note)
    }

    /// Dry run: performs the preview immediately. Real run: opens the confirm sheet first. No other path removes anything.
    private func submit(_ items: [Finding], extraRoots: [URL] = [], label: String, note: String = "") {
        guard !cleaning else { return }
        guard !items.isEmpty else { message = note.isEmpty ? String(localized: "Nothing selected.") : note; return }
        let p = PendingClean(items: items, extraRoots: extraRoots, label: label, note: note)
        if dryRun { Task { await perform(p, permanent: false) } } else { pending = p }
    }

    func perform(_ p: PendingClean, permanent: Bool) async {
        pending = nil
        guard !cleaning else { return }
        cleaning = true
        defer { cleaning = false }
        let dry = dryRun
        let cleaner = Cleaner(dryRun: dry, permanent: permanent, extraRoots: p.extraRoots)
        let items = p.items
        let r = await Task.detached { cleaner.clean(items) }.value
        var parts = [r.summary(dryRun: dry, permanent: permanent)]
        if !p.note.isEmpty { parts.append(p.note) }
        defer { message = parts.joined(separator: " ") }
        guard !dry else { return }
        let gone = Set(r.removed)
        // A removed launch agent keeps running until it is told to stop, so stop it now.
        let agents = launchItems.filter { gone.contains($0.url) && $0.removable }.map(\.label)
        if !agents.isEmpty {
            let outcomes = await Task.detached { agents.map { LaunchAgentUnloader().unload(label: $0) } }.value
            if outcomes.contains(where: { if case .failed = $0 { true } else { false } }) {
                parts.append(String(localized: "The agent could not be stopped, so it keeps running until you log out."))
            } else if outcomes.contains(.stopped) {
                parts.append(String(localized: "The running agent was stopped."))
            } else {
                parts.append(String(localized: "It was not running."))
            }
        }
        junk.removeAll { gone.contains($0.url) }
        large.removeAll { gone.contains($0.url) }
        privacy.removeAll { gone.contains($0.url) }
        plan.removeAll { gone.contains($0.url) }
        apps.removeAll { gone.contains($0.url) }
        launchItems.removeAll { gone.contains($0.url) }
        duplicates = duplicates.compactMap { $0.removing(gone) }
        if let a = selectedApp, gone.contains(a.url) { selectedApp = nil; plan = [] }
        selected.subtract(gone)
    }
}
