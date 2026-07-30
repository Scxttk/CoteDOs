import XCTest
import SwiftUI
import AppKit
@testable import CoteDOs

/// Renders the island offscreen and composites it onto a backdrop, producing the
/// images the README ships. Output goes to `/tmp/cotedos-shots/`.
///
/// Two backdrops, see `Backdrop`: a light plate for the feature tiles, and a real
/// macOS wallpaper for the two shots whose whole point is *where* the pill lives.
///
/// This exists because the obvious way — point `screencapture` at a running
/// copy — needs two grants this machine cannot hand an automated session:
/// Screen Recording (without it `screencapture` returns the wallpaper and
/// nothing else), and the AudioCapture consent that a freshly signed build
/// invalidates, which has to be clicked by a human or the wave is frozen at
/// zero in every shot. Rendering the real views with fabricated state needs
/// neither, is deterministic, and can be re-run after any UI change.
///
/// What is real here: the views, the layout constants, the artwork colour
/// election, the QuickLook thumbnails, the FFT (the wave is a genuine frame of
/// the analyzer's output for a known input signal), and the wallpaper where one is
/// used. What is fabricated: the track, its cover, and the files on the shelf.
///
/// Not a regression test — the assertions only pin that each shot rendered at
/// all. Judging them is done by looking.
@MainActor
final class MarketingShots: XCTestCase {

    private static let outputDirectory = URL(fileURLWithPath: "/tmp/cotedos-shots", isDirectory: true)

    /// Point size of the display the shots pretend to be taken on, so the
    /// wallpaper crop has the framing a real screenshot would have. This Mac's
    /// default scaled resolution.
    private let screenSize = CGSize(width: 1440, height: 900)
    /// 2×, matching the existing assets (a 500×268 pt crop shipped as 1000×536).
    private let scale: CGFloat = 2
    /// Wallpaper left visible above the island, the way the `offset:` debug
    /// command used to buy headroom for the live shots.
    private let headroom: CGFloat = 26

    /// Ships with every Mac, so this is reproducible off this machine, and its
    /// purple happens to be the app's own family.
    private let wallpaper = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Purple.heic")

    // MARK: - The shots

