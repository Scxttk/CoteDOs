import SwiftUI

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
