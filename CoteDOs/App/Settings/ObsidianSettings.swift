import AppKit
import SwiftUI

struct ObsidianSettings: View {
    @ObservedObject var settings: UserSettings

    private var vaultDisplayName: String {
        if let data = settings.vaultBookmark, let url = Persistence.resolveBookmark(data) {
            return url.lastPathComponent
        }
        return String(localized: "settings.obsidian.noVault", defaultValue: "Kein Vault gewählt")
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "settings.obsidian.vault", defaultValue: "Vault-Ordner"))
                        Text(vaultDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.obsidian.choose", defaultValue: "Wählen …"), action: chooseVault)
                }
            }

            Section {
                TextField(String(localized: "settings.obsidian.dailyFolder", defaultValue: "Daily-Ordner"), text: $settings.dailyFolder)
                TextField(String(localized: "settings.obsidian.dailyFormat", defaultValue: "Datumsformat"), text: $settings.dailyFormat)
                TextField(String(localized: "settings.obsidian.heading", defaultValue: "Capture-Überschrift"), text: $settings.captureHeading)
                TextField(String(localized: "settings.obsidian.focusHeading", defaultValue: "Fokuszeit-Überschrift"), text: $settings.focusHeading)
            } header: {
                Text(String(localized: "settings.obsidian.target", defaultValue: "Ziel"))
            }

            Section {
                Picker(String(localized: "settings.obsidian.mode", defaultValue: "Schreibweise"), selection: $settings.captureMode) {
                    ForEach(UserSettings.CaptureMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                Toggle(String(localized: "settings.obsidian.timestamp", defaultValue: "Zeitstempel voranstellen"), isOn: $settings.captureTimestamp)
                Toggle(String(localized: "settings.obsidian.hotkey", defaultValue: "Globaler Hotkey (⌥⌘Space)"), isOn: $settings.captureHotkeyEnabled)
                Toggle(String(localized: "settings.obsidian.focusTracking", defaultValue: "Fokuszeit-Presets ins Daily loggen"), isOn: $settings.focusTrackingEnabled)
            } header: {
                Text(String(localized: "settings.obsidian.behavior", defaultValue: "Verhalten"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "settings.obsidian.choosePrompt", defaultValue: "Vault wählen")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.vaultBookmark = Persistence.bookmarkData(for: url)
        if settings.vaultName.isEmpty { settings.vaultName = url.lastPathComponent }
    }
}
