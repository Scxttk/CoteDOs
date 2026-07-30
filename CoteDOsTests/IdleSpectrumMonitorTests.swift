import XCTest
@testable import CoteDOs

/// The screensaver's clock. (Whether the Mac is actually idle, and whether the
/// tap hears anything, can only be checked by hand — this is the arithmetic
/// that decides *when*.)
final class IdleSpectrumMonitorTests: XCTestCase {

    func testTakeoverArrivesBeforeTheDisplaySleeps() {
        // The whole point: the spectrum is on screen while macOS still
        // considers the display awake, not after it went dark.
        let threshold = IdleSpectrumMonitor.idleThreshold(displaySleepMinutes: 3)
        XCTAssertEqual(threshold, 180 - IdleSpectrumMonitor.leadSeconds)
        XCTAssertLessThan(threshold, 180)
    }

    func testLongDisplayTimerJustShiftsTheThreshold() {
        XCTAssertEqual(IdleSpectrumMonitor.idleThreshold(displaySleepMinutes: 10),
                       600 - IdleSpectrumMonitor.leadSeconds)
    }

    func testShortestRealDisplayTimerStaysAboveTheMinimum() {
        // One minute is as short as macOS lets the display timer go: 45 s left
        // after the lead, still clear of the floor. The floor only exists so a
        // shorter value (or a lead that grows) can't make the takeover fire the
        // moment the cursor stops.
        XCTAssertEqual(IdleSpectrumMonitor.idleThreshold(displaySleepMinutes: 1), 45)
        for minutes in 1...30 {
            XCTAssertGreaterThanOrEqual(IdleSpectrumMonitor.idleThreshold(displaySleepMinutes: minutes),
                                        IdleSpectrumMonitor.minimumIdleSeconds)
        }
    }

    func testNeverAndUnreadableBothFallBack() {
        XCTAssertEqual(IdleSpectrumMonitor.idleThreshold(displaySleepMinutes: 0),
                       IdleSpectrumMonitor.fallbackIdleSeconds)
        XCTAssertEqual(IdleSpectrumMonitor.idleThreshold(displaySleepMinutes: nil),
                       IdleSpectrumMonitor.fallbackIdleSeconds)
    }

    func testIdleSecondsReadsTheSystemClock() {
        // Not a fixed value — just that the read works and is sane. A negative
        // or absurd answer would mean the CGEventSource call changed shape.
        let idle = IdleSpectrumMonitor.idleSeconds()
        XCTAssertGreaterThanOrEqual(idle, 0)
        XCTAssertLessThan(idle, 60 * 60 * 24)
    }
}
