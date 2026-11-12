import SwiftUI
import TidyCore

/// Monochrome theme with a dark and a light variant. Dark: black → #152331 with ice-white accents.
/// Light: paper → pale slate with ink accents. Amber is the single signal color (Review, live mode).
/// Every color is a dark/light pair that follows the window's appearance.
enum Theme {
    static var bgLeft: Color { Color(dark: 0x000000, light: 0xF7F9FB) }
    static var bgRight: Color { Color(dark: 0x152331, light: 0xDCE3EA) }
    static var text: Color { Color(dark: 0xF3F5F7, light: 0x10161C) }
    static var soft: Color { Color(dark: 0xD3D9DF, light: 0x2B3640) }
    static var chipText: Color { Color(dark: 0xE6EAEE, light: 0x1E2832) }
    static var muted: Color { Color(dark: 0xAEB6BE, light: 0x4A5560) }
    static var secondary: Color { Color(dark: 0xA3ABB4, light: 0x55606B) }
    static var label: Color { Color(dark: 0x8D96A0, light: 0x6A7480) }
    static var amber: Color { Color(dark: 0xFFC66B, light: 0xA85A00) }
    /// Text and icons on accent-filled surfaces (buttons, tiles, ticked boxes).
    static var ink: Color { Color(dark: 0x05080C, light: 0xFFFFFF) }
    /// Row group titles and inactive sidebar labels.
    static var dim: Color { Color(dark: 0xC0C7CE, light: 0x3A4651) }
    /// Row subtitles and quiet icons.
    static var faint: Color { Color(dark: 0x98A1AB, light: 0x66717C) }
    static var steel: Color { Color(dark: 0x7C8A99, light: 0x8493A2) }
    /// Strongest-to-weakest steps for gauges and stacked bars.
    static var shades: [Color] {
        [(0xFFFFFF, 0x10161C), (0xC5CED8, 0x3F4C59), (0x8D9AA8, 0x6F7D8B), (0x5C6875, 0xA3AEB9), (0x2E3944, 0xD3DAE1)]
            .map { Color(dark: $0.0, light: $0.1) }
    }
    /// The translucent layer cards, strokes and glows are built from: white over the dark theme, ink over the light one.
    static func veil(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: opacity) : NSColor(hex: 0x10161C, alpha: opacity) })
    }
    /// Outer padding shared by every pane.
    static let pane = EdgeInsets(top: 30, leading: 36, bottom: 24, trailing: 36)
    /// Refresh rate for clock-driven animations.
    static let frame = 1.0 / 40.0

    static var background: LinearGradient {
        LinearGradient(colors: [bgLeft, bgRight], startPoint: .leading, endPoint: .trailing)
    }
    /// Used for buttons, rings, bars, logo: ice-white to silver in dark, slate to ink in light.
    static var accent: LinearGradient {
        LinearGradient(colors: [Color(dark: 0xFFFFFF, light: 0x33414E), Color(dark: 0xD3DAE1, light: 0x1F2A35), Color(dark: 0x9AA7B4, light: 0x0E151C)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Icon tiles, strongest (0) to quietest (3). Icons on them use `ink`.
    static func tile(_ level: Int) -> LinearGradient {
        let steps: [((UInt32, UInt32), (UInt32, UInt32))] = [
            ((0xFFFFFF, 0x33414E), (0xC5CED8, 0x10161C)), ((0xE4E9EE, 0x44525F), (0x9AA7B4, 0x1F2A35)),
            ((0xCBD3DB, 0x55636F), (0x8D9AA8, 0x2E3A46)), ((0xAEB9C4, 0x667480), (0x6F7D8B, 0x3F4C59))]
        let s = steps[min(max(level, 0), steps.count - 1)]
        return LinearGradient(colors: [Color(dark: s.0.0, light: s.0.1), Color(dark: s.1.0, light: s.1.1)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// A color that follows the appearance of the view it is drawn in.
    init(dark: UInt32, light: UInt32) {
        self.init(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) })
    }
}

/// User preferences (UserDefaults keys and defaults). Dry run is deliberately not one of them.
enum Prefs {
    static let appearance = "appearance"
    static let showMenuBarExtra = "showMenuBarExtra"
    static let sidebarCollapsed = "sidebarCollapsed"
    static let largeFileMB = "largeFileMB"
    static let duplicateMB = "duplicateMB"
    static let largeFileChoices = [50, 100, 250, 500, 1000]
    static let duplicateChoices = [1, 5, 10, 50]

    private static func megabytes(_ key: String, default value: Int, allowed: [Int]) -> Int64 {
        let stored = UserDefaults.standard.integer(forKey: key)
        return Int64(allowed.contains(stored) ? stored : value) * 1_000_000
    }
    /// Smallest file the Large Files scan reports, in bytes.
    static var largeFileBytes: Int64 { megabytes(largeFileMB, default: 100, allowed: largeFileChoices) }
    /// Smallest file the Duplicates scan compares, in bytes.
    static var duplicateBytes: Int64 { megabytes(duplicateMB, default: 1, allowed: duplicateChoices) }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

/// Applies the chosen appearance and the theme tint to a window's root view.
private struct Themed: ViewModifier {
    @AppStorage(Prefs.appearance) private var appearance = Appearance.system.rawValue
    func body(content: Content) -> some View {
        content.preferredColorScheme((Appearance(rawValue: appearance) ?? .system).scheme).tint(Theme.text)
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
}

struct AppBackground: View {
    var body: some View { Theme.background.ignoresSafeArea() }
}

extension View {
    /// Translucent rounded card used across the app.
    func glass(radius: CGFloat = 18, fill: Double = 0.06) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.veil(fill)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.veil(0.11), lineWidth: 1))
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, kind: kind, height: height)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: height >= 52 ? 18 : height >= 46 ? 16 : 14, weight: .bold, design: .rounded))
                .foregroundStyle(kind == .secondary ? Theme.chipText : Theme.ink)
                .padding(.horizontal, height * 0.6)
                .frame(height: height)
                .background {
                    if kind == .primary {
                        Capsule().fill(Theme.accent)
                    } else if kind == .destructive {
                        Capsule().fill(Theme.amber)
                    } else {
                        Capsule().fill(Theme.veil(0.08)).overlay(Capsule().stroke(Theme.veil(0.16), lineWidth: 1))
                    }
                }
                .shadow(color: kind == .primary ? Theme.veil(0.18) : .clear, radius: 16, y: 6)
                .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
        }
    }
}

