import AppKit
import Combine
import SwiftUI

/// Aggregates the available media sources into one observable now-playing state.
/// Picks the active source automatically (or per user preference), and keeps the
/// AppleScript traffic down to a hard refresh every 5 s plus the players' own
/// change notifications — the position in between is interpolated locally, once a
/// second, so a moving progress bar costs no IPC at all.
final class NowPlayingManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPlaying = false
    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var isShuffling = false
    /// A queried player is running but macOS is blocking our Apple Events, and
    /// there's nothing to show. Drives the "grant Automation access" prompt.
    @Published private(set) var permissionDenied = false
    @Published private(set) var activeSourceID: UserSettings.MediaSource = .spotify

    /// Accent colour derived from the current cover, tinting the wave visualizer.
    /// nil when there's no artwork (e.g. Apple Music) — the wave then draws white.
    @Published private(set) var artworkColor: Color?
    /// Quantised per-column cover colours — the wave's actual palette; nil when
    /// there's no artwork, and the run then draws in `artworkColor` alone.
    @Published private(set) var coverBars: CoverBarPalette?
    /// The artwork URL the current `artworkColor` was computed for, so we only
    /// recompute when the cover actually changes.
    private var artworkColorURL: URL?

    /// False while the display sleeps: the visualizer reads this to stop its
    /// 30fps animation when nobody can see it (the idle-drain class reported
    /// against every competing notch app). See `setScreensAwake`.
    @Published private(set) var screensAwake = true

    private let spotify = SpotifySource()
    private let music = AppleMusicSource()
    private var sources: [ScriptableMediaSource] { [spotify, music] }
    private var active: ScriptableMediaSource

    private let settings: UserSettings
    private var timer: Timer?
    /// Whether `start()` is in effect (distinguishes a screen-sleep pause, which
    /// keeps us "started", from a full `stop()`).
    private var isStarted = false
    private var secondsSinceHardRefresh = 0
    /// Real AppleScript refresh cadence: tight while playing (smooth position),
    /// relaxed when idle so an unused player doesn't cost a script every 5s.
    /// Genuine playback changes still arrive instantly via DistributedNotificationCenter.
    private let refreshIntervalActive = 5
    private let refreshIntervalIdle = 20
    private var currentRefreshInterval: Int { isPlaying ? refreshIntervalActive : refreshIntervalIdle }
    private var cancellable: AnyCancellable?

    init(settings: UserSettings = .shared) {
        self.settings = settings
        self.active = spotify
    }

    // MARK: Lifecycle

    func start() {
        for source in sources {
            if let name = source.changeNotification {
                DistributedNotificationCenter.default().addObserver(
                    self, selector: #selector(playbackChanged), name: name, object: nil
                )
            }
        }
        // Re-evaluate immediately when the user changes the preferred source.
        cancellable = settings.$mediaSource
            .dropFirst()
            .sink { [weak self] _ in self?.hardRefresh() }

        isStarted = true
        hardRefresh()
        startTimer()
    }

    func stop() {
        isStarted = false
        stopTimer()
        cancellable = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Pause/resume the per-second work and the visualizer when the display
    /// sleeps/wakes. We keep the (event-driven, cheap) DistributedNotificationCenter
    /// observers so playback state is still current the moment the screen wakes.
    func setScreensAwake(_ awake: Bool) {
        guard awake != screensAwake else { return }
        screensAwake = awake
        guard isStarted else { return }
        if awake {
            startTimer()
            hardRefresh()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func playbackChanged() { hardRefresh() }

    private func tick() {
        secondsSinceHardRefresh += 1
        if secondsSinceHardRefresh >= currentRefreshInterval {
            hardRefresh()
            return
        }
        // Cheap local interpolation: advance the progress bar without IPC.
        guard isPlaying, let duration = track?.duration else { return }
        position = min(position + 1, duration)
    }

    // MARK: Source selection & publishing

    /// Which sources to actually query: all in auto mode (to detect the active
    /// app), only the chosen one otherwise.
    private func sourcesToQuery() -> [ScriptableMediaSource] {
        switch settings.mediaSource {
        case .auto: return sources
        case .spotify: return [spotify]
        case .appleMusic: return [music]
        }
    }

    private func hardRefresh() {
        secondsSinceHardRefresh = 0
        let group = DispatchGroup()
        for source in sourcesToQuery() {
            group.enter()
            source.refresh { _ in group.leave() }
        }
        group.notify(queue: .main) { [weak self] in self?.publishActive() }
    }

    private func selectActive() -> ScriptableMediaSource {
        switch settings.mediaSource {
        case .spotify: return spotify
        case .appleMusic: return music
        case .auto:
            if spotify.state.isPlaying { return spotify }
            if music.state.isPlaying { return music }
            if spotify.state.isRunning, spotify.state.track != nil { return spotify }
            if music.state.isRunning, music.state.track != nil { return music }
            return spotify
        }
    }

    private func publishActive() {
        active = selectActive()
        let s = active.state
        activeSourceID = active.id
        isRunning = s.isRunning
        isPlaying = s.isPlaying
        track = s.track
        position = s.position
        isShuffling = s.isShuffling
        // Only prompt when we have nothing to show anyway: any queried source
        // being blocked, with no track surfaced, means the denial is the reason.
        permissionDenied = s.track == nil && sourcesToQuery().contains { $0.state.permissionDenied }
        refreshArtworkColor(for: s.track?.artworkURL)
    }

    #if DEBUG
    /// Publish a fabricated playback state, bypassing the AppleScript sources.
    ///
    /// The only other way to get a track into this object is for a real player
    /// to be running and scriptable, which an offscreen render has no way to
    /// arrange — so the marketing shots would otherwise have to be taken of
    /// "Nothing playing". Goes through the same assignments and the same
    /// artwork pipeline as `publishActive`, so what renders is what the real
    /// path would have produced.
    func applyForTesting(_ state: NowPlayingState) {
        isRunning = state.isRunning
        isPlaying = state.isPlaying
        track = state.track
        position = state.position
        isShuffling = state.isShuffling
        permissionDenied = state.permissionDenied
        refreshArtworkColor(for: state.track?.artworkURL)
    }
    #endif

    /// Recompute the wave tint only when the cover changes; clear it when there's
    /// no artwork so the visualizer falls back to white.
    private func refreshArtworkColor(for url: URL?) {
        guard url != artworkColorURL else { return }
        artworkColorURL = url
        guard let url else {
            artworkColor = nil
            coverBars = nil
            return
        }
        ArtworkColor.fetch(from: url) { [weak self] accents in
            // Ignore a late result for a cover we've already moved on from.
            guard let self, self.artworkColorURL == url else { return }
            self.artworkColor = accents?.primary
        }
        ArtworkColor.fetchBarPalette(from: url) { [weak self] palette in
            guard let self, self.artworkColorURL == url else { return }
            self.coverBars = palette
        }
    }

    // MARK: Transport (forward to active source)

    func playPause() { active.playPause(); scheduleQuickRefresh() }
    func nextTrack() { active.nextTrack(); scheduleQuickRefresh() }
    func previousTrack() { active.previousTrack(); scheduleQuickRefresh() }
    func toggleShuffle() { active.toggleShuffle(); scheduleQuickRefresh() }

    /// Scrub to `seconds`. Updates the local position immediately so the bar
    /// tracks the drag, then confirms with a refresh.
    func seek(to seconds: TimeInterval) {
        guard let duration = track?.duration, duration > 0 else { return }
        let target = min(max(seconds, 0), duration)
        position = target
        active.seek(to: target)
        scheduleQuickRefresh()
    }

    /// Open the current song in its app: the deep link when we have one
    /// (Spotify), otherwise just bring the player to the front (Apple Music).
    func openCurrentTrack() {
        // Only follow the player's deep link for schemes we expect; anything
        // else falls back to bringing the app forward rather than handing an
        // arbitrary URL to the system opener.
        let allowedSchemes: Set<String> = ["spotify", "https", "http"]
        if let url = track?.url, let scheme = url.scheme?.lowercased(),
           allowedSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
        } else {
            active.activate()
        }
    }

    private func scheduleQuickRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.hardRefresh()
        }
    }

}
