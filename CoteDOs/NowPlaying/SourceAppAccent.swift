import AppKit
import Combine
import SwiftUI

/// The icon and accent colour of whichever app is currently producing audio.
///
/// `SpectrumAnalyzer` answers *which* app is making the sound (`sourceBundleID`);
/// this turns that bundle ID into the two things the UI actually wants — the
/// app's icon for the pill's thumbnail, and an accent colour to tint the wave
/// with, so system audio with no scriptable track (a Safari video, a call) gets
/// Safari's blue instead of a flat white run.
///
/// A process-lifetime singleton read straight from view bodies, following
/// `PowerSource`: the alternative is threading a tenth model through
/// `AppDelegate` → `NotchWindowController` → `NotchRootView` → every wave, and
/// the waves that need this are spread across the pill, the spectrum page and
/// the fullscreen takeover. Views observe it directly
/// (`@ObservedObject private var sourceApp = SourceAppAccent.shared`) rather
/// than reaching it through the analyzer — a nested `ObservableObject` doesn't
/// propagate its changes to whoever observes the outer one.
final class SourceAppAccent: ObservableObject {
    static let shared = SourceAppAccent()

    /// The source app's icon, or nil when there's no audio or the bundle ID
    /// doesn't resolve to an installed app.
    @Published private(set) var icon: NSImage?
    /// The source app's dominant colour, or nil while it's still being derived
    /// (extraction is off the main thread) or the icon carries no real hue.
    @Published private(set) var tint: Color?

    /// The bundle ID the current `icon`/`tint` belong to, so a late extraction
    /// callback for an app that has since stopped playing is dropped instead of
    /// tinting the wave for the wrong one.
    private var bundleID: String?
    private var cancellable: AnyCancellable?

    private init() {}

    /// Starts following `spectrum`'s source app. Called once from `AppDelegate`.
    func follow(_ spectrum: SpectrumAnalyzer) {
        cancellable = spectrum.$sourceBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.resolve($0) }
    }

    private func resolve(_ id: String?) {
        guard id != bundleID else { return }
        bundleID = id
        tint = nil
        guard let id, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            icon = nil
            return
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icon = image
        // Same extraction the covers go through, so an app icon and an album
        // sleeve are tinted by one set of rules. Cached per bundle ID inside
        // `ArtworkColor`, so this only really runs once per app.
        ArtworkColor.fetch(from: image, cacheKey: id) { [weak self] color in
            guard let self, self.bundleID == id else { return }
            self.tint = color
        }
    }
}
