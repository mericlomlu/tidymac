import SwiftUI
import TidyCore

struct PerformanceView: View {
    @Environment(Monitor.self) private var mon

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: Pane.perf.title, subtitle: String(localized: "Live numbers, refreshed every 2 seconds."))
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 14) {
                    gauges
                    memoryBreakdown
                    if let b = mon.battery { BatteryRow(battery: b) }
                    Spacer(minLength: 0)
                }
                .frame(width: 400)
                processes.frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            Text("macOS manages memory itself, so there is no \"Free RAM\" button. It would only slow things down. Quit the heaviest apps if you need headroom.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .padding(Theme.pane)
        .onAppear { mon.processViewers += 1 }
        .onDisappear { mon.processViewers -= 1 }
    }

    // MARK: Pieces

    private var gauges: some View {
        HStack(spacing: 10) {
            GaugeTile(title: String(localized: "CPU"), value: mon.cpu, detail: String(localized: "\(ProcessInfo.processInfo.activeProcessorCount) cores"), shade: Theme.shades[0], size: 92)
            GaugeTile(title: String(localized: "Memory"), value: mon.memory?.usedFraction ?? 0,
                      detail: mon.memory.map { String(localized: "\(formatBytes(Int64($0.used))) of \(formatBytes(Int64($0.total)))") } ?? "",
                      shade: Theme.shades[1], size: 92)
            GaugeTile(title: String(localized: "Disk"), value: mon.diskUsedFraction, detail: String(localized: "\(formatBytes(mon.diskFree)) free"), shade: Theme.shades[2], size: 92)
        }
    }

    private var memoryBreakdown: some View {
        let parts = memoryParts
        let total = max(parts.reduce(0) { $0 + $1.bytes }, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("MEMORY").font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.label)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts) { p in
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(p.shade)
                            .frame(width: max(2, geo.size.width * CGFloat(p.bytes) / CGFloat(total)))
                    }
                }
                .animation(.easeOut(duration: 0.6), value: total)
            }
            .frame(height: 12).clipShape(Capsule()).accessibilityHidden(true)
            VStack(spacing: 6) {
                ForEach(parts) { p in
                    HStack(spacing: 8) {
                        Circle().fill(p.shade).frame(width: 9, height: 9)
                        Text(p.name).foregroundStyle(Theme.soft)
                        Spacer()
                        Text(formatBytes(Int64(p.bytes))).monospacedDigit().foregroundStyle(Theme.secondary)
                    }.font(.system(size: 13))
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(radius: 18)
    }

    private struct MemPart: Identifiable { let name: String; let bytes: UInt64; let shade: Color; var id: String { name } }

    private var memoryParts: [MemPart] {
        guard let m = mon.memory else { return [] }
        let parts: [(String, UInt64)] = [(String(localized: "App"), m.app), (String(localized: "Wired"), m.wired),
                                         (String(localized: "Compressed"), m.compressed),
                                         (String(localized: "Cached and other"), m.other), (String(localized: "Free"), m.free)]
        return zip(parts, Theme.shades).map { MemPart(name: $0.0, bytes: $0.1, shade: $1) }
    }

    private var processes: some View {
        let biggest = max(mon.procs.map(\.rssBytes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text("TOP PROCESSES BY MEMORY").font(.system(size: 11, weight: .semibold)).tracking(0.9)
                .foregroundStyle(Theme.label).padding(16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mon.procs) { p in
                        HStack(spacing: 14) {
                            Text(p.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                                .lineLimit(1).frame(width: 190, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(Theme.veil(0.08))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Theme.accent)
                                            .frame(width: max(4, geo.size.width * CGFloat(p.rssBytes) / CGFloat(biggest)))
                                            .animation(.easeOut(duration: 0.5), value: p.rssBytes)
                                    }
                            }.frame(height: 6).accessibilityHidden(true)
                            Text((p.cpu / 100).formatted(.percent.precision(.fractionLength(1)))).font(.system(size: 12)).monospacedDigit()
                                .foregroundStyle(Theme.secondary).frame(width: 48, alignment: .trailing)
                            Text(formatBytes(Int64(p.rssBytes))).font(.system(size: 14, weight: .medium)).monospacedDigit()
                                .foregroundStyle(Theme.chipText).frame(width: 84, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).frame(height: 46)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.veil(0.06)).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                    }
                    if mon.procs.isEmpty {
                        Text("Measuring…").font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.top, 40)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(radius: 18, fill: 0.05)
    }
}
