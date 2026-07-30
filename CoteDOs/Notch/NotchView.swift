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

private extension AnyTransition {
    /// Content transition decoupled from the silhouette spring: content grows in
    /// (opacity + subtle scale, slightly delayed) and fades out fast on collapse,
    /// so it never lingers outside the shrinking shape.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: NotchLayout.contentMorphScale, anchor: .top))
                .animation(NotchLayout.contentInsertAnimation),
            removal: .opacity.animation(NotchLayout.contentRemoveAnimation)
        )
    }

    /// The pill ⇄ condensed-icon handover: a hard, atomic cut. The two views
    /// are near-pixel-identical by construction (same glyph, same size, same
    /// centre — and the swap fires only once the condensed icon has settled,
    /// see `condenseSwapDelay`), so a one-frame swap is invisible. Any
    /// overlap-based scheme is *not*: holding both copies opaque for ~0.1 s means
    /// sub-point offsets between the two view trees make the union read as the
    /// glyph bolding up and thinning back — a visible end-of-collapse blink, and
    /// measurable on recorded frames as white pixel energy doubling for ~4 frames.
    static var iconHandover: AnyTransition { .identity }

    /// Cross-dissolve used when music plays and the tab bar hands off to the
    /// now-playing pill hero (cover + spectrum) — in both directions. The
    /// arriving side starts slightly later (`heroCrossfadeInsertDelay`) so the
    /// capsule has begun growing toward its size before its content fades in;
    /// the departing side's fade covers the delay, so nothing shows empty.
    static var heroCrossfade: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(
                .easeInOut(duration: NotchLayout.heroCrossfadeDuration)
                    .delay(NotchLayout.heroCrossfadeInsertDelay)),
            removal: .opacity.animation(.easeInOut(duration: NotchLayout.heroCrossfadeDuration))
        )
    }
}

/// Compact rendering of a live activity inside the collapsed pill.
private struct ActivityCompactView: View {
    let activity: NotchActivity

