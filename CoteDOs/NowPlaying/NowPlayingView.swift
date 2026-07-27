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

    /// Same battery trade as the wave's ease: the fill ticks once a second, so
    /// a 1s ease is permanently in flight while the panel is open.
    @ObservedObject private var power = PowerSource.shared

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
                        .animation(isScrubbing || power.isOnBattery ? nil : .linear(duration: 1), value: displayedFraction)
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
    /// See `WaveBarsView.morphScale`.
    var morphScale: CGFloat = 1

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
            morphScale: morphScale
        )
    }
}

/// One bar's colours, resolved once per view update rather than per bar per
/// frame. Everything in here is independent of the bar's current level, so the
/// only colour work left in the draw path is the tip whitening — and `HSB`
/// does that as arithmetic, with no trip through NSColor/ColorSync.
private struct BarInk {
    /// The bar's body colour, byte-for-byte what the old per-frame path
    /// produced for this style.
    let base: Color
    let baseHSB: HSB
    /// What the bar's top-to-bottom gradient ends on.
    let foot: Color
    /// The foot decomposed, so `WaveCanvas` can pull it back toward the base on
    /// bars far taller than the ones the drain was measured on.
    let footHSB: HSB

    /// Depth, in the direction Apple's own bars run. A bar on a real iPhone's
    /// Dynamic Island travels from S 0.59 / B 0.60 at its tip to S 0.32 /
    /// B 0.64 at its base (measured off screenshots of the now-playing
    /// island): the colour *drains* toward the foot and lifts a touch in
    /// brightness, rather than darkening. Ours used to do the opposite —
    /// full colour at the tip, 72% brightness at the base — which is what
    /// made the bars read as standing on the black instead of sunk into it.
    static let footSaturation = 0.55   // 0.32 / 0.59
    static let footBrightness = 1.07   // 0.64 / 0.60

    init(_ color: Color) {
        let hsb = HSB(color)
        let drained = hsb.scaledHSB(saturation: Self.footSaturation, brightness: Self.footBrightness)
        self.base = color
        self.baseHSB = hsb
        self.foot = drained.color
        self.footHSB = drained
    }

    /// For styles that *derive* the colour and therefore already know its
    /// components — no decomposition needed at all.
    init(hsb: HSB) {
        let drained = hsb.scaledHSB(saturation: Self.footSaturation, brightness: Self.footBrightness)
        self.base = hsb.color
        self.baseHSB = hsb
        self.foot = drained.color
        self.footHSB = drained
    }

    /// The `.coverImage` style: the quantised cover column, whose shading was
    /// worked out once when the palette was built (see `CoverBarPalette.Bar`).
    init(coverBar: CoverBarPalette.Bar) {
        self.base = coverBar.top
        self.baseHSB = coverBar.topHSB
        self.foot = coverBar.foot
        self.footHSB = HSB(coverBar.foot)
    }
}

/// A run of bar levels that SwiftUI can interpolate.
///
/// A `Canvas` is not animated by putting `.animation` on it: the drawing
/// closure only runs when the view is re-evaluated, so the *view* has to be
/// `Animatable` and feed the interpolated value back into the drawing. This is
/// that value — the whole run as one animatable quantity.
private struct BarLevels: VectorArithmetic {
    var values: [CGFloat]

    static var zero: BarLevels { BarLevels(values: []) }

    static func + (lhs: BarLevels, rhs: BarLevels) -> BarLevels { combine(lhs, rhs, +) }
    static func - (lhs: BarLevels, rhs: BarLevels) -> BarLevels { combine(lhs, rhs, -) }

    /// Runs of different length only meet when the bar count itself changes
    /// (the pill's slider). Pad rather than truncate, so the added bars grow
    /// from nothing instead of the whole wave snapping to a new shape.
    private static func combine(_ lhs: BarLevels, _ rhs: BarLevels, _ op: (CGFloat, CGFloat) -> CGFloat) -> BarLevels {
        let n = max(lhs.values.count, rhs.values.count)
        return BarLevels(values: (0..<n).map { i in
            op(i < lhs.values.count ? lhs.values[i] : 0, i < rhs.values.count ? rhs.values[i] : 0)
        })
    }

