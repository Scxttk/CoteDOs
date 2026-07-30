import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var settings: UserSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var didReset = false

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.launchAtLogin", defaultValue: "Bei Anmeldung starten"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }

                Picker(String(localized: "settings.appearance", defaultValue: "Erscheinungsbild"), selection: $settings.appearance) {
                    ForEach(UserSettings.Appearance.allCases) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                .onChange(of: settings.appearance) { _, value in applyAppearance(value) }
            }

            Section {
                Button(role: .destructive) {
                    Persistence.resetAll()
                    NotificationCenter.default.post(name: .notchMateResetData, object: nil)
                    didReset = true
                } label: {
                    Label(String(localized: "settings.resetData", defaultValue: "Ablage & Cache zurücksetzen"), systemImage: "trash")
                }
                if didReset {
                    Text("settings.resetData.done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "settings.data", defaultValue: "Daten"))
            } footer: {
                LabeledContent("Côte d'OS", value: versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("CoteDOs: launch-at-login toggle failed: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Apply the chosen appearance to the app (affects the Settings window chrome).
func applyAppearance(_ appearance: UserSettings.Appearance) {
    switch appearance {
    case .system: NSApp.appearance = nil
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    }
}
