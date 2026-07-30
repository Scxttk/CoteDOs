import SwiftUI

struct NotchSettings: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        Form {
            Section {
                ForEach(NotchViewModel.Tab.allCases, id: \.self) { tab in
                    Toggle(tab.title, isOn: tabBinding(tab))
                        // The last enabled tab can't be switched off — the
                        // notch always needs at least one page.
                        .disabled(settings.isTabEnabled(tab) && NotchViewModel.enabledTabs.count == 1)
                }
            } header: {
                Text(String(localized: "settings.tabs.header", defaultValue: "Tabs"))
            } footer: {
                Text(String(localized: "settings.tabs.hint", defaultValue: "Deaktivierte Tabs verschwinden aus der Notch. Mindestens ein Tab bleibt immer aktiv."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "settings.liveActivities", defaultValue: "Live Activities (Laden, AirPods, Datei empfangen)"), isOn: $settings.liveActivitiesEnabled)
                Toggle(String(localized: "settings.hud", defaultValue: "HUD-Ersatz (Lautstärke/Helligkeit)"), isOn: $settings.hudEnabled)
                Toggle(String(localized: "settings.suppressOSD", defaultValue: "Lautstärke & Helligkeit nur in der Notch (Bedienungshilfen nötig)"), isOn: $settings.suppressSystemOSD)
                    .disabled(!settings.hudEnabled)
            } header: {
                Text(String(localized: "settings.notch.display", defaultValue: "Anzeige"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func tabBinding(_ tab: NotchViewModel.Tab) -> Binding<Bool> {
        Binding(
            get: { settings.isTabEnabled(tab) },
            set: { settings.setTab(tab, enabled: $0) }
        )
    }
}
