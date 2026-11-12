# Decisions and known issues

## Decisions

| Decision | Why |
|---|---|
| Native SwiftUI, not Electron | Finder/trash/Full Disk Access integration, small, fast, native look |
| SwiftPM only, no `.xcodeproj` | Easy to build from the CLI and from Claude; `build_app.sh` wraps the bundle |
| Core/UI split (`TidyCore` / `TidyMac`) | Logic is testable without UI; safety rules live where tests can hit them |
| Not sandboxed, ad-hoc signed | A sandbox would block the folders a cleaner must read; notarization needs a paid Apple developer account, so downloads are opened once through "Open Anyway" |
| Universal binary (arm64 + x86_64) | The release zip should run on any Mac with macOS 14+; costs a few MB and a deprecation warning from newer toolchains |
| Pane names "Quick Scan" and "Disk Map" | The earlier names matched feature names of a commercial cleaner; a public project should use its own |
| Trash by default, dry run by default | Reversible first; a cleaner's worst failure is irreversible loss |
| One central `PathPolicy` | Single place to audit; modules can't bypass it |
| Scanners parameterised by root/home | Tests use temp dirs, never the real home folder |
| `ps` for top processes | Simple and good enough; avoids private APIs |
| No "Free RAM" / `purge` | macOS manages memory; purging slows the machine and needs admin |
| No malware scanner | A DIY one gives false confidence |
| Tests run with `DEVELOPER_DIR` set to Xcode.app | Active dir is Command Line Tools, which lacks XCTest; avoids changing system settings |
| Repo named `tidymac` in `~/Developer/Repositories` | Matches the lowercase kebab-case convention of the other repos |
| All rights reserved; source visible as a portfolio project | Readable and runnable, not offered for reuse; the licence can be loosened later but not taken back |
| Public version numbering starts at 1.0.0 | The repository was re-created for the public release; the private build numbers (up to 1.1.2) were never published and live on only in the changelog |

## Divergence from the original plan

- Quick Scan runs System Junk, Large Files and Privacy. Disk Map is interactive and Duplicates is slow, so neither is part of it.
- "Large & Old Files" became "Large Files": an age filter was planned but never wired up, so the name promised something the pane did not do.
- Memory "Free RAM" button dropped (see above).
- Login Items lists LaunchAgents/Daemons only; apps registered through `SMAppService` or System Settings login items are not visible to other apps via public API.
- Treemap is slice-and-dice, not squarified.
- Firefox history is not offered: its file also holds bookmarks.

## Decisions from the finalization review (2026-11-12)

| Decision | Why |
|---|---|
| Symlinks resolved in the parent only | The removal acts on the link, so the link's location is what must be allowed |
| `..` refused rather than collapsed | Collapsing it as text and following it on disk can disagree when a symlink is involved |
| Deny-list inside allowed roots | `Pictures` and `Application Support` must stay cleanable, but Photos, Notes, Contacts and backups must never be |
| Return cancels the confirm sheet | A reflex key press should never delete |
| Dry run not persisted, and off needs a confirmation | The safe state should be the one you get without thinking |
| A cancelled scan keeps the previous results | Half a scan would look like "nothing else found" |
| Follows the system appearance by default; the tint is the theme's own | Light and dark are both designed; the system accent would fight a monochrome theme |
| Sidebar collapses to an icon rail instead of disappearing | The dry-run state must stay on screen in every layout |
| Dry run is not in Settings | The safe state should not be something a forgotten preference can switch off |
| Turkish is the second language | It is the other language this Mac is set to use |
| String catalog compiled by `build_app.sh`, not a SwiftPM resource | A SwiftPM resource bundle sits at the app's root, which breaks code signing; `.lproj` folders in `Contents/Resources` are what macOS expects |
| Strings extracted by the compiler (`localize.sh`) | Text-based extractors missed most SwiftUI strings and got number placeholders wrong |
| `launchctl bootout` only after a successful removal | Stopping an agent whose plist is still installed would just have it come back at next login |
| No linter or formatter added | One person, small codebase; the review checked force unwraps and swallowed errors by hand |

## Known issues

1. **Duplicates** shows no percentage: the scan can be cancelled but not measured.
2. **No UI/model tests.** TidyCore has 49 tests; the app target has none, so `AppModel` logic is checked by hand.
3. **Uninstaller** does not check whether the app is running before removing it.
4. **Fixed font sizes** (no Dynamic Type).
5. **Sizes are scan-time sizes;** hard links and APFS clones are counted once per path in Junk, Large Files and Disk Map.
6. **Not checked by eye:** the light theme, the Turkish layout (longer words may truncate in narrow spots), VoiceOver, and a real Trash clean. See SAFETY.md for what the tests do cover.
7. **Turkish plurals** use the same word for one and many, which is correct after a number; a language with real plural forms would need plural variants in the catalog.
8. **A stopped launch agent is not restarted** if its plist is put back from the Trash; it starts again at next login.
9. **Not notarized:** a downloaded copy is blocked by Gatekeeper until "Open Anyway" is used once, and the ad-hoc signature means Full Disk Access is forgotten when the app is replaced by a new build.
10. **The Intel slice is untested:** it is built and signed, but has not been run on an Intel Mac.

## Fixed earlier (design pass, 2026-11-12)

- Selection is still one shared set, but each scan now only replaces its own pane's entries.
- Disk Map colors are stable between launches (djb2 hash instead of `hashValue`) and now slate tints.
- Menu-bar "Open TidyMac" works after the window is closed (single-instance `Window` scene + `openWindow`).
- The status message is cleared when switching panes.
- Real cleans go through a confirm sheet (permanent delete is an unticked opt-in there).
