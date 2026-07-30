import AppKit
import Combine
import CoreGraphics
import IOKit.pwr_mgt
import SwiftUI

/// Puts the fullscreen spectrum up as a screensaver: leave the Mac alone with
/// music running and, just before macOS would blank the display, the spectrum
/// takes the screen instead. Touch anything and it shrinks away again.
///
/// It stands *in front of* the display sleeping rather than after it — the
/// takeover holds a display-sleep assertion for as long as it is up (see
/// `SpectrumFullscreenController`), so the screen stays lit and the Mac doesn't
/// walk on into its lock screen while you're out of the room.
///
/// Deliberately only with audible audio: a spectrum of silence is a black
/// screen with a flat line on it, which is worse than what macOS would have
/// done. Whether anything is audible comes from the tap itself
/// (`SpectrumAnalyzer.hasSignal`), not from a player's play/pause state, so a
/// browser video counts the same as Spotify.
///
/// It ends the way a screensaver ends: into the lock screen. Whatever takes the
/// takeover down — a keystroke, the cursor moving, Esc, the swipe, or the music
/// running out while nobody is there — the Mac locks behind it. That is the
/// half of the display-sleep behaviour this feature displaces, and it has to be
/// given back. A takeover put up by hand is untouched by any of this.
final class IdleSpectrumMonitor {

    /// Why an armed takeover ended, and when. Kept until the Mac is unlocked
    /// again and then shown in the pill: the lock screen you come back to looks
    /// the same whether you ended the guard yourself, somebody else touched the
    /// Mac, or the music simply ran out — and the *time* is what tells those
    /// apart. "Eingabe 14:02" on a Mac you left at 13:50 is somebody else.
    struct EndReport: Equatable {
        enum Cause: Equatable { case input, silence }
        let cause: Cause
        let at: Date
    }

    private let spectrum: SpectrumAnalyzer
    private let settings: UserSettings
    private weak var activities: ActivityManager?
    private let state = SpectrumFullscreen.shared
    private var timer: Timer?
    /// Since when the tap has heard nothing. The takeover survives a gap
    /// between tracks; it doesn't survive the music being over.
    private var silentSince: Date?
    /// Whether the takeover currently up was started by this monitor. Only
    /// those are given up when the music stops — a hotkey takeover put up in a
    /// silent room is exactly as wanted as one put up over Spotify.
    private var presentedByMonitor = false
    /// Whether the takeover currently up is guarding the Mac (see
    /// `SpectrumFullscreen.isArmed`). Copied when it appears rather than read
    /// on demand, because it has to survive being read *after* the takeover is
    /// already gone — that is the moment the lock is owed.
    private var armed = false
    /// Whether the Mac has been left alone at least once since the takeover
    /// appeared. Until then input is ignored: arming with ⌥⌘S is itself a
    /// keystroke, and a hand still resting on the trackpad would otherwise end
    /// the takeover — and lock the Mac — half a second after it arrived.
    private var handsOff = false
    /// Why the takeover is being taken down, set just before asking for the
    /// dismissal — the lock and the report both hang off `isPresented` going
    /// false, which by then no longer knows what caused it.
    private var pendingCause: EndReport.Cause?
    /// Waiting to be shown once the Mac is unlocked. There is no point
    /// presenting a pill nobody can see behind the lock screen.
    private var unreportedEnd: EndReport?
    private var cancellables: Set<AnyCancellable> = []
    private var unlockObserver: NSObjectProtocol?

