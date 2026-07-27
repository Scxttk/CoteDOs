import AppKit
import Combine
import SwiftUI

/// The spectrum taking over the whole screen — for a room with music in it, or
/// as something to have on while reading instead of a Mac to stare at.
///
/// `SpectrumStageView` was already resolution-independent (that is what the
/// spectrum page and the pill are both built on), so this is window plumbing
/// plus the same grow/shrink morph one step up: the run starts at the geometry
/// the island's page just had and expands to fill the screen, and two fingers
/// up plays that backwards before the window closes.
///
/// The gesture is the whole point of the vocabulary: one vertical axis carries
/// the spectrum through all three of its sizes. Down opens the pill into the
/// island and the island into the screen; up walks it back.
final class SpectrumFullscreenController {
    private var window: NSWindow?
    private var scrollMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    private let spectrum: SpectrumAnalyzer
    private let nowPlaying: NowPlayingManager
    private let state = SpectrumFullscreen.shared

    /// How long the shrink-back is given before the window closes. Matches
    /// `NotchLayout.islandMorphAnimation`'s response with a little slack, so the
    /// wave has actually landed by the time the black goes away.
    private static let dismissDuration: TimeInterval = 0.45

    init(spectrum: SpectrumAnalyzer, nowPlaying: NowPlayingManager) {
        self.spectrum = spectrum
        self.nowPlaying = nowPlaying

        state.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                if presented { self?.show() } else { self?.close() }
            }
            .store(in: &cancellables)

        state.$isCollapsing
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.scheduleClose() }
            .store(in: &cancellables)
    }

    private func show() {
        guard window == nil, let screen = NSScreen.main else { return }

        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        // Above the menu bar and the notch panel itself: the takeover should
        // cover the Mac, not sit in it.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.hasShadow = false

        let root = SpectrumFullscreenView(
            levels: spectrum.bands,
            spectrum: spectrum,
            nowPlaying: nowPlaying,
            state: state,
            screenSize: screen.frame.size
        )
        window.contentView = NSHostingView(rootView: root)
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window

        // A local event monitor only sees events while this app is active, and a
        // menu-bar app is not key by default — so take focus for the duration of
        // the takeover, or the swipe back out would never reach us. The hotkey
        // works either way (Carbon, system-wide).
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installScrollMonitor()
    }

    /// Two fingers up sends it back to the island — the same axis that brought
    /// it here, in reverse. Deliberately the *only* pointer-driven way out: a
    /// stray click should not end a visual that is meant to be left running.
    /// ⌥⌘S remains as the failsafe.
    private func installScrollMonitor() {
        removeScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard event.scrollingDeltaY < -NotchLayout.gestureScrollThreshold,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            self?.state.dismiss()
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    /// The view is already animating the wave back down; give it that long
    /// before the window disappears.
    private func scheduleClose() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissDuration) { [weak self] in
            self?.state.finishDismissal()
        }
    }

    private func close() {
        removeScrollMonitor()
        window?.orderOut(nil)
        window = nil
    }
}

/// The fullscreen content: black, and the wave.
private struct SpectrumFullscreenView: View {
    @ObservedObject var levels: SpectrumBands
    @ObservedObject var spectrum: SpectrumAnalyzer
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var state: SpectrumFullscreen
    /// The screen this is filling, for working out how far the wave has to grow.
    let screenSize: CGSize

    /// Fades the black in with the wave rather than slamming it on.
    @State private var shown = false
    /// Whether the run has finished travelling out of the island's page. Flipped
    /// a tick after appearing, for the same reason the island's own morph is
    /// driven from the view model: a state change during installation does not
    /// animate.
    @State private var landed = false

    var body: some View {
        ZStack {
            Color.black
            SpectrumStageView(
                levels: levels,
                isLive: spectrum.isLive,
                isActive: nowPlaying.screensAwake,
                tint: nowPlaying.track != nil ? nowPlaying.artworkColor : nil,
                secondaryTint: nowPlaying.track != nil ? nowPlaying.artworkSecondaryColor : nil,
                tertiaryTint: nowPlaying.track != nil ? nowPlaying.artworkTertiaryColor : nil,
                coverBars: nowPlaying.track != nil ? nowPlaying.coverBars : nil,
                // One step up the same chain: fly out of the island's page near
                // the top of the screen, and back into it on the way out.
                morphOrigin: WaveMorphOrigin(
                    scale: NotchLayout.pageToFullscreenWaveScale(screenSize: screenSize),
                    offsetY: NotchLayout.pageToFullscreenWaveOffset(screenSize: screenSize)
                ),
                // Same run the island is showing, so the third leg of the morph
                // is the same wave again rather than a differently-resolved one.
                // Only while there *is* such a run to continue: without the
                // spectrum-only pill the chain does not exist, and forcing its
                // bar count here would size the fullscreen wave from a setting
                // nothing on screen is using.
                fixedBarCount: UserSettings.shared.pillSpectrumOnly
                    ? NotchLayout.pillSpectrumGeometry(
                        forWidth: UserSettings.shared.pillSpectrumWidth).barCount
                    : nil,
                landed: landed && !state.isCollapsing
            )
            .padding(NotchLayout.stageInset * 2)
        }
        .opacity(shown && !state.isCollapsing ? 1 : 0)
        .animation(.easeInOut(duration: 0.28), value: shown)
        .animation(.easeInOut(duration: 0.28), value: state.isCollapsing)
        .ignoresSafeArea()
        .onAppear {
            shown = true
            DispatchQueue.main.async {
                withAnimation(NotchLayout.islandMorphAnimation) { landed = true }
            }
        }
    }
}
