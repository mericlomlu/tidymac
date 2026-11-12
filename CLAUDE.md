# tidymac: notes for Claude

Personal, local-only macOS cleaner (SwiftUI + SwiftPM). Read `docs/ARCHITECTURE.md` and `docs/SAFETY.md` before changing anything that deletes.

## Commands

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # XCTest needs Xcode.app
./build_app.sh && open build/TidyMac.app                              # build, bundle, run
pkill -x TidyMac                                                      # quit before relaunching
```

## Rules

- Anything that removes files must go through `Cleaner.clean`, which enforces `PathPolicy`. Never call `removeItem`/`trashItem` elsewhere.
- Scanners only find; they never delete.
- Don't widen `PathPolicy.allowedRoots` without adding a test in `TidyCoreTests`.
- Tests must use temp dirs via the `home:`/`root:` parameters. Never touch the real home folder.
- Keep new logic in `TidyCore`; `TidyMac` is UI and state only.
- Don't run the app with dry run off against real data when testing; use fixtures.
- Swift 6 mode: avoid mutable globals; the `Section` name is SwiftUI's (the sidebar enum is `Pane`).
- Git: repository on GitHub (`origin`), shown publicly as a portfolio project. Don't commit or push unless asked, and commit only with the GitHub no-reply email.
- User-facing text: `LocalizedStringKey` literals in views, `String(localized:)` everywhere else, never glued together from fragments. After changing any, run `./localize.sh` and add the Turkish translation to `Resources/Localizable.xcstrings`; a test fails while one is missing.
- Colors come from `Theme` (dark/light pairs). No fixed `.white`/`.black` in views.

## Docs to keep current

Update `CHANGELOG.md`, and `docs/DECISIONS.md` (known issues) when behaviour changes; update `docs/DESIGN.md` after UI changes.
