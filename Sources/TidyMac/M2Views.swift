import SwiftUI
import TidyCore

// MARK: Disk Map

struct SpaceLensView: View {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    @State private var path: [URL] = [SpaceLensView.home]
    @State private var nodes: [SpaceNode] = []
    @State private var loading = false

    private var current: URL { path.last ?? Self.home }
    private var total: Int64 { nodes.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if loading { ScanBar() }
            HStack(alignment: .top, spacing: 16) {
                treemap.frame(maxWidth: .infinity, maxHeight: .infinity)
                largest.frame(width: 300).frame(maxHeight: .infinity)
            }
            Text("Click a folder to drill in. Right-click a block to reveal it in Finder. Disk Map is read-only.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .padding(Theme.pane)
        .task(id: current) {
            // Leaving the folder cancels this task, which stops the sizing job for it.
            loading = true; nodes = []
            let found = await SpaceLens.children(of: current)
            guard !Task.isCancelled else { return }
            nodes = found
            loading = false
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Map").font(Theme.heading(32)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Button { if path.count > 1 { path.removeLast() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(path.count > 1 ? Theme.chipText : Theme.label.opacity(0.4))
                    .disabled(path.count < 2).accessibilityLabel("Back")
                    ForEach(Array(path.enumerated()), id: \.offset) { i, u in
                        if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.label) }
                        Button(i == 0 ? String(localized: "Home") : u.lastPathComponent) { path = Array(path.prefix(i + 1)) }
                            .buttonStyle(.plain)
                            .font(.system(size: 14, weight: i == path.count - 1 ? .semibold : .regular))
                            .foregroundStyle(i == path.count - 1 ? Theme.text : Theme.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatBytes(total)).font(Theme.heading(26)).foregroundStyle(Theme.accent)
                Text("in this folder").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var treemap: some View {
        GeometryReader { geo in
            let top = Array(nodes.prefix(40))
            let rects = SpaceLens.layout(sizes: top.map(\.size), in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(top.enumerated()), id: \.element.id) { i, n in
                    TreemapTile(node: n, rect: rects[i].insetBy(dx: 2, dy: 2)) { if n.isDirectory { path.append(n.url) } }
                }
                if top.isEmpty && !loading {
                    Text("Nothing here").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .padding(6)
        .glass(radius: 18, fill: 0.04)
    }

    private var largest: some View {
        let biggest = max(nodes.first?.size ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text("LARGEST ITEMS").font(.system(size: 11, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.label).padding(16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(nodes.prefix(14)) { n in
                        Button { if n.isDirectory { path.append(n.url) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: n.isDirectory ? "folder" : "doc").foregroundStyle(Theme.label).frame(width: 16)
                                    Text(n.url.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(formatBytes(n.size)).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.chipText)
                                }
                                GeometryReader { geo in
                                    Capsule().fill(Theme.veil(0.08))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(Theme.accent).frame(width: max(3, geo.size.width * CGFloat(n.size) / CGFloat(biggest)))
                                        }
                                }.frame(height: 4)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([n.url]) } }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(radius: 18, fill: 0.05)
    }
}

struct TreemapTile: View {
    let node: SpaceNode
    let rect: CGRect
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onOpen) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(shade)
                .overlay(alignment: .topLeading) {
                    if rect.width > 70 && rect.height > 36 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(node.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(formatBytes(node.size)).font(.system(size: 11)).opacity(0.8)
                        }.padding(7).foregroundStyle(.white)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.veil(hover ? 0.75 : 0.08), lineWidth: hover ? 2 : 1))
        }
        .buttonStyle(.plain)
        .frame(width: max(rect.width, 0), height: max(rect.height, 0))
        .offset(x: rect.minX, y: rect.minY)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } }
        .help("\(node.url.path)\n\(formatBytes(node.size))")
        .accessibilityLabel("\(node.url.lastPathComponent), \(formatBytes(node.size))")
        .accessibilityHint(node.isDirectory ? "Opens this folder" : "")
    }

    /// Stable per-name slate shade (String.hashValue is randomised per launch). Folders lighter than files.
    private var shade: Color {
        var h: UInt32 = 5381
        for b in node.url.lastPathComponent.utf8 { h = h &* 33 &+ UInt32(b) }
        let t = Double(h % 100) / 100
        return Color(hue: 0.58, saturation: 0.10 + 0.08 * t, brightness: (node.isDirectory ? 0.42 : 0.28) + 0.22 * t)
    }
}

// MARK: Duplicates

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let scanning = model.isScanning(.dupes)
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: Pane.dupes.title, subtitle: model.duplicates.isEmpty
                       ? String(localized: "Files of \(formatBytes(Prefs.duplicateBytes)) or more with identical content (SHA-256). The oldest copy is kept.")
                       : String(localized: "\(model.duplicates.count) groups, \(formatBytes(model.duplicateWaste)) wasted. The oldest copy in each group is kept.")) {
                if scanning {
                    SmallButton(title: "Cancel") { model.cancelScan(.dupes) }
                } else if !model.duplicates.isEmpty {
                    SmallButton(title: "Rescan") { model.scan(.dupes) }
                }
            }
            if scanning { ScanBar() }
            StatusLine()
            if model.duplicates.isEmpty { emptyState(scanning: scanning) } else { list; actionBar }
        }
        .padding(Theme.pane)
    }

    private func emptyState(scanning: Bool) -> some View {
        let done = model.hasScanned(.dupes)
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: done && !scanning ? "checkmark.circle" : "doc.on.doc")
                .font(.system(size: 40, weight: .light)).foregroundStyle(Theme.label)
            Text(scanning ? "Comparing files…" : done ? "No duplicates found" : "Not scanned yet")
                .font(Theme.heading(22)).foregroundStyle(Theme.text)
            Text("This reads every large file in your home folder, so it can take a few minutes. You can cancel at any time.")
                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
            if scanning {
                Button("Cancel") { model.cancelScan(.dupes) }.buttonStyle(PillButtonStyle(kind: .secondary, height: 48))
            } else {
                Button(done ? "Scan Again" : "Scan Home Folder") { model.scan(.dupes) }.buttonStyle(PillButtonStyle(height: 48))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.duplicates) { g in
                    HStack(spacing: 10) {
                        Text("\(g.files.count) COPIES").font(.system(size: 12, weight: .semibold)).tracking(0.7)
                            .foregroundStyle(Theme.dim)
                        Text("\(formatBytes(g.size)) each").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(formatBytes(g.wasted)) wasted").font(Theme.heading(14)).foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 16).frame(height: 34).background(Theme.veil(0.05))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    ForEach(g.files) { f in
                        SelectableRow(finding: f, subtitle: displayPath(f.url.deletingLastPathComponent()), showSize: false) {
                            if f.url == g.id { Chip(text: "Keeper", kind: .neutral) }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .glass(radius: 18, fill: 0.05)
    }

    private var actionBar: some View {
        let picked = model.selectedDuplicates
        return ActionBar(pane: .dupes, title: String(localized: "\(formatBytes(totalBytes(picked))) selected"),
                         detail: picked.count == 1 ? String(localized: "1 copy. At least one copy of every file is always kept.")
                             : String(localized: "\(picked.count) copies. At least one copy of every file is always kept."),
                         enabled: !picked.isEmpty)
    }
}