enum ChipKind { case safe, review, neutral }

struct Chip: View {
    private let label: Text
    let kind: ChipKind

    init(text: LocalizedStringKey, kind: ChipKind) { label = Text(text); self.kind = kind }
    /// For text that is already localised (or is data, such as a name).
    init(verbatim: String, kind: ChipKind) { label = Text(verbatim: verbatim); self.kind = kind }

    var body: some View {
        label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(Capsule().fill(bg))
    }
    private var fg: Color { kind == .review ? Theme.amber : kind == .safe ? Theme.chipText : Theme.muted }
    private var bg: Color {
        kind == .review ? Theme.amber.opacity(0.16) : Theme.veil(kind == .safe ? 0.12 : 0.07)
    }
}

/// Small rounded-square checkbox matching the mockups.
struct CheckBox: View {
    let isOn: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isOn ? Color.clear : Theme.veil(0.35), lineWidth: 1.5))
            .overlay { if isOn { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.ink) } }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)   // the row that owns it reads the state
    }
}

/// Compact secondary button used in pane headers.
struct SmallButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.chipText)
            .padding(.horizontal, 14).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.veil(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.veil(0.14), lineWidth: 1))
    }
}

struct LogoTile: View {
    var size: CGFloat = 34
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay { Image(systemName: "sparkles").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(Theme.ink) }
    }
}

// MARK: Shared pane pieces

/// Title and subtitle at the top of a pane, with optional controls on the right.
struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading(32)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            trailing()
        }
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

struct RevealButton: View {
    let url: URL
    var body: some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
        }
        .buttonStyle(.plain).help("Reveal in Finder").accessibilityLabel("Reveal \(url.lastPathComponent) in Finder")
    }
}

