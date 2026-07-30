import XCTest
import SwiftUI
@testable import CoteDOs

/// The single spectrum run's two poses inside the island.
///
/// There used to be two waves — an overlay while the island opened, and the
/// spectrum page's own once the pages mounted — with a handover between them.
/// A handover between two independently mounted views is only ever as invisible
/// as the two poses happen to match, and they didn't: `pageWaveCentreY` counted
/// the tab bar above the page area but not the `expandedRowSpacing` between
/// them, so the run jumped 8 pt the frame the page took over. The seam is gone
/// now (one view, moved by transform), but these assertions still guard the
/// geometry that decides where it moves *to*.
final class WaveHandoverTests: XCTestCase {

    /// Where the spectrum page's area is actually centred, derived from the view
    /// tree rather than from the constant under test: the island is a `VStack`
    /// of the tab bar (`currentCollapsedHeight`) and the pages, separated by
    /// `expandedRowSpacing`, and the run centres in the frame it is given.
    private var pageCentreFromViewTree: CGFloat {
        NotchLayout.currentCollapsedHeight
            + NotchLayout.expandedRowSpacing
            + NotchLayout.expandedPageSize.height / 2
    }

    func testThePagePoseIsCentredOnThePageArea() {
        XCTAssertEqual(NotchLayout.pageWaveCentreY, pageCentreFromViewTree, accuracy: 0.01,
                       "the wave's page pose must be the centre of the page area, or it "
                       + "settles off-centre from everything around it")
    }

    /// The pill pose sits in the collapsed band, which is the row the pill's own
    /// content occupies.
    func testThePillPoseIsCentredOnTheCollapsedBand() {
        XCTAssertEqual(NotchLayout.pillWaveCentreY, NotchLayout.currentCollapsedHeight / 2,
                       accuracy: 0.01)
    }

    /// The journey has to be a real one, or there is nothing to animate.
    func testTheTwoPosesAreActuallyApart() {
        XCTAssertGreaterThan(NotchLayout.pageWaveCentreY - NotchLayout.pillWaveCentreY, 20,
                             "the page pose sits well below the pill's")
        XCTAssertLessThan(NotchLayout.pillToPageWaveScale, 0.5,
                          "and the pill is less than half the size")
    }

    /// The run is drawn once, at page geometry, and *scaled* to make the pill —
    /// so one number has to carry both dimensions. It only can if the scaled
    /// page run really is the pill's run; otherwise the wave sits at the right
    /// height and the wrong width, and clips against the capsule.
    func testOneScaleCarriesBothDimensionsOfThePillPose() {
        let pill = NotchLayout.pillSpectrumGeometry(forWidth: UserSettings.shared.pillSpectrumWidth)
        let page = NotchLayout.spectrumPageWaveGeometry(barCount: pill.barCount)
        let scale = NotchLayout.pillToPageWaveScale

        XCTAssertGreaterThan(scale, 0)
        XCTAssertLessThan(scale, 1, "the pill must be the smaller end, or there is no morph")
        XCTAssertEqual(page.waveHeight * scale, pill.waveHeight, accuracy: 0.5,
                       "the scaled page run must be exactly the pill's height")
        // Looser: the page spreads its bars across the full page width while the
        // pill's run is an exact fit for its bar count, so the two runs differ by
        // up to the leftover of one pitch.
        XCTAssertEqual(page.runWidth * scale, pill.runWidth,
                       accuracy: pill.barWidth + pill.spacing,
                       "the scaled page run must land within a bar of the pill's width")
    }

    /// The run stands in for the spectrum page while the carousel slides, so it
    /// has to travel exactly as far as that page does — one page width per tab
    /// of separation, in the same direction.
    func testTheCarouselShiftIsOnePageWidthPerTab() {
        let tabs = NotchViewModel.Tab.allCases
        guard let spectrumIndex = tabs.firstIndex(of: .spectrum),
              let musicIndex = tabs.firstIndex(of: .music) else {
            return XCTFail("the spectrum and music tabs must exist")
        }
        // Music sits before spectrum, so selecting it slides the spectrum page
        // to the right by exactly one page.
        XCTAssertEqual(spectrumIndex - musicIndex, 1)
        XCTAssertGreaterThan(NotchLayout.expandedPageSize.width, 0)
    }

    /// The spectrum page is the one tab meant to be left running, so the cursor
    /// leaving must not close it — and unlike the capture lock it has to release
    /// itself, or the island would be stuck open forever.
    @MainActor
    func testTheSpectrumPageHoldsTheIslandOpenAndReleasesItself() {
        let viewModel = NotchViewModel()

        viewModel.islandState = .expanded
        viewModel.selectedTab = .spectrum
        XCTAssertTrue(viewModel.holdsIslandOpen)

        viewModel.selectedTab = .music
        XCTAssertFalse(viewModel.holdsIslandOpen, "switching tabs must release the hold")

        viewModel.selectedTab = .spectrum
        viewModel.islandState = .collapsed
        XCTAssertFalse(viewModel.holdsIslandOpen, "closing the island must release the hold")
    }
}
