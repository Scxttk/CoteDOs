import SwiftUI

struct NowPlayingSettings: View {
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
