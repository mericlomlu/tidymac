import SwiftUI
import TidyCore

struct SmartScanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The note sits in its own row under the content, so it can never cover a button or a card.
        VStack(spacing: 0) {
            Group {
                if model.isScanning(.smart) { ScanningState() }
                else if model.hasScanned(.smart) {
                    // Scrolls only when the window is too short for the banner, the cards and the note together.
                    ViewThatFits(in: .vertical) { ResultsState(); ScrollView { ResultsState() } }
                }
                else { StartState() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            DryRunNote().frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28).padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.35), value: model.isScanning(.smart))
        .animation(.easeInOut(duration: 0.35), value: model.hasScanned(.smart))
    }
}

/// The hero orb. Still at rest, so an idle window costs no CPU. While scanning, the clock (TimelineView)
/// drives a comet sweeping the ring plus little sparkles orbiting it. Reduce Motion keeps it still.
struct Orb: View {
    var spinning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.frame, paused: !spinning || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breathe = 1 + (spinning ? 0.035 : 0.02) * sin(t * (spinning ? 3.4 : 1.2))
            ZStack {
                Circle().fill(Theme.veil(spinning ? 0.13 : 0.07))
                    .frame(width: 300, height: 300).blur(radius: 46).scaleEffect(breathe)

                Circle()
                    .stroke(AngularGradient(colors: [Theme.shades[0], Theme.steel, Theme.shades[1], Theme.shades[0]],
                                            center: .center, angle: .degrees(200)), lineWidth: 11)
                    .frame(width: 255, height: 255)
                    .opacity(spinning ? 0.45 : 1)

                if spinning {
                    Circle().trim(from: 0, to: 0.30)
                        .stroke(AngularGradient(colors: [Theme.shades[0].opacity(0), Theme.shades[0]], center: .center,
                                                startAngle: .degrees(0), endAngle: .degrees(108)),
                                style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .frame(width: 255, height: 255)
                        .rotationEffect(.degrees(t * 230))
                        .shadow(color: Theme.veil(0.6), radius: 8)

                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "sparkle")
                            .font(.system(size: 11 + CGFloat(i) * 3, weight: .bold))
                            .foregroundStyle(Theme.veil(0.85))
                            .offset(x: 158 + CGFloat(i) * 6)
                            .rotationEffect(.degrees(t * (55 + Double(i) * 32) + Double(i) * 120))
                    }
                }

                Circle()
                    .fill(RadialGradient(colors: [Color(dark: 0x2A3642, light: 0xFFFFFF), Color(dark: 0x070B0F, light: 0xDCE3EA)],
                                         center: UnitPoint(x: 0.32, y: 0.24), startRadius: 0, endRadius: 190))
                    .frame(width: 231, height: 231)
                Image(systemName: "sparkles")
                    .font(.system(size: 88, weight: .light)).foregroundStyle(Theme.text)
                    .scaleEffect(breathe)
                    .rotationEffect(.degrees(spinning ? 6 * sin(t * 2.4) : 0))
            }
            .frame(width: 340, height: 340)
        }
        .accessibilityHidden(true)
    }
}

struct StartState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Orb(spinning: false)
            VStack(spacing: 10) {
                Text("Let's make some room").font(Theme.heading(40)).foregroundStyle(Theme.text)
                Text("Quick Scan checks caches, logs, big files and browser leftovers. Nothing is removed until you review it.")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            }
            Button("Start Quick Scan") { model.scan(.smart) }
                .buttonStyle(PillButtonStyle(height: 56))
            HStack(spacing: 8) {
                ForEach(ScanningState.stages, id: \.self) { Chip(verbatim: $0, kind: .neutral) }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }
}

struct ScanningState: View {
    @Environment(AppModel.self) private var model
    static var stages: [String] {
        [String(localized: "Caches and logs"), String(localized: "Large files"), String(localized: "Browser data")]
    }