    mutating func scale(by rhs: Double) {
        for i in values.indices { values[i] *= CGFloat(rhs) }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + Double($1 * $1) }
    }
}

/// The wave's *dimensions* as one interpolatable quantity, so a change of size
/// morphs instead of cutting.
///
/// These used to be plain `let`s on `WaveCanvas`, which meant only the bar
/// heights could animate — the run's thickness, gaps and vertical range
/// changed in a single frame. That was invisible while every wave had a fixed
/// size, and became the thing standing between the pill and the spectrum page
/// once both derived their geometry from one rule: the two are the same wave at
/// two scales, so growing from one into the other is a pure interpolation of
/// this struct.
private struct WaveMetrics: VectorArithmetic {
    var barWidth: CGFloat
    var spacing: CGFloat
    var maxHeight: CGFloat
    var floorHeight: CGFloat

    static var zero: WaveMetrics { WaveMetrics(barWidth: 0, spacing: 0, maxHeight: 0, floorHeight: 0) }

    static func + (lhs: WaveMetrics, rhs: WaveMetrics) -> WaveMetrics { combine(lhs, rhs, +) }
    static func - (lhs: WaveMetrics, rhs: WaveMetrics) -> WaveMetrics { combine(lhs, rhs, -) }

    private static func combine(_ lhs: WaveMetrics, _ rhs: WaveMetrics,
                                _ op: (CGFloat, CGFloat) -> CGFloat) -> WaveMetrics {
        WaveMetrics(barWidth: op(lhs.barWidth, rhs.barWidth),
                    spacing: op(lhs.spacing, rhs.spacing),
                    maxHeight: op(lhs.maxHeight, rhs.maxHeight),
                    floorHeight: op(lhs.floorHeight, rhs.floorHeight))
    }

    mutating func scale(by rhs: Double) {
        let f = CGFloat(rhs)
        barWidth *= f
        spacing *= f
        maxHeight *= f
        floorHeight *= f
    }

    var magnitudeSquared: Double {
        Double(barWidth * barWidth + spacing * spacing + maxHeight * maxHeight + floorHeight * floorHeight)
    }
}

/// The whole wave, drawn in a single pass.
///
/// This used to be an `HStack` of `Capsule` views — one SwiftUI view per bar,
/// 32 of them in the pill. That is what made the wave expensive, and it was
/// never the pixels: a thumbnail-sized strip of rounded rects cost ~52% of a
/// core, because every animated frame re-evaluated and re-laid-out 32 views'
/// worth of view graph, 60 times a second. Behind a `Canvas` there is no
/// per-bar identity and no layout — one closure, `count` rounded rects — so a
/// frame costs about what it looks like it should, and the bars can keep
/// easing between spectrum updates on battery as well as on wall power.
private struct WaveCanvas: View, Animatable {
    /// Per-bar magnitude (0…1). Interpolated by SwiftUI; drives height, glow
    /// intensity and the white-hot tip alike.
    var levels: BarLevels
    /// Per-bar colours. Not animatable — a cover change swaps these outright
    /// rather than crossfading, which is the one thing lost by leaving the
    /// view-per-bar layout behind.
    let inks: [BarInk]
    /// The run's dimensions. Deliberately *not* part of `animatableData`: the
    /// levels re-animate 30×/s with their own 0.09 s ease, and when both shared
    /// one animatable value that ease restarted the size interpolation on every
    /// spectrum update — collapsing a 0.4 s morph into 0.09 s (invisible) and
    /// making the motion itself jittery. Resizing is animated one level up
    /// instead, as a transform (see `WaveBarsView.morphScale`).
    let metrics: WaveMetrics