    /// Renders the images the README ships. Run it deliberately:
    ///
    ///     xcodebuild test -project CoteDOs.xcodeproj -scheme CoteDOs \
    ///       -destination 'platform=macOS' -testLanguage en \
    ///       -only-testing:CoteDOsTests/MarketingShots
    ///
    /// `-testLanguage en` is not optional — without it the shots come out in
    /// whatever language this Mac is set to.
    ///
    /// CI skips this with `-skip-testing:` rather than the test gating itself on
    /// an environment variable: the tests run in their own process, so neither a
    /// plain `FOO=1 xcodebuild` nor `TEST_RUNNER_FOO=1` reaches them here, and a
    /// guard that never fires makes the whole thing silently skip while
    /// reporting success. Which it did, twice.
    func testRenderReadmeShots() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: wallpaper.path),
                          "no system wallpaper at \(wallpaper.path)")

        let settings = UserSettings.shared
        let originalStyle = settings.spectrumStyle
        let originalPillOnly = settings.pillSpectrumOnly
        let originalWidth = settings.pillSpectrumWidth
        // The stored presets are whatever this Mac's owner named them, in
        // whatever language they typed — persisted strings, not localized keys,
        // so `-testLanguage en` cannot touch them. The shots want the shipped
        // defaults.
        let originalPresets = settings.timerPresets
        defer {
            settings.spectrumStyle = originalStyle
            settings.pillSpectrumOnly = originalPillOnly
            settings.pillSpectrumWidth = originalWidth
            settings.timerPresets = originalPresets
        }
        settings.timerPresets = TimerPreset.defaults

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cotedos-shot-fixtures", isDirectory: true)
        try? FileManager.default.removeItem(at: scratch)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        // Fixtures
        let coverURL = scratch.appendingPathComponent("cover.png")
        try Self.albumCover().write(to: coverURL)
        let shelfURLs = try Self.shelfFixtures(in: scratch)

        // Models, wired the way AppleDelegate wires them.
        let viewModel = NotchViewModel()
        let activities = ActivityManager()
        let nowPlaying = NowPlayingManager()
        let shelf = FileShelfModel()
        let pomodoro = PomodoroManager(activities: activities)
        let capture = ObsidianCapture(activities: activities)
        let spectrum = SpectrumAnalyzer(bandCount: 32)

        nowPlaying.applyForTesting(NowPlayingState(
            isRunning: true,
            isPlaying: true,
            track: NowPlayingTrack(
                name: "Slow Ascent",
                artist: "Halbmond",
                album: "Nordwand",
                artworkURL: coverURL,
                duration: 4 * 60 + 12,
                url: nil
            ),
            position: 97,
            isShuffling: false
        ))
        shelf.setItemsForTesting(shelfURLs)

        feedAudio(spectrum)

        // The artwork election, the thumbnails and the band publish are all
        // async; let them land before anything is drawn.
        settle(1.2)

        settings.spectrumStyle = .coverImage
        settings.pillSpectrumOnly = false

        func root() -> NotchRootView {
            NotchRootView(viewModel: viewModel, nowPlaying: nowPlaying, shelf: shelf,
                          activities: activities, pomodoro: pomodoro, capture: capture,
                          spectrum: spectrum)
        }

        let expanded = CGSize(width: viewModel.expandedWidth, height: viewModel.expandedHeight)

        // --- the shot at the top of the README ------------------------------
        // On a plate, not a desktop. The wallpaper's top-centre is where the pale
        // part of it lives, and the island lost contrast against exactly the
        // region a real screenshot would have caught. The collapsed pill below
        // carries the "this lives at the top of your screen" job instead, which
        // is the shot that actually needs a desktop behind it.
        viewModel.selectedTab = .music
        viewModel.islandState = .expanded
        viewModel.pagesSettled = true
        settle(NotchLayout.chromeRevealDelay + 0.4)
        feedAudio(spectrum)
        try shoot(root(), islandSize: expanded, named: "hero")

        // --- one tile per tab, on the plate ---------------------------------
        for tab in NotchViewModel.Tab.allCases {
            viewModel.selectedTab = tab
            viewModel.islandState = .expanded
            viewModel.pagesSettled = true
            settle(NotchLayout.chromeRevealDelay + 0.4)
            feedAudio(spectrum)

            try shoot(root(), islandSize: expanded, named: "tab-\(tab.rawValue)")
        }

        // --- collapsed pill -------------------------------------------------
        // Empty shelf: the badge is its own shot below, and the plain pill is
        // what most people will ever see.
        shelf.setItemsForTesting([])
        viewModel.selectedTab = .music
        viewModel.islandState = .collapsed
        settle(0.3)
        feedAudio(spectrum)
        try shoot(root(),
                  islandSize: CGSize(width: viewModel.collapsedWidth(isPlaying: true, hasItems: false, timerText: nil),
                                     height: viewModel.collapsedHeight),
                  on: .desktop, named: "notch-collapsed")

        // --- collapsed, spectrum-only, at its widest ------------------------
        settings.pillSpectrumOnly = true
        settings.pillSpectrumWidth = NotchLayout.pillSpectrumMaxWidth
        settle(0.3)
        feedAudio(spectrum)
        try shoot(root(),
                  islandSize: CGSize(width: viewModel.collapsedWidth(isPlaying: true, hasItems: false, timerText: nil),
                                     height: viewModel.collapsedHeight),
                  on: .desktop, named: "pill-spectrum")
        settings.pillSpectrumOnly = false

        // --- the shelf badge: a pill with files staged -----------------------
        shelf.setItemsForTesting(shelfURLs)
        settle(0.3)
        feedAudio(spectrum)
        try shoot(root(),
                  islandSize: CGSize(width: viewModel.collapsedWidth(isPlaying: true, hasItems: true, timerText: nil),
                                     height: viewModel.collapsedHeight),
                  on: .desktop, named: "pill-shelf")

        // --- the five spectrum styles, side by side -------------------------
        try shootStyleStrip(spectrum: spectrum, nowPlaying: nowPlaying, settings: settings)

        // --- hero: the fullscreen takeover ----------------------------------
        try shootFullscreenHero(spectrum: spectrum, nowPlaying: nowPlaying)

        let written = try FileManager.default.contentsOfDirectory(atPath: Self.outputDirectory.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertGreaterThanOrEqual(written.count, 10,
            "expected the hero, a tile per tab, the pills, the strip and the takeover; got \(written.sorted())")
    }

    // MARK: - Rendering

    /// What sits behind the island.
    ///
    /// Two answers, because they do different jobs. `.desktop` is a real macOS
    /// wallpaper, and it is the only thing that says *this lives at the top of
    /// your screen* — worth it once, for the shot at the top of the README.
    /// `.plate` is Apple's own marketing grey, and it is what the per-feature
    /// tiles want: a wallpaper behind each of five tiles gives five different
    /// backgrounds competing with the interface they are supposed to be showing,
    /// and the violet in that wallpaper fights the violet in the wave.
    private enum Backdrop {
        case desktop
        case plate
    }

    /// Renders `view` over `backdrop`, on a canvas sized around the island.
    private func shoot<V: View>(_ view: V, islandSize: CGSize, on backdrop: Backdrop = .plate,
                                named name: String) throws {
        // Tiles get more air than the desktop shots: on a plate the island is an
        // object being presented, and crowding the frame reads as a crop.
        let pad: CGFloat = backdrop == .plate ? 54 : 30
        let head = backdrop == .plate ? 44 : headroom
        let canvas = CGSize(width: (islandSize.width + pad * 2).rounded(),
                            height: (head + islandSize.height + pad).rounded())
        let top = head - NotchLayout.islandTopGap

        let framed = ZStack(alignment: .top) {
            Color.clear.frame(width: canvas.width, height: canvas.height)
            view
                .frame(width: canvas.width, height: canvas.height - top)
                .offset(y: top)
        }
        .frame(width: canvas.width, height: canvas.height)

        let island = try render(framed, rawSize: canvas)
        let behind = try backdrop == .desktop ? wallpaperCrop(canvas) : marketingPlate(canvas)
        try write(try composite(island, over: behind), named: name)
    }

    /// #F5F5F7 to white, with a soft warm-grey pool under where the island sits.
    /// That grey is the one Apple's own product pages use, and the reason it works
    /// here is contrast: the island is black, so it needs a light field to read as
    /// an object rather than as a hole.
    private func marketingPlate(_ size: CGSize) throws -> CGImage {
        let context = try newContext(size)
        let w = size.width * scale, h = size.height * scale
        context.drawLinearGradient(
            Self.gradient([(0, 0xFFFFFF, 1), (0.55, 0xF7F7F9, 1), (1, 0xEDEDF1, 1)]),
            start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        // A whisper of a vignette. Anything stronger reaches the canvas edge
        // before it has faded and lands as a visible grey band along the bottom,
        // which reads as a badly exported JPEG rather than as depth.
        context.saveGState()
        context.translateBy(x: w / 2, y: h * 0.5)
        context.scaleBy(x: 1, y: 0.62)
        context.drawRadialGradient(
            Self.gradient([(0, 0xB9B9C6, 0), (0.62, 0xB9B9C6, 0), (1, 0xB9B9C6, 0.16)]),
            startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: w * 1.05, options: [])
        context.restoreGState()
        return try XCTUnwrap(context.makeImage(), "plate render failed")
    }

    private static func gradient(_ stops: [(CGFloat, UInt32, CGFloat)]) -> CGGradient {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = stops.map { _, hex, alpha in
            CGColor(colorSpace: space, components: [
                CGFloat((hex >> 16) & 0xFF) / 255,
                CGFloat((hex >> 8) & 0xFF) / 255,
                CGFloat(hex & 0xFF) / 255,
                alpha,
            ])!
        }
        return CGGradient(colorsSpace: space, colors: colors as CFArray,
                          locations: stops.map(\.0))!
    }

    /// One image holding all five colour styles of the same frame, for the
    /// README's "five styles" row.
    ///
    /// Drawn at the spectrum page's size, not the pill's: the pill's bars are
    /// ~2 pt wide, and five rows of those side by side read as five rows of
    /// identical dots — which is the opposite of what the row is for.
    private func shootStyleStrip(spectrum: SpectrumAnalyzer,
                                 nowPlaying: NowPlayingManager,
                                 settings: UserSettings) throws {
        let tileSize = CGSize(width: 300, height: 108)
        var tiles: [CGImage] = []

        for style in UserSettings.SpectrumStyle.allCases {
            settings.spectrumStyle = style
            settle(0.1)
            feedAudio(spectrum)
            let tints = WaveTints.resolve(nowPlaying: nowPlaying, sourceBundleID: nil, sourceAppTint: nil)
            let tile = VStack(spacing: 9) {
                SpectrumStageView(
                    levels: spectrum.bands,
                    isLive: true,
                    isActive: true,
                    tint: tints.primary,
                    secondaryTint: tints.secondary,
                    tertiaryTint: tints.tertiary,
                    coverBars: tints.coverBars
                )
                .frame(width: tileSize.width - 28, height: tileSize.height - 42)
                Text(style.localizedName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: tileSize.width, height: tileSize.height)

            tiles.append(try render(tile, rawSize: tileSize))
        }

        let tileW = CGFloat(tiles[0].width) / scale
        let tileH = CGFloat(tiles[0].height) / scale
        let strip = CGSize(width: tileW * CGFloat(tiles.count), height: tileH)
        let context = try newContext(strip)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: CGSize(width: strip.width * scale, height: strip.height * scale)))
        for (index, tile) in tiles.enumerated() {
            context.draw(tile, in: CGRect(x: CGFloat(index) * tileW * scale, y: 0,
                                          width: tileW * scale, height: tileH * scale))
        }
        try write(try XCTUnwrap(context.makeImage()), named: "spectrum-styles")
    }

    /// The fullscreen takeover, at the size it actually runs at.
    private func shootFullscreenHero(spectrum: SpectrumAnalyzer, nowPlaying: NowPlayingManager) throws {
        feedAudio(spectrum)
        // Cropped tighter than the real 16:10 takeover: full screen leaves most of
        // the frame black, which is honest and a poor hero.
        let size = CGSize(width: 1440, height: 540)
        let tints = WaveTints.resolve(nowPlaying: nowPlaying, sourceBundleID: nil, sourceAppTint: nil)
        let stage = SpectrumStageView(
            levels: spectrum.bands,
            isLive: true,
            isActive: true,
            tint: tints.primary,
            secondaryTint: tints.secondary,
            tertiaryTint: tints.tertiary,
            coverBars: tints.coverBars
        )
        .frame(width: size.width, height: size.height)
        .background(Color.black)

        try write(try render(stage, rawSize: size), named: "spectrum-fullscreen")
    }

    /// Mounts the view in a real (offscreen, transparent, never-fronted) window
    /// and captures the hosting view's own backing store.
    ///
    /// `ImageRenderer` is the obvious tool and it renders the music tab wrong in
    /// two ways: `AsyncImage` never resolves within a pass, so the album cover
    /// comes out as the "no artwork" placeholder no matter how many passes you
    /// make, and the output picker is a `Menu`, which has no SwiftUI-only
    /// representation and draws as a yellow missing-image box. Both need an
    /// AppKit view tree that exists long enough to finish loading and realize
    /// its controls, which is exactly what an `NSHostingView` in a window is —
    /// and capturing your own window needs no Screen Recording grant, which is
    /// the same reason the app's own debug recorder works this way.
    private func render<V: View>(_ view: V, rawSize: CGSize) throws -> CGImage {
        // Whole points, so `pt * scale` is a whole number of pixels and the
        // composite lines up: several of these sizes come out of the bar-pitch
        // geometry and are fractional.
        let size = CGSize(width: rawSize.width.rounded(.up), height: rawSize.height.rounded(.up))
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        host.frame = CGRect(origin: .zero, size: size)

        // On a screen, so the backing store is 2× — a window parked at
        // -10000,-10000 belongs to no display and captures at 1×. Invisible and
        // inert instead: fully transparent, below everything, never key.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.setFrameOrigin(NSPoint(x: 0, y: 0))
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        host.layoutSubtreeIfNeeded()
        // Long enough for AsyncImage, the QuickLook thumbnails and the menu's
        // AppKit backing to finish.
        settle(0.8)

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                                "no backing store for a \(size) view")
        host.cacheDisplay(in: host.bounds, to: rep)
        XCTAssertEqual(rep.pixelsWide, Int(size.width * scale),
                       "captured at \(rep.pixelsWide)px for \(size.width)pt — wrong backing scale")
        return try XCTUnwrap(rep.cgImage, "backing store had no image")
    }

    // MARK: - Wallpaper backdrop

    /// The top-centre `size` of the wallpaper as it would appear on a
    /// `screenSize` display — aspect-filled first, so the framing matches what
    /// a real screenshot of that region would have shown.
    private func wallpaperCrop(_ size: CGSize) throws -> CGImage {
        let image = try XCTUnwrap(NSImage(contentsOf: wallpaper), "wallpaper unreadable")
        var rect = CGRect(origin: .zero, size: image.size)
        let full = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))

        let screen = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)
        let context = try newContext(CGSize(width: screenSize.width, height: screenSize.height))
        // Aspect fill.
        let factor = max(screen.width / CGFloat(full.width), screen.height / CGFloat(full.height))
        let drawn = CGSize(width: CGFloat(full.width) * factor, height: CGFloat(full.height) * factor)
        context.draw(full, in: CGRect(x: (screen.width - drawn.width) / 2,
                                      y: (screen.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
        let filled = try XCTUnwrap(context.makeImage())

        // CG's origin is bottom-left, so the top of the screen is the far edge.
        let crop = CGRect(x: ((screen.width - size.width * scale) / 2).rounded(),
                          y: screen.height - size.height * scale,
                          width: size.width * scale, height: size.height * scale)
        return try XCTUnwrap(filled.cropping(to: crop), "wallpaper crop \(crop) failed")
    }

    private func composite(_ top: CGImage, over bottom: CGImage) throws -> CGImage {
        let context = try newContext(CGSize(width: CGFloat(bottom.width) / scale,
                                            height: CGFloat(bottom.height) / scale))
        let frame = CGRect(x: 0, y: 0, width: CGFloat(bottom.width), height: CGFloat(bottom.height))
        context.draw(bottom, in: frame)
        context.draw(top, in: frame)
        return try XCTUnwrap(context.makeImage())
    }

    private func newContext(_ size: CGSize) throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), "could not create a \(size) bitmap context")
    }

    private func write(_ image: CGImage, named name: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: Self.outputDirectory.appendingPathComponent("\(name).png"))
    }

    /// Drains the main queue for `seconds` so async work (artwork election,
    /// QuickLook thumbnails, the band publish, the chrome reveal) lands before
    /// the next frame is drawn.
    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private var audioPhase = 0.0

    /// Pushes ~0.75 s of synthetic music through the real FFT and lets the band
    /// publish land.
    ///
    /// Called immediately before every shot with a wave in it, not once at the
    /// start: the analyzer releases its window on audio time, so a run that has
    /// heard nothing for a few seconds settles to an even resting row. Colours
    /// survive that, heights do not — which produces a shot of a flat line of
    /// dots in exactly the right colours, and looks like a layout bug.
    private func feedAudio(_ spectrum: SpectrumAnalyzer) {
        // 70 blocks ≈ 0.75 s, which is past the warm-up the running averages
        // need before the levels mean anything. `ingestForTesting` runs the real
        // FFT and hands back the smoothed levels without publishing them, so the
        // last frame is pushed into the analyzer's published state explicitly.
        var levels: [Float] = []
        for _ in 0..<70 {
            levels = spectrum.ingestForTesting(Self.musicBlock(audioBlock, phase: &audioPhase))
            audioBlock += 1
        }
        spectrum.publishForTesting(levels)
        settle(0.1)
    }

    private var audioBlock = 0

    // MARK: - Fixtures

    /// An invented sleeve rather than a real one: it has to carry three colour
    /// families for the cover styles to have anything to quantise onto, and
    /// shipping somebody's album art in marketing images is a different
    /// conversation.
    private static func albumCover() throws -> Data {
        let side = 600
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let s = CGFloat(side)

        let base = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [NSColor(calibratedHue: 0.94, saturation: 0.72, brightness: 0.62, alpha: 1).cgColor,
                                       NSColor(calibratedHue: 0.72, saturation: 0.68, brightness: 0.38, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
        context.drawLinearGradient(base, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

        // A low sun over a horizon: one warm mass, one cool field, a hard edge
        // between them. Three families, which is what the palette election
        // needs to show anything interesting.
        context.saveGState()
        context.addRect(CGRect(x: 0, y: 0, width: s, height: s * 0.42))
        context.clip()
        context.setFillColor(NSColor(calibratedHue: 0.55, saturation: 0.55, brightness: 0.28, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.42))
        context.restoreGState()

        let sun = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                             colors: [NSColor(calibratedHue: 0.11, saturation: 0.85, brightness: 1.0, alpha: 1).cgColor,
                                      NSColor(calibratedHue: 0.05, saturation: 0.90, brightness: 0.85, alpha: 1).cgColor] as CFArray,
                             locations: [0, 1])!
        context.saveGState()
        context.addEllipse(in: CGRect(x: s * 0.30, y: s * 0.34, width: s * 0.40, height: s * 0.40))
        context.clip()
        context.drawLinearGradient(sun, start: CGPoint(x: s * 0.3, y: s * 0.74),
                                   end: CGPoint(x: s * 0.7, y: s * 0.34), options: [])
        context.restoreGState()

        context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.10).cgColor)
        for i in 0..<7 {
            let y = s * 0.42 - CGFloat(i) * s * 0.035 - s * 0.012
            context.fill(CGRect(x: 0, y: y, width: s, height: s * 0.006))
        }

        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }

    /// Four files with different QuickLook outcomes: an image that thumbnails,
    /// a PDF, a folder, and a plain text file.
    private static func shelfFixtures(in directory: URL) throws -> [URL] {
        let image = directory.appendingPathComponent("mockup.png")
        try albumCover().write(to: image)

        let pdf = directory.appendingPathComponent("invoice.pdf")
        let page = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = CGDataConsumer(data: page as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &media, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(media)
        ctx.setFillColor(NSColor.darkGray.cgColor)
        for row in 0..<14 {
            ctx.fill(CGRect(x: 70, y: 720 - CGFloat(row) * 34, width: .random(in: 180...440), height: 9))
        }
        ctx.endPDFPage()
        ctx.closePDF()
        try (page as Data).write(to: pdf)

        let folder = directory.appendingPathComponent("Semester 4", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let notes = directory.appendingPathComponent("notes.txt")
        try "Ablage".data(using: .utf8)!.write(to: notes)

        return [image, pdf, folder, notes]
    }

    private static let sampleRate = 48_000.0
    private static let blockSize = 512

    /// The same signal shape `WaveMotionContactSheetTests` uses — a kick-driven
    /// bass line, a swelling mid chord and off-beat hats. A single sine would
    /// light one band and leave the wave looking dead.
    private static func musicBlock(_ blockIndex: Int, phase: inout Double) -> [Float] {
        let bassStep = 2.0 * Double.pi * 95.0 / sampleRate
        let midFreqs = [440.0, 660.0, 1320.0, 2640.0]
        let blockTime = Double(blockIndex) * Double(blockSize) / sampleRate
        var rng = SystemRandomNumberGenerator()
        return (0..<blockSize).map { i in
            let t = blockTime + Double(i) / sampleRate
            let beatPhase = t.truncatingRemainder(dividingBy: 0.5)
            let kick: Float = beatPhase < 0.08 ? Float(1.0 - beatPhase / 0.08) : 0
            let bass = Float(sin(phase)) * (0.06 + 0.14 * kick)
            phase += bassStep
            let swell = Float(0.5 + 0.5 * sin(2 * .pi * t))
            let mids = midFreqs.reduce(Float(0)) { sum, f in
                sum + Float(sin(2 * .pi * f * t)) * 0.012 * (0.4 + 0.6 * swell)
            }
            let offBeat = (t + 0.25).truncatingRemainder(dividingBy: 0.5)
            let hatEnv: Float = offBeat < 0.05 ? Float(1.0 - offBeat / 0.05) : 0.15
            let hat = Float.random(in: -1...1, using: &rng) * 0.012 * hatEnv
            return bass + mids + hat
        }
    }
}
