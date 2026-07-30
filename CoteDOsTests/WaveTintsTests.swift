import XCTest
@testable import CoteDOs

/// Pins the one rule every wave in the app now shares: **the wave belongs to
/// whoever is making the sound.**
///
/// The bug this came from: the pill resolved the source app's icon accent, but
/// the morphing overlay, the spectrum page and the fullscreen takeover each
/// hard-coded the *player's* cover instead. Safari's audio therefore drew white
/// bars everywhere except the pill — and, if Spotify merely had a track loaded,
/// drew them in that paused track's colour.
final class WaveTintsTests: XCTestCase {

    private let spotify = "com.spotify.client"
    private let safari = "com.apple.Safari"

    func testTheCoverWinsWhenThePlayerIsTheSource() {
        XCTAssertTrue(WaveTints.playerOwnsTheAudio(
            hasCover: true, sourceBundleID: spotify, playerBundleID: spotify))
    }

    func testAPausedPlayerKeepsItsCover() {
        // Players hold their output stream open while paused, so CoreAudio
        // still names Spotify — and `hasSignal` keeps the pill up for a couple
        // of seconds after a pause. Swapping the cover out in that window was
        // the flicker this rule exists to avoid.
        XCTAssertTrue(WaveTints.playerOwnsTheAudio(
            hasCover: true, sourceBundleID: spotify, playerBundleID: spotify))
    }

    func testAnotherAppMakingTheSoundBeatsALoadedCover() {
        // The regression that started this: Safari plays a video while Spotify
        // sits paused with a track loaded. The bars must be Safari's, not that
        // track's.
        XCTAssertFalse(WaveTints.playerOwnsTheAudio(
            hasCover: true, sourceBundleID: safari, playerBundleID: spotify))
    }

    func testAnUnidentifiedSourceFallsBackToTheCover() {
        // No tap, or nothing reporting output — better the player's cover than
        // blanking a wave that is probably its own.
        XCTAssertTrue(WaveTints.playerOwnsTheAudio(
            hasCover: true, sourceBundleID: nil, playerBundleID: spotify))
    }

    func testNoCoverMeansTheSourceAppAlwaysWins() {
        XCTAssertFalse(WaveTints.playerOwnsTheAudio(
            hasCover: false, sourceBundleID: safari, playerBundleID: spotify))
        XCTAssertFalse(WaveTints.playerOwnsTheAudio(
            hasCover: false, sourceBundleID: nil, playerBundleID: spotify))
    }

    /// Cover-only decorations must not leak onto an app-icon tint: `coverBars`
    /// describes an album sleeve's per-column colours and has no app-icon
    /// equivalent, so a Safari wave draws in one accent rather than borrowing
    /// whatever the last sleeve quantised to.
    func testAppIconTintCarriesNoCoverDecorations() {
        let tints = WaveTints(primary: .blue, fromCover: false)
        XCTAssertNil(tints.coverBars)
        XCTAssertFalse(tints.fromCover)
    }
}