    var animatableData: BarLevels {
        get { levels }
        set { levels = newValue }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let total = min(levels.values.count, inks.count)
            guard total > 0 else { return }
            let barWidth = max(0, metrics.barWidth)
            let spacing = max(0, metrics.spacing)
            let runWidth = CGFloat(total) * barWidth + CGFloat(total - 1) * spacing
            var x = (size.width - runWidth) / 2
            for i in 0..<total {
                let level = max(0, min(1, levels.values[i]))
                let height = max(metrics.floorHeight, metrics.maxHeight * level * Self.envelope(at: i, total: total))
                let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                draw(&context, rect: rect, level: level, ink: inks[i])
                x += barWidth + spacing
            }
        }
    }

    /// Height envelope across the run: full in the middle, tapering toward
    /// both ends, so the wave has a *shape* — a crest that swells and falls —
    /// instead of a rectangle of equally tall bars.
    ///
    /// The taper depth depends on the bar count. The Dynamic Island's 6-bar
    /// wave measures 2.0/4.3/12.7/12.0/7.3/2.0 pt — its edge bars sit at ~16%
    /// of the peak, not 45%. A 0.45 floor at 6 bars is what made the pill read
    /// as a flat block; at 16+ bars the same deep taper would duck a third of
    /// the run, so the floor eases back up to 0.45 there. The exponent
    /// steepens for small counts for the same reason: with 6 bars every bar
    /// *is* the curve.
    /// At wide counts the envelope all but disappears (floor 0.75): with 32
    /// bars there is no bucketing, so an imposed crest was the one thing
    /// still masking the music — the stage view proved the same data reads
    /// far livelier without it. Small counts keep the deep Apple-style dip.
    static func envelope(at index: Int, total: Int) -> CGFloat {
        guard total > 1 else { return 1 }
        let spread = min(1, max(0, CGFloat(total - 6) / 10))   // 0 at ≤6 bars, 1 at ≥16
        let floor = 0.16 + (0.75 - 0.16) * spread
        let exponent = 0.8 - 0.3 * spread
        let t = CGFloat(index) / CGFloat(total - 1)
        return floor + (1 - floor) * pow(sin(.pi * t), exponent)
    }

    /// Ceiling for the per-bar glow. Reached only well beyond page size — the
    /// pill's widest bar glows at ~6 pt, the page's at ~13 pt.
    private static let maximumGlowRadius: CGFloat = 16

    /// Tallest bar the measured foot drain applies to in full. Apple's island
    /// bars top out around 13 pt and the spectrum page's around 126, and the
    /// drain reads as depth at both — but it is a *proportional* gradient, so
    /// on a fullscreen bar of 400+ pt the desaturated end owns most of the
    /// shape and the whole wave goes pale. Past this height the foot is pulled
    /// back toward the bar's own colour.
    private static let fullDrainBarHeight: CGFloat = 130
    /// How much drain survives at any size, so big bars keep some depth.
    private static let minimumDrain: CGFloat = 0.35

    /// The colour a bar's gradient ends on, held back on bars taller than the
    /// drain was measured for.
    private static func foot(of ink: BarInk, barHeight: CGFloat) -> Color {
        guard barHeight > fullDrainBarHeight else { return ink.foot }
        let drain = max(minimumDrain, fullDrainBarHeight / barHeight)
        return ink.baseHSB.mixed(to: ink.footHSB, t: Double(drain)).color
    }

    private func draw(_ context: inout GraphicsContext, rect: CGRect, level: CGFloat, ink: BarInk) {
        let capsule = Path(roundedRect: rect, cornerRadius: rect.width / 2)

        // Every bar throws its own light, and louder bands glow harder. On the
        // pure black island this halo is what makes the wave read as alive
        // rather than printed on.
        //
        // The bar's *colour* no longer changes with the level. A peaking bar
        // used to drive its tip up to 60% toward white ("incandescence"); the
        // Dynamic Island doesn't do that — its bars hold their colour and only
        // their height and glow move — and side by side the white tips were
        // the last thing that still read as un-Apple.
        var layer = context
        // Glow radius scales with the bar's own width: a fixed 1–4.5 pt halo
        // was sized for 3 pt panel bars and swallowed the 2 pt pill bars whole,
        // bleeding into their neighbours and flattening the wave's shape.
        //
        // Capped in absolute terms because the same wave now also runs
        // fullscreen, where bars are ~100 pt wide: a blur radius that kept
        // scaling would be a ~100 pt gaussian on every bar of every frame, which
        // is a lot of pixels to throw away on a halo nobody can see the edge of.
        // The cap is far above anything the pill or the page reaches, so their
        // look is untouched.
        let glow = min(Self.maximumGlowRadius, rect.width * (0.4 + 0.9 * level))
        layer.addFilter(.shadow(color: ink.base.opacity(0.35 + 0.45 * level), radius: glow))
        layer.fill(
            capsule,
            with: .linearGradient(
                Gradient(colors: [ink.base, Self.foot(of: ink, barHeight: rect.height)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
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
    /// Size the run is drawn at relative to its own geometry, for the pill⇄page
    /// morph: the caller holds this away from 1 for the first frame after the
    /// wave appears and the spring carries it home. 1 means no morph is running,
    /// which is every wave that isn't mid-transition.
    var morphScale: CGFloat = 1
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

    /// iOS's spectrum bars never fully bottom out — even a silent band keeps a
    /// visible sliver. Ours read as flatter than that; nudge the hard floor up
    /// a touch (was 3) so the quietest bar still reads as "there".
    /// Proportional, with only a hairline clamp (was `max(4, …)`): a 4 pt
    /// floor on the pill's short bars swallowed 22% of the run's height —
    /// the stage view's floor is 14% and its extra headroom is exactly what
    /// makes the same data read livelier there.
    private var floorHeight: CGFloat { max(2, maxHeight * 0.14) }

    /// Fit the source bands to `count` bars: pass through when they match, else
    /// group into `count` buckets. Each bucket blends its max with its mean:
    /// pure max compressed the wave's dynamics — with 32 bands folded onto 6
    /// bars almost every bucket contains *some* loud band, so all bars sat
    /// high (band span 0.66 collapsed to bar span 0.19) and the pill read as a
    /// flat block. The mean half restores the spread; the max half keeps the
    /// punch of a transient that only lives in one band.
    private func fitted(_ source: [CGFloat]) -> [CGFloat] {
        guard count > 0, !source.isEmpty else { return source }
        if source.count == count { return source }
        return (0..<count).map { i in
            let lo = i * source.count / count
            let hi = max(lo + 1, (i + 1) * source.count / count)
            let bucket = source[lo..<min(hi, source.count)]
            let peak = bucket.max() ?? 0
            let mean = bucket.reduce(0, +) / CGFloat(bucket.count)
            return (peak + mean) / 2
        }
    }

    private var metrics: WaveMetrics {
        WaveMetrics(barWidth: barWidth, spacing: spacing, maxHeight: maxHeight, floorHeight: floorHeight)
    }

    private func wave(levels: [CGFloat], inks: [BarInk]) -> WaveCanvas {
        WaveCanvas(levels: BarLevels(values: levels), inks: inks, metrics: metrics)
    }

    @ViewBuilder
    var body: some View {
        if let bands, !bands.isEmpty {
            // Real spectrum: bar height follows each band, eased between
            // updates so the wave flows instead of stepping.
            //
            // This ease is the most expensive thing in the app: a new target
            // arrives before the previous one finishes, so an animation is
            // permanently in flight, and that makes SwiftUI re-evaluate its
            // animated attributes on every 60 Hz display refresh however
            // rarely the bands change. The `Canvas` rewrite (see `WaveCanvas`)
            // made each of those frames much cheaper — but even so the ease
            // measured 25–28% of a core against 9–11% without it, so on
            // battery it goes away and the bars step straight to each
            // published level. `PowerSource` decides; the trade is deliberate.
            //
            // Note what is *not* animated any more: the bar colours. They used
            // to crossfade over 0.4s when the cover changed; a canvas can't
            // interpolate them, so a new palette now takes effect at once.
            let values = fitted(bands)
            wave(levels: values, inks: palette(total: values.count))
                .frame(maxHeight: .infinity, alignment: .center)
                .animation(power.isOnBattery ? nil : .easeOut(duration: 0.09), value: values)
                // The pill⇄page morph, as a transform rather than a redraw: the
                // two ends are the same wave at two scales, so scaling *is* the
                // interpolation — and unlike animating the canvas's geometry it
                // cannot be restarted by the levels' ease, which is what kept
                // the morph from ever being visible.
                .scaleEffect(morphScale)
                .animation(NotchLayout.islandMorphAnimation, value: morphScale)
        } else {
            // Hoisted out of the timeline closure on purpose: the colours don't
            // depend on the clock, so they're resolved once per update instead
            // of on every one of the 30 ticks a second.
            let inks = palette(total: count)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                // The timeline already supplies a new value per frame, so this
                // branch needs no animation of its own.
                wave(levels: (0..<count).map { proceduralLevel(index: $0, time: time) }, inks: inks)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    /// The procedural fallback's level for one bar (0…1) — `WaveCanvas` turns
    /// it into a height the same way it does a real band's.
    private func proceduralLevel(index: Int, time: Double) -> CGFloat {
        guard isActive, maxHeight > 0 else { return floorHeight / max(maxHeight, 1) }
        let phase = Double(index) * 0.7
        return CGFloat(0.35 + 0.65 * abs(sin(time * 4 + phase)))
    }
}

// The per-bar shading helpers that used to live here (`whitened`,
// `brightnessScaled`, `hsbMix`, `multiStop`, `brightnessRamp`) moved onto
// `HSB`: each of them decomposed its `Color` argument on every call, which is
// a ColorSync round-trip, and the wave called them per bar per frame. They now
// operate on components resolved once per palette — see `WaveBarsView.BarInk`.
private extension Color {
    private var hsb: HSB { HSB(self) }

    /// The treatment a colour gets *only when painted as a spectrum bar*: bars
    /// are two points of colour on a pure black field and need presence, while
    /// the same accent stays calmer everywhere else — title glow, placeholder
    /// tint. Keeps the hue; the bands below decide how loud it gets.
    ///
    /// The bands are set against Apple's own answer. The same cover run
    /// through iOS's now-playing pipeline puts the Dynamic Island's bars at
    /// H 0.559 / S 0.59 / B 0.60 at the tip, against an extracted accent of
    /// H 0.563 / S 0.92 / B 0.96 — so Apple picks the *same hue* (1.4° apart)
    /// and then tones it **down**. This used to push the other way, to
    /// S 0.95 / B 1.00, which is where the wave's neon look came from.
    ///
    /// The ceilings now sit on Apple's measured value. The floors stay, so a
    /// washed-out cover doesn't produce a bar you can't see.
    private static let barSaturation: ClosedRange<CGFloat> = 0.45...0.62
    private static let barBrightness: ClosedRange<CGFloat> = 0.54...0.64

    static func stageVivid(_ color: Color) -> Color {
        let c = color.hsb
        // A genuinely neutral colour (white fallback, B/W cover) must stay
        // neutral — saturating it would invent a hue that isn't there.
        guard c.s > 0.02 else { return color }
        return Color(
            hue: c.h,
            saturation: min(max(c.s, barSaturation.lowerBound), barSaturation.upperBound),
            brightness: min(max(c.b, barBrightness.lowerBound), barBrightness.upperBound)
        )
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
