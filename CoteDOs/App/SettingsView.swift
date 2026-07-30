import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label(String(localized: "settings.general", defaultValue: "Allgemein"), systemImage: "gearshape") }

            NotchSettings(settings: settings)
                .tabItem { Label(String(localized: "settings.notch", defaultValue: "Notch"), systemImage: "sparkles") }

            NowPlayingSettings(settings: settings)
                .tabItem { Label(String(localized: "settings.nowPlaying", defaultValue: "Musik"), systemImage: "music.note") }

            TimerSettings(settings: settings)
                .tabItem { Label(String(localized: "settings.timer", defaultValue: "Timer"), systemImage: "timer") }

            ObsidianSettings(settings: settings)
                .tabItem { Label(String(localized: "settings.obsidian", defaultValue: "Obsidian"), systemImage: "square.and.pencil") }
        }
        .frame(width: 520, height: 480)
    }
}

private struct GeneralSettings: View {
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
                    Label(String(localized: "settings.resetData", defaultValue: "Ablage, Favoriten & Cache zurücksetzen"), systemImage: "trash")
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

private struct NowPlayingSettings: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        Form {
            Picker(String(localized: "settings.mediaSource", defaultValue: "Quelle"), selection: $settings.mediaSource) {
                ForEach(UserSettings.MediaSource.allCases) { source in
                    Text(source.localizedName).tag(source)
                }
            }
            Text("settings.mediaSource.hint")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section {
                Toggle(String(localized: "settings.spectrum.pillOnly", defaultValue: "Nur Spektrum statt Cover"), isOn: $settings.pillSpectrumOnly)
                // One knob. Bar width and gap are fixed, so this only decides
                // how many bars there are and how far the pill grows; the
                // readout names the bar count because that is what changes.
                LabeledContent(String(localized: "settings.spectrum.pillWidth", defaultValue: "Breite")) {
                    Slider(
                        value: $settings.pillSpectrumWidth,
                        in: NotchLayout.pillSpectrumMinWidth...NotchLayout.pillSpectrumMaxWidth,
                        step: Double(NotchLayout.pillSpectrumBarPitch)
                    )
                    Text("\(NotchLayout.pillSpectrumBarCount(forWidth: settings.pillSpectrumWidth)) ▎")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(!settings.pillSpectrumOnly)
                Picker(String(localized: "settings.spectrum.style", defaultValue: "Spektrum-Stil"), selection: $settings.spectrumStyle) {
                    ForEach(UserSettings.SpectrumStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                Picker(String(localized: "settings.spectrum.colorSource", defaultValue: "Farbquelle"), selection: $settings.spectrumColorSource) {
                    ForEach(UserSettings.SpectrumColorSource.allCases) { source in
                        Text(source.localizedName).tag(source)
                    }
                }
                .disabled(!settings.spectrumStyle.usesAccentPair)
                ColorPicker(String(localized: "settings.spectrum.colorA", defaultValue: "Akzentfarbe 1"), selection: $settings.spectrumColorA, supportsOpacity: false)
                    .disabled(!settings.spectrumStyle.usesAccentPair || settings.spectrumColorSource == .cover)
                ColorPicker(String(localized: "settings.spectrum.colorB", defaultValue: "Akzentfarbe 2"), selection: $settings.spectrumColorB, supportsOpacity: false)
                    .disabled(!settings.spectrumStyle.usesAccentPair || settings.spectrumColorSource == .cover)
                Toggle(String(localized: "settings.spectrum.screensaver", defaultValue: "Als Bildschirmschoner bei Untätigkeit"), isOn: $settings.spectrumScreensaverEnabled)
            } header: {
                Text(String(localized: "settings.spectrum.header", defaultValue: "Sound-Spektrum"))
            } footer: {
                Text(String(localized: "settings.spectrum.hint", defaultValue: "„Nur Spektrum“ ersetzt das Mini-Cover in der eingeklappten Notch durch ein breiteres Spektrum mit mehr Balken — der Musik-Tab behält sein Cover. „Vom Cover“ leitet die zweite Farbe automatisch aus dem Album-Akzent ab. Der Bildschirmschoner übernimmt den Bildschirm, kurz bevor der Mac das Display abschaltet — nur wenn gerade Ton läuft. Er hält den Bildschirm wach; sobald du etwas anfasst oder die Musik aus ist, sperrt der Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Only meaningful for the Cover style, and best judged while a track
            // is playing: every change recomputes the current cover's palette.
            Section {
                Stepper(value: $settings.coverPaletteSize, in: 1...5) {
                    LabeledContent(
                        String(localized: "settings.cover.paletteSize", defaultValue: "Farben"),
                        value: "\(settings.coverPaletteSize)"
                    )
                }
                Stepper(value: $settings.coverBrightnessLevels, in: 1...4) {
                    LabeledContent(
                        String(localized: "settings.cover.brightnessLevels", defaultValue: "Helligkeitsstufen"),
                        value: "\(settings.coverBrightnessLevels)"
                    )
                }
                LabeledContent(String(localized: "settings.cover.saturation", defaultValue: "Sättigung")) {
                    Slider(value: $settings.coverBarSaturation, in: 0.5...1.4)
                    Text(settings.coverBarSaturation, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                LabeledContent(String(localized: "settings.cover.brightness", defaultValue: "Helligkeit")) {
                    Slider(value: $settings.coverBarBrightness, in: 0.5...1.2)
                    Text(settings.coverBarBrightness, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                Button(String(localized: "settings.cover.reset", defaultValue: "Zurücksetzen")) {
                    settings.coverPaletteSize = 4
                    settings.coverBrightnessLevels = 3
                    settings.coverBarSaturation = 1.0
                    settings.coverBarBrightness = 1.0
                }
            } header: {
                Text(String(localized: "settings.cover.header", defaultValue: "Cover-Stil"))
            } footer: {
                Text(String(localized: "settings.cover.hint", defaultValue: "Gilt nur für den Stil „Cover“. Änderungen wirken sofort auf den laufenden Titel — am besten bei spielender Musik einstellen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(settings.spectrumStyle != .coverImage)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct NotchSettings: View {
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

private struct TimerSettings: View {
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

private struct ObsidianSettings: View {
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

