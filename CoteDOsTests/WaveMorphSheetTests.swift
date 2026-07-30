import XCTest
import SwiftUI
@testable import CoteDOs

/// The pill ⇄ spectrum-page morph, frame by frame.
///
/// The morph is a pure interpolation of `WaveMetrics` between the two ends'
/// geometries (`NotchLayout.pillSpectrumGeometry` and
/// `NotchLayout.spectrumPageWaveGeometry`), which means every in-between frame
/// can be rendered offscreen — the one part of a transition that is normally
/// only judgeable on a real notch. Writes a contact sheet to
/// `/tmp/notchmate-wavebars/morph-sheet.png`.
///
/// What to look for: bar thickness, gaps and height should grow together, so
/// every frame looks like a *complete* wave at some size — never like thin bars
/// in a tall field (thickness lagging height) or a squashed run.
@MainActor
final class WaveMorphSheetTests: XCTestCase {

    private static let outputDirectory = URL(
        fileURLWithPath: "/tmp/notchmate-wavebars", isDirectory: true)

    private let bands: [CGFloat] = (0..<32).map { i in
        let t = CGFloat(i) / 31
        return min(1, 0.25 + 0.55 * abs(sin(.pi * t * 3.1 + 0.4)) + (i % 5 == 2 ? 0.2 : 0))
    }

    /// Both ends must be the same wave at two scales, or there is nothing
    /// sensible to interpolate: same bar-to-height ratio, same gap ratio.
    func testBothEndsShareTheSameProportions() {
        let pill = NotchLayout.pillSpectrumGeometry(forWidth: NotchLayout.pillSpectrumMaxWidth)
        let page = NotchLayout.spectrumPageWaveGeometry

        XCTAssertEqual(pill.spacing / pill.barWidth, page.spacing / page.barWidth, accuracy: 0.01,
                       "gap-to-bar ratio must match at both ends of the morph")
        XCTAssertEqual(pill.barWidth / pill.waveHeight,
                       page.barWidth / page.waveHeight, accuracy: 0.03,
                       "bar thickness must scale with the field at both ends")
        XCTAssertGreaterThan(page.waveHeight, pill.waveHeight * 2,
                             "the page should be a real step up in size, or the morph is pointless")
    }

    /// Renders the interpolation the way `SpectrumStageView.growsFromPill` and
    /// `CollapsedView.arrivesFromPage` drive it.
    func testMorphInterpolatesWholeWavesAtEveryFraction() throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        let pill = NotchLayout.pillSpectrumGeometry(forWidth: NotchLayout.pillSpectrumMaxWidth)
        let page = NotchLayout.spectrumPageWaveGeometry
        let fractions: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let bands = self.bands
        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

        let sheet = VStack(spacing: 10) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, t in
                WaveBarsView(
                    isActive: true,
                    tint: Color(hue: 0.97, saturation: 0.75, brightness: 0.85),
                    bands: bands,
                    count: page.barCount,
                    maxHeight: lerp(pill.waveHeight, page.waveHeight, t),
                    barWidth: lerp(pill.barWidth, page.barWidth, t),
                    spacing: lerp(pill.spacing, page.spacing, t)
                )
                .frame(width: page.runWidth, height: page.waveHeight + 6)
            }
        }
        .padding(12)
        .background(Color.black)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage, "morph sheet failed to render")
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: Self.outputDirectory.appendingPathComponent("morph-sheet.png"))
    }
}
