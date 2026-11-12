# Architecture

SwiftPM package, no Xcode project. Swift 6 language mode, macOS 14+.

```
Package.swift
Sources/
  TidyCore/        library: no UI, fully testable
  TidyMac/         executable: SwiftUI app
Tests/TidyCoreTests/
Resources/         AppIcon.icns, Localizable.xcstrings (all UI text, English + Turkish)
build_app.sh       wraps the release binary into build/TidyMac.app
localize.sh        refreshes the string catalog from the source code
make_icon.swift    renders Resources/AppIcon.icns
```

## TidyCore (logic)

| File | Contents |
|---|---|
| `Models.swift` | `Finding`, `Risk` (`safe`/`review`), `FindingGroup`, `groupByCategory`, `totalBytes`, `formatBytes`, `displayPath`, `allocatedSize(of:)`, `offMain` (cancellable background work) |
| `PathPolicy.swift` | The single deletion gate (see SAFETY.md) |
| `Cleaner.swift` | `Cleaner` (trash/delete through `PathPolicy`, dry-run, JSONL log), `CleanResult` (removed, skipped with reasons, `summary`) |
| `Scanners.swift` | `JunkScanner`, `LargeFileScanner` |
| `Duplicates.swift` | `DuplicateScanner`, `DuplicateGroup` (keeper rule lives here) |
| `SpaceLens.swift` | `SpaceLens.children(of:)` sizes, `SpaceLens.layout` treemap (slice-and-dice, no aspect-ratio optimisation) |
| `M3Scanners.swift` | `AppUninstaller`, `LoginItemScanner`, `PrivacyScanner`, `Browser` |
| `LaunchAgentUnloader.swift` | Stops a removed user launch agent via `launchctl bootout` (injectable runner for tests) |
| `PermissionCheck.swift` | Finds protected folders that cannot be read without Full Disk Access |
| `SystemStats.swift` | `SystemSampler`: mach `host_statistics64` memory, `host_statistics` CPU delta, volume capacity, IOKit battery, `ps` top processes |

Pattern: scanners only *find* and return `Finding`s. Nothing in a scanner deletes. All removal goes through `Cleaner.clean(_:)`.

Scanners take `home:`/`root:` parameters so tests run against temp directories, never the real home folder.

Long scans run through `offMain`: a detached task that is cancelled when the calling task is. Walk loops poll `Task.isCancelled` and return early.

## TidyMac (UI)

| File | Contents |
|---|---|
| `TidyMacApp.swift` | `@main` app (single `Window` + `MenuBarExtra`), `TidyCommands` (menus and shortcuts), `ContentView`, `SidebarView`, `DryRunBadge` |
| `AppModel.swift` | `Pane`, `PaneGroup`, `PendingClean`, `AppModel` |
| `SettingsView.swift` | The Settings window |
| `Theme.swift` | Dark/light color pairs, `Prefs` (UserDefaults keys), `Appearance`, `themed()`, gradients, `glass`, `PillButtonStyle`, `Chip`, `CheckBox`, `LogoTile`, and the shared pane pieces: `PaneHeader`, `SelectableRow`, `ActionBar`, `StatusLine`, `PermissionBanner`, `GaugeTile`, `BatteryRow` |
| `SmartScanViews.swift` | `SmartScanView` (start / scanning / results), `Orb`, `CategoryCard`, `ScanBar`, `DryRunNote` |
| `FindingsViews.swift` | `FindingsView` (review list for Junk, Large Files, Privacy), `ConfirmSheet` |
| `M2Views.swift` | `SpaceLensView`, `DuplicatesView` |
| `M3Views.swift` | `UninstallerView`, `LoginItemsView`, `AppIcons` cache |
| `MonitorViews.swift` | `Monitor` (sampling loop), `RingGauge`, `MenuBarContent` |
| `PerformanceView.swift` | Gauges, memory breakdown bar, process bar chart (data from `Monitor`) |

State:
- `AppModel` (`@Observable`, `@MainActor`): results per pane, one shared `selected: Set<URL>`, which scans are `active` and which panes have been `scanned`, `cleaning`, `dryRun`, the status `message`, and `unreadable` folders. Created once in the App, injected via `.environment`.
- `Monitor` (`@Observable`, `@MainActor`): starts sampling in `init()`; a detached task owns its own `SystemSampler` and publishes a snapshot every 2 s. `ps` runs only while a view showing processes is on screen (`processViewers`).

## Data flow

```
Scan button / ⌘R → AppModel.scan(pane) → one Task per pane → TidyCore scanner (off the main actor) → results adopted unless cancelled
user ticks rows  → model.selected
Clean button / ⌘⌫ → AppModel.cleanSelection(in:) → (running-browser guard, keeper rule) → submit
submit → dry run: perform now · otherwise: PendingClean → ConfirmSheet → perform
perform → Cleaner(dryRun, permanent, extraRoots).clean off the main actor → PathPolicy → trash/delete + log → CleanResult.summary → model.message
```

## Preferences

`Prefs` (in `Theme.swift`) holds the UserDefaults keys: appearance, menu-bar item, sidebar collapsed, and the two scan thresholds. Views bind to them with `@AppStorage`; `AppModel` reads the thresholds when a scan starts. Dry run is not stored.

## Localisation

Text in views is a `LocalizedStringKey` literal; text built in code uses `String(localized:)`, in `TidyCore` as well (the lookup goes to the app bundle). Shared components take already-localised `String`s, except `SmallButton` and `Chip(text:)`, which take keys.

`localize.sh` builds with `-emit-localized-strings`, so the compiler lists every localisable string, and `xcstringstool sync` merges that list into `Resources/Localizable.xcstrings`. `build_app.sh` compiles the catalog into `.lproj` folders inside the app. The package itself declares no resources: `swift run` and the tests simply show English.

Words are never assembled from fragments. Where English needs a singular and a plural there are two full sentences ("1 item", "%lld items"), each translated as a whole.

## Build output

`build_app.sh` quits a running TidyMac, runs `swift build -c release`, copies the binary into `build/TidyMac.app`, compiles the string catalog into `Contents/Resources/<lang>.lproj`, writes `Info.plist` (bundle id `local.tidymac`, version, min macOS 14, utilities category, icon, localisations), signs (ad hoc, or with `TIDYMAC_SIGN_ID`) and verifies the signature. No entitlements, no sandbox.
