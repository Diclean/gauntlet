import XCTest
@testable import Dares

/// The lead change of the title race: the matchweek in which the #1 position changed
/// hands. The detection is a pure function (`Dares/Race/LeadChange.swift`).
final class LeadChangeTests: XCTestCase {
    // MARK: - Helpers

    /// The matchweeks of a season.
    private func makeWeeks(_ numbers: [Int]) -> [RaceWeek] {
        numbers.enumerated().map { index, number in
            RaceWeek(
                id: "week-\(number)",
                number: number,
                startsAt: Date(timeIntervalSince1970: Double(index) * 604_800)
            )
        }
    }

    /// The cumulative points of every player, matchweek by matchweek.
    private func makeSeries(_ cumulative: [String: [Int]]) -> [RaceSeries] {
        cumulative.keys.sorted().map { id in
            RaceSeries(
                user: User(id: id, displayName: id.capitalized),
                cumulative: cumulative[id] ?? [],
                perWeek: cumulative[id] ?? []
            )
        }
    }

    // MARK: - Tests

    func testTheLeaderWhoNeverChangedHasNoLeadChange() {
        let weeks = makeWeeks([1, 2, 3, 4])
        let series = makeSeries([
            "alex": [40, 70, 90, 120],
            "lee": [10, 30, 60, 80],
        ])

        XCTAssertNil(LeadChange.week(weeks: weeks, series: series))
    }

    func testTheSingleChangeOfHandsIsFound() {
        let weeks = makeWeeks([1, 2, 3, 4])
        let series = makeSeries([
            "alex": [40, 70, 90, 120],
            "lee": [10, 90, 100, 130],
        ])

        // Alex leads in MW1, Lee takes the lead in MW2 and keeps it.
        XCTAssertEqual(LeadChange.week(weeks: weeks, series: series), 2)
    }

    func testTheMostRecentChangeOfHandsWins() {
        let weeks = makeWeeks([1, 2, 3, 4, 5])
        let series = makeSeries([
            "alex": [10, 10, 30, 30, 30],
            "lee": [0, 25, 20, 45, 40],
        ])

        // Lee overtakes Alex in MW2, Alex takes it back in MW3, Lee wins it in MW4.
        XCTAssertEqual(LeadChange.week(weeks: weeks, series: series), 4)
    }

    func testADrawAtTheTopIsNotAChangeOfHands() {
        let weeks = makeWeeks([1, 2, 3])
        let series = makeSeries([
            "alex": [10, 20, 30],
            "lee": [0, 30, 30],
        ])

        // Lee takes the lead in MW2, the draw in MW3 does not take it away.
        XCTAssertEqual(LeadChange.week(weeks: weeks, series: series), 2)
    }

    func testAPlayerWithoutPointsIsNeverTheLeader() {
        let weeks = makeWeeks([1, 2, 3])
        let series = makeSeries([
            "alex": [0, 0, 10],
            "lee": [0, 0, 0],
        ])

        XCTAssertNil(LeadChange.week(weeks: weeks, series: series))
    }

    func testAnEmptyRaceHasNoLeadChange() {
        XCTAssertNil(LeadChange.week(weeks: [], series: []))
        XCTAssertNil(LeadChange.week(weeks: makeWeeks([1]), series: []))
    }

    func testTheLeadChangeOfTheDemoRaceIsTheLastMatchweek() async throws {
        let client = DemoAPIClient(autoSimulate: false)
        let race = try await client.race(groupID: DemoSeed.sundayLeagueID)

        // Lee leads the table until the last matchweek, where Alex overtakes him.
        XCTAssertEqual(LeadChange.week(of: race), DemoSeed.matchweekCount)
    }
}
