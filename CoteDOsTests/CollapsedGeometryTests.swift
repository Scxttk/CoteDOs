import XCTest
@testable import CoteDOs

/// Unit tests for the collapsed pill's width and horizontal-shift formulas —
/// the two must stay in lock-step with each other and with the `CollapsedView`
/// layout (all three read the same `NotchLayout` constants).
@MainActor
final class CollapsedGeometryTests: XCTestCase {

    private var viewModel: NotchViewModel!
    private var originalSpectrumOnly = false
    private var originalSpectrumWidth = 0.0

    override func setUp() {
        super.setUp()
        viewModel = NotchViewModel()
        // Pin the setting the width formula branches on, so the tests don't
        // depend on whatever the host app's defaults happen to be.
        originalSpectrumOnly = UserSettings.shared.pillSpectrumOnly
        originalSpectrumWidth = UserSettings.shared.pillSpectrumWidth
        UserSettings.shared.pillSpectrumOnly = false
    }

    override func tearDown() {
        UserSettings.shared.pillSpectrumOnly = originalSpectrumOnly
        UserSettings.shared.pillSpectrumWidth = originalSpectrumWidth
        super.tearDown()
    }

    private func timerSegmentWidth(_ text: String) -> CGFloat {
        NotchLayout.collapsedTimerIconWidth + NotchLayout.collapsedTimerInnerSpacing
            + CGFloat(text.count) * NotchLayout.collapsedTimerCharWidth
    }

    private let endPadding = 2 * (NotchLayout.collapsedContentPadding + NotchLayout.collapsedEndPadding)

    // MARK: Width

    func testIdleWidthIsGlyphPlusPadding() {
        XCTAssertEqual(
            viewModel.collapsedWidth(isPlaying: false, hasItems: false, timerText: nil),
            NotchLayout.collapsedGlyphWidth + endPadding
        )
    }

    func testTimerOnlyWidth() {
        let text = "12:34"
        XCTAssertEqual(
            viewModel.collapsedWidth(isPlaying: false, hasItems: false, timerText: text),
            timerSegmentWidth(text) + endPadding
        )
    }

    func testHeroPlusTimerPlusBadgeWidth() {
        let text = "9:59"
        let heroCore = NotchLayout.collapsedArtworkWidth + NotchLayout.collapsedItemSpacing + NotchLayout.collapsedWavesWidth
        let expected = heroCore
            + NotchLayout.collapsedItemSpacing + timerSegmentWidth(text)
            + NotchLayout.collapsedItemSpacing + NotchLayout.collapsedBadgeWidth
            + endPadding
        XCTAssertEqual(
            viewModel.collapsedWidth(isPlaying: true, hasItems: true, timerText: text),
            expected
        )
    }

    /// The slider's value is snapped to a whole number of bars, so the pill is
    /// exactly as wide as the run inside it — never a fractional bar wider,
    /// which would show up as a gap next to the timer segment.
    func testSpectrumOnlyPillIsExactlyAsWideAsItsBars() {
        UserSettings.shared.pillSpectrumOnly = true
        // Between 9 bars (30.8) and 10 bars (34.4), nearer the former.
        UserSettings.shared.pillSpectrumWidth = 32
        let text = "12:34"
        let run = NotchLayout.pillSpectrumWidth(forBarCount: 9)
        XCTAssertEqual(NotchLayout.pillSpectrumBarCount(forWidth: 32), 9)
        XCTAssertEqual(
            viewModel.collapsedWidth(isPlaying: true, hasItems: false, timerText: text),
            run + NotchLayout.collapsedItemSpacing + timerSegmentWidth(text) + endPadding
        )
    }

