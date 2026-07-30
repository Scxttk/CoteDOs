import AppKit
import SwiftUI

/// Quantised cover colours for the spectrum bars: one colour per bar, taken
/// from the vertical slice of cover that bar sits over (left bar = left of
/// cover), split into the slice's top and bottom half so a bar keeps a faint
/// cover-derived gradient.
///
/// Precomputed per bar count rather than per fixed column: which colour wins a
/// slice depends on how wide the slice is, so five bars are not just six bars
/// resampled. The collapsed pill and the expanded wave draw different counts,
/// hence a small table.
/// The accents a cover actually contains: the dominant hue, plus — when the
/// artwork really has them — up to two more colour families (secondary at
/// least 60° from the winner, tertiary at least 45° from both). Only `primary`
/// tints the wave today; the other two describe what the extractor found and
/// are what `ArtworkColorTests` pins the hue-bucket vote against.
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
/// 2 ColorSync conversions on every track change, of which one or two rows were
/// ever drawn. The expensive per-cover analysis still happens once, off the
/// main thread; a row is a couple of vote passes over a 48×48 sample, cheap
/// enough to do on first use.
final class CoverBarPalette: Equatable {
    struct Bar: Equatable {
        /// The one colour this bar's slice of sleeve elected.
        let top: Color
        /// `top` decomposed, so `WaveBarsView`'s per-frame foot work is
        /// arithmetic instead of a ColorSync round-trip (see `HSB`).
        let topHSB: HSB
        /// What the bar's gradient ends on: the same colour, drained, never a
        /// second one. A bar on the iPhone holds its hue from tip to foot and
        /// only loses saturation and light on the way down — measured across
        /// three sleeves, under 10° of hue over a whole bar. Derived here
        /// rather than in the view because the palette is built once per cover,
        /// off the main thread, and then cached.
        let foot: Color

        init(color: Color) {
            self.top = color
            self.topHSB = HSB(color)
            self.foot = HSB(color).brightnessScaled(0.92)
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

    /// One palette is built per cover, so identity is equality — exactly the
    /// "did the cover change" question SwiftUI asks.
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
