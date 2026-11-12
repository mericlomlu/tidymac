# Changelog

All notable changes.

## 1.0.0 (2026-11-12)

First public release.

- Nine panes: Quick Scan, System Junk, Large Files, Duplicates, Uninstaller, Disk Map, Performance, Privacy and Login Items, plus a menu-bar extra
- Safety model: dry run on at every launch, Trash by default, a confirm sheet for every real clean, one central `PathPolicy`, and an activity log (see `docs/SAFETY.md`)
- Light and dark themes, English and Turkish, a Settings window and a collapsible sidebar
- Universal build (Apple Silicon and Intel) for macOS 14 or later; ad-hoc signed, not notarized

## Development history (before the public release)

TidyMac was built privately first. The build numbers below were used during that time and were never published; version numbering starts again at 1.0.0 with the public release. Entries keep the names used at the time.

### Private build 1.1.2 (2026-11-12)

- **Fix:** on the Quick Scan screen the "Dry run is on" note no longer covers the Cancel button or the category cards at the default and minimum window sizes. It now has its own row under the content, the screens are slightly more compact, and the results scroll if the window is still too short
- README: screenshots added (`docs/screenshots/`)

### Private build 1.1.1 (2026-11-12)

- **Renamed panes:** "Smart Scan" is now "Quick Scan" and "Space Lens" is now "Disk Map" (English and Turkish), so the app uses its own names. Entries below keep the names used at the time
- **Universal build:** `build_app.sh` builds for Apple Silicon and Intel; `./build_app.sh --zip` also writes `build/TidyMac-<version>.zip` for a release
- The app's copyright line no longer says "not for distribution"
- README: install steps for a downloaded copy (including "Open Anyway"), a use-at-your-own-risk note and a no-affiliation note
- The last pane you had open is not restored once after this update (the saved name changed); it opens on Quick Scan

### Private build 1.1.0 (2026-11-12)

- **Settings window** (⌘,): theme, menu-bar item on/off, size thresholds for Large Files (50 MB–1 GB) and Duplicates (1–50 MB). Dry run is deliberately not a setting
- **Light mode:** every theme color is now a dark/light pair; the app follows the system appearance unless a theme is chosen in Settings
- **Collapsible sidebar** (⌃⌘S or the sidebar button): collapses to an icon rail that keeps every pane and the dry-run state visible
- **Localisation:** all user-facing text goes through a string catalog (`Resources/Localizable.xcstrings`); Turkish translation added; `localize.sh` refreshes the catalog from the compiler's own list of strings
- **Login Items:** removing a user launch agent now also stops it (`launchctl bootout gui/<uid>/<label>`), and the result says whether it was running
- `LICENSE` added (all rights reserved); repository initialised (private)
- Tests: 45 → 49 (launch-agent unloader, translation completeness and placeholder check)

### Private build 1.0.0 (2026-11-12)

#### Finalization review: safety
- `PathPolicy` checks the item a removal would act on: symlinks are resolved in the parent folder only, so a link is judged by where it lives. Paths containing `.` or `..` are refused outright
- `PathPolicy` normalises home and every root the same way (a symlinked home works; `/private/var/db` now matches), ignores extra roots outside the home folder, refuses everything when home is `/`, and compares deny rules case-insensitively
- New deny-list inside the allowed roots: Photos libraries, the Notes container, the Contacts database and iPhone backups are never removable
- Login Items removal now goes through the confirm sheet like every other delete (it used to trash immediately)
- Confirm sheet: Return and Escape cancel; deleting takes a click; permanent delete is styled amber
- Turning dry run off asks for confirmation
- Duplicates: a file that cannot be read in full is excluded instead of hashed from a partial read; hard links are no longer reported; the "never remove every copy" rule moved into `TidyCore`
- Privacy no longer offers Firefox `places.sqlite` (it holds bookmarks); Safari history includes its `-wal`/`-shm` files; Chrome's current cookie path is found
- Uninstaller: an app's `Containers` and `Group Containers` folders are `review` and never pre-ticked
- `Cleaner` is an immutable struct and reports when the log could not be written