/// One tickable finding. The whole name area toggles it, and VoiceOver hears the name, size and state together.
struct SelectableRow<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let subtitle: String
    var showSize = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let on = model.selected.contains(finding.url)
        HStack(spacing: 14) {
            Button { model.toggle(finding.url) } label: {
                HStack(spacing: 14) {
                    CheckBox(isOn: on)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.url.lastPathComponent).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(finding.url.lastPathComponent), \(formatBytes(finding.size)), \(subtitle)")
            .accessibilityValue(on ? "Selected" : "Not selected")
            .accessibilityAddTraits(.isToggle)
            trailing()
            if showSize {
                Text(formatBytes(finding.size)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.chipText).frame(width: 80, alignment: .trailing).accessibilityHidden(true)
            }
            RevealButton(url: finding.url)
        }
        .padding(.horizontal, 16).frame(height: 46)
        .overlay(alignment: .top) { Rectangle().fill(Theme.veil(0.06)).frame(height: 1) }
    }
}

struct RiskChip: View {
    let risk: Risk
    var body: some View { Chip(text: risk == .review ? "Review" : "Safe", kind: risk == .review ? .review : .safe) }
}

/// Floating bar at the bottom of a review list: what is selected, and the button that cleans it.
struct ActionBar: View {
    @Environment(AppModel.self) private var model
    let pane: Pane
    let title: String
    let detail: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading(22)).foregroundStyle(Theme.text)
                Text(verbatim: detail + " " + (model.dryRun ? String(localized: "Dry run is on, so this only previews.")
                                                             : String(localized: "Items go to the Trash after you confirm.")))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if model.cleaning { ProgressView().controlSize(.small) }
            Button(model.dryRun ? "Preview clean" : "Clean") { model.cleanSelection(in: pane) }
                .buttonStyle(PillButtonStyle(height: 48)).disabled(!enabled || model.cleaning)
        }
        .padding(.vertical, 14).padding(.leading, 20).padding(.trailing, 16)
        .glass(radius: 18, fill: 0.08)
        .shadow(color: Color(dark: 0x000000, light: 0x5C6875).opacity(0.35), radius: 20, y: 10)
    }
}

/// Result of the last action, plus a busy line while a clean is running. Shown under every pane header,
/// so it stays visible when a clean empties the list.
struct StatusLine: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.cleaning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.dryRun ? "Checking what would be removed…" : "Cleaning…")
            }
            .font(.system(size: 13)).foregroundStyle(Theme.soft)
        } else if !model.message.isEmpty {
            Label(model.message, systemImage: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.soft)
                .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                .glass(radius: 12, fill: 0.07)
        }
    }
}

/// Explains that results are incomplete without Full Disk Access, and where to grant it.
struct PermissionBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if !model.unreadable.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 18)).foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Some folders could not be read, so these results are incomplete.")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("macOS blocks \(model.unreadable.map(\.lastPathComponent).joined(separator: ", ")) until TidyMac has Full Disk Access. Turn it on in System Settings, reopen TidyMac, then scan again.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let url = PermissionCheck.settingsURL {
                    SmallButton(title: "Open Settings") { NSWorkspace.shared.open(url) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.amber.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.amber.opacity(0.35), lineWidth: 1))
        }
    }
}

/// Ring gauge with a title and one line of detail, used by Performance and the menu-bar panel.
struct GaugeTile: View {
    let title: String
    let value: Double
    let detail: String
    let shade: Color
    var size: CGFloat = 70

    var body: some View {
        VStack(spacing: size > 80 ? 8 : 6) {
            RingGauge(value: value, shade: shade, size: size)
            Text(title).font(.system(size: size > 80 ? 13 : 12, weight: .semibold)).foregroundStyle(Theme.soft)
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, size > 80 ? 16 : 12).padding(.horizontal, 4)
        .glass(radius: size > 80 ? 18 : 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Int(value * 100)) percent, \(detail)")
    }
}

struct BatteryRow: View {
    let battery: BatteryStats
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: battery.charging ? "battery.100.bolt" : "battery.75").foregroundStyle(Theme.chipText)
            Text(battery.charging ? "Battery, charging" : "Battery").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.soft)
            Spacer()
            ProgressView(value: Double(battery.percent) / 100).tint(Theme.text).frame(width: 100)
            Text("\(battery.percent)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.text).frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).glass(radius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(battery.charging ? "Battery \(battery.percent) percent, charging" : "Battery \(battery.percent) percent")
    }
}
