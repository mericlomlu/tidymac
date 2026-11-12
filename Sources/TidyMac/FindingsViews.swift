import SwiftUI
import TidyCore

/// Review list used by System Junk, Large Files and Privacy.
struct FindingsView: View {
    @Environment(AppModel.self) private var model
    let pane: Pane
    let intro: String

    var body: some View {
        let items = model.findings(in: pane)
        let scanning = model.isScanning(pane)
        VStack(alignment: .leading, spacing: 14) {
            header(items, scanning: scanning)
            if scanning { ScanBar() }
            PermissionBanner()
            StatusLine()
            if items.isEmpty {
                emptyState(scanning: scanning)
            } else {
                ScrollView { groupsList(items).padding(.bottom, 4) }
                    .scrollIndicators(.never)
                    .glass(radius: 18, fill: 0.05)
                actionBar(items)
            }
        }
        .padding(Theme.pane)
    }

    // MARK: Pieces

    private func header(_ items: [Finding], scanning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { model.pane = .smart } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)); Text("Quick Scan") }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.soft)
            }.buttonStyle(.plain)
            PaneHeader(title: pane.title, subtitle: subtitle(items)) {
                if !items.isEmpty {
                    SmallButton(title: "Select all Safe") { model.selectAllSafe(in: pane) }
                    SmallButton(title: "Select none") { model.selectNone(in: pane) }
                    SmallButton(title: "Rescan") { model.scan(pane) }.disabled(scanning)
                }
            }
        }
    }

    private func subtitle(_ items: [Finding]) -> String {
        if !items.isEmpty { return String(localized: "\(formatBytes(totalBytes(items))) found.") + " " + intro }
        return model.hasScanned(pane) ? String(localized: "Nothing found in the last scan.") : String(localized: "Not scanned yet.")
    }

    private func emptyState(scanning: Bool) -> some View {
        let done = model.hasScanned(pane)
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: done && !scanning ? "checkmark.circle" : pane.icon)
                .font(.system(size: 40, weight: .light)).foregroundStyle(Theme.label)
            Text(scanning ? "Scanning…" : done ? "Nothing to clean here" : "Not scanned yet")
                .font(Theme.heading(22)).foregroundStyle(Theme.text)
            Text("Scans only read your files. Nothing is changed until you confirm a clean.")
                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            Button(done ? "Scan Again" : "Scan \(pane.title)") { model.scan(pane) }
                .buttonStyle(PillButtonStyle(height: 48)).disabled(scanning)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func groupsList(_ items: [Finding]) -> some View {
        let groups = groupByCategory(items)
        let biggest = max(groups.first?.size ?? 1, 1)
        return LazyVStack(spacing: 0) {
            ForEach(groups) { g in
                HStack(spacing: 12) {
                    Text(g.name.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.7)
                        .foregroundStyle(Theme.dim).lineLimit(1).frame(width: 150, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Theme.veil(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.accent).frame(width: max(6, geo.size.width * CGFloat(g.size) / CGFloat(biggest)))
                            }
                    }.frame(height: 6).accessibilityHidden(true)
                    Text(formatBytes(g.size)).font(Theme.heading(14)).foregroundStyle(Theme.text)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 16).frame(height: 34).background(Theme.veil(0.05))
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                ForEach(g.items) { f in
                    SelectableRow(finding: f, subtitle: displayPath(f.url.deletingLastPathComponent())) { RiskChip(risk: f.risk) }
                }
            }
        }
    }

    private func actionBar(_ items: [Finding]) -> some View {
        let picked = items.filter { model.selected.contains($0.url) }
        return ActionBar(pane: pane, title: String(localized: "\(formatBytes(totalBytes(picked))) selected"),
                         detail: String(localized: "\(picked.count) of \(items.count) items."), enabled: !picked.isEmpty)
    }
}

/// Shown before any real (non dry-run) clean. Return cancels; deleting always takes a deliberate click.
struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    let pending: PendingClean
    @State private var permanent = false

    var body: some View {
        let groups = groupByCategory(pending.items)
        let count = pending.items.count
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(permanent ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.tile(0))).frame(width: 52, height: 52)
                    .overlay { Image(systemName: permanent ? "exclamationmark.triangle" : "trash")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.ink) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permanent ? "Delete \(formatBytes(pending.bytes)) permanently?" : "Move \(formatBytes(pending.bytes)) to the Trash?")
                        .font(Theme.heading(24)).foregroundStyle(Theme.text)
                    Text(verbatim: (count == 1 ? String(localized: "1 item from \(pending.label).")
                                               : String(localized: "\(count) items from \(pending.label)."))
                         + " " + (permanent ? String(localized: "This cannot be undone.")
                                            : String(localized: "You can put them back until you empty the Trash.")))
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
            }
            VStack(spacing: 0) {
                ForEach(groups.prefix(5)) { g in
                    HStack {
                        Text("\(g.name) (\(g.items.count))").foregroundStyle(Theme.soft)
                        Spacer()
                        Text(formatBytes(g.size)).fontWeight(.semibold).monospacedDigit().foregroundStyle(Theme.text)
                    }.font(.system(size: 14)).frame(height: 30)
                }
                if groups.count > 5 {
                    Text("and \(groups.count - 5) more categories").font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(height: 24)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8).glass(radius: 14)

            Toggle("Delete permanently instead. Skips the Trash and cannot be undone.", isOn: $permanent)
                .toggleStyle(.checkbox).tint(Theme.amber).font(.system(size: 13)).foregroundStyle(Theme.dim)

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Text("Every action is logged to log.jsonl").font(.system(size: 12)).foregroundStyle(Theme.faint)
                Spacer()
                Button(permanent ? "Delete Permanently" : "Move to Trash") { Task { await model.perform(pending, permanent: permanent) } }
                    .buttonStyle(PillButtonStyle(kind: permanent ? .destructive : .secondary, height: 46))
                Button("Cancel") { model.pending = nil }
                    .buttonStyle(PillButtonStyle(height: 46)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 440)
        .background(AppBackground())
        .themed()
        .onExitCommand { model.pending = nil }
    }
}
