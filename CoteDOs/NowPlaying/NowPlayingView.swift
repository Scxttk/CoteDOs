import AppKit
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    /// Shared spectrum tap, owned by AppDelegate and driven centrally in
    /// `NotchRootView` (so the collapsed pill's wave is live too). The music tab
    /// just observes it.
    @ObservedObject var spectrum: SpectrumAnalyzer
    /// Local to the music tab: only needs to enumerate output devices while the
    /// tab is on screen, so it starts/stops with the view.
    @StateObject private var output = AudioOutputController()

    /// Scrub fraction while the progress bar is being dragged (nil = not dragging),
    /// so the bar follows the finger before the seek lands.
    @State private var scrubFraction: Double?

    var body: some View {
        // Empty containers (Spacers + a narrower content column) pad the edges,
        // top and bottom so the actual controls cluster closer together in the
        // centre, while the island stays solid black.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                topRow
                progressRow
                controlsRow
            }
            .frame(maxWidth: 300)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { output.start() }
        .onDisappear { output.stop() }
    }

    // MARK: Row 1 — cover · title/artist · wave

    private var topRow: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                if let track = nowPlaying.track {
                    Text(track.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                } else if nowPlaying.permissionDenied {
                    Text(String(localized: "nowplaying.denied", defaultValue: "Kein Zugriff auf den Player"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Button(action: openAutomationSettings) {
                        Text(String(localized: "nowplaying.denied.cta", defaultValue: "Automatisierung erlauben"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor(enabled: true)
                } else {
                    Text(nowPlaying.isRunning
                         ? String(localized: "nowplaying.idle", defaultValue: "Nichts läuft")
                         : String(localized: "nowplaying.notOpen", defaultValue: "Kein Player geöffnet"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Only the real track's accent when there's an actual track to
            // derive it from — otherwise (system audio with no scriptable
            // track) a stale accent from the last track shouldn't bleed in.
            //
            // `spectrum` is the shared tap and runs (and carries real bands)
            // whenever the screen is awake — regardless of whether Spotify/Music
            // is actually playing, e.g. while Safari plays a video with Spotify
            // paused. Gate `bands` on `nowPlaying.isPlaying` too, or this tab
            // shows someone else's audio moving under the paused track: `bands`
            // must never be passed live when `isActive` is false, since
            // `WaveBarsView` ignores `isActive` once it has real band data.
            LiveWaveBarsView(
                levels: spectrum.bands,
                isLive: spectrum.isLive,
                showsLiveBands: nowPlaying.isPlaying,
                isActive: nowPlaying.isPlaying && nowPlaying.screensAwake,
                tint: nowPlaying.track != nil ? nowPlaying.artworkColor : nil,
                secondaryTint: nowPlaying.track != nil ? nowPlaying.artworkSecondaryColor : nil,
                tertiaryTint: nowPlaying.track != nil ? nowPlaying.artworkTertiaryColor : nil,
                coverBars: nowPlaying.track != nil ? nowPlaying.coverBars : nil,
                count: 6
            )
            .frame(width: 34, height: 30)
        }
    }

    /// Tapping the cover opens the song in its app (deep link, or brings the app
    /// forward). Only interactive when there's actually a track.
    private var artwork: some View {
        Button(action: { nowPlaying.openCurrentTrack() }) {
            Group {
                if let url = nowPlaying.track?.artworkURL {
                    // Cross-fade to the new cover on track change instead of
                    // popping through the grey placeholder.
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholderArtwork
                        }
                    }
                } else {
                    placeholderArtwork
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(nowPlaying.track == nil)
        .pointingHandCursor(enabled: nowPlaying.track != nil)
    }

    /// Deep-link straight to System Settings → Privacy & Security → Automation
    /// so the user can re-enable our Apple Events access.
    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.08))
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.4))
            )
    }

    // MARK: Row 2 — current time · progress · total time

    private var fraction: Double {
        guard let duration = nowPlaying.track?.duration, duration > 0 else { return 0 }
        return min(max(nowPlaying.position / duration, 0), 1)
    }

    /// What the bar shows: the drag position while scrubbing, else live playback.
    private var displayedFraction: Double { scrubFraction ?? fraction }

    private var progressRow: some View {
        HStack(spacing: 8) {
            timeLabel(displayedFraction * (nowPlaying.track?.duration ?? 0))
            GeometryReader { geo in
                let isScrubbing = scrubFraction != nil
                // Minimal: a dim track and a bright filled bar; the play head is
                // simply the end of the filled bar (no knob). The bar thickens a
                // touch while scrubbing for feedback.
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white.opacity(isScrubbing ? 1 : 0.9))
                        .frame(width: max(0, geo.size.width * displayedFraction))
                        // Ease the fill between the 1s local position ticks and
                        // over the discontinuous jump when the 5s hard refresh
                        // corrects the interpolated position — otherwise the bar
                        // steps and snaps. No easing while scrubbing, so the bar
                        // tracks the finger instantly.
                        .animation(isScrubbing ? nil : .linear(duration: 1), value: displayedFraction)
                }
                .frame(height: isScrubbing ? 5 : 3)
                .frame(maxHeight: .infinity)   // enlarge the vertical hit area
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard nowPlaying.track?.duration ?? 0 > 0 else { return }
                            scrubFraction = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            if let f = scrubFraction, let d = nowPlaying.track?.duration {
                                nowPlaying.seek(to: f * d)
                            }
                            scrubFraction = nil
                        }
                )
                .animation(.easeOut(duration: 0.12), value: isScrubbing)
            }
            .frame(height: 14)
            timeLabel(nowPlaying.track?.duration ?? 0)
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> some View {
        Text(timeString(seconds))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .frame(width: 30)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Row 3 — prev · play/pause · next · output picker

    private var controlsRow: some View {
        HStack(spacing: 16) {
            ControlButton(systemName: "backward.fill", size: 15, action: nowPlaying.previousTrack)
            ControlButton(
                systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                size: 20,
                action: nowPlaying.playPause
            )
            ControlButton(systemName: "forward.fill", size: 15, action: nowPlaying.nextTrack)
            outputPicker
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Audio-output selector (replaces the old shuffle + favourite buttons):
    /// pick which device the sound plays through, current one checked.
    private var outputPicker: some View {
        Menu {
            ForEach(output.devices) { device in
                Button { output.select(device) } label: {
                    if device.id == output.currentDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointingHandCursor(enabled: true)
    }
}

/// A pointing-hand cursor while hovering, for clickable non-button surfaces.
private struct PointingHandCursor: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.onHover { inside in
            if enabled, inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}

/// Transport button with a hover highlight (visible when expanded).
private struct ControlButton: View {
    let systemName: String
    var size: CGFloat
    var color: Color = .white
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(color)
                .frame(width: 34, height: 32)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.16 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// `WaveBarsView` fed from the live tap. It exists as a view of its own so the
/// band updates — 15 a second — invalidate the bars and nothing else: the
/// levels live on their own observable (`SpectrumBands`), and this is the only
/// place that observes it. Wrap the wave in this instead of reading
/// `spectrum.bands.values` from a parent, or the parent starts re-rendering at
/// the tap's rate again and takes the whole notch with it.
struct LiveWaveBarsView: View {
    @ObservedObject var levels: SpectrumBands
    /// False when the tap isn't running (no permission, macOS < 14.4, …) —
    /// the wave then falls back to its procedural animation.
    var isLive: Bool
    /// Additional gate for callers that must not show *someone else's* audio,
    /// e.g. the music tab while its own player is paused.
    var showsLiveBands: Bool = true

    var isActive: Bool
    var tint: Color?
    var secondaryTint: Color?
    var tertiaryTint: Color?
    var coverBars: CoverBarPalette?
    var count: Int = 4
    var maxHeight: CGFloat = 26
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var flattensToLayer: Bool = true

    var body: some View {
        WaveBarsView(
            isActive: isActive,
            tint: tint,
            secondaryTint: secondaryTint,
            tertiaryTint: tertiaryTint,
            coverBars: coverBars,
            bands: (isLive && showsLiveBands) ? levels.values : nil,
            count: count,
            maxHeight: maxHeight,
            barWidth: barWidth,
            spacing: spacing,
            flattensToLayer: flattensToLayer
        )
    }
}

/// Frequency bars for the now-playing wave. When `bands` carries real spectrum
/// data (from `SpectrumAnalyzer`) the bars reflect the song's actual frequencies;
/// otherwise they fall back to a procedural animation. Tinted to the cover's
/// accent colour when one is available, else the default blue.
struct WaveBarsView: View {
    var isActive: Bool
    var tint: Color?
    /// The cover's real second and third colour families (see
    /// `ArtworkAccents`), when it has them. Used by `.alternating`/`.gradient`
    /// in "Vom Cover" mode; nil → a pair is derived from `tint` instead.
    var secondaryTint: Color? = nil
    var tertiaryTint: Color? = nil
    /// Quantised cover colours (see `ArtworkColor.fetchBarPalette`) for the
    /// `.coverImage` style: one colour per bar, taken from the slice of cover
    /// that bar sits over. nil → the style falls back to `.solid` behaviour.
    var coverBars: CoverBarPalette? = nil
    /// Live per-band magnitudes (0…1). nil/empty → procedural fallback.
    var bands: [CGFloat]? = nil
    var count: Int = 4
    var maxHeight: CGFloat = 26
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    /// Rasterize the whole run into one GPU-composited layer (`drawingGroup`).
    /// Worth it for a wave that only exists while the panel is open: it keeps
    /// CoreGraphics from shading every bar's gradient and glow on the main
    /// thread during the expand animation. *Not* worth it for the collapsed
    /// pill, which draws a handful of tiny capsules but does so all day — there
    /// the offscreen render target is allocated and waited on every frame, and
    /// `sample` showed exactly that (`RBLayer display` → `wait_for_allocations`)
    /// sitting at the top of the main thread while the pill idled.
    var flattensToLayer: Bool = true

    @ObservedObject private var settings = UserSettings.shared
    /// Decides whether the bars ease between updates — see the `body` comment.
    @ObservedObject private var power = PowerSource.shared

    /// Per-bar fill, top-to-bottom gradient as before, but the *base* colour
    /// now depends on the chosen spectrum style: same for every bar (`.solid`,
    /// unchanged behaviour), alternating between the two accent colours, or
    /// interpolated across the bar's position for a continuous left-to-right
    /// gradient look.
    /// The two accents used by `.alternating`/`.gradient`. `.cover` derives them
    /// from the current track's accent (same source the `.solid` tint uses) so
    /// the spectrum keeps matching whatever is playing; `.manual` uses the
    /// fixed pair chosen in Settings.
    private var accentPair: (Color, Color) {
        switch settings.spectrumColorSource {
        case .manual:
            return (settings.spectrumColorA, settings.spectrumColorB)
        case .cover:
            // Prefer the colour the sleeve actually contains; the synthetic
            // hue-shift pair is only for covers without a real second accent.
            if let tint, let secondaryTint { return (tint, secondaryTint) }
            return Color.huePair(from: tint ?? .white)
        }
    }

    /// The colour stops the `.gradient` style runs through, stage-vivid. Up to
    /// three real cover colours; a single-hued cover still gets a two-stop run
    /// via the synthetic pair so the wave never collapses to one flat colour.
    private var gradientStops: [Color] {
        let (a, b) = accentPair
        var stops = [a, b]
        if settings.spectrumColorSource == .cover, let tertiaryTint {
            stops.append(tertiaryTint)
        }
        return stops.map(Color.stageVivid)
    }

    /// One bar's colours, resolved once per view update rather than per bar per
    /// frame. Everything in here is independent of the bar's current level, so
    /// the only colour work left in the draw path is the tip whitening — and
    /// `HSB` does that as arithmetic, with no trip through NSColor/ColorSync.
    private struct BarInk {
        /// The bar's body colour, byte-for-byte what the old per-frame path
        /// produced for this style.
        let base: Color
        let baseHSB: HSB
        /// What the bar's top-to-bottom gradient ends on.
        let foot: Color

        /// Depth: full colour at the tip falling to ~72% brightness at the
        /// base, so a tall bar reads as lit from its top rather than printed.
        init(_ color: Color) {
            let hsb = HSB(color)
            self.base = color
            self.baseHSB = hsb
            self.foot = hsb.brightnessScaled(0.72)
        }

        /// For styles that *derive* the colour and therefore already know its
        /// components — no decomposition needed at all.
        init(hsb: HSB) {
            self.base = hsb.color
            self.baseHSB = hsb
            self.foot = hsb.brightnessScaled(0.72)
        }

        /// The `.coverImage` style: the quantised cover column, whose shading
        /// was worked out once when the palette was built (see `CoverBarPalette.Bar`).
        init(coverBar: CoverBarPalette.Bar) {
            self.base = coverBar.top
            self.baseHSB = coverBar.topHSB
            self.foot = coverBar.foot
        }
    }

    // iOS's Dynamic Island wave bars are flat, fully-opaque colour top to
    // bottom — no fade. Ours used to fade each bar down to 55% opacity, which
    // (combined with how thin these bars are) made the colour nearly
    // impossible to actually see. Now one solid colour per bar.
    /// The whole run's colours. Built once per update: the old code derived
    /// each bar's colour inside the draw call, which meant four ColorSync
    /// round-trips per bar per frame — ~2900/s for the 32-bar pill at 30 fps,
    /// and the single biggest item in a `sample` of the idling app.
    private func palette(total: Int) -> [BarInk] {
        // No tint (no artwork, or the cover's dominant-colour extraction found
        // no real hue) — default to white rather than a hardcoded accent,
        // matching `ArtworkColor`'s own "no real colour here" answer.
        let accent = tint.map(Color.stageVivid) ?? .white

        switch settings.spectrumStyle {
        case .coverImage:
            // With a cover the bars carry the quantised palette; without one
            // this style falls back to `.solid` behaviour, bar by bar.
            let fallback = BarInk(accent)
            guard let coverBars else { return Array(repeating: fallback, count: total) }
            return (0..<total).map { index in
                coverBars.bar(forBarAt: index, total: total).map(BarInk.init(coverBar:)) ?? fallback
            }
        case .solid:
            return Array(repeating: BarInk(accent), count: total)
        case .shades:
            // Full saturation across the whole run, brightness climbing left to
            // right — a lit VU ramp. The earlier version desaturated the left
            // bars toward grey (after the iOS reference), which at 16 bars
            // turned half the wave grey; on a black notch, grey reads as off.
            let lit = HSB(Color.stageVivid(tint ?? .white))
            return (0..<total).map { index in
                let t = CGFloat(Self.position(of: index, total: total))
                return BarInk(hsb: HSB(h: lit.h, s: lit.s, b: lit.b * (0.60 + 0.40 * t)))
            }
        case .alternating:
            let stops = gradientStops.map(BarInk.init)
            return (0..<total).map { stops[$0 % stops.count] }
        case .gradient:
            let stops = gradientStops.map(HSB.init)
            return (0..<total).map { index in
                BarInk(hsb: Self.multiStop(stops, t: Self.position(of: index, total: total)))
            }
        }
    }

    /// A bar's place in the run, 0…1.
    private static func position(of index: Int, total: Int) -> Double {
        total > 1 ? Double(index) / Double(total - 1) : 0
    }

    /// `t` (0…1) mapped across an evenly spaced run of `stops` — the wave
    /// flows through every colour the cover offered, not just two.
    private static func multiStop(_ stops: [HSB], t: Double) -> HSB {
        guard stops.count > 1 else { return stops.first ?? HSB(.white) }
        let clamped = max(0, min(1, t))
        let scaled = clamped * Double(stops.count - 1)
        let index = min(stops.count - 2, Int(scaled))
        return stops[index].mixed(to: stops[index + 1], t: scaled - Double(index))
    }

    /// How far a bar's tip is driven into white at this level: nothing below
    /// 0.7, then ramping to a 60% white blend at full deflection — an
    /// overdriven-VU-meter incandescence that only the beat peaks reach, so
    /// it reads as *energy*, not as a palette change.
    private func incandescence(at level: CGFloat) -> Double {
        Double(max(0, (min(1, level) - 0.7) / 0.3)) * 0.6
    }

    /// `level` is the band's normalized magnitude (0…1), independent of the
    /// pixel height — it drives the glow.
    private func bar(_ height: CGFloat, level: CGFloat, ink: BarInk) -> some View {
        let boosted = max(0, min(1, level))
        let heat = incandescence(at: level)
        // The halo bleaches with the tip: a peaking bar throws hotter,
        // whiter light than one idling at its running average.
        let glow = ink.baseHSB.whitened(heat * 0.5, original: ink.base)
        return Capsule()
            .fill(LinearGradient(
                colors: [ink.baseHSB.whitened(heat, original: ink.base), ink.foot],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: barWidth, height: height)
            // The spectacle: every bar throws its own light, and louder bands
            // glow harder. On the pure black island this halo is what makes
            // the wave read as alive rather than printed on.
            .shadow(color: glow.opacity(0.35 + 0.45 * boosted),
                    radius: 1 + 3.5 * boosted)
    }

    /// iOS's spectrum bars never fully bottom out — even a silent band keeps a
    /// visible sliver. Ours read as flatter than that; nudge the hard floor up
    /// a touch (was 3) so the quietest bar still reads as "there".
    private var floorHeight: CGFloat { max(4, maxHeight * 0.14) }

    /// Height envelope across the run: full in the middle, tapering toward
    /// both ends (edges reach ~45%), so the wave has a *shape* — a crest that
    /// swells and falls — instead of a rectangle of equally tall bars. The
    /// low exponent keeps the top flat-ish; only the outer few bars duck.
    private func envelope(forBarAt index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 1 }
        let t = CGFloat(index) / CGFloat(total - 1)
        return 0.45 + 0.55 * pow(sin(.pi * t), 0.6)
    }

    /// Fit the source bands to `count` bars: pass through when they match, else
    /// group into `count` buckets (max per bucket keeps the punch) so the tiny
    /// collapsed pill can show 3 bars from the 5-band spectrum.
    private func fitted(_ source: [CGFloat]) -> [CGFloat] {
        guard count > 0, !source.isEmpty else { return source }
        if source.count == count { return source }
        return (0..<count).map { i in
            let lo = i * source.count / count
            let hi = max(lo + 1, (i + 1) * source.count / count)
            return source[lo..<min(hi, source.count)].max() ?? 0
        }
    }

    /// The `drawingGroup` sandwich, applied only where it pays off (see
    /// `flattensToLayer`). The symmetric padding keeps the flattened canvas
    /// large enough that the outermost bars' glow isn't clipped at its edge.
    @ViewBuilder
    private func flattened(_ content: some View) -> some View {
        if flattensToLayer {
            content.padding(8).drawingGroup().padding(-8)
        } else {
            content
        }
    }

    @ViewBuilder
    var body: some View {
        if let bands, !bands.isEmpty {
            // Real spectrum: bar height follows each band, eased between
            // updates so the wave flows instead of stepping — on wall power.
            //
            // That ease is the most expensive thing in this app. A new target
            // arrives before the previous one finishes, so an animation is
            // permanently in flight, and an in-flight animation makes SwiftUI
            // re-evaluate its animated attributes on every *display* refresh
            // (60 Hz) however rarely the bands change — which is why halving
            // the publish rate changed nothing: the animator, not the
            // publisher, sets the pace. Measured on one signal, interleaved,
            // same machine: ~52% of a core with the ease, ~16% without.
            //
            // On battery it goes away and the bars step straight to each
            // published level, which reads as a visibly harder motion.
            // `PowerSource` decides; the trade is deliberate.
            //
            // The real fix is neither: 32 bars are 32 SwiftUI views, so every
            // animated frame re-evaluates and re-lays-out that whole subtree.
            // Drawn as one `Canvas` the per-frame cost would collapse and the
            // ease could stay on always.
            let values = fitted(bands)
            let inks = palette(total: values.count)
            flattened(
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(values.indices, id: \.self) { i in
                        bar(max(floorHeight, maxHeight * values[i] * envelope(forBarAt: i, total: values.count)),
                            level: values[i], ink: inks[i])
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(power.isOnBattery ? nil : .easeOut(duration: 0.09), value: values)
                .animation(.easeInOut(duration: 0.4), value: tint)
                .animation(.easeInOut(duration: 0.4), value: secondaryTint)
                .animation(.easeInOut(duration: 0.4), value: tertiaryTint)
                .animation(.easeInOut(duration: 0.4), value: coverBars)
            )
        } else {
            // Hoisted out of the timeline closure on purpose: the colours don't
            // depend on the clock, so they're resolved once per update instead
            // of on every one of the 30 ticks a second.
            let inks = palette(total: count)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                flattened(
                    HStack(alignment: .center, spacing: spacing) {
                        ForEach(0..<count, id: \.self) { index in
                            let height = proceduralHeight(index: index, time: time)
                            bar(max(floorHeight, height * envelope(forBarAt: index, total: count)),
                                level: maxHeight > 0 ? height / maxHeight : 0, ink: inks[index])
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .animation(.easeInOut(duration: 0.4), value: tint)
                    .animation(.easeInOut(duration: 0.4), value: secondaryTint)
                    .animation(.easeInOut(duration: 0.4), value: tertiaryTint)
                    .animation(.easeInOut(duration: 0.4), value: coverBars)
                )
            }
        }
    }

    private func proceduralHeight(index: Int, time: Double) -> CGFloat {
        guard isActive else { return floorHeight }
        let phase = Double(index) * 0.7
        let value = 0.35 + 0.65 * abs(sin(time * 4 + phase))
        return maxHeight * CGFloat(value)
    }
}

// The per-bar shading helpers that used to live here (`whitened`,
// `brightnessScaled`, `hsbMix`, `multiStop`, `brightnessRamp`) moved onto
// `HSB`: each of them decomposed its `Color` argument on every call, which is
// a ColorSync round-trip, and the wave called them per bar per frame. They now
// operate on components resolved once per palette — see `WaveBarsView.BarInk`.
private extension Color {
    private var hsb: HSB { HSB(self) }

    /// The push a colour gets *only when painted as a spectrum bar*: bars are
    /// two points of colour on a pure black field and need stage lighting,
    /// while the same accent stays tone-mapped (calmer) everywhere else —
    /// title glow, placeholder tint. Keeps the hue, forces presence.
    static func stageVivid(_ color: Color) -> Color {
        let c = color.hsb
        // A genuinely neutral colour (white fallback, B/W cover) must stay
        // neutral — saturating it would invent a hue that isn't there.
        guard c.s > 0.02 else { return color }
        return Color(hue: c.h, saturation: max(0.68, min(0.95, c.s * 1.3)), brightness: max(0.85, min(1, c.b * 1.25)))
    }

    /// A two-tone pair derived from a single base colour: same saturation and
    /// brightness, hue shifted by ~130° so the pair reads as a deliberate
    /// two-tone rather than a harsh full complementary clash.
    static func huePair(from color: Color) -> (Color, Color) {
        let c = color.hsb
        let shifted = Color(hue: (c.h + 0.36).truncatingRemainder(dividingBy: 1), saturation: c.s, brightness: c.b)
        return (color, shifted)
    }

}
