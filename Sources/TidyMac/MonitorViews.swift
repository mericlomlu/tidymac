import SwiftUI
import TidyCore

@Observable @MainActor
final class Monitor {
    var memory: MemoryStats?
    var cpu = 0.0
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var battery: BatteryStats?
    var procs: [ProcessInfoRow] = []
    /// How many visible views show the process list. `ps` only runs while this is above zero.
    var processViewers = 0
    private var task: Task<Void, Never>?

    init() { start() }   // begin sampling at launch so the menu-bar label is live before any window opens

    struct Snapshot: Sendable {
        let memory: MemoryStats, cpu: Double, disk: (Int64, Int64), battery: BatteryStats?, procs: [ProcessInfoRow]?
    }

    func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .utility) { [weak self] in
            let sampler = SystemSampler()
            _ = sampler.cpuUsage()   // establish CPU baseline
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                let wantsProcesses = await (self?.processViewers ?? 0) > 0
                let d = sampler.disk()
                let snap = Snapshot(memory: sampler.memory(), cpu: sampler.cpuUsage(), disk: (d.free, d.total),
                                    battery: sampler.battery(), procs: wantsProcesses ? sampler.topProcesses(limit: 8) : nil)
                await self?.apply(snap)
            }
        }
    }

    private func apply(_ s: Snapshot) {
        memory = s.memory; cpu = s.cpu; diskFree = s.disk.0; diskTotal = s.disk.1; battery = s.battery
        if let p = s.procs { procs = p }
    }

    var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }
}

/// Circular gauge used by `GaugeTile`.
struct RingGauge: View {
    let value: Double
    let shade: Color
    var size: CGFloat = 70
    var body: some View {
        ZStack {
            Circle().stroke(Theme.veil(0.12), lineWidth: size * 0.13)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(shade, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            Text("\(Int(value * 100))%").font(Theme.heading(size * 0.24)).foregroundStyle(Theme.text)
        }
        .frame(width: size, height: size)
    }
}

struct MenuBarContent: View {
    @Environment(Monitor.self) private var mon
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                LogoTile(size: 28)
                Text("TidyMac").font(Theme.heading(18)).foregroundStyle(Theme.text)
                Spacer()
                Chip(text: model.dryRun ? "Dry run on" : "Trash mode", kind: model.dryRun ? .safe : .review)
            }

            HStack(spacing: 8) {
                GaugeTile(title: String(localized: "CPU"), value: mon.cpu, detail: String(localized: "\(ProcessInfo.processInfo.activeProcessorCount) cores"), shade: Theme.shades[0])
                GaugeTile(title: String(localized: "Memory"), value: mon.memory?.usedFraction ?? 0,
                          detail: mon.memory.map { String(localized: "\(formatBytes(Int64($0.used))) used") } ?? "", shade: Theme.shades[1])
                GaugeTile(title: String(localized: "Disk"), value: mon.diskUsedFraction, detail: String(localized: "\(formatBytes(mon.diskFree)) free"), shade: Theme.shades[2])
            }

            if let b = mon.battery { BatteryRow(battery: b) }

            VStack(alignment: .leading, spacing: 0) {
                Text("TOP MEMORY").font(.system(size: 11, weight: .semibold)).tracking(0.9)
                    .foregroundStyle(Theme.label).padding(.bottom, 4)
                if mon.procs.isEmpty {
                    Text("Measuring…").font(.system(size: 13)).foregroundStyle(Theme.secondary).frame(height: 26)
                }
                ForEach(mon.procs.prefix(3)) { p in
                    HStack {
                        Text(p.name).lineLimit(1).foregroundStyle(Theme.chipText)
                        Spacer()
                        Text(formatBytes(Int64(p.rssBytes))).monospacedDigit().foregroundStyle(Theme.secondary)
                    }.font(.system(size: 13)).frame(height: 26)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10).glass(radius: 14)

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: model.isScanning(.smart) ? String(localized: "Scanning…")
                         : model.hasScanned(.smart) ? formatBytes(model.safeBytes) : String(localized: "Not scanned"))
                        .font(Theme.heading(22)).foregroundStyle(Theme.text)
                    Text(model.hasScanned(.smart) ? "safe to clean" : "Run Quick Scan").font(.system(size: 12)).foregroundStyle(Theme.soft)
                }
                Spacer()
                Button("Quick Scan") {
                    model.pane = .smart
                    showWindow()
                    model.scan(.smart)
                }
                .buttonStyle(PillButtonStyle(height: 40)).disabled(model.isScanning(.smart))
            }
            .padding(.vertical, 12).padding(.leading, 16).padding(.trailing, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.veil(0.14), Theme.veil(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.veil(0.18), lineWidth: 1))

            HStack {
                Button("Open TidyMac") { showWindow() }.buttonStyle(.plain).foregroundStyle(Theme.chipText)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }.font(.system(size: 13, weight: .medium))
        }
        .padding(18)
        .frame(width: 340)
        .background(AppBackground())
        .themed()
        .onAppear { mon.processViewers += 1 }
        .onDisappear { mon.processViewers -= 1 }
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

}
