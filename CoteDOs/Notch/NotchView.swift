import SwiftUI
import AppKit

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var shelf: FileShelfModel
    @ObservedObject var activities: ActivityManager
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject var capture: ObsidianCapture
    @ObservedObject var spectrum: SpectrumAnalyzer
    /// Observed so `islandWidth` re-evaluates when the spectrum-only pill mode
    /// flips — the pill's width formula changes with it.
    @ObservedObject private var settings = UserSettings.shared
    /// Observed so the island's own wave stands down while the fullscreen
    /// takeover is up: it is completely covered by that window and would
    /// otherwise keep redrawing 30 times a second behind it.
    @ObservedObject private var fullscreen = SpectrumFullscreen.shared
    /// Icon and accent of whichever app is actually making the sound, so a
    /// Safari video tints the wave with Safari's blue instead of the paused
    /// player's cover.
    @ObservedObject private var sourceApp = SourceAppAccent.shared

    /// The colours every wave in this view draws with — one answer, so the
    /// pill's run and the page's run can't disagree mid-morph.
    private var waveTints: WaveTints {
        WaveTints.resolve(nowPlaying: nowPlaying, sourceBundleID: spectrum.sourceBundleID, sourceAppTint: sourceApp.tint)
    }

    /// Run the audio tap whenever the screen is on, regardless of whether
    /// anything is playing — `spectrum.hasSignal` (derived from the tapped
    /// signal itself, see `SpectrumAnalyzer`) is what tells the rest of the UI
    /// whether audio is actually audible right now. Gated on `screensAwake` so
    /// it isn't tapping/FFT-ing to a dark display.
    private func syncSpectrum() {
        if nowPlaying.screensAwake {
            spectrum.start()
        } else {
            spectrum.stop()
        }
    }

    /// True whenever the pill hero (cover-or-generic-icon + live wave) should
    /// take over the collapsed pill — Spotify/Music playing, or any other
    /// system audio (browser video, calls, …) with no scriptable track to show.
    private var hasAudioHero: Bool {
        nowPlaying.isPlaying || spectrum.hasSignal
    }

    private var islandWidth: CGFloat {
        switch viewModel.islandState {
        case .expanded:
            return viewModel.expandedWidth
        case .band:
            return NotchLayout.bandWidth
        case .solo:
            // Playing or timing: the pill hero (cover + spectrum and/or timer
            // readout) has already taken over, so the capsule is pill-width —
            // no tab label to make room for.
            if hasAudioHero || pomodoro.pillText != nil {
                return viewModel.collapsedWidth(isPlaying: hasAudioHero, hasItems: !shelf.items.isEmpty, timerText: pomodoro.pillText)
            }
            // Otherwise hug the single surviving tab group (selected icon + label).
            return viewModel.soloWidth(for: viewModel.selectedTab)
        case .condensing:
            // Already the pill's width: the capsule narrows onto the selected
            // icon during this stage, so the final swap changes nothing.
            return viewModel.collapsedWidth(isPlaying: hasAudioHero, hasItems: !shelf.items.isEmpty, timerText: pomodoro.pillText)
        case .collapsed:
            if let activity = activities.current {
                return activity.kind == .audioRoute ? NotchLayout.activityRouteWidth : NotchLayout.activityWidth
            }
            return viewModel.collapsedWidth(isPlaying: hasAudioHero, hasItems: !shelf.items.isEmpty, timerText: pomodoro.pillText)
        }
    }
    private var islandHeight: CGFloat {
        viewModel.isExpanded ? viewModel.expandedHeight : viewModel.collapsedHeight
    }

    /// Horizontal shift of the island *frame* off screen centre: with the audio
    /// hero active, the hero core stays centred and the trailing segments
    /// (timer, badge) grow rightward — so the whole capsule sits asymmetric by
    /// half the trailing width. Mirrors the `islandWidth` switch: the pill hero
    /// takes over from `.solo` on, so those stages already rest at the shifted
    /// position; `.expanded`/`.band` and activity pills stay centred. The shift
    /// changes inside the very same `withAnimation` transactions as the width,
    /// so it rides the staged walk's tuned springs.
    private var islandXOffset: CGFloat {
        switch viewModel.islandState {
        case .expanded, .band:
            return 0
        case .solo, .condensing, .collapsed:
            if viewModel.islandState == .collapsed, activities.current != nil { return 0 }
            return viewModel.collapsedTrailingShift(isPlaying: hasAudioHero, hasItems: !shelf.items.isEmpty, timerText: pomodoro.pillText)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
                // The island floats detached below the screen edge, iPhone-style.
                .padding(.top, NotchLayout.islandTopGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { syncSpectrum() }
        .onChange(of: nowPlaying.isPlaying) { _, playing in
            // Deliberately does *not* switch to the music tab any more. The
            // selected tab is remembered across launches now
            // (`NotchViewModel.selectedTab`), and this fired on the first poll
            // after launch — so the restored tab was overwritten with Musik
            // before it was ever seen, and every track change dragged you back
            // there. Which tab you are on is your choice, not playback's.
            syncSpectrum()
            // If the tap suspended itself after silence, a player flipping to
            // "playing" is the fastest resume signal there is — don't wait
            // for the probe.
            if playing { spectrum.pokeResume() }
        }
        .onChange(of: nowPlaying.screensAwake) { _, _ in syncSpectrum() }
    }

    // MARK: The wave that survives the morph

    /// Whether the spectrum is currently drawn as one persistent object that
    /// travels between the pill and the page.
    ///
    /// Only when the pill is *nothing but* the wave: with a timer readout or a
    /// shelf badge beside it the run is no longer centred in the capsule, and
    /// an overlay would have to re-derive an offset the `HStack` already owns.
    /// Those cases keep the plain crossfade, which is correct if less pretty.
    private var morphingWaveActive: Bool {
        settings.pillSpectrumOnly && hasAudioHero
            && pomodoro.pillText == nil && shelf.items.isEmpty
    }

    /// Whether a live activity (volume/brightness HUD, audio route, battery)
    /// has taken the collapsed pill over. It replaces the pill's usual content
    /// and narrows the capsule to its own width — see `islandWidth`.
    private var activityOwnsPill: Bool {
        viewModel.islandState == .collapsed && activities.current != nil
    }

    /// Whether the travelling wave is mounted at all.
    ///
    /// Deliberately *not* a function of where the island is: while it is active
    /// this run is the only spectrum in the island, so it stays mounted through
    /// every state and simply moves. Giving it up when the pages mount means the
    /// spectrum page needs a second wave of its own, and that means a handover —
    /// which can only ever be as invisible as the two independently mounted views'
    /// poses happen to match. They don't. So there is nothing to hand over to.
    ///
    /// The exceptions are the two states where something else owns the pixels.
    /// The fullscreen takeover covers the island completely and has a wave of
    /// its own, so this one should not keep redrawing 30 times a second
    /// underneath it. A live activity takes over the collapsed pill the same
    /// way the pill hero does — but the hero is *content*, which the activity
    /// replaces, while this wave is an overlay that no content swap can reach:
    /// left mounted, it drew straight through the volume HUD's bar.
    private var morphingWaveVisible: Bool {
        morphingWaveActive && !fullscreen.isPresented && !activityOwnsPill
    }

    /// Whether the wave currently belongs on the spectrum page rather than in
    /// the pill's band. The travel between the two poses *is* the morph.
    private var waveIsOnPage: Bool {
        viewModel.islandState == .expanded && viewModel.selectedTab == .spectrum
    }

    /// How far the wave has to slide because the carousel has slid.
    ///
    /// The spectrum page lives in the carousel and moves with it, so an overlay
    /// pinned to the island's centre would paint over whichever page is sliding
    /// past. Rather than hand the wave over for the duration of a swipe, the run
    /// travels the same
    /// distance the page does — one page width per tab of separation, the same
    /// arithmetic `ExpandedView` applies to the carousel — and the island's own
    /// clip takes care of hiding it once it is off the edge.
    private var waveCarouselShift: CGFloat {
        guard viewModel.islandState == .expanded else { return 0 }
        let tabs = NotchViewModel.Tab.allCases
        guard let spectrumIndex = tabs.firstIndex(of: .spectrum),
              let currentIndex = tabs.firstIndex(of: viewModel.selectedTab) else { return 0 }
        return CGFloat(spectrumIndex - currentIndex) * NotchLayout.expandedPageSize.width
    }

    /// The bar count the run holds at every size.
    ///
    /// The pill's, everywhere: a count that changed as the wave travelled would
    /// re-bucket the spectrum on the very frames the eye is following, so the
    /// morph is purely geometric — the same bars, further apart and taller.
    private var pageWaveBarCount: Int { pillWaveGeometry.barCount }

    private var pillWaveGeometry: NotchLayout.PillSpectrumGeometry {
        NotchLayout.pillSpectrumGeometry(forWidth: settings.pillSpectrumWidth)
    }

    /// The one spectrum in the island, at whichever size and place the current
    /// state calls for.
    ///
    /// Everything about it is a *transform* of a single, never-remounted run:
    /// the canvas is always built at the page's geometry, and the pill is that
    /// same run scaled down. Nothing here redraws at a new size — the canvas's
    /// bar width, spacing and height are draw parameters, not animatable
    /// attributes, so animating them moves nothing while the bars snap. Scale
    /// and offset are the interpolation, which is why one view can cover the
    /// whole journey.
    private var morphingWave: some View {
        let wave = NotchLayout.spectrumPageWaveGeometry(barCount: pageWaveBarCount)
        let onPage = waveIsOnPage
        let tints = waveTints
        return LiveWaveBarsView(
            levels: spectrum.bands,
            isLive: spectrum.isLive,
            isActive: nowPlaying.screensAwake,
            tint: tints.primary,
            secondaryTint: tints.secondary,
            tertiaryTint: tints.tertiary,
            coverBars: tints.coverBars,
            count: wave.barCount,
            maxHeight: wave.waveHeight,
            barWidth: wave.barWidth,
            spacing: wave.spacing,
            morphScale: onPage ? 1 : NotchLayout.pillToPageWaveScale
        )
        // Page-sized frame at both ends, even while the run is drawn small
        // inside it: this is an overlay, so the frame costs no layout, and
        // `scaleEffect` scales about the frame's centre — so holding the frame
        // still is what keeps the shrunken run centred on the pill.
        .frame(width: wave.runWidth, height: wave.frameHeight)
        .offset(
            x: waveCarouselShift,
            y: (onPage ? NotchLayout.pageWaveCentreY : NotchLayout.pillWaveCentreY) - wave.frameHeight / 2
        )
        .animation(NotchLayout.islandMorphAnimation, value: onPage)
        // The carousel's own spring, so the run slides in step with the page it
        // stands in for rather than racing or trailing it.
        .animation(NotchLayout.tabChangeAnimation, value: waveCarouselShift)
        .allowsHitTesting(false)
    }

    private var island: some View {
        let cornerRadius = viewModel.isExpanded ? NotchLayout.expandedCornerRadius : viewModel.collapsedHeight / 2
        let shape = IslandShape(cornerRadius: cornerRadius)
        // The dark silhouette leads; content is clipped to the same rounded rect
        // so it can't float outside the shape while it resizes. The highlight rim
        // and shadow stay outside the clip.
        //
        // The explicit `.frame` before the clip is load-bearing: mid-morph the
        // content lays out larger than the animated island, and `clipShape` clips
        // to the bounds of the view it's attached to. Without the frame those
        // bounds are the (full-size) content, so nothing gets clipped and the
        // content floats over the wallpaper without black behind it.
        // The island's chrome — black fill, drop shadow, hairline rim — is
        // flattened into one GPU-composited layer. Rendered plainly, the
        // shadow's gaussian blur and the rim's gradient are rasterized by
        // CoreGraphics on the main thread for *every* frame of the morph
        // (and, before the shadow was decoupled from the content, for every
        // 30 Hz spectrum tick too) — `sample` showed exactly this shading
        // work under the expand jank. The symmetric padding gives the
        // flattened canvas room for the blur; the content stays outside the
        // group, because flattening kills AppKit-backed subviews (the
        // capture field).
        let chrome = ZStack {
            shape
                .fill(NotchLayout.islandFill)
                .shadow(
                    color: .black.opacity(viewModel.isExpanded ? NotchLayout.islandShadowOpacityExpanded : NotchLayout.islandShadowOpacityCollapsed),
                    radius: NotchLayout.islandShadowRadius,
                    y: NotchLayout.islandShadowYOffset
                )
            // Hairline rim, brightest along the top edge: separates the
            // near-black island from a dark menu bar / wallpaper.
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(NotchLayout.islandStrokeTopOpacity),
                        .white.opacity(NotchLayout.islandStrokeBottomOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: NotchLayout.islandStrokeWidth
            )
        }
        .padding(40)
        .drawingGroup()
        .padding(-40)

        return chrome
            .overlay(
                ZStack(alignment: .top) {
                    content
                    // The spectrum lives *above* the island's content rather
                    // than inside it, so that opening the island moves one wave
                    // instead of dissolving the pill's into the page's. Nothing
                    // else can do that: the pill and the page are different
                    // subtrees mounted at different moments, so any wave owned
                    // by either of them has to fade when its owner does.
                    // Fades rather than cuts: an activity arriving (the volume
                    // HUD is the common one) rides the island morph, and the
                    // wave should leave with it instead of blinking out a
                    // frame early.
                    if morphingWaveVisible { morphingWave.transition(.opacity) }
                }
                .frame(width: islandWidth, height: islandHeight, alignment: .top)
                .clipShape(shape)
            )
            .frame(width: islandWidth, height: islandHeight)
            .offset(x: islandXOffset)
            // Settings changes alter the pill's width formula outside the
            // staged walk's withAnimation calls; morph instead of snapping.
            .animation(NotchLayout.islandMorphAnimation, value: settings.pillSpectrumOnly)
            .animation(NotchLayout.islandMorphAnimation, value: settings.pillSpectrumWidth)
            // Timer start/stop and audio start/stop change width *and* offset
            // at rest, outside the walk's withAnimation calls; slide, don't snap.
            .animation(NotchLayout.islandMorphAnimation, value: pomodoro.pillText != nil)
            .animation(NotchLayout.islandMorphAnimation, value: hasAudioHero)
    }

    @ViewBuilder private var content: some View {
        let state = viewModel.islandState
        // When music plays or a focus timer is active, the collapse morphs
        // toward the pill content (cover + live spectrum and/or timer readout)
        // rather than the selected tab's icon+label — uniformly, whichever tab
        // you close from. So from the `.solo` stage on the pill hero stands in
        // for the tab bar and just shrinks into place; this dissolves the
        // "close Capture while music runs" dilemma, because the collapse
        // target depends on the pill content, not on the tab.
        let heroContent = hasAudioHero || pomodoro.pillText != nil
        // `.band` is included, not just `.solo`/`.condensing`: at that stage the
        // island has already shrunk to pill height while the tab bar is still
        // showing *every* tab and its label — so the hero (the wave) and those
        // labels occupied the same band and drew straight through each other on
        // every collapse. With the hero standing in from `.band` on, the tab bar
        // is gone by the time the island is pill-sized. On the way up it means
        // the chrome appears only once the island is actually open, which is the
        // order `chromeRevealed` already wanted.
        let pillHero = heroContent && (state == .band || state == .solo || state == .condensing)
        let showsExpanded = state != .collapsed && !pillHero
        // Hero content → the tab bar and the pill hero are *different* content,
        // so cross-dissolve them. Otherwise the condensed icon and the pill
        // glyph are identical, so keep the hold-opaque handover (no dip).
        let handover: AnyTransition = heroContent ? .heroCrossfade : .iconHandover

        // Two explicit layers so the collapsed pill is *always* on top of the
        // outgoing tab bar during the handover.
        ZStack(alignment: .top) {
            if showsExpanded {
                // Expanded through condensing: the tab bar is one persistent
                // view that sheds its parts itself (pages, then unselected
                // tabs, then labels), so nothing ever re-appears. By the time
                // it unmounts only the selected icon is left — pixel-identical
                // to the pill icon replacing it (idle case).
                ExpandedView(viewModel: viewModel, nowPlaying: nowPlaying, shelf: shelf, pomodoro: pomodoro, capture: capture, spectrum: spectrum, spectrumWaveDrawnByOverlay: morphingWaveActive, spectrumWaveBarCount: morphingWaveActive ? pageWaveBarCount : nil)
                    .transition(handover)
            }
            if state == .collapsed || pillHero {
                if state == .collapsed, let activity = activities.current {
                    ActivityCompactView(activity: activity)
                        .foregroundStyle(.white)
                        .transition(.notchContent)
                } else {
                    // The pill hero: renders continuously across solo → condensing
                    // → collapsed when playing (one persistent view, so only the
                    // capsule shrinks around it — no swap), or just at collapsed
                    // when idle.
                    CollapsedView(viewModel: viewModel, nowPlaying: nowPlaying, shelf: shelf, pomodoro: pomodoro, spectrum: spectrum, hasAudioHero: hasAudioHero, waveDrawnByOverlay: morphingWaveActive)
                        .foregroundStyle(.white)
                        .transition(handover)
                }
            }
        }
    }
}