    var body: some View {
        VStack(spacing: 14) {
            Orb(spinning: true)
            VStack(spacing: 8) {
                Text("Scanning your Mac").font(Theme.heading(36)).foregroundStyle(Theme.text)
                Text(model.scanStep < Self.stages.count
                     ? "Checking \(Self.stages[model.scanStep].lowercased()). This only reads, nothing is changed."
                     : "Almost done.")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted)
                    .contentTransition(.opacity).animation(.easeInOut, value: model.scanStep)
            }

            StageProgress(step: model.scanStep, total: Self.stages.count)
                .frame(width: 440)

            HStack(spacing: 22) {
                ForEach(Array(Self.stages.enumerated()), id: \.offset) { i, name in
                    StageLabel(name: name, state: i < model.scanStep ? .done : i == model.scanStep ? .active : .pending)
                }
            }

            HStack(spacing: 6) {
                Text(formatBytes(model.foundSoFar))
                    .font(Theme.heading(22)).monospacedDigit().foregroundStyle(Theme.accent)
                    .contentTransition(.numericText()).animation(.snappy, value: model.foundSoFar)
                Text("found so far").font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
            Button("Cancel") { model.cancelScan(.smart) }
                .buttonStyle(PillButtonStyle(kind: .secondary, height: 40)).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }
}

/// Determinate bar (finished stages) with a shimmering segment on the stage that is running.
struct StageProgress: View {
    let step: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let seg = geo.size.width / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.veil(0.10))
                Capsule().fill(Theme.accent)
                    .frame(width: max(0, min(CGFloat(step), CGFloat(total)) * seg))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: step)
                if step < total && !reduceMotion {
                    TimelineView(.animation(minimumInterval: Theme.frame)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat((t * 0.9).truncatingRemainder(dividingBy: 1))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.veil(0), Theme.veil(0.75), Theme.veil(0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: seg * 0.55)
                            .offset(x: CGFloat(step) * seg + (seg * 1.1) * phase - seg * 0.3)
                            .opacity(0.5 + 0.5 * sin(t * 4))
                    }
                    .mask(Capsule())
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scan progress")
        .accessibilityValue("\(step) of \(total) steps done")
    }
}

struct StageLabel: View {
    enum State { case done, active, pending }
    let name: String
    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            switch state {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.text)
                    .transition(.scale.combined(with: .opacity))
            case .active:
                TimelineView(.animation(minimumInterval: Theme.frame, paused: reduceMotion)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    Circle().fill(Theme.text).frame(width: 9, height: 9)
                        .scaleEffect(1 + 0.35 * sin(t * 6)).opacity(0.7 + 0.3 * sin(t * 6))
                        .frame(width: 14, height: 14)
                }
            case .pending:
                Circle().stroke(Theme.veil(0.3), lineWidth: 1.5).frame(width: 12, height: 12).frame(width: 14, height: 14)
            }
            Text(name).font(.system(size: 13, weight: state == .active ? .semibold : .medium))
                .foregroundStyle(state == .pending ? Theme.label : Theme.chipText)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name + ": " + (state == .done ? String(localized: "done")
                                    : state == .active ? String(localized: "in progress") : String(localized: "waiting"))))
    }
}

/// Counts up to its target with an ease-out, so the big number feels earned. One task per target:
/// a new target cancels the previous count instead of racing it.
struct CountUpBytes: View {
    let target: Int64
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(formatBytes(Int64(shown)))
            .font(.system(size: 96, weight: .bold, design: .rounded)).monospacedDigit().tracking(-3)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(formatBytes(target))
            .task(id: target) {
                let start = shown, end = Double(target)
                guard !reduceMotion else { shown = end; return }
                let steps = 45
                for i in 1...steps {
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                    let p = Double(i) / Double(steps)
                    shown = start + (end - start) * (1 - pow(1 - p, 3))
                }
                shown = end
            }
    }
}

