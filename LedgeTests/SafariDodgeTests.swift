import XCTest
@testable import Ledge

/// The pure positioning half of the Safari-fullscreen dodge. (The AX traversal
/// can't be unit-tested — it's covered by the manual checklist.)
final class SafariDodgeTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1728, height: 1117)

    func testDodgeSitsRightOfTheURLField() {
        let pillWidth: CGFloat = 120
        let urlFieldMaxX: CGFloat = 1100
        let centerX = SafariFullscreenMonitor.dodgePillCenterX(
            urlFieldMaxX: urlFieldMaxX, screenFrame: screen, pillWidth: pillWidth)
        XCTAssertEqual(centerX, urlFieldMaxX + NotchLayout.safariDodgeGap + pillWidth / 2)
        // The pill's left edge clears the field by exactly the gap.
        XCTAssertEqual(centerX - pillWidth / 2, urlFieldMaxX + NotchLayout.safariDodgeGap)
    }

    func testDodgeClampsAtTheRightScreenEdge() {
        let pillWidth: CGFloat = 200
        let centerX = SafariFullscreenMonitor.dodgePillCenterX(
            urlFieldMaxX: screen.maxX - 50, screenFrame: screen, pillWidth: pillWidth)
        XCTAssertEqual(centerX + pillWidth / 2, screen.maxX - NotchLayout.safariDodgeEdgeMargin,
                       "pill's right edge must keep the margin from the screen edge")
    }

    func testFallbackWithoutAXPositionsRightOfCentre() {
        let pillWidth: CGFloat = 120
        let centerX = SafariFullscreenMonitor.dodgePillCenterX(
            urlFieldMaxX: nil, screenFrame: screen, pillWidth: pillWidth)
        XCTAssertEqual(centerX, screen.midX + NotchLayout.safariDodgeFallbackOffset)
        XCTAssertLessThanOrEqual(centerX + pillWidth / 2, screen.maxX - NotchLayout.safariDodgeEdgeMargin)
    }

    func testFallbackClampsOnNarrowScreens() {
        let narrow = NSRect(x: 0, y: 0, width: 800, height: 600)
        let pillWidth: CGFloat = 240
        let centerX = SafariFullscreenMonitor.dodgePillCenterX(
            urlFieldMaxX: nil, screenFrame: narrow, pillWidth: pillWidth)
        XCTAssertEqual(centerX + pillWidth / 2, narrow.maxX - NotchLayout.safariDodgeEdgeMargin)
    }

    func testSecondaryScreenOffsetIsRespected() {
        // Screens left of the primary have negative X — the clamp must work in
        // that coordinate space too.
        let secondary = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let centerX = SafariFullscreenMonitor.dodgePillCenterX(
            urlFieldMaxX: -600, screenFrame: secondary, pillWidth: 100)
        XCTAssertEqual(centerX, -600 + NotchLayout.safariDodgeGap + 50)
        XCTAssertLessThan(centerX, secondary.maxX)
    }
}
