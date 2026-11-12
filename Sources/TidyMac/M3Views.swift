import SwiftUI
import TidyCore

// MARK: Uninstaller

/// App icons are slow to load, so each one is fetched once and kept.
@MainActor
enum AppIcons {
    private static var cache: [URL: NSImage] = [:]
    static func icon(for url: URL) -> NSImage {
        if let hit = cache[url] { return hit }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url] = image
        return image
    }
}

/// Full-height master/detail: app list on the left, everything that would be removed on the right.
struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var filtered: [InstalledApp] {
        query.isEmpty ? model.apps
            : model.apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let scanning = model.isScanning(.uninstall)
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: Pane.uninstall.title,
                       subtitle: String(localized: "\(model.apps.count) apps, \(formatBytes(model.apps.reduce(0) { $0 + $1.size })). Apple apps are never listed.")) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.label)
                    TextField("Search apps", text: $query).textFieldStyle(.plain).foregroundStyle(Theme.text).frame(width: 180)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.veil(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.veil(0.14), lineWidth: 1))
                SmallButton(title: "Refresh") { model.scan(.uninstall) }.disabled(scanning)
            }
            if scanning { ScanBar() }
            StatusLine()
            HStack(alignment: .top, spacing: 16) {
                appList(scanning: scanning).frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
                planPanel.frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Theme.pane)
        .task { if !model.hasScanned(.uninstall) { model.scan(.uninstall) } }
    }

    private func appList(scanning: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { a in
                    let on = model.selectedApp?.id == a.id
                    Button { model.choose(a) } label: {
                        HStack(spacing: 12) {
                            Image(nsImage: AppIcons.icon(for: a.url)).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Text(a.bundleID).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 6)
                            Text(formatBytes(a.size)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.chipText)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.veil(0.13) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if filtered.isEmpty {
                    Text(scanning ? "Looking for apps…" : model.apps.isEmpty ? "No third-party apps found." : "No apps match.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.top, 40)
                }
            }
            .padding(8)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
        .glass(radius: 18, fill: 0.05)
    }

    @ViewBuilder private var planPanel: some View {
        if let app = model.selectedApp {
            PlanPanel(app: app)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "xmark.app").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.label)
                Text("Select an app").font(Theme.heading(22)).foregroundStyle(Theme.text)
                Text("See everything an app leaves behind before you remove it.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(radius: 18, fill: 0.04)
        }
    }
}

/// Everything removing one app would take, with the app's own data left unticked.
private struct PlanPanel: View {
    @Environment(AppModel.self) private var model
    let app: InstalledApp

    var body: some View {
        let picked = model.plan.filter { model.selected.contains($0.url) }
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: AppIcons.icon(for: app.url)).resizable().frame(width: 52, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove \(app.name)").font(Theme.heading(22)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(model.plan.isEmpty ? "\(app.bundleID) · looking for leftovers…"
                         : "\(app.bundleID) · \(model.plan.count) items, \(formatBytes(totalBytes(model.plan)))")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(16)
            Text("The app and the files it left behind. The app's own documents and loose matches are marked Review and start unticked. Quit the app before removing it.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.plan) { f in SelectableRow(finding: f, subtitle: f.category) { RiskChip(risk: f.risk) } }
                }
            }
            .scrollIndicators(.never)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatBytes(totalBytes(picked))) selected").font(Theme.heading(20)).foregroundStyle(Theme.text)
                    Text("\(picked.count) of \(model.plan.count) items").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button(model.dryRun ? "Preview uninstall" : "Uninstall") { model.cleanSelection(in: .uninstall) }
                    .buttonStyle(PillButtonStyle(height: 46)).disabled(picked.isEmpty || model.cleaning)
            }
            .padding(16)
            .background(Theme.veil(0.05))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(radius: 18, fill: 0.05)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: Login items

struct LoginItemsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: String(localized: "Login Items & Launch Agents"),
                       subtitle: String(localized: "Background items that start automatically. Removing a user item moves it to the Trash and stops it. System items are read-only.")) {
                SmallButton(title: "Refresh") { model.scan(.login) }.disabled(model.isScanning(.login))
            }
            StatusLine()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.launchItems) { i in row(i) }
                    if model.launchItems.isEmpty {
                        Text(model.isScanning(.login) ? "Looking for login items…" : "No login items or launch agents found.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.top, 40)
                    }
                }
            }
            .scrollIndicators(.never)
            .glass(radius: 18, fill: 0.05)
        }
        .padding(Theme.pane)
        .onAppear { model.scan(.login) }
    }

    private func row(_ i: LaunchItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(i.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(i.program).font(.system(size: 12)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if i.runAtLoad { Chip(text: "at login", kind: .neutral) }
            Text(i.removable ? "User" : "System").font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(width: 48, alignment: .trailing)
            RevealButton(url: i.url)
            Button { model.requestRemove(i) } label: {
                Image(systemName: "trash").foregroundStyle(i.removable ? Theme.chipText : Theme.label.opacity(0.4))
            }
            .buttonStyle(.plain).disabled(!i.removable || model.cleaning)
            .help(i.removable ? (model.dryRun ? "Preview moving this item to the Trash" : "Move to Trash (asks first)") : "System items are read-only")
            .accessibilityLabel(i.removable ? "Move \(i.label) to Trash" : "\(i.label) is a system item and cannot be removed")
        }
        .padding(.horizontal, 16).frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(Theme.veil(0.06)).frame(height: 1) }
    }
}