struct ResultsState: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    /// First pane with something in it, in the order it is safest to work through.
    private var firstPaneWithFindings: Pane? {
        [Pane.junk, .privacy, .large].first { !model.findings(in: $0).isEmpty }
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("Scan complete")
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chipText)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Theme.veil(0.09)))
                .overlay(Capsule().stroke(Theme.veil(0.22), lineWidth: 1))
                .scaleEffect(appeared ? 1 : 0.6).opacity(appeared ? 1 : 0)

                if firstPaneWithFindings == nil {
                    Text("Nothing to clean").font(Theme.heading(56)).foregroundStyle(Theme.text).padding(.vertical, 14)
                    Text("No junk, large files or browser leftovers were found.").font(.system(size: 18)).foregroundStyle(Theme.soft)
                } else {
                    CountUpBytes(target: model.safeBytes)
                    Text("is safe to clean right now").font(.system(size: 18)).foregroundStyle(Theme.soft)
                    if model.reviewBytes > 0 {
                        Text("Another \(formatBytes(model.reviewBytes)) needs your review first.")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                if let first = firstPaneWithFindings {
                    Button("Review and Clean") { model.pane = first }.buttonStyle(PillButtonStyle(height: 56))
                }
                Button("Scan Again") { model.scan(.smart) }
                    .buttonStyle(PillButtonStyle(kind: firstPaneWithFindings == nil ? .primary : .secondary, height: 56))
            }
            .scaleEffect(appeared ? 1 : 0.9).opacity(appeared ? 1 : 0)

            PermissionBanner().padding(.horizontal, 40)
            StatusLine().padding(.horizontal, 40)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                    CategoryCard(card: c)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.25 + Double(i) * 0.09), value: appeared)
                }
            }
            .padding(.horizontal, 40).padding(.top, 4)
        }
        .padding(.vertical, 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: appeared)
        .onAppear { appeared = true }
    }

    private var cards: [ScanCard] {
        let none = String(localized: "None"), review = String(localized: "Review")
        let nothing = String(localized: "Nothing found"), reviewFirst = String(localized: "Review first")
        func size(_ b: Int64) -> String { b == 0 ? none : formatBytes(b) }
        func hasReview(_ items: [Finding]) -> Bool { items.contains { $0.risk == .review } }
        func riskText(_ items: [Finding]) -> String {
            items.isEmpty ? nothing : hasReview(items) ? String(localized: "Some to review") : String(localized: "Safe")
        }
        func riskKind(_ items: [Finding]) -> ChipKind { items.isEmpty ? .neutral : hasReview(items) ? .review : .safe }

        let junkItems = model.junk.count == 1 ? String(localized: "1 item") : String(localized: "\(model.junk.count) items")
        let locations = Set(model.junk.map(\.category)).count
        let junkDetail = locations == 1 ? String(localized: "\(junkItems) in 1 location") : String(localized: "\(junkItems) in \(locations) locations")

        let limit = formatBytes(Prefs.largeFileBytes)
        let largeFiles = model.large.count == 1 ? String(localized: "1 file over \(limit)") : String(localized: "\(model.large.count) files over \(limit)")
        let largePicked = model.large.filter { model.selected.contains($0.url) }.count
        let largeDetail = largeFiles + ", " + (largePicked == 0 ? String(localized: "none picked yet") : String(localized: "\(largePicked) picked"))

        let dupesScanned = model.hasScanned(.dupes)
        let groups = model.duplicates.count == 1 ? String(localized: "1 group of identical files")
                                                 : String(localized: "\(model.duplicates.count) groups of identical files")
        return [
            ScanCard(id: "junk", size: size(totalBytes(model.junk)), detail: junkDetail,
                     chipText: riskText(model.junk), chip: riskKind(model.junk), action: review, pane: .junk, tile: Theme.tile(0)),
            ScanCard(id: "large", size: size(totalBytes(model.large)), detail: largeDetail,
                     chipText: model.large.isEmpty ? nothing : reviewFirst, chip: model.large.isEmpty ? .neutral : .review,
                     action: review, pane: .large, tile: Theme.tile(1)),
            ScanCard(id: "privacy", size: size(totalBytes(model.privacy)), detail: String(localized: "Browser caches, history and cookies"),
                     chipText: riskText(model.privacy), chip: riskKind(model.privacy), action: review, pane: .privacy, tile: Theme.tile(2)),
            ScanCard(id: "dupes", size: dupesScanned ? size(model.duplicateWaste) : String(localized: "Not yet"),
                     detail: dupesScanned ? groups : String(localized: "Comparing files takes a few minutes"),
                     chipText: !dupesScanned ? String(localized: "Not scanned") : model.duplicates.isEmpty ? nothing : reviewFirst,
                     chip: dupesScanned && !model.duplicates.isEmpty ? .review : .neutral,
                     action: dupesScanned ? review : String(localized: "Scan"), pane: .dupes, tile: Theme.tile(3)),
        ]
    }
}

struct ScanCard: Identifiable {
    let id: String
    let size, detail, chipText: String
    var name: String { pane.title }
    let chip: ChipKind
    let action: String
    let pane: Pane
    let tile: LinearGradient
}

struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let card: ScanCard

    var body: some View {
        Button { model.pane = card.pane } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(card.tile).frame(width: 40, height: 40)
                    .overlay { Image(systemName: card.pane.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink) }
                Text(card.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(card.size).font(Theme.heading(26)).foregroundStyle(Theme.text)
                Text(card.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .lineLimit(2).frame(minHeight: 32, alignment: .topLeading)
                HStack {
                    Chip(verbatim: card.chipText, kind: card.chip)
                    Spacer()
                    Text(card.action).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chipText).underline()
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).glass(radius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.name): \(card.size). \(card.detail). \(card.chipText).")
        .accessibilityHint("Opens \(card.name)")
    }
}

/// Indeterminate bar for scans that cannot report percentages (a bright segment sweeps across).
struct ScanBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.frame, paused: reduceMotion)) { ctx in
            let p = reduceMotion ? 0.36 : CGFloat((ctx.date.timeIntervalSinceReferenceDate * 0.7).truncatingRemainder(dividingBy: 1))
            GeometryReader { geo in
                Capsule().fill(Theme.veil(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * 0.28)
                            .offset(x: (geo.size.width * 1.28) * p - geo.size.width * 0.28)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scanning")
    }
}

/// Bottom-right reminder of the safety mode. Switching dry run off asks for confirmation first.
struct DryRunNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Dry run", isOn: Binding(get: { model.dryRun }, set: { model.setDryRun($0) }))
                .labelsHidden().toggleStyle(.switch).tint(Theme.steel)
                .accessibilityLabel("Dry run")
            Text(model.dryRun ? "Dry run is on. Scans and cleans only preview, nothing is deleted."
                              : "Dry run is off. Items move to the Trash after you confirm.")
                .font(.system(size: 13)).foregroundStyle(model.dryRun ? Theme.soft : Theme.amber).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .glass(radius: 14, fill: 0.07)
    }
}
