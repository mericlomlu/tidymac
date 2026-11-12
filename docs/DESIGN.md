# Design

The UI as built (1.0.0). Direction: playful and monochrome. Pane names are TidyMac's own: "Quick Scan" and "Disk Map" were renamed before the public release from names that matched another product's features.

## Visual language (`Theme.swift`)

Two variants of one monochrome theme. Every color is a dark/light pair (`Color(dark:light:)`), and the app follows the system appearance unless Settings says otherwise.

| | Dark | Light |
|---|---|---|
| Background (left → right) | `#000000 → #152331` | `#F7F9FB → #DCE3EA` |
| Accent gradient (buttons, rings, bars, logo) | `#FFFFFF → #D3DAE1 → #9AA7B4` | `#33414E → #1F2A35 → #0E151C` |
| Text / secondary / labels | `#F3F5F7` / `#A3ABB4` / `#8D96A0` | `#10161C` / `#55606B` / `#6A7480` |
| Ink (text on accent) | `#05080C` | `#FFFFFF` |
| Amber (signal) | `#FFC66B` | `#A85A00` |
| Veil (cards, strokes, glows) | white at 4–18 % | `#10161C` at 4–18 % |

- **Signal colour:** amber, and only for things that need care: Review chips, live ("Trash mode") state, the permanent-delete button, the Full Disk Access banner.
- The system accent colour is not used; the tint is the theme's text color.
- Treemap tiles stay slate with white labels in both variants.
- **Type:** system font; `.rounded` bold for headings and numbers. Sizes are fixed points.
- **Surfaces:** `glass()` cards (veil at 4–8 % with a 1 pt 11 % stroke), 18 pt radius for panels, 10–14 pt for controls. Pill buttons: primary (silver), secondary (glass), destructive (amber).
- **Motion:** clock-driven (`TimelineView` at 40 fps) and only while something is happening. At rest nothing animates. Reduce Motion stops the orb, shimmer, pulses and count-up.

## Shell

- One `Window` (default 1120×720, minimum 1000×660), hidden title bar. The sidebar's top padding clears the traffic lights.
- Custom sidebar, 232 pt: logo, three groups, and the dry-run badge pinned to the bottom. A small spinner marks a pane whose scan is running. The last pane is restored on launch.
- The sidebar collapses (⌃⌘S, or the button beside the logo) to a 76 pt icon rail: pane icons with tooltips, an amber dot on a scanning pane, and the dry-run badge as an icon. It never hides completely, so the safety state is always on screen.
- Settings (⌘,) is a standard grouped form: theme, menu-bar item, scan thresholds, and where the activity log is.
- Menus: View gets ⌘1…⌘9 for panes; a Scan menu holds Scan (⌘R), Stop Scan (⌘.), Select All Safe Items (⇧⌘A), Deselect All (⇧⌘D), Clean Selected Items (⌘⌫) and a Dry Run toggle.
- Menu-bar extra: CPU % label; panel with three ring gauges, battery, top memory, the "safe to clean" number and a Quick Scan button.

| Group | Panes |
|---|---|
| Cleanup | Quick Scan, System Junk, Large Files, Duplicates, Uninstaller |
| Analyze | Disk Map, Performance |
| Protect | Privacy, Login Items |

## Pane anatomy

Every pane uses the same stack: `PaneHeader` (32 pt title, one-line subtitle, small buttons on the right) → `ScanBar` while scanning → `PermissionBanner` if folders were unreadable → `StatusLine` with the last result → content → `ActionBar` when something can be cleaned.

- **Rows** (`SelectableRow`): checkbox, name, one line of context, risk chip, size, reveal button. Clicking the name area toggles the row.
- **Empty states** have three wordings: not scanned yet, scanning, and scanned with nothing found (checkmark icon, "Scan Again").
- **Action bar:** selected size, count, a sentence saying whether this previews or really cleans, and the button ("Preview clean" in dry run, "Clean" otherwise).

## Screens

- **Quick Scan:** start (still orb, one button, three chips) → scanning (spinning orb, three-stage bar and checklist, running total, Cancel) → results (count-up of what is safe, a line for what needs review, "Review and Clean" to the first pane with findings, "Scan Again", four category cards). With nothing found the hero reads "Nothing to clean".
- **System Junk / Large Files / Privacy** (`FindingsView`): grouped by category with a size bar per group. Junk and Privacy pre-tick Safe items; Large Files pre-ticks nothing.
- **Duplicates:** groups with copies, size each and wasted size; the oldest copy carries a Keeper chip and starts unticked. Cancel is available while comparing.
- **Uninstaller:** searchable app list on the left; on the right the removal plan for the chosen app (the app, then leftovers, with the app's own data marked Review).
- **Disk Map:** breadcrumb, treemap of the 40 largest children, ranked list beside it. Read-only.
- **Performance:** three gauges, memory breakdown bar, battery, top processes by memory.
- **Login Items:** one list; user items have a trash button that goes through the same confirm flow, system items are read-only.

## Safety in the UI

- **Dry run** is visible in the sidebar on every pane ("Dry run on · Preview only" or amber "Trash mode · Live"), on the Quick Scan screen (a note in its own row under the content, so it never covers a button or card; the results scroll if the window is too short), in the menu-bar panel and in every action bar. Turning it off shows an alert first.
- **Confirm sheet** before any real clean: what and how much, by category; an unticked "Delete permanently" checkbox that turns the icon and button amber. The default button is Cancel.
- **Results** are stated plainly, including what was skipped and why.

## Not designed

Dynamic Type, progress percentage for Duplicates. The light theme and the Turkish layout were built from the palette and the string list and have not been reviewed by eye. See DECISIONS.md.