    /// How long before the display would go dark the spectrum takes over. Just
    /// enough to be there first; any earlier and it would interrupt a Mac the
    /// user is still glancing at.
    static let leadSeconds: TimeInterval = 15
    /// Never take over sooner than this, whatever the system timer says.
    static let minimumIdleSeconds: TimeInterval = 30
    /// Used when macOS is set to never sleep the display: "never" is a
    /// statement about blanking the screen, not about wanting no screensaver,
    /// so the feature still runs — just on its own conservative clock.
    static let fallbackIdleSeconds: TimeInterval = 300
    /// Fresh input has to be at most this old to count as "the user is back".
    /// Not zero: the poll itself lands somewhere inside the second.
    private static let inputResetSeconds: TimeInterval = 2
    /// Silence tolerated before the takeover gives up — long enough to cover
    /// track changes, an ad break, or a paused video someone comes back to.
    private static let silenceGraceSeconds: TimeInterval = 90
    /// Checking idle time is a cheap CGEventSource read; the fast rate is only
    /// so the takeover gets out of the way promptly once the user is back.
    private static let watchInterval: TimeInterval = 5
    private static let presentedInterval: TimeInterval = 0.5

    init(spectrum: SpectrumAnalyzer, activities: ActivityManager? = nil, settings: UserSettings = .shared) {
        self.spectrum = spectrum
        self.activities = activities
        self.settings = settings
    }

