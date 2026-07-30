import AppKit
import Combine
import SwiftUI

/// Whether the user has asked macOS for less movement, and what the island
/// should do about it.
///
/// This app is mostly motion — a pill that springs open in four stages, a wave
/// that travels between two hosts, a run that grows to fill the screen. All of
/// that is exactly what *Settings → Accessibility → Display → Reduce Motion*
/// exists to switch off, and until now the setting did nothing here.
///
/// The rule adopted: **transitions become crossfades, content keeps moving.**
/// The staged morph is decoration — it communicates nothing the end state
/// doesn't — so with Reduce Motion on, the island simply arrives. The spectrum
/// keeps animating, because the spectrum *is* the information; freezing it would
/// be like muting a music player to reduce motion. Apple's own visualizers make
/// the same call.
///
/// `NSWorkspace`, not `@Environment(\.accessibilityReduceMotion)`: most of the
/// timing lives in `NotchLayout` as plain constants read from AppKit controller
/// code, where there is no SwiftUI environment to read.
@MainActor
final class Motion: ObservableObject {
    static let shared = Motion()

    /// Published so SwiftUI redraws when the user flips the setting while the app
    /// is running, which is the case a `let` read at launch gets wrong.
    @Published private(set) var reduced: Bool

    private init() {
        reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    /// Reads without the main-actor hop, for the `NotchLayout` constants.
    ///
    /// The value is a process-wide accessibility flag that AppKit caches, so this
    /// is a cheap read rather than IPC, and every caller is on the main thread
    /// anyway — they are animation curves being handed to SwiftUI.
    nonisolated static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `animation` normally; a short crossfade when the user wants less movement.
    ///
    /// Deliberately not `nil`/`.none`: an instant state change makes the island
    /// *pop*, which reads as a glitch rather than as calm. A 0.12 s fade is the
    /// shortest duration that still looks intentional.
    nonisolated static func gate(_ animation: Animation) -> Animation {
        isReduced ? .easeInOut(duration: 0.12) : animation
    }
}
