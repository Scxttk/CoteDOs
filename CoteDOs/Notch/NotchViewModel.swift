import Combine
import SwiftUI

final class NotchViewModel: ObservableObject {
    enum Tab: CaseIterable {
        case music
        case spectrum
        case files
        case capture
        case timer
        case claude

        var title: String {
            switch self {
            case .music:   return String(localized: "tab.music", defaultValue: "Musik")
            case .spectrum: return String(localized: "tab.spectrum", defaultValue: "Spectrum")
            case .files:   return String(localized: "tab.files", defaultValue: "Ablage")
            case .capture: return String(localized: "tab.capture", defaultValue: "Capture")
            case .timer:   return String(localized: "tab.timer", defaultValue: "Timer")
            case .claude:  return String(localized: "tab.claude", defaultValue: "Claude")
            }
        }

        var icon: String {
            switch self {
            case .music:   return "waveform"   // the app's own identity, not a note
            case .spectrum: return "chart.bar.fill"
            case .files:   return "tray.full"
            case .capture: return "square.and.pencil"
            case .timer:   return "timer"
            case .claude:  return "steeringwheel"   // fallback; rendered as the 🦀 (see TabIcon)
            }
        }

        /// Tabs whose icon is an emoji glyph instead of an SF Symbol — SF
        /// Symbols simply doesn't stock a crab, and the Claude tab gets
        /// Claude Code's crab.
        var emojiIcon: String? {
            self == .claude ? "🦀" : nil
        }
    }

    /// The island's visual state. Collapsing is staged (iPhone-style):
    /// - `.band`  — capsule holding all three tab groups (icon + label).
    /// - `.solo`  — only the selected tab group remains (icon + label), the
    ///   others having faded out as the capsule narrows onto it.
    /// - `.condensing` — the label drops too; just the selected icon is left,
    ///   the capsule now exactly pill-width and -positioned.
    /// - `.collapsed` — the real pill content swaps in, pixel-identical to the
    ///   condensed icon, so the handover is invisible.
    /// The controller orchestrates the steps; only `.expanded` and `.collapsed`
    /// are resting states, the rest are transient stops on the way down.
    enum IslandState {
        case expanded
        case band
        case solo
        case condensing
        case collapsed
    }

    @Published var islandState: IslandState = .collapsed {
        didSet {
            // Any step away from rest invalidates the mounted pages — the
            // collapse-side removal fade keys off this flipping false at the
            // very first collapse hop, and a later expand must re-earn it
            // via the controller's settle timer (see `pagesSettleDelay`).
            if islandState != .expanded { pagesSettled = false }
            // Only a *closed* island resets the tab bar's entrance. On the way
            // down it has to stay visible: the selected icon is what the pill's
            // glyph is handed over from, and that handover is pixel-tuned.
            if islandState == .collapsed { chromeRevealed = false }
        }
    }