    func start() {
        schedule(interval: Self.watchInterval)
        // Locking hangs off the takeover actually being gone, not off the
        // reason it went: Esc and the swipe-up gesture are handled inside the
        // takeover itself and never come through `tick()`, and they are input
        // like any other. Fires at `finishDismissal`, so the shrink animation
        // plays out first and the lock screen lands on an empty desktop.
        state.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented {
                    self.armed = self.state.isArmed
                    self.handsOff = false
                    self.silentSince = nil
                    return
                }
                let wasArmed = self.armed
                let cause = self.pendingCause
                self.armed = false
                self.presentedByMonitor = false
                self.handsOff = false
                self.silentSince = nil
                self.pendingCause = nil
                guard wasArmed else { return }
                // Esc and the swipe are input as much as a keystroke is; only
                // the silence rule names itself, so anything unlabelled is
                // somebody having touched the Mac.
                self.unreportedEnd = EndReport(cause: cause ?? .input, at: Date())
                ScreenLock.lockNow()
            }
            .store(in: &cancellables)

        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.reportEnd()
        }
        // The unlock may already have happened — the monitor is torn down with
        // the screen and rebuilt on wake, and on some wakes that lands after
        // the notification has been and gone.
        reportEnd()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
        }
        unlockObserver = nil
        silentSince = nil
        presentedByMonitor = false
        armed = false
        handsOff = false
    }

    deinit { stop() }

    private func schedule(interval: TimeInterval) {
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: Decisions

    private func tick() {
        let idle = Self.idleSeconds()
        if state.isPresented {
            schedule(interval: Self.presentedInterval)
            if idle >= Self.inputResetSeconds { handsOff = true }
            // A takeover nobody armed is just something to look at: it stays
            // until its own gesture or Esc takes it down.
            guard armed else { return }
            // The lock rides on `isPresented` going false (see `start()`), so
            // this only has to ask for the dismissal.
            if handsOff, idle < Self.inputResetSeconds {
                pendingCause = .input
                state.dismiss()
            } else if presentedByMonitor, outOfMusic() {
                pendingCause = .silence
                state.dismiss()
            }
            return
        }

        schedule(interval: Self.watchInterval)
        guard settings.spectrumScreensaverEnabled,
              spectrum.hasSignal,
              !Self.screenIsLocked(),
              !Self.displaySleepPrevented(),
              idle >= idleThreshold()
        else { return }
        // Armed: an idle Mac is an unattended one, so this takeover guards it
        // exactly like the hotkey's does.
        state.present(armed: true)
        presentedByMonitor = true
    }

    /// Show what ended the guard, once there is somebody in front of an
    /// unlocked Mac to see it. The clock time is the point of the whole thing —
    /// "Eingabe" alone says nothing, "Eingabe 14:02" on a Mac left at 13:50
    /// says somebody was here.
    private func reportEnd() {
        guard let report = unreportedEnd, !Self.screenIsLocked() else { return }
        unreportedEnd = nil
        let clock = Self.clockFormatter.string(from: report.at)
        let title: String
        let icon: String
        let tint: Color
        switch report.cause {
        case .input:
            title = String(localized: "activity.guardEnded.input", defaultValue: "Eingabe \(clock)")
            icon = "hand.tap.fill"
            tint = .orange
        case .silence:
            title = String(localized: "activity.guardEnded.silence", defaultValue: "Ton aus \(clock)")
            icon = "speaker.slash.fill"
            tint = .white
        }
        activities?.present(NotchActivity(
            kind: .fileReceived,    // generic "something happened" slot
            priority: 4,
            icon: icon,
            tint: tint,
            title: title,
            autoDismiss: 6
        ))
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// True once the tap has been silent past the grace period. Tracked here
    /// rather than read as an instant "is it quiet right now", so the takeover
    /// isn't torn down by the two seconds between two songs.
    private func outOfMusic() -> Bool {
        guard !spectrum.hasSignal else {
            silentSince = nil
            return false
        }
        guard let since = silentSince else {
            silentSince = Date()
            return false
        }
        return Date().timeIntervalSince(since) >= Self.silenceGraceSeconds
    }

    /// How long the Mac has to sit untouched: the system's own display-sleep
    /// timer for the current power source, minus the lead.
    func idleThreshold() -> TimeInterval {
        Self.idleThreshold(displaySleepMinutes: Self.systemDisplaySleepMinutes())
    }

    /// The pure half, so the arithmetic is testable without a Mac's power
    /// settings underneath it. `nil` (unreadable) and 0 ("never") both fall
    /// back to the fixed clock.
    static func idleThreshold(displaySleepMinutes: Int?) -> TimeInterval {
        guard let minutes = displaySleepMinutes, minutes > 0 else { return fallbackIdleSeconds }
        return max(minimumIdleSeconds, TimeInterval(minutes) * 60 - leadSeconds)
    }

    // MARK: System state

    /// Seconds since the last human input anywhere on the system — keyboard,
    /// mouse, trackpad. `combinedSessionState` so input to *other* apps counts
    /// too; this app is usually not the one being typed into.
    static func idleSeconds() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    /// macOS's display-sleep timer in minutes for the power source in use, read
    /// from the same preferences `pmset -g` prints. 0 means never; nil means the
    /// file wasn't there or didn't have the shape expected.
    ///
    /// There is no public API for this — `IOPMCopyActivePMPreferences` is C-only
    /// and unavailable to Swift, and `IOPMrootDomain` doesn't publish the
    /// timers — so the preference file is read directly. It is world-readable
    /// and only touched when something changes it, so this is a plist parse a
    /// handful of times a day, not a hot path.
    static func systemDisplaySleepMinutes(onBattery: Bool = PowerSource.shared.isOnBattery) -> Int? {
        let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.PowerManagement.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let profile = onBattery ? "Battery Power" : "AC Power"
        guard let source = plist[profile] as? [String: Any] else { return nil }
        return source["Display Sleep Timer"] as? Int
    }

    /// True while something else is deliberately holding the display awake: a
    /// video playing (WebKit takes this out for every `HTMLMediaElement`, which
    /// is what a fullscreen YouTube or Twitch tab is), a video call, a
    /// `caffeinate`.
    ///
    /// Without this the monitor read "nobody has touched the keyboard for three
    /// minutes" as "the display is about to go dark" — and put the spectrum
    /// over a video somebody was watching. Untouched is not idle; the display
    /// sleeping is idle, and this is the difference between the two.
    ///
    /// Only checked while no takeover is up, so the app's own assertion (held
    /// for the duration of one) can never be what this sees.
    static func displaySleepPrevented() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let counts = status?.takeRetainedValue() as? [String: Any]
        else { return false }
        // Deliberately *not* `InternalPreventDisplaySleep`: powerd holds that
        // one around its own display-off transitions and it reads as active on
        // an otherwise idle Mac, which would switch the feature off for good.
        let held = counts[kIOPMAssertionTypePreventUserIdleDisplaySleep as String] as? Int ?? 0
        return held > 0
    }

    /// Nothing should be put on top of the lock screen.
    static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Int) == 1
    }
}
