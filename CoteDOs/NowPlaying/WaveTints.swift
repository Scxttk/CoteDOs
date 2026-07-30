import SwiftUI

/// The colours one wave run draws with, and where they came from.
///
/// Exists because the same question — "what colour is this wave?" — was
/// answered independently at every place a wave is built, and the answers
/// disagreed. The pill resolved the source app's icon accent; the morphing
/// overlay, the spectrum page and the fullscreen takeover all hard-coded
/// `nowPlaying.track != nil ? artworkColor : nil`, which is the *player's*
/// cover regardless of who is actually making the sound. So a Safari video
/// drew white bars everywhere except the pill — and, if Spotify merely had a
/// track loaded, drew them in that paused track's colour.
///
/// One rule now, in one place: **the wave belongs to whoever is making the
/// sound.**
struct WaveTints {
    var primary: Color?
    var secondary: Color?
    var tertiary: Color?
    var coverBars: CoverBarPalette?
    /// Whether these came from the player's cover rather than the source app's
    /// icon. The pill's thumbnail branches on the same answer, so the artwork
    /// it shows and the colour beside it can never disagree.
    var fromCover: Bool

    /// Resolves the tints for the audio playing right now.
    ///
    /// - Parameters:
    ///   - sourceBundleID: `SpectrumAnalyzer.sourceBundleID` — the app CoreAudio
    ///     reports as having an active output stream, or nil when nothing does
    ///     (or the tap isn't running).
    ///   - sourceAppTint: `SourceAppAccent.tint` for that app.
    static func resolve(
        nowPlaying: NowPlayingManager,
        sourceBundleID: String?,
        sourceAppTint: Color?
    ) -> WaveTints {
        let playerOwnsIt = playerOwnsTheAudio(
            hasCover: nowPlaying.track?.artworkURL != nil,
            sourceBundleID: sourceBundleID,
            playerBundleID: nowPlaying.activeSourceID.bundleID
        )
        guard playerOwnsIt else {
            // Generic system audio: one accent from the app's icon. No
            // secondary, tertiary or per-bar palette — those describe an album
            // sleeve's colour families, and an app icon has no equivalent to
            // fake.
            return WaveTints(primary: sourceAppTint, fromCover: false)
        }
        return WaveTints(
            primary: nowPlaying.artworkColor,
            secondary: nowPlaying.artworkSecondaryColor,
            tertiary: nowPlaying.artworkTertiaryColor,
            coverBars: nowPlaying.coverBars,
            fromCover: true
        )
    }

    /// Whether the track's cover is the honest colour for what's audible.
    ///
    /// Deliberately not keyed on `isPlaying`. Pausing drops that flag at once
    /// while `spectrum.hasSignal` holds the pill open for another couple of
    /// seconds, and swapping the cover for the player's own app icon in that
    /// window showed Spotify's logo beside flat bars for no reason — so a
    /// paused track keeps its cover, which is also honest, because players hold
    /// their output stream open while paused and CoreAudio still names them.
    ///
    /// What it must *not* do is let the player win merely because it is
    /// playing. Another app making noise — Safari playing a video while Spotify
    /// sits paused, or even while it plays — is exactly the case the app-icon
    /// branch exists for, and whoever is actually audible should win.
    ///
    /// Internal rather than private so the tests can exercise the rule without
    /// standing up a live `NowPlayingManager`.
    static func playerOwnsTheAudio(hasCover: Bool, sourceBundleID: String?, playerBundleID: String?) -> Bool {
        guard hasCover else { return false }
        // No identifiable source — keep the cover rather than blanking a wave
        // that may well be the player's.
        guard let sourceBundleID else { return true }
        return sourceBundleID == playerBundleID
    }
}
