import SwiftUI
import TidyCore

/// The Settings window (⌘,). Dry run is not a setting on purpose: it is on at every launch.
struct SettingsView: View {
    @AppStorage(Prefs.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(Prefs.showMenuBarExtra) private var showMenuBarExtra = true
    @AppStorage(Prefs.largeFileMB) private var largeFileMB = 100
    @AppStorage(Prefs.duplicateMB) private var duplicateMB = 1

    private var logURL: URL { Cleaner().logURL }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("Match System").tag(Appearance.system.rawValue)
                    Text("Light").tag(Appearance.light.rawValue)
                    Text("Dark").tag(Appearance.dark.rawValue)
                }
                .pickerStyle(.segmented)
                Toggle("Show TidyMac in the menu bar", isOn: $showMenuBarExtra)
            }
            Section {
                Picker("Large Files lists files of at least", selection: $largeFileMB) {
                    ForEach(Prefs.largeFileChoices, id: \.self) { Text(formatBytes(Int64($0) * 1_000_000)).tag($0) }
                }
                Picker("Duplicates compares files of at least", selection: $duplicateMB) {
                    ForEach(Prefs.duplicateChoices, id: \.self) { Text(formatBytes(Int64($0) * 1_000_000)).tag($0) }
                }
            } header: {
                Text("Scanning")
            } footer: {
                Text("Changes apply to the next scan.").foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Dry run") { Text("Always on when TidyMac opens") }
                LabeledContent("Activity log") {
                    Button("Show in Finder") {
                        let fm = FileManager.default
                        if fm.fileExists(atPath: logURL.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        } else {
                            NSWorkspace.shared.open(logURL.deletingLastPathComponent().deletingLastPathComponent())
                        }
                    }
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("Every preview and every clean is written to the activity log. Dry run cannot be turned off here; switch it in the sidebar when you want a real clean.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .themed()
    }
}