    /// True once the island has rested in `.expanded` long enough to afford
    /// mounting the page carousel (the heaviest view-building moment).
    /// Set by the controller; cleared automatically whenever the island
    /// leaves `.expanded`.
    @Published var pagesSettled = false {
        didSet {
            guard pagesSettled != oldValue else { return }
            guard pagesSettled else { spectrumWaveLanded = false; return }
            // One runloop tick after the pages mount, so the spectrum page's
            // wave draws its first frame back up at the pill's size and place
            // and *then* travels down into the panel.
            //
            // This lives on the view model rather than in the page's own
            // `onAppear` for a reason that cost two attempts to find: a state
            // change made while a view is still being installed is folded into
            // its insertion and animates not at all, so a wave that drove its
            // own morph never moved however long the spring was.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pagesSettled else { return }
                withAnimation(NotchLayout.islandMorphAnimation) { self.spectrumWaveLanded = true }
                // The tab bar is the last thing to arrive: the island opens, the
                // wave travels into place, and only then does the chrome fade
                // up around it. Showing all three at once made the wave read as
                // arriving *behind* an interface that was already there.
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchLayout.chromeRevealDelay) { [weak self] in
                    guard let self, self.pagesSettled else { return }
                    withAnimation(NotchLayout.contentInsertAnimation) { self.chromeRevealed = true }
                }
            }
        }
    }

    /// False while the spectrum page's wave is still "in flight" from the pill.
    /// Drives the pill⇄page morph — see `SpectrumStageView.morphOrigin`.
    @Published private(set) var spectrumWaveLanded = false

    /// False until the wave has landed, so the tab bar enters last.
    @Published private(set) var chromeRevealed = false

    /// The logical open/closed state — `.band` counts as closed (it's a
    /// transient stop on the way down; hover/gesture logic treats it like the
    /// pill so a re-hover immediately re-expands).
    var isExpanded: Bool { islandState == .expanded }

    /// True whenever the island is *not* fully collapsed — i.e. at `.expanded`
    /// or anywhere along the staged collapse/expand walk (`.band`/`.solo`/
    /// `.condensing`). The click hit-test rect keys off this so it stays at the
    /// large footprint while the silhouette is still visibly springing down,
    /// instead of snapping to the tiny pill the instant the logical state
    /// flips. Without it the collapsing island can't be caught and clicks fall
    /// through mid-walk. Hover uses the stricter `isExpanded` instead (see
    /// `NotchWindowController.evaluateHover`) — a cursor sitting in the
    /// leftover space of a collapsing/expanding notch shouldn't reopen it,
    /// only actually hovering the pill should.
    var occupiesExpandedFootprint: Bool { islandState != .collapsed }

    @Published var selectedTab: Tab = .music

    /// The tabs actually offered — each tab can be switched off in Settings.
    /// Used by the tab bar and the swipe pager; the carousel itself keeps all
    /// pages mounted (indices stay stable, the page is just unreachable while
    /// disabled). The Settings UI guarantees at least one tab stays enabled.
    static var enabledTabs: [Tab] {
        Tab.allCases.filter { UserSettings.shared.isTabEnabled($0) }
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // If the currently selected tab gets disabled in Settings, fall back to
        // the first enabled tab — otherwise the island would sit on a page the
        // tab bar no longer offers. Receive on main so `enabledTabs` is read
        // *after* the setting actually changed (`objectWillChange` fires before).
        UserSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let enabled = Self.enabledTabs
                if !enabled.contains(self.selectedTab), let fallback = enabled.first {
                    self.selectedTab = fallback
                }
            }
            .store(in: &cancellables)
    }

    /// While true (e.g. the capture field is focused) the island won't auto-
    /// collapse when the cursor leaves it — otherwise typing would dismiss it.
    @Published var isInteractionLocked: Bool = false

    /// Bumped to ask the capture field to take focus (e.g. via the global hotkey).
    @Published var captureFocusToken: Int = 0

    func requestCaptureFocus() {
        guard Self.enabledTabs.contains(.capture) else { return }
        selectedTab = .capture
        captureFocusToken += 1
    }

    // Visible island dimensions (sourced from NotchLayout).
    /// Taller while the spectrum-only pill is on — that mode is for watching,
    /// and the extra height is the bars' travel. Single source for the
    /// silhouette, the hit/hover rects and the content rows' pinning, so the
    /// pill can't end up taller than the area that reacts to it.
    var collapsedHeight: CGFloat { NotchLayout.currentCollapsedHeight }
    var expandedWidth: CGFloat { NotchLayout.expandedWidth }
    var expandedHeight: CGFloat { NotchLayout.expandedHeight }

    /// Collapsed pill width, computed to hug whatever the pill actually shows.
    /// Depends on playback (artwork + visualizer are wider than the idle
    /// glyph), the focus-timer readout (replaces the glyph when idle, joins to
    /// the right of the visualizer when playing) and the shelf badge, plus the
    /// end padding that keeps content clear of the capsule's corner curve —
    /// otherwise the clip swallows edges.
    func collapsedWidth(isPlaying: Bool, hasItems: Bool, timerText: String?) -> CGFloat {
        var core: CGFloat
        if isPlaying {
            // Spectrum-only mode drops the artwork thumbnail and lets the wave
            // span the freed space; by construction the two variants are the
            // same width, but both read their own constant so neither silently
            // drifts if one is retuned.
            core = UserSettings.shared.pillSpectrumOnly
                ? NotchLayout.pillSpectrumSnappedWidth(UserSettings.shared.pillSpectrumWidth)
                : NotchLayout.collapsedArtworkWidth + NotchLayout.collapsedItemSpacing + NotchLayout.collapsedWavesWidth
            if let timerText {
                core += NotchLayout.collapsedItemSpacing + Self.timerSegmentWidth(timerText)
            }
        } else if let timerText {
            core = Self.timerSegmentWidth(timerText)
        } else {
            core = NotchLayout.collapsedGlyphWidth
        }
        if hasItems {
            core += NotchLayout.collapsedItemSpacing + NotchLayout.collapsedBadgeWidth
        }
        return core + 2 * (NotchLayout.collapsedContentPadding + NotchLayout.collapsedEndPadding)
    }

    /// How far the collapsed capsule's *frame* shifts right of screen centre so
    /// the audio hero core stays exactly centred while the trailing segments
    /// (timer readout, shelf badge) grow to the right of it. Zero without the
    /// hero: a timer-only or idle pill stays symmetric as before. The trailing
    /// segments' centre sits `trailing/2` right of the frame centre, so
    /// shifting the frame by that amount puts the hero core back on
    /// `screen.midX`. Must stay in lock-step with `collapsedWidth` — both read
    /// the very same `NotchLayout` constants, or the visible pill and the
    /// hit/hover rects drift apart.
    func collapsedTrailingShift(isPlaying: Bool, hasItems: Bool, timerText: String?) -> CGFloat {
        guard isPlaying else { return 0 }
        var trailing: CGFloat = 0
        if let timerText {
            trailing += NotchLayout.collapsedItemSpacing + Self.timerSegmentWidth(timerText)
        }
        if hasItems {
            trailing += NotchLayout.collapsedItemSpacing + NotchLayout.collapsedBadgeWidth
        }
        return trailing / 2
    }

    /// Estimated width of the pill's timer segment (icon + readout). Must stay
    /// in lock-step with the segment layout in `CollapsedView`.
    private static func timerSegmentWidth(_ text: String) -> CGFloat {
        NotchLayout.collapsedTimerIconWidth + NotchLayout.collapsedTimerInnerSpacing
            + CGFloat(text.count) * NotchLayout.collapsedTimerCharWidth
    }

    /// Width of the intermediate `.solo` capsule. The icon is pinned at the
    /// capsule *centre* (its final pill position) with the label trailing to
    /// the right, so collapsing on further only fades the label and shrinks the
    /// capsule — the icon never moves. Keeping the icon centred means the label
    /// width is mirrored as empty space on the left, hence the label counts
    /// twice. The estimate errs generous; slight looseness is harmless,
    /// clipping is not.
    func soloWidth(for tab: Tab) -> CGFloat {
        let labelWidth = CGFloat(tab.title.count) * NotchLayout.soloLabelCharWidth
        return NotchLayout.soloBaseWidth + 2 * labelWidth
    }

    // The panel keeps a constant size; only the SwiftUI island animates.
    // Extra margin leaves room for the island's shadow.
    var panelWidth: CGFloat { expandedWidth + NotchLayout.panelHorizontalMargin }
    var panelHeight: CGFloat { expandedHeight + NotchLayout.panelVerticalMargin }
}
