# Safety

A cleaner's worst bug is deleting something that mattered. These rules are enforced in code and covered by tests (`Tests/TidyCoreTests`, mostly `SafetyTests.swift`).

## Rules

1. **Scan → review → confirm.** Scanners never delete. The user ticks rows and presses a button.
2. **Dry run by default.** `AppModel.dryRun` is `true` at every launch (not persisted) and can only be turned off through `setDryRun`, which shows a confirmation. Dry run logs `dry-run` entries and touches nothing.
3. **Trash by default.** `FileManager.trashItem`. Permanent delete is an unticked checkbox in the confirm sheet.
4. **One gate.** `Cleaner.clean` calls `PathPolicy.isDeletable` for every item; failures are returned in `skipped`, never deleted. `Cleaner.clean` is the only code that removes anything.
5. **One request path.** In the app every removal goes through `AppModel.submit`: a preview in dry run, the confirm sheet otherwise. There is no direct delete button.
6. **Log every action.** `~/Library/Application Support/TidyMac/log.jsonl`, one JSON object per line: time, action (`dry-run`/`trashed`/`deleted`), path, bytes, category. If the log cannot be written the clean still happens and the result message says so.

## PathPolicy

**What is checked.** The item a removal would act on: symlinks are resolved in the *parent* folder and the last component is kept as is, because removing a symlink removes the link, not its target. So a link is judged by where it lives, and a path that reaches a protected place through a linked folder is refused. Paths containing `.` or `..` are refused outright.

**Always blocked:** `/`, the home folder itself, and anything under `/System /usr /bin /sbin /private/var/db /Library/Apple /etc /dev /cores`. If the home folder is `/`, everything is blocked.

**Never removable, even inside an allowed root** (user data stores):
- any `*.photoslibrary` and its contents
- `Library/Group Containers/group.com.apple.notes`
- `Library/Application Support/AddressBook`
- `Library/Application Support/MobileSync` (iPhone backups)

**Allowed** (strictly *inside* these, never the root itself), relative to home:
`Library/{Caches, Logs, Application Support, Preferences, Containers, Group Containers, Saved Application State, LaunchAgents, HTTPStorages, WebKit, Safari}`, `Library/Developer/Xcode/{DerivedData, Archives, iOS DeviceSupport}`, `Library/Developer/CoreSimulator/Caches`, `.npm/_cacache`, `.cache`, `Downloads, Desktop, Documents, Movies, Music, Pictures`, `.Trash`.
Plus: top-level `*.app` in `/Applications` and `~/Applications`.

**Extra roots.** Callers can pass `extraRoots` (Duplicates and Large Files pass the home folder). An extra root is ignored unless it is the home folder or inside it. Under an extra root, any hidden path component (`.ssh`, `.gnupg`, …) and anything under `Library` is refused.

**Case.** Deny rules compare case-insensitively (the default file system does); allow rules compare exactly.

The allowed roots are broad: inside `Documents` or `Application Support` the policy only stops the listed data stores. What protects everything else there is that scanners only *offer* specific things and the user ticks them.

## Per-feature guards

- **Duplicates:** never removes every copy in a group (`DuplicateGroup.removable`; if all are selected, the oldest is kept). Skips `Library`, hidden folders (`.git`, `.Trash`, …) and `node_modules`. A file that cannot be read in full is left out rather than compared. Hard links to one file are not duplicates.
- **Large Files:** lists only files the policy would allow removing. Nothing is pre-ticked.
- **Uninstaller:** Apple apps (`com.apple.*`) are never listed. Exact bundle-ID matches are `safe` and pre-selected, except in `Containers` and `Group Containers`, which hold the app's own documents and are `review`. Prefix/suffix and app-name matches are `review` and start unticked.
- **Privacy:** bookmarks are never offered (Firefox `places.sqlite` mixes them with history, so it is left alone). History/cookie databases of a *running* browser are left out with a message; caches are still cleaned.
- **Login Items:** only `~/Library/LaunchAgents` plists are removable; `/Library/*` items are read-only. After a real removal the agent is stopped with `launchctl bootout gui/<uid>/<label>` (`LaunchAgentUnloader`). That command only ever addresses the current user's own session, runs only for an item whose plist was just trashed, never in dry run, and refuses labels that are not plain reverse-DNS names. It removes no files.
- **Disk Map, Performance, menu bar:** read-only.
- **Confirm sheet:** item summary, size, "delete permanently" unticked. Return and Escape cancel; the delete button needs a click.

## Known gaps

- The policy and extra roots are chosen by the caller. The app only ever uses the default policy, with the home folder as the one extra root.
- Check-then-act: the policy check and the removal are separate steps. Acceptable for a single-user local tool.
- The Trash path is not unit-tested, because a test would write to the real `~/.Trash`. Dry run, permanent delete and every refusal are tested.
- Without Full Disk Access some folders cannot be read; the app shows a banner but cannot scan them.
- Trashing apps in `/Applications` may prompt for admin rights, and the app does not check whether the app being removed is running.
- No recovery UI: restoring means using Finder's Put Back. A launch agent that was stopped is not restarted by putting its plist back; it starts again at next login.
- Settings can change scan thresholds and appearance only. Nothing in Settings affects what may be deleted, and dry run cannot be switched off there.
- Loose Uninstaller matches can be wrong; that is why they start unticked.
