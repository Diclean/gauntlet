import XCTest
@testable import Dares

/// The tab bar of the club screen: the symbols of the four tabs and the names
/// the screen reader reads out.
final class TabBarTests: XCTestCase {
    @MainActor
    func testEveryTabHasItsHouseSymbol() {
        XCTAssertEqual(BrutalTabBar.Tab.match.symbol, "soccerball")
        XCTAssertEqual(BrutalTabBar.Tab.feed.symbol, "square.grid.2x2")
        XCTAssertEqual(BrutalTabBar.Tab.table.symbol, "list.number")
        // The VAR check is the video check; the checkered flag stands in on a
        // system where the symbol is missing.
        XCTAssertTrue(
            ["video.badge.checkmark", "flag.checkered"].contains(BrutalTabBar.Tab.varCheck.symbol)
        )
    }

    func testTheTabsAreReadOut() {
        XCTAssertEqual(BrutalTabBar.Tab.match.accessibilityName(waiting: 0), "Matchday")
        XCTAssertEqual(BrutalTabBar.Tab.feed.accessibilityName(waiting: 0), "Feed")
        XCTAssertEqual(BrutalTabBar.Tab.table.accessibilityName(waiting: 0), "The Table")
    }

    func testTheVARCountsTheProofsThatWait() {
        XCTAssertEqual(BrutalTabBar.Tab.varCheck.accessibilityName(waiting: 5), "VAR check, 5 waiting")
        XCTAssertEqual(BrutalTabBar.Tab.varCheck.accessibilityName(waiting: 0), "VAR check")
    }
}
