import AppKit
import SwiftUI

/// The taste-dependent half of the bar-palette computation, read from
/// `UserSettings` on the main thread and handed to `ArtworkColor` so the
/// background work never touches the settings object. Equatable so a changed
/// value can invalidate the cache.
struct CoverBarTuning: Equatable {
    var paletteSize: Int
    var brightnessLevels: Int
    var saturation: CGFloat
    var brightness: CGFloat

    init(settings: UserSettings = .shared) {
        paletteSize = max(1, min(5, settings.coverPaletteSize))
        brightnessLevels = max(1, min(4, settings.coverBrightnessLevels))
        saturation = CGFloat(settings.coverBarSaturation)
        brightness = CGFloat(settings.coverBarBrightness)
    }
}

/// Quantised cover colours for the `.coverImage` spectrum style: one colour per
/// bar, taken from the vertical slice of cover that bar sits over (left bar =
/// left of cover), split into the slice's top and bottom half so a bar keeps a
/// faint cover-derived gradient.
///
/// Precomputed per bar count rather than per fixed column: which colour wins a
/// slice depends on how wide the slice is, so five bars are not just six bars
/// resampled. The collapsed pill and the expanded wave draw different counts,
/// hence a small table.
/// The accents a cover actually contains: the dominant hue, plus — when the
/// artwork really has them — up to two more colour families (secondary at
/// least 60° from the winner, tertiary at least 45° from both). They feed the
/// `gradient`/`alternating` styles in "Vom Cover" mode, so the wave runs
/// through colours the sleeve actually contains instead of synthetic shifts.
struct ArtworkAccents: Equatable {
    let primary: Color
    let secondary: Color?
    let tertiary: Color?

    init(primary: Color, secondary: Color? = nil, tertiary: Color? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }
}

/// A class deriving its rows lazily, not a precomputed struct: building the
/// row for every supported bar count eagerly meant ~30 rows × up to 32 bars ×
/// 2 ColorSync conversions on every track change (and every tuning-slider
/// step), of which one or two rows were ever drawn. The expensive per-cover
/// analysis still happens once, off the main thread; a row is a couple of
/// vote passes over a 48×48 sample, cheap enough to do on first use.
final class CoverBarPalette: Equatable {
    struct Bar: Equatable {
        let top: Color
        let bottom: Color
        /// `top` decomposed, so the per-frame tip whitening in `WaveBarsView`
        /// is arithmetic instead of a ColorSync round-trip (see `HSB`).
        let topHSB: HSB
        /// What the bar's gradient actually ends on. Neighbouring bars over
        /// the same region of the artwork quantise to the *same* colour —
        /// that bundling is the point — so when a column's two halves land on
        /// one palette entry the gradient is spread by brightness instead,
        /// keeping the bar from reading as a flat slab. Derived here rather
        /// than in the view because the palette is built once per cover, off
        /// the main thread, and then cached.
        let foot: Color

        init(top: Color, bottom: Color) {
            self.top = top
            self.bottom = bottom
            self.topHSB = HSB(top)
            self.foot = top == bottom ? HSB(bottom).brightnessScaled(0.92) : bottom
        }
    }

    /// Bar counts a row can be derived for — everything the pill's bar-count
    /// slider can ask for (6…32), the small waves (3…5) and the music tab (6).
    static let supportedBarCounts = Array(3...32)

    /// Derives the row for one bar count. Captures the finished per-cover
    /// analysis (quantised pixel assignments), so calling it is cheap.
    private let derive: (Int) -> [Bar]
    /// Memoized rows, filled on demand. Main-thread only, like every other
    /// consumer of the palette.
    private var rows: [Int: [Bar]] = [:]

    init(derive: @escaping (Int) -> [Bar]) {
        self.derive = derive
    }

    /// Fixed-content palette for tests and previews.
    convenience init(bars: [Int: [Bar]]) {
        self.init { bars[$0] ?? [] }
    }

    /// One palette is built per cover × tuning, so identity is equality —
    /// exactly the "did the cover change" question SwiftUI asks.
    static func == (lhs: CoverBarPalette, rhs: CoverBarPalette) -> Bool { lhs === rhs }

    func bar(forBarAt index: Int, total: Int) -> Bar? {
        // Clamp to the nearest supported count rather than drawing nothing,
        // if a caller ever asks for an unsupported bar count.
        let count = Self.supportedBarCounts.contains(total)
            ? total
            : Self.supportedBarCounts.min { abs($0 - total) < abs($1 - total) } ?? 5
        let row = rows[count] ?? {
            let derived = derive(count)
            rows[count] = derived
            return derived
        }()
        guard index >= 0, !row.isEmpty else { return nil }
        return row[min(index, row.count - 1)]
    }
}