    /// Widening only adds bars — the gap between them never changes. That is
    /// the whole point of collapsing the old width + bar-count pair into one
    /// knob, and it is what keeps every slider position looking tuned.
    func testWideningAddsBarsAtAConstantPitch() {
        let narrow = NotchLayout.pillSpectrumBarCount(forWidth: NotchLayout.pillSpectrumMinWidth)
        let wide = NotchLayout.pillSpectrumBarCount(forWidth: NotchLayout.pillSpectrumMaxWidth)
        XCTAssertEqual(narrow, NotchLayout.pillSpectrumBarRange.lowerBound)
        XCTAssertEqual(wide, NotchLayout.pillSpectrumBarRange.upperBound)
        for count in NotchLayout.pillSpectrumBarRange {
            let width = NotchLayout.pillSpectrumWidth(forBarCount: count)
            XCTAssertEqual(NotchLayout.pillSpectrumBarCount(forWidth: Double(width)), count,
                           "\(width) pt should hold exactly \(count) bars")
            let bars = CGFloat(count) * NotchLayout.collapsedWaveBarWidth
            XCTAssertEqual(width - bars, CGFloat(count - 1) * NotchLayout.collapsedWaveSpacing, accuracy: 0.001)
        }
    }

    /// The default is Apple's own run, measured off a real Dynamic Island:
    /// 6 bars, 20.0 pt end to end.
    func testDefaultWidthIsApplesSixBarRun() {
        XCTAssertEqual(NotchLayout.pillSpectrumBarCount(forWidth: NotchLayout.pillSpectrumDefaultWidth), 6)
        XCTAssertEqual(NotchLayout.pillSpectrumDefaultWidth, 20.0, accuracy: 0.001)
    }

    // MARK: Shift

    func testShiftIsZeroWithoutHero() {
        XCTAssertEqual(viewModel.collapsedTrailingShift(isPlaying: false, hasItems: false, timerText: nil), 0)
        XCTAssertEqual(viewModel.collapsedTrailingShift(isPlaying: false, hasItems: false, timerText: "12:34"), 0,
                       "timer-only pill stays symmetric")
        XCTAssertEqual(viewModel.collapsedTrailingShift(isPlaying: false, hasItems: true, timerText: nil), 0,
                       "badge-only pill stays symmetric")
    }

    func testShiftIsZeroForHeroAlone() {
        XCTAssertEqual(viewModel.collapsedTrailingShift(isPlaying: true, hasItems: false, timerText: nil), 0)
    }

    func testHeroPlusTimerShiftIsHalfTheTrailingSegment() {
        let text = "12:34"
        XCTAssertEqual(
            viewModel.collapsedTrailingShift(isPlaying: true, hasItems: false, timerText: text),
            (NotchLayout.collapsedItemSpacing + timerSegmentWidth(text)) / 2
        )
    }

    func testHeroPlusTimerPlusBadgeShift() {
        let text = "45:00"
        let trailing = NotchLayout.collapsedItemSpacing + timerSegmentWidth(text)
            + NotchLayout.collapsedItemSpacing + NotchLayout.collapsedBadgeWidth
        XCTAssertEqual(
            viewModel.collapsedTrailingShift(isPlaying: true, hasItems: true, timerText: text),
            trailing / 2
        )
    }

    /// The invariant behind the whole asymmetric-pill feature: with the shift
    /// applied, the hero core's centre sits exactly on screen centre. The hero
    /// core spans from the pill's leading edge (plus paddings) through the
    /// artwork + wave; everything after it is "trailing".
    func testHeroCoreCentreLandsOnScreenCentreWithShift() {
        let text = "12:34"
        for hasItems in [false, true] {
            let width = viewModel.collapsedWidth(isPlaying: true, hasItems: hasItems, timerText: text)
            let shift = viewModel.collapsedTrailingShift(isPlaying: true, hasItems: hasItems, timerText: text)
            // Frame centred at 0, then shifted: leading edge at shift − width/2.
            let leadingEdge = shift - width / 2
            let heroCore = NotchLayout.collapsedArtworkWidth + NotchLayout.collapsedItemSpacing + NotchLayout.collapsedWavesWidth
            let heroCentre = leadingEdge + endPadding / 2 + heroCore / 2
            XCTAssertEqual(heroCentre, 0, accuracy: 0.001,
                           "hasItems=\(hasItems): hero core centre must sit on screen centre")
        }
    }
}