    private var isRoute: Bool { activity.kind == .audioRoute }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.icon)
                // The audio-route icon is bumped up so a connecting device reads
                // clearly at a glance (the main "markant" ask).
                .font(.system(size: isRoute ? 17 : 12, weight: .semibold))
                .foregroundStyle(activity.tint)
                .frame(width: isRoute ? 22 : 16)
            if let progress = activity.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                    }
                }
                .frame(height: 4)
            } else {
                Text(activity.title)
                    .font(.system(size: isRoute ? 12 : 11, weight: isRoute ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail = activity.detail {
                    BatteryBadge(text: detail)
                }
            }
        }
        .padding(.horizontal, isRoute ? 12 : 14)
        // Same fixed top band as CollapsedView, so activity content doesn't
        // drift vertically while the island morphs.
        .frame(height: NotchLayout.currentCollapsedHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A small tinted battery pill (icon + percentage), tinted red/orange when low.
private struct BatteryBadge: View {
    let text: String

    private var level: Int? { Int(text.replacingOccurrences(of: "%", with: "")) }

    private var color: Color {
        switch level ?? 100 {
        case ..<15: return .red
        case ..<30: return .orange
        default: return .green
        }
    }

    private var symbol: String {
        switch level ?? 100 {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }
}

private struct ExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var shelf: FileShelfModel
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject var capture: ObsidianCapture
    @ObservedObject var spectrum: SpectrumAnalyzer
    /// True while `NotchRootView` is drawing the spectrum itself, above this
    /// view, so it can travel in from the pill as one object — the page then
    /// leaves a hole exactly where the wave will land, and takes it back over
    /// once the flight is done.
    var spectrumWaveDrawnByOverlay: Bool = false
    /// Bar count the page's wave must hold so that taking over from the
    /// travelling one is invisible. nil → the page resolves its own.
    var spectrumWaveBarCount: Int?
    /// Icon and accent of whichever app is making the sound, so the spectrum
    /// page is coloured by the audio it is actually drawing.
    @ObservedObject private var sourceApp = SourceAppAccent.shared

    /// The colours the spectrum page's wave draws with — the same answer the
    /// pill and the travelling overlay resolve, so the morph doesn't change
    /// colour halfway through. See `WaveTints`.
    private var waveTints: WaveTints {
        WaveTints.resolve(nowPlaying: nowPlaying, sourceBundleID: spectrum.sourceBundleID, sourceAppTint: sourceApp.tint)
    }

    private var pageIndex: Int {
        NotchViewModel.Tab.allCases.firstIndex(of: viewModel.selectedTab) ?? 0
    }

    /// False during the band collapse stage: the island has shrunk to just the
    /// tab-bar capsule, the pages are gone, only the bar remains (and must stay
    /// the *same view* as in the expanded state, or its icons would visibly
    /// re-appear instead of simply staying put). Also false until the island
    /// has *rested* in `.expanded` for a beat (`pagesSettled`): building all
    /// five pages is the heaviest view-mount of the app, and doing it
    /// mid-spring dropped frames — the shape morphs first, the content
    /// materialises into a nearly still island.
    private var showsPages: Bool { viewModel.islandState == .expanded && viewModel.pagesSettled }

    var body: some View {
        VStack(spacing: showsPages ? NotchLayout.expandedRowSpacing : 0) {
            // The tab bar occupies exactly the collapsed pill's band (flush top,
            // same height), so its icons sit on the same y as the pill's glyph —
            // the hero flight between them is purely horizontal, not diagonal.
            NotchTabBar(
                selection: $viewModel.selectedTab,
                // .band/.expanded keep every tab; .solo/.condensing keep
                // only the selected one. Labels survive until .condensing, where
                // the text drops and just the icon remains.
                showsAllTabs: viewModel.islandState == .expanded || viewModel.islandState == .band,
                // Labels live only in expanded/band/solo. Must be false in
                // .collapsed too, not just .condensing: while the tab bar is
                // held opaque during the pill handover, `!= .condensing` would
                // flip true again and fade the label back in ("Mu" reappears).
                showsLabels: viewModel.islandState == .expanded
                    || viewModel.islandState == .band
                    || viewModel.islandState == .solo
            )
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.currentCollapsedHeight)
            // Last beat of the opening: the island widens, the wave travels
            // into it, and the chrome fades up around them (see
            // `NotchViewModel.chromeRevealed`). Opacity only — the row keeps
            // its layout throughout, so nothing below it shifts.
            //
            // `.band` counts as part of the opening, not as a state that shows
            // chrome: the expand walk always rests there first, so treating it
            // as "not expanded" made the row appear, blink out on reaching
            // `.expanded`, and fade back in — the opposite of the intended
            // order. On the way *down* `chromeRevealed` is still true, so the
            // row stays opaque for the pill's icon handover.
            .opacity(viewModel.chromeRevealed || viewModel.islandState == .solo
                     || viewModel.islandState == .condensing || viewModel.islandState == .collapsed ? 1 : 0)

            // The pages live in a carousel that slides as one strip. Unlike
            // insertion/removal transitions this can't get the direction wrong on
            // quick back-and-forth swipes — the offset is a pure function of the
            // selected index.
            if showsPages {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        page(.music, in: geo.size) { NowPlayingView(nowPlaying: nowPlaying, spectrum: spectrum) }
                        page(.spectrum, in: geo.size) {
                            // The whole page is the wave. Colours follow
                            // whichever app is making the sound — the track's
                            // cover when that's the player, the source app's
                            // icon accent otherwise.
                            //
                            // Unless the wave is the one travelling in from the
                            // pill, in which case it is drawn above this page
                            // and the page itself is only the tap target that
                            // hands it the whole screen.
                            if spectrumWaveDrawnByOverlay {
                                Color.clear
                            } else {
                            let tints = waveTints
                            SpectrumStageView(
                                levels: spectrum.bands,
                                isLive: spectrum.isLive,
                                isActive: nowPlaying.screensAwake,
                                tint: tints.primary,
                                secondaryTint: tints.secondary,
                                tertiaryTint: tints.tertiary,
                                coverBars: tints.coverBars,
                                fixedBarCount: spectrumWaveBarCount
                            )
                            }
                        }
                        // Click the page to hand the wave the whole screen;
                        // Escape brings it back (see
                        // `SpectrumFullscreenController.installKeyMonitor`). The
                        // swipe-down/swipe-up pair still works — this is the
                        // same step on the same axis, reachable without a
                        // trackpad gesture. `contentShape` because the page is
                        // mostly empty space, and while the overlay owns the
                        // wave it is literally `Color.clear`.
                        .contentShape(Rectangle())
                        .onTapGesture { SpectrumFullscreen.shared.present() }
                        page(.files, in: geo.size) { ShelfView(shelf: shelf) }
                        page(.capture, in: geo.size) { CaptureView(capture: capture, viewModel: viewModel) }
                        page(.timer, in: geo.size) { PomodoroView(pomodoro: pomodoro) }
                    }
                    .offset(x: -CGFloat(pageIndex) * geo.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .transition(.notchContent)
            }
        }
        // Inset the content (and the carousel clip in particular) from the
        // island edge so it clears the rounded corners; sliding pages must not
        // poke past the dark body onto the wallpaper.
        .padding(.horizontal, NotchLayout.expandedContentInset)
        .padding(.bottom, showsPages ? NotchLayout.expandedBottomPadding : 0)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func page<Content: View>(
        _ tab: NotchViewModel.Tab, in size: CGSize, @ViewBuilder content: () -> Content
    ) -> some View {
        let isFront = viewModel.selectedTab == tab
        content()
            .frame(width: size.width, height: size.height)
            .scaleEffect(isFront ? 1 : NotchLayout.tabPageInactiveScale)
            .opacity(isFront ? 1 : NotchLayout.tabPageInactiveOpacity)
            // Clipped-away pages are still hit-testable; don't let them swallow
            // clicks or file drops meant for the front page.
            .allowsHitTesting(isFront)
    }
}

/// A tab's glyph.
private struct TabIcon: View {
    let tab: NotchViewModel.Tab
    var dimmed = false

    var body: some View {
        Image(systemName: tab.icon)
    }
}

private struct NotchTabBar: View {
    @Binding var selection: NotchViewModel.Tab
    /// When false (`.solo`/`.condensing`), only the selected tab is present —
    /// the others have left the layout, letting the capsule narrow onto it.
    let showsAllTabs: Bool
    /// When false (`.condensing`), the labels drop and only the icon remains.
    let showsLabels: Bool
    /// Observed so the bar re-renders live when tabs are toggled in Settings.
    @ObservedObject private var settings = UserSettings.shared

    /// Shrinks the full row when the enabled tabs would overflow the island —
    /// only ever in the states that show all of them. Solo and condensing keep
    /// scale 1, because their metrics are tuned to hand the selected icon over
    /// to the pill glyph pixel for pixel; animating back to 1 as the row goes
    /// solo also brings that icon up to its final size just in time.
    private var fitScale: CGFloat {
        guard showsAllTabs else { return 1 }
        return NotchLayout.tabBarFitScale(titles: NotchViewModel.enabledTabs.map(\.title))
    }

    var body: some View {
        let scale = fitScale
        HStack(spacing: NotchLayout.tabBarSpacing) {
            ForEach(NotchViewModel.enabledTabs, id: \.self) { value in
                tab(title: value.title, value: value)
            }
        }
        .scaleEffect(scale)
        .animation(NotchLayout.condenseFadeAnimation, value: scale)
    }

    @ViewBuilder
    private func tab(title: String, value: NotchViewModel.Tab) -> some View {
        if showsAllTabs || selection == value {
            let isSelected = selection == value
            // Solo/condensing (this is the only tab): pin the *icon* at the
            // capsule centre — exactly where the pill icon will sit — so that
            // collapsing further only fades the label and shrinks the capsule;
            // the icon never moves again and the pill handover is pixel-exact.
            let soloMode = !showsAllTabs
            Button {
                guard selection != value else { return }
                Haptics.perform(.alignment)
                withAnimation(NotchLayout.tabChangeAnimation) { selection = value }
            } label: {
                HStack(spacing: NotchLayout.tabIconLabelSpacing) {
                    if soloMode {
                        // An invisible mirror of the real label, left of the
                        // icon: it reserves exactly the label's own width (real
                        // text metrics, no estimate), so the symmetric HStack
                        // centres the icon precisely. `.opacity(0)` (not
                        // `.hidden()`, which drops its layout space here) keeps
                        // the space through the label fade, so the icon holds
                        // dead centre — no wander, no flicker at the handover.
                        Text(title).fixedSize().opacity(0)
                    }
                    // Every icon renders itself, always — switching tabs must only
                    // change the highlight (foreground opacity), never replace or
                    // move the icon view, or it visibly pops back in.
                    TabIcon(tab: value, dimmed: !isSelected)
                    // The label stays in the layout even when hidden (fixed size,
                    // opacity only) so the mirror stays balanced; it just fades
                    // fast while the capsule narrows over it.
                    Text(title)
                        .fixedSize()
                        .opacity(showsLabels ? 1 : 0)
                        .animation(NotchLayout.condenseFadeAnimation, value: showsLabels)
                }
                .font(.system(size: NotchLayout.bandFontSize, weight: .medium))
                .padding(.vertical, NotchLayout.tabItemPaddingVertical)
                .padding(.horizontal, NotchLayout.tabItemPaddingHorizontal)
                .foregroundStyle(.white.opacity(isSelected ? 1 : NotchLayout.tabInactiveOpacity))
            }
            .buttonStyle(.plain)
            // Insertion waits for the selected icon's flight to its slot to
            // finish (it crosses the other tabs' positions on the way);
            // removal on collapse stays immediate — the capsule narrows fast
            // and lingering neighbours would get clipped against its rim.
            .transition(.asymmetric(
                insertion: .opacity.animation(
                    NotchLayout.condenseFadeAnimation.delay(NotchLayout.tabJoinFadeDelay)),
                removal: .opacity.animation(NotchLayout.condenseFadeAnimation)
            ))
        }
    }
}

private struct CollapsedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var shelf: FileShelfModel
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject var spectrum: SpectrumAnalyzer
    @ObservedObject private var settings = UserSettings.shared
    /// Whether the pill hero (cover-or-generic-icon + wave) should show at all —
    /// true for Spotify/Music, but also for any other system audio (browser
    /// video, calls, …) that has no scriptable track to show a cover for.
    let hasAudioHero: Bool
    /// True when `NotchRootView` draws the spectrum above the island so it can
    /// travel to the page as one object. The pill then reserves the run's space
    /// but leaves it empty — the width estimate in `collapsedWidth` still has to
    /// hold, or the capsule clips against its own silhouette.
    var waveDrawnByOverlay: Bool = false

    /// Icon and accent of whichever app is making the sound. Resolved centrally
    /// (once per bundle-ID change, not per wave-bar redraw) so the pill, the
    /// spectrum page and the fullscreen takeover all read the same answer.
    @ObservedObject private var sourceApp = SourceAppAccent.shared

    /// The colours this pill's wave and thumbnail draw with. See `WaveTints`.
    private var tints: WaveTints {
        WaveTints.resolve(nowPlaying: nowPlaying, sourceBundleID: spectrum.sourceBundleID, sourceAppTint: sourceApp.tint)
    }

    var body: some View {
        let tints = self.tints
        // Spacings/paddings here must stay in lock-step with the width estimate
        // in `NotchViewModel.collapsedWidth`, or the pill clips against the
        // silhouette — so both sides read from the same `NotchLayout` constants.
        return HStack(spacing: NotchLayout.collapsedItemSpacing) {
            if hasAudioHero {
                if settings.pillSpectrumOnly {
                    // Spectrum-only mode: no thumbnail at all (neither cover
                    // nor source-app icon — "only the spectrum" holds for both
                    // kinds of audio), just the wave in the space the
                    // thumbnail freed up.
                    //
                    // Geometry is the spectrum *page* scaled down — one rule,
                    // one knob: the field keeps the page's aspect, so widening
                    // the pill also makes it taller and its bars thicker, and
                    // the run holds however many of those fit. That is why
                    // this reads like the page instead of like a stripe of
                    // hairlines. See `NotchLayout.pillSpectrumGeometry`.
                    let wave = NotchLayout.pillSpectrumGeometry(forWidth: settings.pillSpectrumWidth)
                    if waveDrawnByOverlay {
                        // The run itself is drawn above the island so it can
                        // travel to the page without ever unmounting; the pill
                        // only reserves its space here.
                        Color.clear
                            .frame(width: wave.runWidth, height: wave.frameHeight)
                    } else {
                        LiveWaveBarsView(
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
                            spacing: wave.spacing
                        )
                        .frame(width: wave.runWidth, height: wave.frameHeight)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                } else if tints.fromCover, let url = nowPlaying.track?.artworkURL {
                    // Fade the new cover in (transaction animation) over a placeholder
                    // tinted to the track's accent colour rather than flat grey, so a
                    // track change doesn't flash a grey square then pop during the
                    // hero crossfade.
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            nowPlaying.artworkColor ?? Color.white.opacity(0.1)
                        }
                    }
                    .frame(width: NotchLayout.collapsedArtworkWidth, height: NotchLayout.collapsedArtworkWidth)
                    .clipShape(RoundedRectangle(cornerRadius: NotchLayout.collapsedArtworkCornerRadius))
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    // System audio with no scriptable track (browser video, a
                    // call, …) — show the source app's own icon full-bleed when
                    // we can identify it (no background/padding: app icons like
                    // Safari's already bake in their own rounding and margin, so
                    // wrapping them in another rounded-rect frame just shrank
                    // them further and read as an extra border), else fall back
                    // to a plain glyph on a tinted background.
                    Group {
                        if let icon = sourceApp.icon {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: NotchLayout.collapsedArtworkCornerRadius)
                                .fill(Color.white.opacity(0.1))
                                .overlay {
                                    Image(systemName: "waveform").font(.system(size: 11))
                                }
                        }
                    }
                    .frame(width: NotchLayout.collapsedArtworkWidth, height: NotchLayout.collapsedArtworkWidth)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
                if !settings.pillSpectrumOnly {
                    LiveWaveBarsView(
                        levels: spectrum.bands,
                        isLive: spectrum.isLive,
                        isActive: nowPlaying.screensAwake,
                        tint: tints.primary,
                        secondaryTint: tints.secondary,
                        tertiaryTint: tints.tertiary,
                        coverBars: tints.coverBars,
                        count: NotchLayout.collapsedWaveBarCount,
                        maxHeight: NotchLayout.collapsedWaveMaxHeight,
                        barWidth: NotchLayout.collapsedWaveBarWidth,
                        spacing: NotchLayout.collapsedWaveSpacing
                    )
                    .frame(width: NotchLayout.collapsedWavesWidth, height: NotchLayout.collapsedArtworkWidth)
                    .transition(.opacity)
                }
            } else if pomodoro.pillText == nil {
                // Idle glyph reflects the tab you'd return to, so it isn't
                // always the music icon when you last used another tab.
                TabIcon(tab: viewModel.selectedTab)
                    .font(.system(size: NotchLayout.bandFontSize, weight: .medium))
            }

            // The focus-timer readout joins to the right of the artwork + wave
            // while music plays and stands alone otherwise (it replaces the
            // idle glyph above rather than crowding it).
            if let readout = pomodoro.pillText {
                timerSegment(readout)
            }

            if !shelf.items.isEmpty {
                Label("\(shelf.items.count)", systemImage: "tray.full.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: NotchLayout.collapsedBadgeFontSize, weight: .semibold))
            }
        }
        .padding(.horizontal, NotchLayout.collapsedContentPadding)
        // Pin the pill row to a fixed top band. Without this the row is
        // vertically centered in the *animated* island frame during the morph,
        // so the glyph starts mid-island and drifts up — the diagonal flight.
        .frame(height: viewModel.collapsedHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        // The spectrum-only toggle and its sliders swap the hero's layout in
        // place; a scoped value animation can't interfere with the staged
        // expand/collapse walk's explicit withAnimation calls.
        .animation(NotchLayout.islandMorphAnimation, value: settings.pillSpectrumOnly)
        .animation(NotchLayout.islandMorphAnimation, value: settings.pillSpectrumWidth)
    }

    /// The passive focus-timer readout. Sizes must stay in lock-step with the
    /// width estimate in `NotchViewModel.timerSegmentWidth`.
    private func timerSegment(_ readout: String) -> some View {
        let paused = pomodoro.phase == .paused
        return HStack(spacing: NotchLayout.collapsedTimerInnerSpacing) {
            Image(systemName: paused ? "pause.fill" : "timer")
                .font(.system(size: NotchLayout.collapsedTimerIconSize, weight: .semibold))
                .foregroundStyle(paused ? Color.white.opacity(0.55) : Color.orange)
                .frame(width: NotchLayout.collapsedTimerIconWidth)
            Text(readout)
                .font(.system(size: NotchLayout.collapsedTimerFontSize, weight: .semibold))
                .monospacedDigit()
                .opacity(paused ? 0.55 : 1)
        }
    }
}
