import SwiftUI

struct TimerSettings: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        Form {
            Section {
                ForEach($settings.timerPresets) { $preset in
                    HStack(spacing: 12) {
                        TextField(
                            String(localized: "settings.timer.name", defaultValue: "Name"),
                            text: $preset.name,
                            prompt: Text(String(localized: "settings.timer.name", defaultValue: "Name"))
                        )
                        .labelsHidden()
                        Spacer(minLength: 0)
                        Toggle(String(localized: "settings.timer.isFocus", defaultValue: "Fokuszeit"), isOn: $preset.isFocus)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help(String(localized: "settings.timer.isFocusHint", defaultValue: "Zählt als Fokuszeit"))
                        Stepper(value: $preset.minutes, in: 1...180) {
                            Text(String(localized: "settings.timer.minutes", defaultValue: "\(preset.minutes) min"))
                                .monospacedDigit()
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        Button {
                            settings.timerPresets.removeAll { $0.id == preset.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { settings.timerPresets.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    settings.timerPresets.append(
                        TimerPreset(name: String(localized: "timer.preset.new", defaultValue: "Neuer Timer"), minutes: 25)
                    )
                } label: {
                    Label(String(localized: "settings.timer.add", defaultValue: "Timer hinzufügen"), systemImage: "plus")
                }
            } header: {
                Text(String(localized: "settings.timer.presets", defaultValue: "Voreinstellungen"))
            } footer: {
                Text(String(localized: "settings.timer.chainHint", defaultValue: "Die Reihenfolge der Liste bestimmt die Kette beim automatischen Fortsetzen. Die Checkbox markiert Presets, deren Sitzungen als Fokuszeit ins Obsidian-Daily geloggt werden."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "settings.timer.countUp", defaultValue: "Aufwärts zählen (verstrichene Zeit)"), isOn: $settings.timerCountsUp)
                Toggle(String(localized: "settings.timer.autoChain", defaultValue: "Automatisch mit nächstem Timer fortsetzen"), isOn: $settings.timerAutoChain)
                Toggle(String(localized: "settings.timer.sound", defaultValue: "Ton bei Ablauf"), isOn: $settings.timerSoundEnabled)
            } header: {
                Text(String(localized: "settings.timer.behavior", defaultValue: "Verhalten"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
