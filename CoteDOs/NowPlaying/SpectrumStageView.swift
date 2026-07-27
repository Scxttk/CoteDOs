import SwiftUI

/// The spectrum with nothing else on the page: bars sized from the space they
/// are given rather than from constants, so the same view works at pill size
/// and blown up to a whole screen.
///
/// This is the scalable form of the wave. `WaveBarsView` takes its geometry as
/// parameters and draws through a single `Canvas`, so the only thing standing
/// between the pill's 20 pt run and a screen-saver-sized one is deciding how
/// many bars to draw and how thick — which is what this view does. Everything
/// visual (colour derivation, the vertical gradient, the glow) is shared, so
/// the big version can't drift away from the small one.
struct SpectrumStageView: View {
    /// Live band levels, observed here and nowhere above, so a spectrum update
    /// redraws the bars and not the page around them (see `SpectrumBands`).
    @ObservedObject var levels: SpectrumBands
    var isLive: Bool
    var isActive: Bool
    var tint: Color?
    var secondaryTint: Color?
    var tertiaryTint: Color?
    var coverBars: CoverBarPalette?

    /// Never more than the analyzer actually resolves — past that the extra
    /// bars are interpolation, not information.
    private let maximumBars = 32
    /// How tall a fully deflected bar is relative to its width. Without this
    /// the stage just keeps the count and stretches: at 1280×720 a run of 32
    /// bars is 22 pt wide and 700 tall, which reads as hairlines rather than
    /// as the pill's wave made big. Tying thickness to the *height* instead
    /// keeps the proportion at every size, and the width then decides how many
    /// bars fit. (Apple's island is stubbier still, around 6 — that looks
    /// sparse once a bar is the height of a hand.)
    private let barAspectRatio: CGFloat = 12
    /// Breathing room so the tallest bar and its glow don't touch the edges.
    private let inset: CGFloat = 12

    /// How many bars of roughly `height / barAspectRatio` fit across `width`,
    /// keeping the fixed bar-to-gap ratio and the analyzer's resolution.
    private func barCount(width: CGFloat, height: CGFloat) -> Int {
        guard width > 0, height > 0 else { return 1 }
        let target = max(1, height / barAspectRatio)
        let pitch = target * (1 + NotchLayout.waveBarGapRatio)
        let fits = Int(((width + target * NotchLayout.waveBarGapRatio) / pitch).rounded())
        return max(1, min(maximumBars, fits))
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width - inset * 2)
            let height = max(0, geo.size.height - inset * 2)
            let count = barCount(width: width, height: height)
            let barWidth = NotchLayout.waveBarWidth(fitting: count, into: width)
            WaveBarsView(
                isActive: isActive,
                tint: tint,
                secondaryTint: secondaryTint,
                tertiaryTint: tertiaryTint,
                coverBars: coverBars,
                bands: isLive ? levels.values : nil,
                count: count,
                maxHeight: height,
                barWidth: barWidth,
                spacing: barWidth * NotchLayout.waveBarGapRatio
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
