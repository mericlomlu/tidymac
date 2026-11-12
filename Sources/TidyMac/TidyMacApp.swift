import SwiftUI
import TidyCore

@main
struct TidyMacApp: App {
    @State private var model = AppModel()
    @State private var monitor = Monitor()
    @AppStorage(Prefs.showMenuBarExtra) private var showMenuBarExtra = true

    var body: some Scene {
        // A single-instance window so the menu-bar "Open TidyMac" can always bring it back.
        Window("TidyMac", id: "main") {
            ContentView()
                .environment(model).environment(monitor)
                .frame(minWidth: 1000, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 720)
        .commands { TidyCommands(model: model) }

        Settings { SettingsView() }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarContent().environment(model).environment(monitor)
        } label: {
            Label(monitor.cpu.formatted(.percent.precision(.fractionLength(0))), systemImage: "gauge.with.dots.needle.33percent")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu-bar commands. Every destructive one goes through the same request path as the buttons.
struct TidyCommands: Commands {
    let model: AppModel
    @AppStorage(Prefs.sidebarCollapsed) private var sidebarCollapsed = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .sidebar) {
            Button(sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") { sidebarCollapsed.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            ForEach(Array(Pane.ordered.enumerated()), id: \.element) { i, p in
                Button(p.title) { model.pane = p }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
        }
        CommandMenu("Scan") {
            Button(model.hasScanned(model.pane) ? "Scan Again" : "Scan") { model.scan(model.pane) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.pane.scannable || model.isScanning(model.pane))
            Button("Stop Scan") { model.cancelScan(model.pane) }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isScanning(model.pane))
            Divider()
            Button("Select All Safe Items") { model.selectAllSafe(in: model.pane) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.findings(in: model.pane).isEmpty)
            Button("Deselect All") { model.selectNone(in: model.pane) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.findings(in: model.pane).isEmpty)
            Divider()
            Button(model.dryRun ? "Preview Clean of Selected Items" : "Clean Selected Items…") { model.cleanSelection(in: model.pane) }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.findings(in: model.pane).contains { model.selected.contains($0.url) } || model.cleaning)
            Divider()
            Toggle("Dry Run", isOn: Binding(get: { model.dryRun }, set: { model.setDryRun($0) }))
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("pane") private var storedPane = Pane.smart.rawValue

    var body: some View {
        @Bindable var m = model
        HStack(spacing: 0) {
            SidebarView()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .scrollContentBackground(.hidden)
        .sheet(item: $m.pending) { p in ConfirmSheet(pending: p) }
        .alert("Turn off dry run?", isPresented: $m.askGoLive) {
            Button("Keep Dry Run On", role: .cancel) {}
            Button("Turn Off Dry Run") { model.confirmGoLive() }
        } message: {
            Text("Cleans will then move items to the Trash. You still confirm each clean before anything is removed, and dry run comes back on the next time TidyMac opens.")
        }
        .onAppear { if let p = Pane(rawValue: storedPane) { model.pane = p } }
        .onChange(of: model.pane) { model.message = ""; storedPane = model.pane.rawValue }
        .themed()
    }

    @ViewBuilder private var detail: some View {
        switch model.pane {
        case .smart: SmartScanView()
        case .junk: FindingsView(pane: .junk, intro: String(localized: "Only items marked Safe are ticked for you."))
        case .large: FindingsView(pane: .large, intro: String(localized: "Nothing is ticked: pick what you no longer need."))
        case .privacy: FindingsView(pane: .privacy, intro: String(localized: "Caches are ticked. History and cookies need your say-so."))
        case .lens: SpaceLensView()
        case .dupes: DuplicatesView()
        case .uninstall: UninstallerView()
        case .login: LoginItemsView()
        case .perf: PerformanceView()
        }
    }
}

// MARK: Sidebar

/// Custom sidebar. Collapses to an icon rail (⌃⌘S) that still shows every pane and the safety state.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.sidebarCollapsed) private var collapsed = false

    var body: some View {
        VStack(alignment: collapsed ? .center : .leading, spacing: 4) {
            header.padding(.top, 30).padding(.bottom, 14)   // clears the traffic lights under the hidden title bar

            ForEach(PaneGroup.all) { g in
                if collapsed {
                    Rectangle().fill(Theme.veil(0.10)).frame(width: 24, height: 1).padding(.vertical, 8)
                } else {
                    Text(g.title.uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(0.9)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(g.panes) { p in SidebarRow(pane: p, collapsed: collapsed) }
            }
            Spacer()
            DryRunBadge(compact: collapsed)
        }
        .padding(collapsed ? 10 : 14)
        .frame(width: collapsed ? 76 : 232)
        .frame(maxHeight: .infinity)
        .background(Theme.veil(0.04))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.veil(0.08)).frame(width: 1) }
        .animation(.snappy(duration: 0.25), value: collapsed)
    }

    @ViewBuilder private var header: some View {
        if collapsed {
            VStack(spacing: 10) { LogoTile(); toggle }
        } else {
            HStack(spacing: 10) {
                LogoTile()
                Text("TidyMac").font(Theme.heading(20)).foregroundStyle(Theme.text)
                Spacer()
                toggle
            }
            .padding(.horizontal, 8)
        }
    }

    private var toggle: some View {
        Button { collapsed.toggle() } label: {
            Image(systemName: "sidebar.left").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.label)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Show Sidebar" : "Hide Sidebar")
        .accessibilityLabel(collapsed ? "Show Sidebar" : "Hide Sidebar")
    }
}

struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let pane: Pane
    var collapsed = false

    var body: some View {
        let active = model.pane == pane
        Button { model.pane = pane } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon).frame(width: 20)
                    .foregroundStyle(active ? Theme.text : Theme.label)
                    .overlay(alignment: .topTrailing) {
                        if collapsed && model.isScanning(pane) { Circle().fill(Theme.amber).frame(width: 6, height: 6).offset(x: 5, y: -4) }
                    }
                if !collapsed {
                    Text(pane.title).font(.system(size: 14, weight: .medium))
                        .foregroundStyle(active ? Theme.text : Theme.dim)
                    Spacer()
                    if model.isScanning(pane) { ProgressView().controlSize(.mini).accessibilityLabel("Scanning") }
                }
            }
            .padding(.horizontal, 10).frame(height: 38)
            .frame(maxWidth: collapsed ? 44 : .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Theme.veil(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? pane.title : "")
        .accessibilityLabel(pane.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Always-visible safety state. Click to switch; turning dry run off asks for confirmation first.
struct DryRunBadge: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        Button { model.setDryRun(!model.dryRun) } label: {
            HStack(spacing: 8) {
                Image(systemName: model.dryRun ? "shield" : "trash")
                if !compact {
                    Text(model.dryRun ? "Dry run on" : "Trash mode")
                    Spacer()
                    Text(model.dryRun ? "Preview only" : "Live").font(.system(size: 11)).opacity(0.7)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(model.dryRun ? Theme.chipText : Theme.amber)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.veil(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(model.dryRun ? Theme.veil(0.18) : Theme.amber.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(model.dryRun ? "Scans and cleans only preview. Click to allow real cleaning (Trash)."
                           : "Real cleaning is on. Items go to the Trash after you confirm. Click to go back to dry run.")
        .accessibilityLabel(model.dryRun ? "Dry run is on. Cleans only preview." : "Dry run is off. Cleans move items to the Trash.")
        .accessibilityHint(model.dryRun ? "Turns dry run off after a confirmation" : "Turns dry run back on")
    }
}
