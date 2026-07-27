import XCTest
import SwiftUI
@testable import CoteDOs

/// Renders `WaveBarsView` offscreen — every style, plus the wide spectrum-only
/// variant — and writes PNGs to `/tmp/notchmate-wavebars/`. Primarily a visual
/// harness: the wave only exists animated on a live notch, and this is the one
/// way to look at a frozen frame of it (and to let a review judge colour
/// choices) without pointing a camera at the screen. The assertions just pin
/// that every style renders at all.
///
/// Comparing a PNG against one from an earlier run only works when *the same
/// tests* ran in both: a preceding `ImageRenderer` pass in the same process
/// shifts later output by up to 5/255 on a few percent of pixels (invisible,
/// but enough to change the checksum). Run one test method in isolation on
/// both sides of a before/after comparison, or compare pixels with a
/// tolerance.
@MainActor
final class WaveBarsSnapshotTests: XCTestCase {

    private static let outputDirectory = URL(fileURLWithPath: "/tmp/notchmate-wavebars", isDirectory: true)

    /// A frozen "mid-song" frame: uneven, with a couple of peaks.
    private let bands: [CGFloat] = [
        0.35, 0.55, 0.80, 1.00, 0.70, 0.45, 0.60, 0.90,
        0.50, 0.30, 0.65, 0.85, 0.40, 0.75, 0.55, 0.25,
    ]