#### Finalization review: behaviour
- Scan state is per pane: overlapping scans no longer show a fake Smart Scan screen or re-enable buttons early, and a scan cannot start twice
- Scans can be cancelled (Smart Scan, Duplicates; Space Lens stops sizing a folder you leave)
- Cleaning, the Uninstaller's leftover search and the login-item scan run off the main thread
- The result message sits under the pane header, so it survives a clean that empties the list; it explains why items were skipped
- Full Disk Access: unreadable protected folders are detected and a banner explains that results are incomplete
- Large Files (renamed from "Large & Old Files"; there was never an age filter) lists only files the safety rules allow removing, and skips `node_modules`
- Empty states tell "not scanned" from "nothing found"; Smart Scan has a "Nothing to clean" result, a correct Privacy chip, and "Review and Clean" opens the first pane that has findings

#### Finalization review: polish
- Scan menu with shortcuts (⌘R, ⌘., ⇧⌘A, ⇧⌘D, ⌘⌫), ⌘1…⌘9 for panes, a Dry Run menu item
- The orb is still at rest (no idle CPU); all clock-driven animation honours Reduce Motion
- VoiceOver: rows read name, size and selection as one toggle; treemap tiles, cards and gauges are labelled
- The last pane is restored on launch; the window has a real minimum size
- Shared `PaneHeader`, `SelectableRow`, `ActionBar`, `GaugeTile`, `BatteryRow`; unused `Meter`/`StatsBlock` removed; `ps` is sampled only while a process list is visible
- `build_app.sh`: version 1.0.0, complete Info.plist, quits a running copy, verifies the signature, optional `TIDYMAC_SIGN_ID`
- Tests: 15 → 45

### Private build 0.1 (2026-11-12, development milestones)

#### Design pass: playful monochrome
- New theme (`Theme.swift`): black → `#152331` background, ice-white/silver accents, amber only for Review
- Grouped custom sidebar (Cleanup / Analyze / Protect) with an always-visible, clickable Dry run badge
- Smart Scan: start, scanning (spinning orb) and results screens with a hero "safe to clean" number and category cards
- Review list (System Junk, Large & Old Files, Privacy): grouped rows with size bars, risk chips, bottom action bar
- Confirm sheet before real cleans; permanent delete is an unticked opt-in
- Menu-bar panel: ring gauges, battery, top memory, reclaimable space, Smart Scan button
- App icon regenerated in the new palette
- Fixes: per-pane selection, stable Space Lens colors, menu-bar Open works after closing the window, message cleared per pane
- Core: `totalBytes`, `groupByCategory` (+ test)
- Space Lens, Duplicates and Performance restyled (see round 2); every pane now follows the theme

#### Design pass, round 2: remaining panes
- Space Lens: breadcrumb navigation, hover highlight on tiles, ranked "largest items" panel beside the map
- Duplicates: glass groups with wasted size, Keeper chip, action bar with a "one copy always kept" note, empty state
- Performance: ring gauges, memory breakdown bar (app / wired / compressed / cached / free), top-process bar chart
- Shared `SmallButton`; `RingGauge` is resizable

#### Design pass, feedback round 1 (from first screenshots)
- Scanning: clock-driven orb (breathing glow, comet sweeping the ring, orbiting sparkles), determinate progress bar with a shimmer on the running stage, per-stage checklist, live "found so far" counter
- Results: count-up number, staggered card entrance
- Indeterminate `ScanBar` for single-pane scans (Junk, Large Files, Privacy, Duplicates, Uninstaller)
- Uninstaller rebuilt as full-height master/detail with search, app icons and a scrolling removal plan
- Login Items restyled to match (glass list, consistent padding)

#### M4: monitor and polish
- `SystemSampler` (memory, CPU, disk, battery, top processes) with tests
- Menu-bar extra with live CPU % and stats panel
- Performance pane
- App icon (`Resources/AppIcon.icns`, `make_icon.swift`)

#### M3: uninstaller, login items, privacy
- `AppUninstaller` with bundle-ID leftover matching (Apple apps excluded)
- `LoginItemScanner` (user agents removable, system read-only)
- `PrivacyScanner` for Safari/Chrome/Firefox; running browsers' history/cookies are protected

#### M2: analysis
- `SpaceLens` treemap view
- `DuplicateScanner` (size → 64 KB hash → SHA-256), keeper logic
- `PathPolicy` extra roots now refuse hidden folders and `Library`

#### M1: foundation
- `PathPolicy`, `Cleaner` (trash, dry run, JSONL log)
- `JunkScanner`, `LargeFileScanner`
- SwiftUI shell, Smart Scan, System Junk, Large & Old Files
- `build_app.sh` for an ad-hoc-signed `.app`

#### Housekeeping
- Moved from `~/TidyMac` to `~/Developer/Repositories/tidymac`
- Added README and `docs/`
