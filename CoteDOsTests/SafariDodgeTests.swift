import XCTest
@testable import CoteDOs

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

    func testSecondaryScreenOffsetIsRespected() {
        // Screens left of the primary have negative X — the clamp must work in
        // that coordinate space too.
        let secondary = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let centerX = SafariFullscreenMonitor.dodgePillCenterX(
            urlFieldMaxX: -600, screenFrame: secondary, pillWidth: 100)
        XCTAssertEqual(centerX, -600 + NotchLayout.safariDodgeGap + 50)
        XCTAssertLessThan(centerX, secondary.maxX)
    }

    // MARK: Visibility gate — the dodge only applies while the toolbar is on
    // screen. A video put fullscreen from the page (`f` on YouTube/Twitch)
    // reports the window as fullscreen with the toolbar gone.

    func testToolbarFieldUnderTheNotchIsVisible() {
        let field = NSRect(x: 500, y: screen.maxY - 52, width: 700, height: 30)
        XCTAssertTrue(SafariFullscreenMonitor.isURLFieldVisible(field, on: screen))
    }

    func testFieldParkedAboveTheTopEdgeIsNotVisible() {
        // Safari can keep a hidden toolbar in the AX tree, slid off the top.
        let field = NSRect(x: 500, y: screen.maxY - 10, width: 700, height: 30)
        XCTAssertFalse(SafariFullscreenMonitor.isURLFieldVisible(field, on: screen))
    }

    func testEmptyFieldIsNotVisible() {
        let field = NSRect(x: 500, y: screen.maxY - 52, width: 0, height: 0)
        XCTAssertFalse(SafariFullscreenMonitor.isURLFieldVisible(field, on: screen))
    }

    func testFieldOnAnotherScreenIsNotVisible() {
        let field = NSRect(x: -1400, y: 1000, width: 700, height: 30)
        XCTAssertFalse(SafariFullscreenMonitor.isURLFieldVisible(field, on: screen))
    }
}