    func testEveryStyleRendersAndWritesASnapshot() throws {
        let settings = UserSettings.shared
        let originalStyle = settings.spectrumStyle
        let originalSource = settings.spectrumColorSource
        defer {
            settings.spectrumStyle = originalStyle
            settings.spectrumColorSource = originalSource
        }
        settings.spectrumColorSource = .cover

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        // A warm red sleeve with teal and amber families — the three-stop case.
        let tint = Color(hue: 0.97, saturation: 0.75, brightness: 0.85)
        let secondary = Color(hue: 0.50, saturation: 0.65, brightness: 0.75)
        let tertiary = Color(hue: 0.10, saturation: 0.80, brightness: 0.90)

        for style in UserSettings.SpectrumStyle.allCases {
            settings.spectrumStyle = style

            // The wide spectrum-only pill layout (16 bars, 48×20 frame).
            let wave = WaveBarsView(
                isActive: true,
                tint: tint,
                secondaryTint: secondary,
                tertiaryTint: tertiary,
                bands: bands,
                count: NotchLayout.collapsedWideWaveBarCount,
                maxHeight: NotchLayout.collapsedWideWaveMaxHeight,
                barWidth: NotchLayout.collapsedWaveBarWidth,
                spacing: NotchLayout.collapsedWaveSpacing
            )
            .frame(width: NotchLayout.collapsedWideWavesWidth, height: NotchLayout.collapsedWideWaveFrameHeight)
            .padding(14)
            .background(Color.black)

            let renderer = ImageRenderer(content: wave)
            renderer.scale = 8   // 2pt bars are unjudgeable at 1:1
            let image = try XCTUnwrap(renderer.cgImage, "style \(style.rawValue) failed to render")

            let rep = NSBitmapImageRep(cgImage: image)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.outputDirectory.appendingPathComponent("wave-\(style.rawValue).png"))
        }
    }

    /// The spectrum-only pill at its two ends: Apple's 6-bar default and the
    /// slider's 32-bar maximum. The 6-bar case is where the wave used to read
    /// as a flat block — 32 bands folded onto 6 bars by pure max, a 0.45
    /// envelope floor and an oversized glow between them levelled the run —
    /// so this frame exists to judge exactly that: the edge bars should duck
    /// well below the crest (Apple's sit at ~16% of peak).
    func testSpectrumOnlyPillRendersAtBothEnds() throws {
        let settings = UserSettings.shared
        let originalStyle = settings.spectrumStyle
        let originalSource = settings.spectrumColorSource
        defer {
            settings.spectrumStyle = originalStyle
            settings.spectrumColorSource = originalSource
        }
        settings.spectrumStyle = .gradient
        settings.spectrumColorSource = .cover

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        // A 32-band frame the way the analyzer would hand it over mid-song.
        let fullBands: [CGFloat] = (0..<32).map { i in
            let t = CGFloat(i) / 31
            return 0.25 + 0.55 * abs(sin(.pi * t * 3.1 + 0.4)) + (i % 5 == 2 ? 0.2 : 0)
        }.map { min(1, $0) }

        for count in [6, 32] {
            let wave = WaveBarsView(
                isActive: true,
                tint: Color(hue: 0.97, saturation: 0.75, brightness: 0.85),
                secondaryTint: Color(hue: 0.50, saturation: 0.65, brightness: 0.75),
                bands: fullBands,
                count: count,
                maxHeight: NotchLayout.collapsedWideWaveMaxHeight,
                barWidth: NotchLayout.collapsedWaveBarWidth,
                spacing: NotchLayout.collapsedWaveSpacing
            )
            .frame(width: NotchLayout.pillSpectrumWidth(forBarCount: count), height: NotchLayout.collapsedWideWaveFrameHeight)
            .padding(14)
            .background(Color.black)

            let renderer = ImageRenderer(content: wave)
            renderer.scale = 8
            let image = try XCTUnwrap(renderer.cgImage, "pill wave failed to render at \(count) bars")
            let rep = NSBitmapImageRep(cgImage: image)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.outputDirectory.appendingPathComponent("pill-spectrum-\(count).png"))
        }
    }

    /// A stand-in for what `ArtworkColor` quantises out of a real sleeve:
    /// mostly two-tone columns, plus a couple that landed on a single colour
    /// (the case the bar's own gradient has to rescue).
    private func coverPalette(count: Int) -> CoverBarPalette {
        let colors: [Color] = [
            Color(hue: 0.08, saturation: 0.80, brightness: 0.90),
            Color(hue: 0.55, saturation: 0.70, brightness: 0.80),
            Color(hue: 0.75, saturation: 0.65, brightness: 0.85),
        ]
        let row = (0..<count).map { index -> CoverBarPalette.Bar in
            let top = colors[index % colors.count]
            // Every third column quantises to one colour top and bottom.
            let bottom = index % 3 == 0 ? top : colors[(index + 1) % colors.count]
            return CoverBarPalette.Bar(top: top, bottom: bottom)
        }
        return CoverBarPalette(bars: [count: row])
    }

    /// `.coverImage` with an actual quantised palette — the branch the style
    /// sweep above cannot reach, since it passes no `coverBars` and the style
    /// therefore renders its no-artwork fallback. Worth a frame of its own:
    /// this is the path where a bar's shading is precomputed alongside the
    /// palette instead of derived while drawing.
    func testCoverImageStyleRendersItsQuantisedPalette() throws {
        let settings = UserSettings.shared
        let originalStyle = settings.spectrumStyle
        defer { settings.spectrumStyle = originalStyle }
        settings.spectrumStyle = .coverImage

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        let count = NotchLayout.collapsedWideWaveBarCount
        let wave = WaveBarsView(
            isActive: true,
            tint: Color(hue: 0.08, saturation: 0.80, brightness: 0.90),
            coverBars: coverPalette(count: count),
            bands: bands,
            count: count,
            maxHeight: NotchLayout.collapsedWideWaveMaxHeight,
            barWidth: NotchLayout.collapsedWaveBarWidth,
            spacing: NotchLayout.collapsedWaveSpacing
        )
        .frame(width: NotchLayout.collapsedWideWavesWidth, height: NotchLayout.collapsedWideWaveFrameHeight)
        .padding(14)
        .background(Color.black)

        let renderer = ImageRenderer(content: wave)
        renderer.scale = 8
        let image = try XCTUnwrap(renderer.cgImage, "coverImage with a palette failed to render")
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: Self.outputDirectory.appendingPathComponent("wave-coverImage-palette.png"))
    }

    /// The scalable form: the same wave asked to fill a page, and then a
    /// screen. Bar count and thickness are derived from the space, so this is
    /// the test that catches a stage that renders hairlines, slabs, or a run
    /// that doesn't sit centred in the area it was given.
    func testSpectrumStageScalesFromPanelToScreen() throws {
        let settings = UserSettings.shared
        let originalStyle = settings.spectrumStyle
        defer { settings.spectrumStyle = originalStyle }
        settings.spectrumStyle = .solid

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        let levels = SpectrumBands.forTesting(bands)
        let sizes: [(String, CGSize, CGFloat)] = [
            ("panel", CGSize(width: 380, height: 150), 3),
            ("screen", CGSize(width: 1280, height: 720), 1),
        ]
        for (name, size, scale) in sizes {
            let stage = SpectrumStageView(
                levels: levels,
                isLive: true,
                isActive: true,
                tint: Color(hue: 0.563, saturation: 0.92, brightness: 0.96)
            )
            .frame(width: size.width, height: size.height)
            .background(Color.black)

            let renderer = ImageRenderer(content: stage)
            renderer.scale = scale
            let image = try XCTUnwrap(renderer.cgImage, "stage failed to render at \(name)")
            let rep = NSBitmapImageRep(cgImage: image)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.outputDirectory.appendingPathComponent("stage-\(name).png"))
        }
    }

    /// Neighbouring bars over the same region of a cover quantise to the same
    /// colour — that bundling is deliberate — so a column whose two halves
    /// landed on one palette entry must still get a gradient, spread by
    /// brightness, rather than reading as a flat slab.
    func testASingleColourColumnStillGetsAGradientFoot() {
        let color = Color(hue: 0.55, saturation: 0.70, brightness: 0.80)
        let flat = CoverBarPalette.Bar(top: color, bottom: color)
        XCTAssertNotEqual(flat.foot, color, "a single-colour column must not render as one flat colour")

        let other = Color(hue: 0.08, saturation: 0.80, brightness: 0.90)
        let twoTone = CoverBarPalette.Bar(top: color, bottom: other)
        XCTAssertEqual(twoTone.foot, other, "a two-tone column keeps the cover's own second colour")
    }
}
