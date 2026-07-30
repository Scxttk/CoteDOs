import XCTest
@testable import CoteDOs

final class ObsidianVaultTests: XCTestCase {
    private let heading = "## 📥 Capture"

    func testReplacesEmptyPlaceholderBullet() {
        let content = """
        # Today

        ## 📥 Capture

        -

        ## 🌙 Plan
        """
        let result = ObsidianVault.appending(bullet: "- 09:00 hello", underHeading: heading, to: content)
        XCTAssertTrue(result.contains("- 09:00 hello"))
        // The lone placeholder "-" should be replaced, not duplicated.
        XCTAssertFalse(result.contains("\n-\n"))
        // Insertion stays inside the Capture section, above the next heading.
        let captureRange = result.range(of: heading)!
        let planRange = result.range(of: "## 🌙 Plan")!
        let bulletRange = result.range(of: "- 09:00 hello")!
        XCTAssertTrue(bulletRange.lowerBound > captureRange.upperBound)
        XCTAssertTrue(bulletRange.upperBound < planRange.lowerBound)
    }

    func testAppendsAfterExistingBullets() {
        let content = """
        ## 📥 Capture
        - first
        - second
        """
        let result = ObsidianVault.appending(bullet: "- third", underHeading: heading, to: content)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.last, "- third")
        XCTAssertEqual(lines.firstIndex(of: "- second")! + 1, lines.firstIndex(of: "- third")!)
    }

    func testCreatesHeadingWhenMissing() {
        let content = "# Note\n\nSome text\n"
        let result = ObsidianVault.appending(bullet: "- captured", underHeading: heading, to: content)
        XCTAssertTrue(result.contains(heading))
        XCTAssertTrue(result.contains("- captured"))
        XCTAssertTrue(result.range(of: heading)!.lowerBound < result.range(of: "- captured")!.lowerBound)
    }

    func testCreatesHeadingInEmptyDocument() {
        let result = ObsidianVault.appending(bullet: "- captured", underHeading: heading, to: "")
        XCTAssertEqual(result, "## 📥 Capture\n\n- captured\n")
    }

    func testInsertsUnderHeadingWithNoBulletsYet() {
        let content = "## 📥 Capture\n\n## Next"
        let result = ObsidianVault.appending(bullet: "- x", underHeading: heading, to: content)
        let bullet = result.range(of: "- x")!
        let next = result.range(of: "## Next")!
        XCTAssertTrue(bullet.upperBound < next.lowerBound)
    }

    // MARK: Headings that have been dressed up

    /// The real one: a daily-note template switched to Obsidian's Iconize
    /// plugin, the settings field still said `## 📥 Capture`, and every capture
    /// from then on went to a second section at the bottom of the note — under
    /// "Plan für morgen", which is not where anybody looks for them.
    func testFindsTheHeadingBehindAnIconToken() {
        let content = "## :LiInbox: Capture\n\n- \n\n## 🌙 Plan für morgen\n\n- \n"
        let result = ObsidianVault.appending(bullet: "- captured", underHeading: heading, to: content)
        XCTAssertFalse(result.contains("## 📥 Capture"), "must not invent a second section")
        let bullet = result.range(of: "- captured")!
        let plan = result.range(of: "## 🌙 Plan für morgen")!
        XCTAssertTrue(bullet.upperBound < plan.lowerBound, "belongs in the section that is already there")
    }

    func testMatchesAcrossDecoration() {
        XCTAssertEqual(ObsidianVault.headingWords("## 📥 Capture"), "capture")
        XCTAssertEqual(ObsidianVault.headingWords("## :LiInbox: Capture"), "capture")
        XCTAssertEqual(ObsidianVault.headingWords("##Capture"), "capture")
        XCTAssertEqual(ObsidianVault.headingWords("## :LiSunrise: Heute geplant"), "heute geplant")
        // The icon name must not survive as letters.
        XCTAssertFalse(ObsidianVault.headingWords("## :LiInbox: Capture").contains("li"))
    }

    /// Ignoring decoration must not start matching different sections.
    func testDoesNotMatchADifferentHeading() {
        let content = "## :LiNotebook: Log\n\n- entry\n"
        let result = ObsidianVault.appending(bullet: "- captured", underHeading: heading, to: content)
        XCTAssertTrue(result.contains("## 📥 Capture"), "no Capture section here, so it makes one")
        XCTAssertTrue(result.range(of: "- entry")!.upperBound < result.range(of: "## 📥 Capture")!.lowerBound)
    }
}
